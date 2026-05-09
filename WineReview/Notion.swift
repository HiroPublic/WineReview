import Foundation

protocol NotionWineRepositoryProtocol {
    func queryInventory() async throws -> InventorySnapshot
    func queryStockWines() async throws -> [Wine]
    func retrieveWine(pageId: String) async throws -> Wine
    func updateReview(pageId: String, rating: String, tastingDate: Date, markOutOfStock: Bool, evaluation: Bool, comment: String) async -> SaveResult
}

struct NotionWineRepository: NotionWineRepositoryProtocol {
    let config: AppConfig
    let mapping: NotionPropertyMapping
    let session: URLSession = .shared

    func queryInventory() async throws -> InventorySnapshot {
        guard config.hasNotionConfig else { throw AppError.missingConfig("Notion") }
        var wines: [Wine] = []
        var cursor: String?

        repeat {
            let payload = queryPayload(startCursor: cursor, stockOnly: false)
            let json = try await request(
                path: "/v1/databases/\(config.notionWineTrackerDatabaseId)/query",
                method: "POST",
                payload: payload
            )
            guard let dict = json as? [String: Any] else {
                throw AppError.decoding("Notion query root is not an object")
            }
            let results = dict["results"] as? [[String: Any]] ?? []
            let parsedWines = results.compactMap { parseWine(page: $0) }
            wines.append(contentsOf: parsedWines)
            cursor = dict["next_cursor"] as? String
            if (dict["has_more"] as? Bool) != true {
                cursor = nil
            }
        } while cursor != nil

        return InventorySnapshot(stockWines: wines.filter(\.stock), totalCount: wines.count)
    }

    func queryStockWines() async throws -> [Wine] {
        try await queryInventory().stockWines
    }

    func retrieveWine(pageId: String) async throws -> Wine {
        let json = try await request(path: "/v1/pages/\(pageId)", method: "GET", payload: nil)
        guard let page = json as? [String: Any], let parsedWine = parseWine(page: page) else {
            throw AppError.decoding("Wine page could not be parsed")
        }
        let comments: [String]
        do {
            comments = try await retrieveComments(blockId: pageId)
        } catch {
            if isNotionCommentsPermissionError(error) {
                comments = []
            } else {
                throw error
            }
        }
        let wine = Wine(
            id: parsedWine.id,
            notionPageId: parsedWine.notionPageId,
            notionUrl: parsedWine.notionUrl,
            coverImageURL: parsedWine.coverImageURL,
            name: parsedWine.name,
            type: parsedWine.type,
            rating: parsedWine.rating,
            country: parsedWine.country,
            region: parsedWine.region,
            cave: parsedWine.cave,
            cepage: parsedWine.cepage,
            price: parsedWine.price,
            detail: parsedWine.detail,
            detailAccented: parsedWine.detailAccented,
            comments: comments,
            tastingDate: parsedWine.tastingDate,
            purchaseDate: parsedWine.purchaseDate,
            stock: parsedWine.stock,
            evaluation: parsedWine.evaluation
        )
        return wine
    }

    func updateReview(pageId: String, rating: String, tastingDate: Date, markOutOfStock: Bool, evaluation: Bool, comment: String) async -> SaveResult {
        var failures: [SaveFailure] = []
        var propertySucceeded = false
        var commentSucceeded = false

        do {
            try await updatePageProperties(pageId: pageId, rating: rating, tastingDate: tastingDate, markOutOfStock: markOutOfStock, evaluation: evaluation)
            propertySucceeded = true
        } catch {
            failures.append(SaveFailure(operation: "properties", message: friendlyFailureMessage(for: error, operation: "properties")))
        }

        do {
            try await appendReviewComment(pageId: pageId, comment: comment, tastingDate: tastingDate)
            commentSucceeded = true
        } catch {
            failures.append(SaveFailure(operation: "comment", message: friendlyFailureMessage(for: error, operation: "comment")))
        }

        return SaveResult(propertyUpdateSucceeded: propertySucceeded, commentWriteSucceeded: commentSucceeded, failures: failures)
    }

    private func updatePageProperties(pageId: String, rating: String, tastingDate: Date, markOutOfStock: Bool, evaluation: Bool) async throws {
        let page = try await request(path: "/v1/pages/\(pageId)", method: "GET", payload: nil)
        let currentProperties = (page as? [String: Any])?["properties"] as? [String: Any] ?? [:]
        var properties: [String: Any] = [:]

        properties[mapping.rating] = propertyUpdate(for: currentProperties[mapping.rating], text: rating)
        properties[mapping.tastingDate] = datePropertyUpdate(for: currentProperties[mapping.tastingDate], date: tastingDate)
        properties[mapping.evaluation] = [
            "checkbox": evaluation
        ]
        properties[mapping.stock] = [
            "checkbox": !markOutOfStock
        ]

        try await request(path: "/v1/pages/\(pageId)", method: "PATCH", payload: ["properties": properties])
    }

    private func appendReviewComment(pageId: String, comment: String, tastingDate: Date) async throws {
        let datedComment = "Review \(tastingDate.notionDateString)\n\(comment)"
        let payload: [String: Any] = [
            "parent": [
                "page_id": pageId
            ],
            "rich_text": [
                [
                    "type": "text",
                    "text": ["content": datedComment]
                ]
            ]
        ]
        try await request(path: "/v1/comments", method: "POST", payload: payload)
    }

    private func retrieveComments(blockId: String) async throws -> [String] {
        let json = try await request(path: "/v1/comments?block_id=\(blockId)", method: "GET", payload: nil)
        guard let dict = json as? [String: Any] else {
            throw AppError.decoding("Notion comments root is not an object")
        }
        let results = dict["results"] as? [[String: Any]] ?? []
        return results.compactMap { commentText($0) }.filter { !$0.isEmpty }
    }

    private func queryPayload(startCursor: String?, stockOnly: Bool = true) -> [String: Any] {
        var payload: [String: Any] = [
            "sorts": [
                [
                    "property": mapping.purchaseDate,
                    "direction": "descending"
                ]
            ],
            "page_size": 50
        ]
        if stockOnly {
            payload["filter"] = [
                "property": mapping.stock,
                "checkbox": ["equals": true]
            ]
        }
        if let startCursor {
            payload["start_cursor"] = startCursor
        }
        return payload
    }

    @discardableResult
    private func request(path: String, method: String, payload: [String: Any]?) async throws -> Any {
        guard let url = URL(string: "https://api.notion.com\(path)") else {
            throw AppError.decoding("Invalid URL: \(path)")
        }
        var request = URLRequest(url: url)
        request.httpMethod = method
        request.setValue("Bearer \(config.notionApiKey)", forHTTPHeaderField: "Authorization")
        request.setValue("2022-06-28", forHTTPHeaderField: "Notion-Version")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        if let payload {
            request.httpBody = try JSONSerialization.data(withJSONObject: payload)
        }

        do {
            let (data, response) = try await session.data(for: request)
            guard let http = response as? HTTPURLResponse else {
                throw AppError.decoding("HTTP response is unavailable")
            }
            guard 200..<300 ~= http.statusCode else {
                let message = String(data: data, encoding: .utf8) ?? HTTPURLResponse.localizedString(forStatusCode: http.statusCode)
                throw AppError.notionAPI(statusCode: http.statusCode, message: message)
            }
            if data.isEmpty { return [:] }
            return try JSONSerialization.jsonObject(with: data)
        } catch let error as AppError {
            throw error
        } catch let error as URLError {
            throw AppError.network(error)
        } catch {
            throw AppError.decoding(error.localizedDescription)
        }
    }

    private func parseWine(page: [String: Any]) -> Wine? {
        guard let id = page["id"] as? String,
              let properties = page["properties"] as? [String: Any] else {
            return nil
        }
        let url = (page["url"] as? String).flatMap(URL.init(string:))
        let name = resolvedTitle(from: properties)
        return Wine(
            id: id,
            notionPageId: id,
            notionUrl: url,
            coverImageURL: coverURL(page["cover"]),
            name: name,
            type: selectName(properties[mapping.type]),
            rating: propertyText(properties[mapping.rating]),
            country: selectName(properties[mapping.country]),
            region: selectName(properties[mapping.region]),
            cave: selectName(properties[mapping.cave]),
            cepage: multiSelectNames(properties[mapping.cepage]),
            price: number(properties[mapping.price]),
            detail: richText(properties[mapping.detail]),
            detailAccented: richText(properties["Détail"]),
            comments: [],
            tastingDate: date(properties[mapping.tastingDate]),
            purchaseDate: date(properties[mapping.purchaseDate]),
            stock: checkbox(properties[mapping.stock]) ?? false,
            evaluation: checkbox(properties[mapping.evaluation]) ?? false
        )
    }

    private func coverURL(_ cover: Any?) -> URL? {
        guard let cover = cover as? [String: Any],
              let type = cover["type"] as? String else {
            return nil
        }
        switch type {
        case "external":
            let external = cover["external"] as? [String: Any]
            return (external?["url"] as? String).flatMap(URL.init(string:))
        case "file":
            let file = cover["file"] as? [String: Any]
            return (file?["url"] as? String).flatMap(URL.init(string:))
        default:
            return nil
        }
    }

    private func resolvedTitle(from properties: [String: Any]) -> String {
        let candidates: [String?] = [
            title(properties[mapping.title]),
            title(properties["Name"]),
            title(properties["名前"]),
            propertyText(properties[mapping.title]),
            propertyText(properties["Name"]),
            propertyText(properties["名前"]),
            firstTitleProperty(in: properties)
        ]
        return candidates
            .compactMap { $0?.trimmingCharacters(in: .whitespacesAndNewlines) }
            .first { !$0.isEmpty } ?? "名称未設定"
    }

    private func firstTitleProperty(in properties: [String: Any]) -> String? {
        for property in properties.values {
            if let text = title(property), !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                return text
            }
        }
        return nil
    }

    private func title(_ property: Any?) -> String? {
        guard let dict = property as? [String: Any],
              let values = dict["title"] as? [[String: Any]] else { return nil }
        return values.compactMap { $0["plain_text"] as? String }.joined()
    }

    private func richText(_ property: Any?) -> String? {
        guard let dict = property as? [String: Any],
              let values = dict["rich_text"] as? [[String: Any]] else { return nil }
        let text = values.compactMap { $0["plain_text"] as? String }.joined()
        return text.isEmpty ? nil : text
    }

    private func commentText(_ comment: [String: Any]) -> String? {
        guard let values = comment["rich_text"] as? [[String: Any]] else { return nil }
        let text = values.compactMap { $0["plain_text"] as? String }.joined()
        return text.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private func friendlyFailureMessage(for error: Error, operation: String) -> String {
        if operation == "comment", isNotionCommentsPermissionError(error) {
            return "Notion IntegrationにCommentsの読み書き権限がありません。NotionのIntegration設定でRead comments / Insert commentsを有効にし、このDBまたはページをIntegrationへ共有してください。"
        }
        if isNotionRestrictedResourceError(error) {
            return "Notion Integrationの権限が不足しています。対象DB/ページがIntegrationに共有されているか、必要なCapabilitiesが有効か確認してください。"
        }
        return error.localizedDescription
    }

    private func isNotionCommentsPermissionError(_ error: Error) -> Bool {
        guard isNotionRestrictedResourceError(error) else { return false }
        return error.localizedDescription.localizedCaseInsensitiveContains("permission")
    }

    private func isNotionRestrictedResourceError(_ error: Error) -> Bool {
        guard case AppError.notionAPI(let statusCode, let message) = error else {
            return false
        }
        return statusCode == 403 &&
            (message.localizedCaseInsensitiveContains("restricted_resource") ||
             message.localizedCaseInsensitiveContains("Insufficient permissions"))
    }

    private func selectName(_ property: Any?) -> String? {
        guard let dict = property as? [String: Any],
              let select = dict["select"] as? [String: Any] else { return nil }
        return select["name"] as? String
    }

    private func multiSelectNames(_ property: Any?) -> [String] {
        guard let dict = property as? [String: Any],
              let values = dict["multi_select"] as? [[String: Any]] else { return [] }
        return values.compactMap { $0["name"] as? String }
    }

    private func number(_ property: Any?) -> Int? {
        guard let dict = property as? [String: Any] else { return nil }
        if let int = dict["number"] as? Int { return int }
        if let double = dict["number"] as? Double { return Int(double) }
        return nil
    }

    private func date(_ property: Any?) -> Date? {
        guard let dict = property as? [String: Any] else { return nil }
        let start: String?
        if let date = dict["date"] as? [String: Any] {
            start = date["start"] as? String
        } else {
            start = richText(property)
        }
        guard let start else { return nil }
        let formatter = ISO8601DateFormatter()
        if let parsed = formatter.date(from: start) {
            return parsed
        }
        let dayFormatter = DateFormatter()
        dayFormatter.calendar = Calendar(identifier: .gregorian)
        dayFormatter.locale = Locale(identifier: "en_US_POSIX")
        dayFormatter.dateFormat = "yyyy-MM-dd"
        if let parsed = dayFormatter.date(from: start) {
            return parsed
        }
        dayFormatter.dateFormat = "yyyy/MM/dd"
        return dayFormatter.date(from: start)
    }

    private func checkbox(_ property: Any?) -> Bool? {
        guard let dict = property as? [String: Any] else { return nil }
        return dict["checkbox"] as? Bool
    }

    private func propertyText(_ property: Any?) -> String? {
        guard let dict = property as? [String: Any] else { return nil }
        if let select = selectName(property) { return select }
        if let text = richText(property) { return text }
        if let number = dict["number"] as? Double { return String(format: "%.1f", number) }
        if let number = dict["number"] as? Int { return "\(number)" }
        return nil
    }

    private func propertyType(_ property: Any?) -> String? {
        (property as? [String: Any])?["type"] as? String
    }

    private func propertyUpdate(for property: Any?, text: String) -> [String: Any] {
        switch propertyType(property) {
        case "select":
            return ["select": ["name": text]]
        case "rich_text":
            return ["rich_text": richTextPayload(text)]
        case "number":
            return ["number": ratingNumber(from: text)]
        case "title":
            return ["title": richTextPayload(text)]
        default:
            if (property as? [String: Any])?["select"] != nil {
                return ["select": ["name": text]]
            }
            if (property as? [String: Any])?["number"] != nil {
                return ["number": ratingNumber(from: text)]
            }
            return ["rich_text": richTextPayload(text)]
        }
    }

    private func datePropertyUpdate(for property: Any?, date: Date) -> [String: Any] {
        let text = date.notionDateString
        switch propertyType(property) {
        case "date":
            return ["date": ["start": text]]
        case "rich_text":
            return ["rich_text": richTextPayload(text)]
        case "title":
            return ["title": richTextPayload(text)]
        default:
            if (property as? [String: Any])?["rich_text"] != nil {
                return ["rich_text": richTextPayload(text)]
            }
            return ["date": ["start": text]]
        }
    }

    private func richTextPayload(_ text: String) -> [[String: Any]] {
        [
            [
                "type": "text",
                "text": ["content": text]
            ]
        ]
    }

    private func ratingNumber(from text: String) -> Double {
        if let value = Double(text) {
            return value
        }
        let starCount = text.filter { $0 == "★" || $0 == "*" }.count
        return Double(max(starCount, 0))
    }
}
