import Foundation

struct EnvLoader {
    func load() -> [String: String] {
        load(from: .main)
    }

    func load(from bundle: Bundle) -> [String: String] {
        var values: [String: String] = [:]
        for resourceName in ["AppDefaults", ".env"] {
            guard let url = bundle.url(forResource: resourceName, withExtension: "env") ?? bundle.url(forResource: resourceName, withExtension: nil),
                  let text = try? String(contentsOf: url, encoding: .utf8) else {
                continue
            }
            values.merge(parse(text)) { _, new in new }
        }
        return values
    }

    func parse(_ text: String) -> [String: String] {
        var result: [String: String] = [:]
        let lines = text.components(separatedBy: .newlines)
        var index = 0

        while index < lines.count {
            let line = lines[index].trimmingCharacters(in: .whitespacesAndNewlines)
            index += 1
            guard !line.isEmpty, !line.hasPrefix("#"), let equals = line.firstIndex(of: "=") else {
                continue
            }
            let key = String(line[..<equals]).trimmingCharacters(in: .whitespacesAndNewlines)
            var value = String(line[line.index(after: equals)...]).trimmingCharacters(in: .whitespacesAndNewlines)

            if value.hasPrefix("\"") {
                while !value.hasSuffix("\""), index < lines.count {
                    value += "\n" + lines[index]
                    index += 1
                }
            }
            if value.hasPrefix("\""), value.hasSuffix("\""), value.count >= 2 {
                value.removeFirst()
                value.removeLast()
            }
            result[key] = unescape(value)
        }
        return result
    }

    private func unescape(_ value: String) -> String {
        value
            .replacingOccurrences(of: "\\n", with: "\n")
            .replacingOccurrences(of: "\\r", with: "\r")
            .replacingOccurrences(of: "\\t", with: "\t")
            .replacingOccurrences(of: "\\\"", with: "\"")
    }
}

final class SettingsStore {
    private let defaults: UserDefaults
    private let key = "wineReview.settings.v1"

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
    }

    func load() -> AppSettings {
        let env = EnvLoader().load()
        let hasSavedSettings: Bool
        let saved: AppSettings
        if let data = defaults.data(forKey: key),
           let decoded = try? JSONDecoder().decode(AppSettings.self, from: data) {
            hasSavedSettings = true
            saved = decoded
        } else {
            hasSavedSettings = false
            saved = AppSettings()
        }

        var merged = saved
        merged.notionApiKey = preferSaved(saved.notionApiKey, env["NOTION_API_KEY"])
        merged.notionDatabaseId = preferSaved(saved.notionDatabaseId, env["NOTION_WINE_TRACKER_DATABASE_ID"])
        merged.openAIAPIKey = preferSaved(saved.openAIAPIKey, env["OPENAI_API_KEY"])
        merged.openAIModel = preferSaved(saved.openAIModel, env["OPENAI_MODEL"]) == "" ? "gpt-4.1-mini" : preferSaved(saved.openAIModel, env["OPENAI_MODEL"])
        merged.geminiAPIKey = preferSaved(saved.geminiAPIKey, env["GEMINI_API_KEY"])
        merged.geminiModel = preferSaved(saved.geminiModel, env["GEMINI_MODEL"]) == "" ? "gemini-1.5-pro" : preferSaved(saved.geminiModel, env["GEMINI_MODEL"])
        let providerValue = hasSavedSettings ? saved.aiProvider.rawValue : (env["GENAI_PROVIDER"] ?? saved.aiProvider.rawValue)
        if let provider = AIProvider(rawValue: providerValue) {
            merged.aiProvider = provider
        }
        merged.template1 = preferEnv(env["WINE_REVIEW_TEMPLATE_1"], saved.template1)
        merged.template2 = preferEnv(env["WINE_REVIEW_TEMPLATE_2"], saved.template2)
        return merged
    }

    func save(_ settings: AppSettings) {
        guard let data = try? JSONEncoder().encode(settings) else { return }
        defaults.set(data, forKey: key)
    }

    func config(from settings: AppSettings) -> AppConfig {
        AppConfig(
            notionApiKey: settings.notionApiKey,
            notionWineTrackerDatabaseId: settings.notionDatabaseId,
            openAIAPIKey: settings.openAIAPIKey.nilIfBlank,
            openAIModel: settings.openAIModel.nilIfBlank,
            geminiAPIKey: settings.geminiAPIKey.nilIfBlank,
            geminiModel: settings.geminiModel.nilIfBlank,
            aiProvider: settings.aiProvider
        )
    }

    private func preferSaved(_ saved: String, _ env: String?) -> String {
        saved.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? (env ?? "") : saved
    }

    private func preferEnv(_ env: String?, _ saved: String) -> String {
        guard let env, !env.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            return saved
        }
        return env
    }
}

final class DraftStore {
    private let defaults: UserDefaults
    private let key = "wineReview.drafts.v1"

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
    }

    func load() -> [UUID: ReviewSession] {
        guard let data = defaults.data(forKey: key),
              let sessions = try? JSONDecoder().decode([ReviewSession].self, from: data) else {
            return [:]
        }
        return Dictionary(uniqueKeysWithValues: sessions.map { ($0.id, $0) })
    }

    func save(_ sessions: [UUID: ReviewSession]) {
        let values = Array(sessions.values)
        guard let data = try? JSONEncoder().encode(values) else { return }
        defaults.set(data, forKey: key)
    }
}

extension String {
    var nilIfBlank: String? {
        let trimmed = trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }
}
