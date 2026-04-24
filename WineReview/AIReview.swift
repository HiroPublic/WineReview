import Foundation

protocol AIReviewRepositoryProtocol {
    func generateCandidates(input: ReviewGenerationInput) async throws -> [String]
    func generateFinalReview(input: FinalReviewGenerationInput) async throws -> String
}

struct AIReviewRepository: AIReviewRepositoryProtocol {
    let config: AppConfig

    func generateCandidates(input: ReviewGenerationInput) async throws -> [String] {
        let prompt = ReviewPromptBuilder().candidatePrompt(input: input)
        let raw = try await generateText(prompt: prompt, maxTokens: 900)
        return try CandidateParser().parseFiveCandidates(from: raw)
    }

    func generateFinalReview(input: FinalReviewGenerationInput) async throws -> String {
        let prompt = ReviewPromptBuilder().finalReviewPrompt(input: input)
        let raw = try await generateText(prompt: prompt, maxTokens: 500)
        return sanitizeFinalReview(raw, wineName: input.wine.name)
    }

    private func generateText(prompt: String, maxTokens: Int) async throws -> String {
        switch config.aiProvider {
        case .openai:
            guard let key = config.openAIAPIKey, let model = config.openAIModel else {
                throw AppError.missingConfig("OpenAI")
            }
            return try await OpenAIClient(apiKey: key, model: model).generate(prompt: prompt, maxTokens: maxTokens)
        case .gemini:
            guard let key = config.geminiAPIKey, let model = config.geminiModel else {
                throw AppError.missingConfig("Gemini")
            }
            return try await GeminiClient(apiKey: key, model: model).generate(prompt: prompt, maxTokens: maxTokens)
        }
    }

    private func sanitizeFinalReview(_ text: String, wineName: String) -> String {
        let cleaned = text
            .components(separatedBy: .newlines)
            .map { line in
                line
                    .trimmingCharacters(in: .whitespacesAndNewlines)
                    .trimmingCharacters(in: CharacterSet(charactersIn: "#-*「」\" "))
            }
            .filter { !$0.isEmpty }
            .joined(separator: " ")

        return removeLeadingWineName(from: cleaned, wineName: wineName)
    }

    private func removeLeadingWineName(from text: String, wineName: String) -> String {
        var result = text.trimmingCharacters(in: .whitespacesAndNewlines)
        let names = [
            wineName,
            "「\(wineName)」",
            "\"\(wineName)\"",
            "\(wineName):",
            "\(wineName)：",
            "「\(wineName)」:",
            "「\(wineName)」："
        ]

        for name in names {
            if result.hasPrefix(name) {
                result.removeFirst(name.count)
                return result.trimmingCharacters(in: CharacterSet(charactersIn: " \n\r\t:：」\""))
            }
        }

        return result
    }
}

struct OpenAIClient {
    let apiKey: String
    let model: String
    let session: URLSession = .shared

    func generate(prompt: String, maxTokens: Int) async throws -> String {
        guard let url = URL(string: "https://api.openai.com/v1/responses") else {
            throw AppError.decoding("Invalid OpenAI URL")
        }
        let payload: [String: Any] = [
            "model": model,
            "input": [
                [
                    "role": "system",
                    "content": "あなたはワインレビュー作成を支援する日本語編集者です。不明な情報を補完せず、ユーザー入力とワイン情報だけで自然なレビューを作成してください。"
                ],
                [
                    "role": "user",
                    "content": prompt
                ]
            ],
            "temperature": 0.7,
            "max_output_tokens": maxTokens
        ]
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try JSONSerialization.data(withJSONObject: payload)

        do {
            let (data, response) = try await session.data(for: request)
            guard let http = response as? HTTPURLResponse else {
                throw AppError.decoding("OpenAI HTTP response is unavailable")
            }
            guard 200..<300 ~= http.statusCode else {
                throw AppError.aiAPI(provider: .openai, statusCode: http.statusCode, message: String(data: data, encoding: .utf8) ?? "")
            }
            guard let dict = try JSONSerialization.jsonObject(with: data) as? [String: Any] else {
                throw AppError.decoding("OpenAI response is not an object")
            }
            if let outputText = dict["output_text"] as? String, !outputText.isEmpty {
                return outputText
            }
            if let output = dict["output"] as? [[String: Any]] {
                let texts = output.flatMap { item -> [String] in
                    guard let content = item["content"] as? [[String: Any]] else { return [] }
                    return content.compactMap { contentItem in
                        if let text = contentItem["text"] as? String { return text }
                        if let text = contentItem["output_text"] as? String { return text }
                        return nil
                    }
                }
                let joined = texts.joined(separator: "\n")
                if !joined.isEmpty { return joined }
            }
            throw AppError.decoding("OpenAI text output is empty")
        } catch let error as AppError {
            throw error
        } catch let error as URLError {
            throw AppError.network(error)
        } catch {
            throw AppError.decoding(error.localizedDescription)
        }
    }
}

struct GeminiClient {
    let apiKey: String
    let model: String
    let session: URLSession = .shared

    func generate(prompt: String, maxTokens: Int) async throws -> String {
        guard let encodedModel = model.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed),
              let url = URL(string: "https://generativelanguage.googleapis.com/v1beta/models/\(encodedModel):generateContent?key=\(apiKey)") else {
            throw AppError.decoding("Invalid Gemini URL")
        }
        let payload: [String: Any] = [
            "contents": [
                [
                    "role": "user",
                    "parts": [["text": prompt]]
                ]
            ],
            "generationConfig": [
                "temperature": 0.7,
                "maxOutputTokens": maxTokens
            ]
        ]
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try JSONSerialization.data(withJSONObject: payload)

        do {
            let (data, response) = try await session.data(for: request)
            guard let http = response as? HTTPURLResponse else {
                throw AppError.decoding("Gemini HTTP response is unavailable")
            }
            guard 200..<300 ~= http.statusCode else {
                throw AppError.aiAPI(provider: .gemini, statusCode: http.statusCode, message: String(data: data, encoding: .utf8) ?? "")
            }
            guard let dict = try JSONSerialization.jsonObject(with: data) as? [String: Any],
                  let candidates = dict["candidates"] as? [[String: Any]] else {
                throw AppError.decoding("Gemini response is not an object")
            }
            let texts = candidates.flatMap { candidate -> [String] in
                guard let content = candidate["content"] as? [String: Any],
                      let parts = content["parts"] as? [[String: Any]] else { return [] }
                return parts.compactMap { $0["text"] as? String }
            }
            let joined = texts.joined(separator: "\n")
            if joined.isEmpty {
                throw AppError.decoding("Gemini text output is empty")
            }
            return joined
        } catch let error as AppError {
            throw error
        } catch let error as URLError {
            throw AppError.network(error)
        } catch {
            throw AppError.decoding(error.localizedDescription)
        }
    }
}

struct ReviewPromptBuilder {
    func candidatePrompt(input: ReviewGenerationInput) -> String {
        let tastingSection = tastingSummary(input.tastingInput)
        return """
        ワイン情報:
        \(wineSummary(input.wine))

        評価:
        - Rating: \(input.rating)
        - 評価補足: \(input.ratingNote)

        \(tastingSection)

        初回生成用テキスト:
        \(input.initialGenerationText)

        出力条件:
        - 日本語で、番号付きリストの5項目だけを出力してください。
        - ワイン中級者が販売店ソムリエに評価を伝える場面に合う表現にしてください。
        - ユーザーのテースティング入力を優先して表現に反映してください。
        - 不明な生産者名、品種、産地、味わいは補完しないでください。
        """
    }

    func finalReviewPrompt(input: FinalReviewGenerationInput) -> String {
        let candidates = input.candidateComments.enumerated().map { index, text in
            "\(index + 1). \(text)"
        }.joined(separator: "\n")
        let tastingSection = tastingSummary(input.tastingInput)
        let lengthGuidance = reviewLengthGuidance(from: input.finalGenerationText)
        return """
        ワイン情報:
        \(wineSummary(input.wine))

        Rating: \(input.rating)

        \(tastingSection)

        初回生成された5つの説明候補:
        \(candidates)

        再生成用テキスト:
        \(input.finalGenerationText)

        出力条件:
        - Notionにそのまま保存できる日本語レビューを1段落で出力してください。
        - ワイン名やタイトルを先頭に付けず、レビュー本文だけを出力してください。
        \(lengthGuidance)
        - Markdown見出しや箇条書きは使わないでください。
        - 不明な情報は断定しないでください。
        """
    }

    private func wineSummary(_ wine: Wine) -> String {
        let existingMemo = [
            wine.detail,
            wine.detailAccented,
            wine.comments.isEmpty ? nil : wine.comments.joined(separator: "\n")
        ]
        .compactMap { $0 }
        .filter { !$0.isEmpty }
        .joined(separator: "\n")

        return """
        - 名前: \(wine.name)
        - 種類: \(wine.type ?? "未設定")
        - 国: \(wine.country ?? "未設定")
        - 地域: \(wine.region ?? "未設定")
        - 購入店/保管場所: \(wine.cave ?? "未設定")
        - 品種: \(wine.cepage.isEmpty ? "未設定" : wine.cepage.joined(separator: ", "))
        - 価格: \(wine.price.map { "¥\($0)" } ?? "未設定")
        - 既存メモ/Comments: \(existingMemo.isEmpty ? "未設定" : existingMemo)
        """
    }

    private func tastingSummary(_ tastingInput: TastingInput?) -> String {
        guard let tastingInput else {
            return "ユーザーのテースティング入力:\n- 未入力"
        }

        let profile = TastingProfile.resolve(from: tastingInput.wineType)
        let sliderLines = profile.sliderLabels
            .compactMap { label -> String? in
                guard let value = tastingInput.sliders[label] else { return nil }
                return "  - \(label): \(value)"
            }
            .joined(separator: "\n")

        let impressionTags = tastingInput.impressionTags.isEmpty ? "未入力" : tastingInput.impressionTags.joined(separator: "、")
        let foodPairingTags = tastingInput.foodPairingTags.isEmpty ? "未入力" : tastingInput.foodPairingTags.joined(separator: "、")
        let freeNote = tastingInput.freeNote.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? "未入力" : tastingInput.freeNote

        return """
        ユーザーのテースティング入力:
        - ワインタイプ: \(tastingInput.wineType)
        - スライダー評価:
        \(sliderLines)
        - 印象タグ:
          \(impressionTags)
        - 料理相性:
          \(foodPairingTags)
        - 自由メモ:
          \(freeNote)
        """
    }

    private func reviewLengthGuidance(from text: String) -> String {
        let patterns = [
            #"(?:約|およそ)?\s*(\d{2,4})\s*文字"#,
            #"(?:約|およそ)?\s*(\d{2,4})\s*字"#
        ]

        for pattern in patterns {
            guard let regex = try? NSRegularExpression(pattern: pattern) else { continue }
            let range = NSRange(text.startIndex..<text.endIndex, in: text)
            guard let match = regex.firstMatch(in: text, range: range),
                  let numberRange = Range(match.range(at: 1), in: text) else {
                continue
            }

            let number = String(text[numberRange])
            return "- 文字数は\(number)文字前後を目安にしてください。再生成用テキストの文字数指定を優先してください。"
        }

        return "- 再生成用テキストに文字数指定がある場合はその指示を優先してください。指定がない場合は160文字程度にしてください。"
    }
}

struct CandidateParser {
    func parseFiveCandidates(from text: String) throws -> [String] {
        let lines = text
            .components(separatedBy: .newlines)
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }

        var candidates: [String] = []
        let numberedPattern = #"^\s*(?:\d+[\.\)、)]|[-*])\s*(.+)$"#
        let regex = try? NSRegularExpression(pattern: numberedPattern)

        for line in lines {
            let range = NSRange(line.startIndex..<line.endIndex, in: line)
            if let match = regex?.firstMatch(in: line, range: range),
               let textRange = Range(match.range(at: 1), in: line) {
                candidates.append(String(line[textRange]).trimmingCharacters(in: .whitespacesAndNewlines))
            }
        }

        if candidates.count < 5, lines.count == 5 {
            candidates = lines.map { $0.trimmingCharacters(in: CharacterSet(charactersIn: "-* 　")) }
        }

        let cleaned = candidates.filter { !$0.isEmpty }
        guard cleaned.count >= 5 else {
            throw AppError.candidateParseFailed
        }
        return Array(cleaned.prefix(5))
    }
}
