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
    var type: String = "Type"
    var country: String = "Country"
    var region: String = "Region"
    var cave: String = "Cave"
    var cepage: String = "Cepage"
    var price: String = "Price"
    var detail: String = "Detail"
    var tastingDate: String = "tasting date"
    var purchaseDate: String = "Purchase date"
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
    var initialGenerationText: String
    var candidateComments: [String]
    var finalGenerationText: String
    var drafts: [ReviewDraft]
    var finalComment: String
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
}

struct FinalReviewGenerationInput {
    let wine: Wine
    let rating: String
    let candidateComments: [String]
    let finalGenerationText: String
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
        formatter.dateFormat = "yyyy-MM-dd"
        return formatter.string(from: self)
    }
}
