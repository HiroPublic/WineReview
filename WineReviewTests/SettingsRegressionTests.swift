import XCTest
@testable import WineReview

final class SettingsRegressionTests: XCTestCase {
    func testAppDefaultsProvideTemplate2WithoutBundlingSecrets() throws {
        let env = EnvLoader().load(from: Bundle(for: Self.self))

        XCTAssertEqual(
            env["WINE_REVIEW_TEMPLATE_2"],
            "コメント案をまとめて160文字くらいのレビューコメントにしてください。"
        )
        XCTAssertNil(env["NOTION_API_KEY"])
        XCTAssertNil(env["OPENAI_API_KEY"])
        XCTAssertNil(env["GEMINI_API_KEY"])
    }

    @MainActor
    func testOldDefaultFinalPromptIsRefreshedFromCurrentTemplate2() {
        let store = AppStore()
        let sessionId = UUID()
        let oldDefault = "コメント案のなかで、＜＞をまとめて160文字くらいのレビューコメントにしてください。"
        let currentTemplate = "コメント案をまとめて160文字くらいのレビューコメントにしてください。"

        store.settings.template2 = currentTemplate
        store.sessions = [
            sessionId: ReviewSession(
                id: sessionId,
                wineId: "wine-1",
                rating: "★★★",
                ratingNote: "",
                tastingDate: Date(),
                markOutOfStock: true,
                evaluation: false,
                initialGenerationText: "",
                candidateComments: [],
                finalGenerationText: oldDefault,
                drafts: [],
                finalComment: ""
            )
        ]

        store.refreshFinalPromptIfDefault(sessionId: sessionId)

        XCTAssertEqual(store.sessions[sessionId]?.finalGenerationText, currentTemplate)
    }

    @MainActor
    func testEditedFinalPromptIsNotOverwritten() {
        let store = AppStore()
        let sessionId = UUID()
        let editedPrompt = "ユーザーが手で調整したまとめ方。"

        store.settings.template2 = "コメント案をまとめて160文字くらいのレビューコメントにしてください。"
        store.sessions = [
            sessionId: ReviewSession(
                id: sessionId,
                wineId: "wine-1",
                rating: "★★★",
                ratingNote: "",
                tastingDate: Date(),
                markOutOfStock: true,
                evaluation: false,
                initialGenerationText: "",
                candidateComments: [],
                finalGenerationText: editedPrompt,
                drafts: [],
                finalComment: ""
            )
        ]

        store.refreshFinalPromptIfDefault(sessionId: sessionId)

        XCTAssertEqual(store.sessions[sessionId]?.finalGenerationText, editedPrompt)
    }

    func testEmbeddedMobileProvisionExpirationIsParsed() throws {
        let profile = """
        garbage
        <?xml version="1.0" encoding="UTF-8"?>
        <!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
        <plist version="1.0">
        <dict>
        <key>ExpirationDate</key>
        <date>2026-05-14T02:19:18Z</date>
        </dict>
        </plist>
        trailer
        """

        let status = try AppInstallationProfileReader().read(from: Data(profile.utf8))

        let formatter = ISO8601DateFormatter()
        XCTAssertEqual(status.expirationDate, formatter.date(from: "2026-05-14T02:19:18Z"))
    }
}
