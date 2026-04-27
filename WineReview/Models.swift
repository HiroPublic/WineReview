import Foundation

enum AIProvider: String, Codable, CaseIterable, Identifiable {
    case openai
    case gemini

    var id: String { rawValue }
    var label: String {
        switch self {
        case .openai: "OpenAI"
        case .gemini: "Gemini"
        }
    }
}

struct AppConfig: Equatable {
    var notionApiKey: String
    var notionWineTrackerDatabaseId: String
    var openAIAPIKey: String?
    var openAIModel: String?
    var geminiAPIKey: String?
    var geminiModel: String?
    var aiProvider: AIProvider

    var hasNotionConfig: Bool {
        !notionApiKey.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty &&
            !notionWineTrackerDatabaseId.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    var hasSelectedAIConfig: Bool {
        switch aiProvider {
        case .openai:
            return !(openAIAPIKey ?? "").isEmpty && !(openAIModel ?? "").isEmpty
        case .gemini:
            return !(geminiAPIKey ?? "").isEmpty && !(geminiModel ?? "").isEmpty
        }
    }

    var missingConfigMessage: String? {
        if !hasNotionConfig {
            return "Notion APIキーまたはWine Tracker DB IDが未設定です。"
        }
        if !hasSelectedAIConfig {
            return "\(aiProvider.label)のAPIキーまたはモデルが未設定です。"
        }
        return nil
    }
}

struct NotionPropertyMapping: Codable, Equatable {
    var title: String = "Name"
    var stock: String = "Stock"
    var rating: String = "Rating"
    var evaluation: String = "評価"
    var type: String = "Type"
    var country: String = "Country"
    var region: String = "Region"
    var cave: String = "Cave"
    var cepage: String = "Cepage"
    var price: String = "Price"
    var detail: String = "Detail"
    var tastingDate: String = "tasting date"
    var purchaseDate: String = "Purchase date"

    enum CodingKeys: String, CodingKey {
        case title
        case stock
        case rating
        case evaluation
        case type
        case country
        case region
        case cave
        case cepage
        case price
        case detail
        case tastingDate
        case purchaseDate
    }

    init() {}

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        title = try container.decodeIfPresent(String.self, forKey: .title) ?? title
        stock = try container.decodeIfPresent(String.self, forKey: .stock) ?? stock
        rating = try container.decodeIfPresent(String.self, forKey: .rating) ?? rating
        evaluation = try container.decodeIfPresent(String.self, forKey: .evaluation) ?? evaluation
        type = try container.decodeIfPresent(String.self, forKey: .type) ?? type
        country = try container.decodeIfPresent(String.self, forKey: .country) ?? country
        region = try container.decodeIfPresent(String.self, forKey: .region) ?? region
        cave = try container.decodeIfPresent(String.self, forKey: .cave) ?? cave
        cepage = try container.decodeIfPresent(String.self, forKey: .cepage) ?? cepage
        price = try container.decodeIfPresent(String.self, forKey: .price) ?? price
        detail = try container.decodeIfPresent(String.self, forKey: .detail) ?? detail
        tastingDate = try container.decodeIfPresent(String.self, forKey: .tastingDate) ?? tastingDate
        purchaseDate = try container.decodeIfPresent(String.self, forKey: .purchaseDate) ?? purchaseDate
    }
}

struct AppSettings: Codable, Equatable {
    var notionApiKey: String = ""
    var notionDatabaseId: String = ""
    var openAIAPIKey: String = ""
    var openAIModel: String = "gpt-4.1-mini"
    var geminiAPIKey: String = ""
    var geminiModel: String = "gemini-1.5-pro"
    var aiProvider: AIProvider = .openai
    var propertyMapping: NotionPropertyMapping = .init()
    var template1: String = "このワインのテースティングの良い評価として５つの説明候補をあげてください\n言い振りは、ワイン中級者が販売店ソムリエに評価をつたえるためのレビューにしてください"
    var template2: String = "コメント案をまとめて160文字くらいのレビューコメントにしてください。"
    var defaultStyle: String = "自然で具体的"
    var maxRegenerationCount: Int = 10
}

struct Wine: Identifiable, Equatable, Hashable {
    let id: String
    let notionPageId: String
    let notionUrl: URL?
    let name: String
    let type: String?
    let rating: String?
    let country: String?
    let region: String?
    let cave: String?
    let cepage: [String]
    let price: Int?
    let detail: String?
    let detailAccented: String?
    let comments: [String]
    let tastingDate: Date?
    let purchaseDate: Date?
    let stock: Bool
    let evaluation: Bool

    var shortSummary: String {
        [
            type,
            country,
            region,
            cepage.isEmpty ? nil : cepage.joined(separator: ", "),
            price.map { "¥\($0)" }
        ]
        .compactMap { $0 }
        .filter { !$0.isEmpty }
        .joined(separator: " / ")
    }
}

struct InventorySnapshot: Equatable {
    let stockWines: [Wine]
    let totalCount: Int
}

struct ReviewSession: Identifiable, Codable, Equatable {
    let id: UUID
    var wineId: String
    var rating: String
    var ratingNote: String
    var tastingDate: Date
    var markOutOfStock: Bool
    var evaluation: Bool
    var initialGenerationText: String
    var tastingInput: TastingInput?
    var candidateComments: [String]
    var finalGenerationText: String
    var drafts: [ReviewDraft]
    var finalComment: String

    enum CodingKeys: String, CodingKey {
        case id
        case wineId
        case rating
        case ratingNote
        case tastingDate
        case markOutOfStock
        case evaluation
        case initialGenerationText
        case tastingInput
        case candidateComments
        case finalGenerationText
        case drafts
        case finalComment
    }

    init(
        id: UUID,
        wineId: String,
        rating: String,
        ratingNote: String,
        tastingDate: Date,
        markOutOfStock: Bool,
        evaluation: Bool,
        initialGenerationText: String,
        tastingInput: TastingInput? = nil,
        candidateComments: [String],
        finalGenerationText: String,
        drafts: [ReviewDraft],
        finalComment: String
    ) {
        self.id = id
        self.wineId = wineId
        self.rating = rating
        self.ratingNote = ratingNote
        self.tastingDate = tastingDate
        self.markOutOfStock = markOutOfStock
        self.evaluation = evaluation
        self.initialGenerationText = initialGenerationText
        self.tastingInput = tastingInput
        self.candidateComments = candidateComments
        self.finalGenerationText = finalGenerationText
        self.drafts = drafts
        self.finalComment = finalComment
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(UUID.self, forKey: .id)
        wineId = try container.decode(String.self, forKey: .wineId)
        rating = try container.decode(String.self, forKey: .rating)
        ratingNote = try container.decodeIfPresent(String.self, forKey: .ratingNote) ?? ""
        tastingDate = try container.decodeIfPresent(Date.self, forKey: .tastingDate) ?? Date()
        markOutOfStock = try container.decodeIfPresent(Bool.self, forKey: .markOutOfStock) ?? true
        evaluation = try container.decodeIfPresent(Bool.self, forKey: .evaluation) ?? false
        initialGenerationText = try container.decodeIfPresent(String.self, forKey: .initialGenerationText) ?? ""
        tastingInput = try container.decodeIfPresent(TastingInput.self, forKey: .tastingInput)
        candidateComments = try container.decodeIfPresent([String].self, forKey: .candidateComments) ?? []
        finalGenerationText = try container.decodeIfPresent(String.self, forKey: .finalGenerationText) ?? ""
        drafts = try container.decodeIfPresent([ReviewDraft].self, forKey: .drafts) ?? []
        finalComment = try container.decodeIfPresent(String.self, forKey: .finalComment) ?? ""
    }
}

struct ReviewDraft: Identifiable, Codable, Equatable {
    let id: UUID
    let text: String
    let feedbackText: String?
    let provider: AIProvider
    let model: String
    let createdAt: Date
    let generationIndex: Int
}

struct ReviewGenerationInput {
    let wine: Wine
    let rating: String
    let ratingNote: String
    let initialGenerationText: String
    let tastingInput: TastingInput?
}

struct TastingInput: Codable, Equatable {
    let wineType: String
    let sliders: [String: Int]
    let impressionTags: [String]
    let foodPairingTags: [String]
    let freeNote: String
}

func smallStarRating(from text: String) -> String {
    let starCount = text.filter { $0 == "★" || $0 == "*" }.count
    guard starCount > 0 else { return text.isEmpty ? "***" : text }
    return String(repeating: "*", count: min(starCount, 5))
}

struct TastingProfile: Equatable {
    let wineType: String
    let sliderLabels: [String]
    let impressionTags: [String]

    static let foodPairingTags = ["和食", "魚料理", "鶏肉", "豚肉", "牛肉", "チーズ", "前菜", "パスタ"]

    static func resolve(from wineType: String?) -> TastingProfile {
        let raw = (wineType ?? "").lowercased()

        if raw.contains("sparkling") || raw.contains("champagne") || raw.contains("cava") || raw.contains("cremant") || raw.contains("mousseux") || raw.contains("泡") || raw.contains("スパークリング") {
            return sparkling
        }
        if raw.contains("rose") || raw.contains("rosé") || raw.contains("ロゼ") {
            return rose
        }
        if raw.contains("red") || raw.contains("rouge") || raw.contains("赤") {
            return red
        }
        return white
    }

    static let white = TastingProfile(
        wineType: "白ワイン",
        sliderLabels: ["すっきり感", "酸味", "果実味", "香り", "コク", "ミネラル感", "後味"],
        impressionTags: ["柑橘", "青リンゴ", "洋梨", "ミネラル", "すっきり", "まろやか", "上品", "爽やか"]
    )

    static let red = TastingProfile(
        wineType: "赤ワイン",
        sliderLabels: ["重み", "タンニン", "果実味", "酸味", "なめらかさ", "樽・スパイス感", "後味"],
        impressionTags: ["赤い果実", "黒い果実", "スパイス", "樽の香り", "しっかり", "なめらか", "力強い", "コクがある"]
    )

    static let rose = TastingProfile(
        wineType: "ロゼワイン",
        sliderLabels: ["すっきり感", "果実味", "酸味", "華やかさ", "軽やかさ", "コク", "後味"],
        impressionTags: ["いちご", "赤い果実", "花の香り", "すっきり", "華やか", "軽やか", "飲みやすい", "上品"]
    )

    static let sparkling = TastingProfile(
        wineType: "スパークリング",
        sliderLabels: ["泡の細かさ", "泡の強さ", "すっきり感", "酸味", "果実味", "コク", "後味"],
        impressionTags: ["きめ細かい泡", "爽快", "柑橘", "青リンゴ", "すっきり", "クリーミー", "上品", "乾杯向き"]
    )
}

struct FinalReviewGenerationInput {
    let wine: Wine
    let rating: String
    let candidateComments: [String]
    let finalGenerationText: String
    let tastingInput: TastingInput?
}

struct SaveResult: Equatable {
    var propertyUpdateSucceeded: Bool
    var commentWriteSucceeded: Bool
    var failures: [SaveFailure]

    var succeeded: Bool {
        propertyUpdateSucceeded && commentWriteSucceeded && failures.isEmpty
    }
}

struct SaveFailure: Identifiable, Equatable {
    let id = UUID()
    let operation: String
    let message: String
}

enum AppRoute: Hashable {
    case inventory
    case wineDetail(String)
    case ratingInput(String)
    case initialPrompt(UUID)
    case aiReview(UUID)
    case finalConfirmation(UUID)
    case saveComplete(String)
    case settings
}

enum AppError: LocalizedError {
    case missingConfig(String)
    case invalidEnvValue(String)
    case notionAPI(statusCode: Int, message: String)
    case aiAPI(provider: AIProvider, statusCode: Int, message: String)
    case network(URLError)
    case decoding(String)
    case candidateParseFailed
    case notFound(String)
    case partialSave([SaveFailure])

    var errorDescription: String? {
        switch self {
        case .missingConfig(let key):
            return "\(key)が未設定です。"
        case .invalidEnvValue(let key):
            return "\(key)の値が正しくありません。"
        case .notionAPI(let statusCode, let message):
            return "Notion APIエラー \(statusCode): \(message)"
        case .aiAPI(let provider, let statusCode, let message):
            return "\(provider.label) APIエラー \(statusCode): \(message)"
        case .network(let error):
            return "通信に失敗しました: \(error.localizedDescription)"
        case .decoding(let message):
            return "レスポンス解析に失敗しました: \(message)"
        case .candidateParseFailed:
            return "5つの説明候補を読み取れませんでした。再生成してください。"
        case .notFound(let name):
            return "\(name)が見つかりません。"
        case .partialSave(let failures):
            return failures.map(\.message).joined(separator: "\n")
        }
    }
}

extension Date {
    var notionDateString: String {
        let formatter = DateFormatter()
        formatter.calendar = Calendar(identifier: .gregorian)
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = TimeZone(secondsFromGMT: 0)
        formatter.dateFormat = "yyyy/MM/dd"
        return formatter.string(from: self)
    }
}
