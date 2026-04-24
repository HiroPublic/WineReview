import Foundation
import SwiftUI

@MainActor
final class AppStore: ObservableObject {
    @Published var path: [AppRoute] = []
    @Published var settings: AppSettings
    @Published var config: AppConfig
    @Published var wines: [Wine] = []
    @Published var sessions: [UUID: ReviewSession] = [:]
    @Published var isLoading = false
    @Published var isGenerating = false
    @Published var isSaving = false
    @Published var message: String?
    @Published var lastSaveResult: SaveResult?
    @Published var totalWineCount = 0

    private let settingsStore = SettingsStore()
    private let draftStore = DraftStore()

    init() {
        let loaded = settingsStore.load()
        settings = loaded
        config = settingsStore.config(from: loaded)
        sessions = draftStore.load()
    }

    func bootstrap() async {
        if config.missingConfigMessage == nil {
            await loadInventory(forceRefresh: true)
        } else {
            path = [.settings]
        }
    }

    func saveSettings() {
        settingsStore.save(settings)
        config = settingsStore.config(from: settings)
        message = "設定を保存しました。"
    }

    func loadInventory(forceRefresh: Bool) async {
        guard config.hasNotionConfig else {
            message = config.missingConfigMessage
            return
        }
        isLoading = true
        defer { isLoading = false }
        do {
            let inventory = try await makeWineRepository().queryInventory()
            wines = inventory.stockWines.filter(\.stock)
            totalWineCount = inventory.totalCount
            message = wines.isEmpty ? "在庫ありのワインがありません。" : nil
            if forceRefresh, path.isEmpty {
                path = [.inventory]
            }
        } catch {
            message = error.localizedDescription
        }
    }

    func wine(id: String) -> Wine? {
        wines.first { $0.id == id || $0.notionPageId == id }
    }

    func session(id: UUID) -> ReviewSession? {
        sessions[id]
    }

    func createSession(for wine: Wine) -> UUID {
        sessions = sessions.filter { _, session in
            session.wineId != wine.id && session.wineId != wine.notionPageId
        }
        let id = UUID()
        let session = ReviewSession(
            id: id,
            wineId: wine.id,
            rating: wine.rating ?? "★★★",
            ratingNote: "",
            tastingDate: Date(),
            markOutOfStock: true,
            initialGenerationText: settings.template1,
            tastingInput: nil,
            candidateComments: [],
            finalGenerationText: settings.template2,
            drafts: [],
            finalComment: ""
        )
        sessions[id] = session
        persistDrafts()
        return id
    }

    func updateSession(_ session: ReviewSession) {
        sessions[session.id] = session
        persistDrafts()
    }

    func refreshFinalPromptIfDefault(sessionId: UUID) {
        guard var session = sessions[sessionId], session.finalGenerationText.isDefaultFinalPrompt else {
            return
        }
        session.finalGenerationText = settings.template2
        updateSession(session)
    }

    func generateCandidates(sessionId: UUID) async {
        guard var session = sessions[sessionId], let wine = wine(id: session.wineId) else {
            message = "レビューセッションが見つかりません。"
            return
        }
        guard config.hasSelectedAIConfig else {
            message = config.missingConfigMessage
            return
        }
        isGenerating = true
        defer { isGenerating = false }
        do {
            let input = ReviewGenerationInput(
                wine: wine,
                rating: session.rating,
                ratingNote: session.ratingNote,
                initialGenerationText: session.initialGenerationText,
                tastingInput: session.tastingInput
            )
            let candidates = try await AIReviewRepository(config: config).generateCandidates(input: input)
            session.candidateComments = candidates
            session.drafts.append(
                ReviewDraft(
                    id: UUID(),
                    text: candidates.joined(separator: "\n"),
                    feedbackText: nil,
                    provider: config.aiProvider,
                    model: currentModel,
                    createdAt: Date(),
                    generationIndex: session.drafts.count + 1
                )
            )
            updateSession(session)
        } catch {
            message = error.localizedDescription
        }
    }

    func generateFinalReview(sessionId: UUID, selectedCandidateIndexes: Set<Int>) async {
        guard var session = sessions[sessionId], let wine = wine(id: session.wineId) else {
            message = "レビューセッションが見つかりません。"
            return
        }
        guard session.drafts.count < settings.maxRegenerationCount else {
            message = "再生成回数の上限に達しました。"
            return
        }
        let selected = selectedCandidateIndexes.sorted().compactMap { index in
            session.candidateComments.indices.contains(index) ? session.candidateComments[index] : nil
        }
        let candidates = selected.isEmpty ? session.candidateComments : selected

        isGenerating = true
        defer { isGenerating = false }
        do {
            let input = FinalReviewGenerationInput(
                wine: wine,
                rating: session.rating,
                candidateComments: candidates,
                finalGenerationText: session.finalGenerationText,
                tastingInput: session.tastingInput
            )
            let final = try await AIReviewRepository(config: config).generateFinalReview(input: input)
            session.finalComment = final
            session.drafts.append(
                ReviewDraft(
                    id: UUID(),
                    text: final,
                    feedbackText: session.finalGenerationText,
                    provider: config.aiProvider,
                    model: currentModel,
                    createdAt: Date(),
                    generationIndex: session.drafts.count + 1
                )
            )
            updateSession(session)
        } catch {
            message = error.localizedDescription
        }
    }

    func saveReview(sessionId: UUID) async {
        guard let session = sessions[sessionId], let wine = wine(id: session.wineId) else {
            message = "保存対象が見つかりません。"
            return
        }
        guard !session.finalComment.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            message = "最終コメントを入力してください。"
            return
        }

        isSaving = true
        defer { isSaving = false }
        let result = await makeWineRepository().updateReview(
            pageId: wine.notionPageId,
            rating: session.rating,
            tastingDate: session.tastingDate,
            markOutOfStock: session.markOutOfStock,
            comment: session.finalComment
        )
        lastSaveResult = result
        if result.succeeded {
            if session.markOutOfStock {
                wines.removeAll { $0.id == wine.id || $0.notionPageId == wine.notionPageId }
                totalWineCount = max(totalWineCount, wines.count)
            } else {
                await reloadWine(pageId: wine.notionPageId)
            }
            message = nil
            path.append(.saveComplete(wine.id))
        } else {
            message = result.failures.map(\.message).joined(separator: "\n")
        }
    }

    func reloadWine(pageId: String) async {
        isLoading = true
        defer { isLoading = false }
        do {
            let refreshed = try await makeWineRepository().retrieveWine(pageId: pageId)
            if let index = wines.firstIndex(where: { $0.id == pageId }) {
                wines[index] = refreshed
            } else {
                wines.append(refreshed)
            }
        } catch {
            message = error.localizedDescription
        }
    }

    func resetMessage() {
        message = nil
    }

    private func makeWineRepository() -> NotionWineRepository {
        NotionWineRepository(config: config, mapping: settings.propertyMapping)
    }

    private var currentModel: String {
        switch config.aiProvider {
        case .openai:
            return config.openAIModel ?? ""
        case .gemini:
            return config.geminiModel ?? ""
        }
    }

    private func persistDrafts() {
        draftStore.save(sessions)
    }
}

private extension String {
    var isDefaultFinalPrompt: Bool {
        let defaultPrompts = [
            AppSettings().template2,
            "コメント案のなかで、＜＞をまとめて160文字くらいのレビューコメントにしてください。"
        ]
        return defaultPrompts.contains(self)
    }
}
