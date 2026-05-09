import SwiftUI

struct RootView: View {
    @EnvironmentObject private var store: AppStore

    var body: some View {
        NavigationStack(path: $store.path) {
            LaunchView()
                .navigationDestination(for: AppRoute.self) { route in
                    switch route {
                    case .inventory:
                        InventoryWineListView()
                    case .wineDetail(let wineId):
                        WineDetailView(wineId: wineId)
                    case .ratingInput(let wineId):
                        RatingInputView(wineId: wineId)
                    case .initialPrompt(let sessionId):
                        InitialPromptEditorView(sessionId: sessionId)
                    case .aiReview(let sessionId):
                        AIReviewView(sessionId: sessionId)
                    case .finalConfirmation(let sessionId):
                        FinalConfirmationView(sessionId: sessionId)
                    case .saveComplete(let wineId):
                        SaveCompleteView(wineId: wineId)
                    case .settings:
                        SettingsView()
                    }
                }
        }
        .alert("通知", isPresented: messageBinding) {
            Button("OK") { store.resetMessage() }
        } message: {
            Text(store.message ?? "")
        }
    }

    private var messageBinding: Binding<Bool> {
        Binding(
            get: { store.message != nil },
            set: { if !$0 { store.resetMessage() } }
        )
    }
}

struct LaunchView: View {
    @EnvironmentObject private var store: AppStore

    var body: some View {
        VStack(alignment: .leading, spacing: 24) {
            Spacer()
            VStack(alignment: .leading, spacing: 10) {
                Text("Wine Review")
                    .font(.largeTitle.bold())
                Text("Notionの在庫ワインから選び、AIとレビュー文を整えて保存します。")
                    .font(.body)
                    .foregroundStyle(.secondary)
            }

            VStack(spacing: 12) {
                StatusRow(title: "Notion連携", isReady: store.config.hasNotionConfig)
                StatusRow(title: "\(store.config.aiProvider.label)設定", isReady: store.config.hasSelectedAIConfig)
            }

            if store.isLoading {
                ProgressView("同期中")
                    .frame(maxWidth: .infinity, alignment: .center)
            }

            Button {
                if store.config.missingConfigMessage == nil {
                    store.path.append(.inventory)
                } else {
                    store.path.append(.settings)
                }
            } label: {
                Label(store.config.missingConfigMessage == nil ? "在庫一覧へ" : "初期設定へ", systemImage: "wineglass")
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.borderedProminent)

            Button {
                store.path.append(.settings)
            } label: {
                Label("設定を開く", systemImage: "gearshape")
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.bordered)
            Spacer()
        }
        .padding()
        .readableContent()
        .navigationTitle("起動")
    }
}

struct StatusRow: View {
    let title: String
    let isReady: Bool

    var body: some View {
        HStack {
            Image(systemName: isReady ? "checkmark.circle.fill" : "exclamationmark.triangle.fill")
                .foregroundStyle(isReady ? .green : .orange)
            Text(title)
            Spacer()
            Text(isReady ? "設定済み" : "未設定")
                .foregroundStyle(.secondary)
        }
        .padding()
        .background(.thinMaterial)
        .clipShape(RoundedRectangle(cornerRadius: 8))
    }
}

struct InventoryWineListView: View {
    @EnvironmentObject private var store: AppStore
    @Environment(\.horizontalSizeClass) private var horizontalSizeClass
    @State private var searchText = ""
    @State private var sortMode = SortMode.purchaseDate
    @State private var displayMode = DisplayMode.list
    @State private var selectedVisualWine: Wine?

    enum SortMode: String, CaseIterable, Identifiable {
        case purchaseDate = "購入日"
        case name = "名前"
        case price = "価格"

        var id: String { rawValue }
    }

    enum DisplayMode: String, CaseIterable, Identifiable {
        case list = "一覧"
        case visual = "ビジュアル"

        var id: String { rawValue }
    }

    var filteredWines: [Wine] {
        let base = searchText.isEmpty ? store.wines : store.wines.filter {
            [$0.name, $0.type, $0.country, $0.region, $0.detail, $0.detailAccented].compactMap { $0 }.joined(separator: " ").localizedCaseInsensitiveContains(searchText)
        }
        switch sortMode {
        case .purchaseDate:
            return base.sorted { ($0.purchaseDate ?? .distantPast) > ($1.purchaseDate ?? .distantPast) }
        case .name:
            return base.sorted { $0.name.localizedStandardCompare($1.name) == .orderedAscending }
        case .price:
            return base.sorted { ($0.price ?? 0) > ($1.price ?? 0) }
        }
    }

    private var usesGridLayout: Bool {
        horizontalSizeClass == .regular
    }

    private var visualGridColumns: [GridItem] {
        [GridItem(.flexible(), spacing: 16)]
    }

    var body: some View {
        VStack(spacing: 0) {
            Picker("表示", selection: $displayMode) {
                ForEach(DisplayMode.allCases) { mode in
                    Text(mode.rawValue).tag(mode)
                }
            }
            .pickerStyle(.segmented)
            .padding(.horizontal, 16)
            .padding(.top, 8)
            .padding(.bottom, 12)

            Group {
                if store.isLoading && store.wines.isEmpty {
                    ProgressView("在庫ワインを取得中")
                } else if filteredWines.isEmpty {
                    ContentUnavailableView("在庫ありのワインがありません", systemImage: "wineglass", description: Text("再読み込みするか、設定を確認してください。"))
                } else {
                    ScrollView {
                        if displayMode == .visual {
                            LazyVGrid(columns: visualGridColumns, spacing: 16) {
                                ForEach(filteredWines) { wine in
                                    WineVisualCardView(
                                        wine: wine,
                                        onImageTap: { selectedVisualWine = wine },
                                        onTextTap: { store.path.append(.wineDetail(wine.id)) }
                                    )
                                }
                            }
                            .padding(16)
                        } else if usesGridLayout {
                            LazyVGrid(columns: [GridItem(.adaptive(minimum: 320, maximum: 520), spacing: 16)], spacing: 16) {
                                ForEach(filteredWines) { wine in
                                    NavigationLink(value: AppRoute.wineDetail(wine.id)) {
                                        WineCardView(wine: wine)
                                    }
                                    .buttonStyle(.plain)
                                }
                            }
                            .padding(20)
                        } else {
                            LazyVStack(spacing: 0) {
                                ForEach(filteredWines) { wine in
                                    NavigationLink(value: AppRoute.wineDetail(wine.id)) {
                                        WineRowView(wine: wine)
                                            .padding(.horizontal, 16)
                                            .padding(.vertical, 10)
                                            .frame(maxWidth: .infinity, alignment: .leading)
                                            .contentShape(Rectangle())
                                    }
                                    .buttonStyle(.plain)

                                    Divider()
                                        .padding(.leading, 16)
                                }
                            }
                            .background(.background)
                        }
                    }
                    .refreshable {
                        await store.loadInventory(forceRefresh: true)
                    }
                }
            }
        }
        .searchable(text: $searchText, prompt: "ワイン名、国、品種で検索")
        .navigationTitle("在庫ワイン")
        .navigationBarTitleDisplayMode(.inline)
        .sheet(item: $selectedVisualWine) { wine in
            WineImagePreviewSheet(wine: wine)
        }
        .toolbar {
            ToolbarItem(placement: .principal) {
                HStack(alignment: .firstTextBaseline, spacing: 8) {
                    Text("在庫ワイン")
                        .font(.headline)
                    Text("\(store.wines.count) / \(store.totalWineCount)")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
            ToolbarItem(placement: .topBarLeading) {
                Menu {
                    Picker("並び替え", selection: $sortMode) {
                        ForEach(SortMode.allCases) { mode in
                            Text(mode.rawValue).tag(mode)
                        }
                    }
                } label: {
                    Image(systemName: "arrow.up.arrow.down")
                }
            }
            ToolbarItem(placement: .topBarTrailing) {
                Button {
                    Task { await store.loadInventory(forceRefresh: true) }
                } label: {
                    Image(systemName: "arrow.clockwise")
                }
                .disabled(store.isLoading)
            }
            ToolbarItem(placement: .topBarTrailing) {
                Button {
                    store.path.append(.settings)
                } label: {
                    Image(systemName: "gearshape")
                }
            }
        }
        .task {
            if store.wines.isEmpty {
                await store.loadInventory(forceRefresh: false)
            }
        }
    }
}

struct WineVisualCardView: View {
    let wine: Wine
    let onImageTap: () -> Void
    let onTextTap: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Button(action: onImageTap) {
                WineCoverImageView(url: wine.coverImageURL, height: 220)
            }
            .buttonStyle(.plain)

            Button(action: onTextTap) {
                VStack(alignment: .leading, spacing: 4) {
                    Text(wine.name)
                        .font(.headline)
                        .foregroundStyle(.primary)
                        .lineLimit(2)
                    if !wine.shortSummary.isEmpty {
                        Text(wine.shortSummary)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .lineLimit(3)
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            .buttonStyle(.plain)
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .topLeading)
        .background(.background)
        .clipShape(RoundedRectangle(cornerRadius: 14))
        .overlay {
            RoundedRectangle(cornerRadius: 14)
                .stroke(.quaternary)
        }
    }
}

struct WineCoverImageView: View {
    let url: URL?
    var height: CGFloat = 220

    var body: some View {
        Group {
            if let url {
                AsyncImage(url: url) { phase in
                    switch phase {
                    case .empty:
                        ProgressView()
                            .frame(maxWidth: .infinity, maxHeight: .infinity)
                    case .success(let image):
                        image
                            .resizable()
                            .scaledToFill()
                    case .failure:
                        placeholder
                    @unknown default:
                        placeholder
                    }
                }
            } else {
                placeholder
            }
        }
        .frame(maxWidth: .infinity)
        .frame(height: height)
        .background(.thinMaterial)
        .clipShape(RoundedRectangle(cornerRadius: 12))
        .contentShape(RoundedRectangle(cornerRadius: 12))
    }

    private var placeholder: some View {
        VStack(spacing: 10) {
            Image(systemName: "photo")
                .font(.title2)
            Text("カバー画像なし")
                .font(.caption)
        }
        .foregroundStyle(.secondary)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(.thinMaterial)
    }
}

struct WineImagePreviewSheet: View {
    @Environment(\.dismiss) private var dismiss
    let wine: Wine

    var body: some View {
        NavigationStack {
            ZStack {
                Color.black.ignoresSafeArea()
                VStack(spacing: 16) {
                    WineCoverImageView(url: wine.coverImageURL, height: 420)
                        .clipShape(RoundedRectangle(cornerRadius: 18))
                        .padding(.horizontal, 20)
                    VStack(spacing: 6) {
                        Text(wine.name)
                            .font(.headline)
                            .foregroundStyle(.white)
                            .multilineTextAlignment(.center)
                        if !wine.shortSummary.isEmpty {
                            Text(wine.shortSummary)
                                .font(.subheadline)
                                .foregroundStyle(.white.opacity(0.8))
                                .multilineTextAlignment(.center)
                                .padding(.horizontal, 24)
                        }
                    }
                    Spacer()
                }
                .padding(.top, 24)
            }
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("閉じる") {
                        dismiss()
                    }
                    .foregroundStyle(.white)
                }
            }
            .toolbarBackground(.hidden, for: .navigationBar)
        }
        .presentationBackground(.black)
    }
}

struct WineCardView: View {
    let wine: Wine

    var body: some View {
        WineRowView(wine: wine)
            .padding(16)
            .frame(maxWidth: .infinity, minHeight: 136, alignment: .topLeading)
            .background(.background)
            .clipShape(RoundedRectangle(cornerRadius: 8))
            .overlay {
                RoundedRectangle(cornerRadius: 8)
                    .stroke(.quaternary)
            }
            .contentShape(RoundedRectangle(cornerRadius: 8))
    }
}

struct WineRowView: View {
    let wine: Wine

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(alignment: .firstTextBaseline) {
                Text(wine.name)
                    .font(.headline)
                Spacer()
                if let rating = wine.rating {
                    Text(rating)
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
            }
            Text(wine.shortSummary.isEmpty ? "詳細情報なし" : wine.shortSummary)
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .lineLimit(2)
            if let detail = wine.detail, !detail.isEmpty {
                Text(detail)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(2)
            } else if let detail = wine.detailAccented, !detail.isEmpty {
                Text(detail)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(2)
            }
        }
        .padding(.vertical, 4)
    }
}

struct WineDetailView: View {
    @EnvironmentObject private var store: AppStore
    @Environment(\.openURL) private var openURL
    let wineId: String

    var wine: Wine? { store.wine(id: wineId) }

    var body: some View {
        Group {
            if let wine {
                List {
                    Section {
                        VStack(alignment: .leading, spacing: 8) {
                            Text(wine.name)
                                .font(.title2.bold())
                            Text(wine.shortSummary)
                                .foregroundStyle(.secondary)
                        }
                    }
                    Section("プロパティ") {
                        DetailRow("Type", wine.type)
                        DetailRow("Country", wine.country)
                        DetailRow("Region", wine.region)
                        DetailRow("Cave", wine.cave)
                        DetailRow("Cepage", wine.cepage.joined(separator: ", "))
                        DetailRow("Rating", wine.rating)
                        DetailRow("Price", wine.price.map { "¥\($0)" })
                        DetailRow("tasting date", wine.tastingDate.map(dateText))
                        DetailRow("Purchase date", wine.purchaseDate.map(dateText))
                        DetailRow("Stock", wine.stock ? "在庫あり" : "在庫なし")
                    }
                    Section("Détail") {
                        Text(wine.detailAccented ?? "Détailは未設定です。")
                            .foregroundStyle(wine.detailAccented == nil ? .secondary : .primary)
                    }
                    Section("Comments") {
                        if wine.comments.isEmpty {
                            Text("Commentsはありません。")
                                .foregroundStyle(.secondary)
                        } else {
                            ForEach(Array(wine.comments.enumerated()), id: \.offset) { _, comment in
                                Text(comment)
                            }
                        }
                    }
                    Section {
                        Button {
                            if let url = wine.notionUrl {
                                openURL(url)
                            } else {
                                store.message = "Notion URLが取得できません。"
                            }
                        } label: {
                            Label("Notionで開く", systemImage: "arrow.up.right.square")
                        }
                    }
                }
            } else {
                ContentUnavailableView("ワインが見つかりません", systemImage: "questionmark.circle")
            }
        }
        .navigationTitle("ワイン詳細")
        .task(id: wineId) {
            await store.reloadWine(pageId: wineId)
        }
        .toolbar {
            ToolbarItem(placement: .topBarLeading) {
                if let wine {
                    Button {
                        startReview(for: wine)
                    } label: {
                        Image(systemName: "square.and.pencil")
                    }
                }
            }
            ToolbarItem(placement: .topBarTrailing) {
                Button {
                    Task { await store.reloadWine(pageId: wineId) }
                } label: {
                    Image(systemName: "arrow.clockwise")
                }
            }
        }
        .safeAreaInset(edge: .bottom) {
            if let wine {
                Button {
                    startReview(for: wine)
                } label: {
                    Label("レビューを作成", systemImage: "square.and.pencil")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderedProminent)
                .padding()
                .background(.bar)
            }
        }
    }

    private func startReview(for wine: Wine) {
        _ = store.createSession(for: wine)
        store.path.append(.ratingInput(wine.id))
    }
}

struct RatingInputView: View {
    @EnvironmentObject private var store: AppStore
    let wineId: String
    @State private var sessionId: UUID?
    @State private var rating = "★★★"
    @State private var ratingNote = ""
    @State private var tastingDate = Date()
    @State private var markOutOfStock = true
    @State private var evaluation = false

    private let ratingOptions = ["*", "**", "***", "****", "*****"]

    var body: some View {
        Form {
            if let wine = store.wine(id: wineId) {
                Section("対象ワイン") {
                    Text(wine.name)
                    DetailRow("現在のRating", wine.rating)
                    DetailRow("現在の評価", wine.evaluation ? "オン" : "オフ")
                }
            }
            Section("評価") {
                Picker("Rating", selection: $rating) {
                    ForEach(ratingOptions, id: \.self) { Text($0).tag($0) }
                }
                TextField("評価補足", text: $ratingNote, axis: .vertical)
                    .lineLimit(2...4)
                DatePicker("試飲日", selection: $tastingDate, displayedComponents: .date)
                Toggle("評価", isOn: $evaluation)
                Toggle("保存時にStockを在庫なしへ変更", isOn: $markOutOfStock)
            }
            Section {
                Button {
                    guard let wine = store.wine(id: wineId) else { return }
                    let id = sessionId ?? store.createSession(for: wine)
                    var session = store.session(id: id) ?? ReviewSession(id: id, wineId: wine.id, rating: rating, ratingNote: "", tastingDate: Date(), markOutOfStock: true, evaluation: wine.evaluation, initialGenerationText: store.settings.template1, candidateComments: [], finalGenerationText: store.settings.template2, drafts: [], finalComment: "")
                    session.rating = rating
                    session.ratingNote = ratingNote
                    session.tastingDate = tastingDate
                    session.markOutOfStock = markOutOfStock
                    session.evaluation = evaluation
                    store.updateSession(session)
                    store.path.append(.initialPrompt(id))
                } label: {
                    Label("次へ", systemImage: "chevron.right")
                }
            }
        }
        .navigationTitle("評価入力")
        .onAppear {
            if let existing = store.sessions.values.first(where: { $0.wineId == wineId }) {
                sessionId = existing.id
                rating = smallStarRating(from: existing.rating)
                ratingNote = existing.ratingNote
                tastingDate = existing.tastingDate
                markOutOfStock = existing.markOutOfStock
                evaluation = existing.evaluation
            } else if let wine = store.wine(id: wineId) {
                rating = smallStarRating(from: wine.rating ?? "***")
                evaluation = wine.evaluation
            }
        }
    }
}

struct InitialPromptEditorView: View {
    @EnvironmentObject private var store: AppStore
    @Environment(\.openURL) private var openURL
    let sessionId: UUID
    @State private var promptText = ""
    @State private var sliderValues: [String: Int] = [:]
    @State private var selectedImpressionTags: [String] = []
    @State private var selectedFoodPairingTags: [String] = []
    @State private var freeNote = ""
    @State private var isFoodSectionExpanded = false

    private let sliderRange = 1...5
    private let maxImpressionTagCount = 3
    private let maxFoodPairingTagCount = 2

    private var session: ReviewSession? {
        store.session(id: sessionId)
    }

    private var wine: Wine? {
        guard let session else { return nil }
        return store.wine(id: session.wineId)
    }

    private var profile: TastingProfile {
        TastingProfile.resolve(from: wine?.type ?? session?.tastingInput?.wineType)
    }

    var body: some View {
        Form {
            if let wine {
                Section {
                    WineOverviewCard(wine: wine)
                    if let url = wine.notionUrl {
                        Button {
                            openURL(url)
                        } label: {
                            Label("Notionで開く", systemImage: "arrow.up.right.square")
                        }
                    }
                }
            }
            if let session {
                Section("Rating・試飲日") {
                    DetailRow("Rating", session.rating)
                    DetailRow("試飲日", dateText(session.tastingDate))
                    if !session.ratingNote.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                        DetailRow("評価補足", session.ratingNote)
                    }
                }
            }
            Section {
                ForEach(profile.sliderLabels, id: \.self) { label in
                    SliderRatingRow(
                        label: label,
                        value: bindingForSlider(label),
                        range: sliderRange
                    )
                }
            } header: {
                HStack {
                    Text("\(profile.wineType)の味わい")
                    Spacer()
                    Text("1:少ない  5:多い")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
            Section("印象・飲み口タグ") {
                TagSelectionGrid(
                    tags: profile.impressionTags,
                    selectedTags: selectedImpressionTags,
                    selectionLimit: maxImpressionTagCount,
                    toggle: toggleImpressionTag
                )
                Text("最大\(maxImpressionTagCount)個まで選択できます。")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Section {
                DisclosureGroup("料理との相性も入力する", isExpanded: $isFoodSectionExpanded) {
                    VStack(alignment: .leading, spacing: 12) {
                        TagSelectionGrid(
                            tags: TastingProfile.foodPairingTags,
                            selectedTags: selectedFoodPairingTags,
                            selectionLimit: maxFoodPairingTagCount,
                            toggle: toggleFoodPairingTag
                        )
                        Text("最大\(maxFoodPairingTagCount)個まで選択できます。")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    .padding(.vertical, 8)
                }
            }
            Section("自由メモ") {
                TextEditor(text: $freeNote)
                    .frame(minHeight: 120)
                Text("例: 香りが良く、酸味がきれい。和食にも合わせやすかった。")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Section("レビュー文体・文字数") {
                TextEditor(text: $promptText)
                    .frame(minHeight: 180)
                Text("\(promptText.count)文字")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Section {
                Button {
                    saveInputs()
                    store.path.append(.aiReview(sessionId))
                    Task { await store.generateCandidates(sessionId: sessionId) }
                } label: {
                    if store.isGenerating {
                        ProgressView()
                    } else {
                        Label("AIでレビュー案を作成", systemImage: "sparkles")
                    }
                }
                .disabled(store.isGenerating || promptText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            }
        }
        .navigationTitle("テースティング入力・レビュー生成準備")
        .onAppear {
            loadInputs()
        }
        .onDisappear {
            saveInputs()
        }
    }

    private func loadInputs() {
        promptText = session?.initialGenerationText ?? store.settings.template1

        let currentProfile = profile
        var resolvedSliders = Dictionary(uniqueKeysWithValues: currentProfile.sliderLabels.map { ($0, 3) })
        if let existing = session?.tastingInput {
            for label in currentProfile.sliderLabels {
                if let value = existing.sliders[label] {
                    resolvedSliders[label] = min(max(value, sliderRange.lowerBound), sliderRange.upperBound)
                }
            }
            selectedImpressionTags = existing.impressionTags.filter(currentProfile.impressionTags.contains)
            selectedFoodPairingTags = existing.foodPairingTags.filter(TastingProfile.foodPairingTags.contains)
            freeNote = existing.freeNote
            isFoodSectionExpanded = !selectedFoodPairingTags.isEmpty
        } else {
            selectedImpressionTags = []
            selectedFoodPairingTags = []
            freeNote = ""
            isFoodSectionExpanded = false
        }
        sliderValues = resolvedSliders
    }

    private func saveInputs() {
        guard var session = store.session(id: sessionId) else { return }
        session.initialGenerationText = promptText
        session.tastingInput = TastingInput(
            wineType: profile.wineType,
            sliders: orderedSliderDictionary(),
            impressionTags: selectedImpressionTags,
            foodPairingTags: selectedFoodPairingTags,
            freeNote: freeNote.trimmingCharacters(in: .whitespacesAndNewlines)
        )
        store.updateSession(session)
    }

    private func orderedSliderDictionary() -> [String: Int] {
        Dictionary(uniqueKeysWithValues: profile.sliderLabels.map { label in
            (label, min(max(sliderValues[label] ?? 3, sliderRange.lowerBound), sliderRange.upperBound))
        })
    }

    private func bindingForSlider(_ label: String) -> Binding<Int> {
        Binding(
            get: { sliderValues[label] ?? 3 },
            set: { sliderValues[label] = $0 }
        )
    }

    private func toggleImpressionTag(_ tag: String) {
        if selectedImpressionTags.contains(tag) {
            selectedImpressionTags.removeAll { $0 == tag }
        } else if selectedImpressionTags.count < maxImpressionTagCount {
            selectedImpressionTags.append(tag)
        }
    }

    private func toggleFoodPairingTag(_ tag: String) {
        if selectedFoodPairingTags.contains(tag) {
            selectedFoodPairingTags.removeAll { $0 == tag }
        } else if selectedFoodPairingTags.count < maxFoodPairingTagCount {
            selectedFoodPairingTags.append(tag)
        }
    }
}

struct WineOverviewCard: View {
    let wine: Wine

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(wine.name)
                .font(.headline)

            VStack(alignment: .leading, spacing: 8) {
                DetailRow("Type", wine.type)
                DetailRow("Country", wine.country)
                DetailRow("Region", wine.region)
                DetailRow("Cepage", wine.cepage.isEmpty ? nil : wine.cepage.joined(separator: ", "))
                DetailRow("Price", wine.price.map { "¥\($0)" })
                DetailRow("Rating", wine.rating)
            }

            VStack(alignment: .leading, spacing: 4) {
                Text("Detail")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Text(detailExcerpt)
                    .font(.subheadline)
                    .foregroundStyle(detailExcerpt == "未設定" ? .secondary : .primary)
                    .lineLimit(4)
            }
        }
        .padding(.vertical, 4)
    }

    private var detailExcerpt: String {
        let source = wine.detailAccented ?? wine.detail
        let trimmed = source?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        guard !trimmed.isEmpty else { return "未設定" }
        if trimmed.count <= 140 {
            return trimmed
        }
        return String(trimmed.prefix(140)) + "…"
    }
}

struct SliderRatingRow: View {
    let label: String
    @Binding var value: Int
    let range: ClosedRange<Int>

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Text(label)
                Spacer()
                Text("\(value)")
                    .font(.subheadline.monospacedDigit())
                    .foregroundStyle(.secondary)
            }
            Slider(
                value: Binding(
                    get: { Double(value) },
                    set: { value = Int($0.rounded()) }
                ),
                in: Double(range.lowerBound)...Double(range.upperBound),
                step: 1
            )
            HStack {
                Text("\(range.lowerBound)")
                Spacer()
                Text("\(range.upperBound)")
            }
            .font(.caption)
            .foregroundStyle(.secondary)
        }
        .padding(.vertical, 2)
    }
}

struct TagSelectionGrid: View {
    let tags: [String]
    let selectedTags: [String]
    let selectionLimit: Int
    let toggle: (String) -> Void

    var body: some View {
        WrappingTagLayout(horizontalSpacing: 8, verticalSpacing: 8) {
            ForEach(tags, id: \.self) { tag in
                let isSelected = selectedTags.contains(tag)
                Button {
                    toggle(tag)
                } label: {
                    Text(tag)
                        .font(.subheadline)
                        .lineLimit(nil)
                        .multilineTextAlignment(.center)
                        .fixedSize(horizontal: false, vertical: true)
                        .padding(.horizontal, 12)
                        .padding(.vertical, 8)
                        .background(isSelected ? Color.accentColor.opacity(0.18) : Color(.secondarySystemBackground))
                        .foregroundStyle(isSelected ? Color.accentColor : Color.primary)
                        .clipShape(Capsule())
                        .overlay {
                            Capsule()
                                .stroke(isSelected ? Color.accentColor : Color.secondary.opacity(0.25), lineWidth: 1)
                        }
                }
                .buttonStyle(.plain)
                .disabled(!isSelected && selectedTags.count >= selectionLimit)
                .opacity(!isSelected && selectedTags.count >= selectionLimit ? 0.45 : 1)
            }
        }
    }
}

struct WrappingTagLayout: Layout {
    let horizontalSpacing: CGFloat
    let verticalSpacing: CGFloat

    func sizeThatFits(
        proposal: ProposedViewSize,
        subviews: Subviews,
        cache: inout ()
    ) -> CGSize {
        layout(in: proposal.width ?? .greatestFiniteMagnitude, subviews: subviews).size
    }

    func placeSubviews(
        in bounds: CGRect,
        proposal: ProposedViewSize,
        subviews: Subviews,
        cache: inout ()
    ) {
        let rows = layout(in: bounds.width, subviews: subviews).rows

        for row in rows {
            for item in row.items {
                subviews[item.index].place(
                    at: CGPoint(x: bounds.minX + item.x, y: bounds.minY + row.y),
                    anchor: .topLeading,
                    proposal: ProposedViewSize(item.size)
                )
            }
        }
    }

    private func layout(in maxWidth: CGFloat, subviews: Subviews) -> (rows: [Row], size: CGSize) {
        var rows: [Row] = []
        var currentItems: [Item] = []
        var currentX: CGFloat = 0
        var currentHeight: CGFloat = 0
        var y: CGFloat = 0
        var widestRow: CGFloat = 0

        for index in subviews.indices {
            let size = size(for: subviews[index], maxWidth: maxWidth)
            let itemSpacing = currentItems.isEmpty ? 0 : horizontalSpacing

            if !currentItems.isEmpty, currentX + itemSpacing + size.width > maxWidth {
                rows.append(Row(y: y, height: currentHeight, items: currentItems))
                widestRow = max(widestRow, currentX)
                y += currentHeight + verticalSpacing
                currentItems = []
                currentX = 0
                currentHeight = 0
            }

            let x = currentItems.isEmpty ? 0 : currentX + horizontalSpacing
            currentItems.append(Item(index: index, x: x, size: size))
            currentX = x + size.width
            currentHeight = max(currentHeight, size.height)
        }

        if !currentItems.isEmpty {
            rows.append(Row(y: y, height: currentHeight, items: currentItems))
            widestRow = max(widestRow, currentX)
        }

        let totalHeight = rows.last.map { $0.y + $0.height } ?? 0
        return (rows, CGSize(width: min(widestRow, maxWidth), height: totalHeight))
    }

    private func size(for subview: LayoutSubview, maxWidth: CGFloat) -> CGSize {
        let naturalSize = subview.sizeThatFits(.unspecified)

        guard naturalSize.width > maxWidth else {
            return naturalSize
        }

        return subview.sizeThatFits(ProposedViewSize(width: maxWidth, height: nil))
    }

    private struct Row {
        let y: CGFloat
        let height: CGFloat
        let items: [Item]
    }

    private struct Item {
        let index: Int
        let x: CGFloat
        let size: CGSize
    }
}

struct AIReviewView: View {
    @EnvironmentObject private var store: AppStore
    let sessionId: UUID
    @State private var selectedCandidates: Set<Int> = []
    @State private var feedback = ""
    @State private var finalComment = ""

    var body: some View {
        Form {
            if let session = store.session(id: sessionId) {
                Section("5つの説明候補") {
                    if store.isGenerating && session.candidateComments.isEmpty {
                        ProgressView("候補を生成中")
                    }
                    ForEach(Array(session.candidateComments.enumerated()), id: \.offset) { index, candidate in
                        Button {
                            toggleCandidateSelection(index: index, session: session)
                        } label: {
                            HStack(alignment: .top) {
                                Image(systemName: selectedCandidates.contains(index) ? "checkmark.circle.fill" : "circle")
                                Text(candidate)
                                    .foregroundStyle(.primary)
                            }
                        }
                    }
                    Button {
                        Task { await store.generateCandidates(sessionId: sessionId) }
                    } label: {
                        Label("5候補を再生成", systemImage: "arrow.clockwise")
                    }
                    .disabled(store.isGenerating)
                }

                Section("再生成用テキスト") {
                    HStack {
                        Button("短く") { appendFeedbackPreset("もっと短く。") }
                        Button("詳しく") { appendFeedbackPreset("具体的な要素を少し追加。") }
                        Button("自然に") { appendFeedbackPreset("より自然な言い回しに。") }
                    }
                    .buttonStyle(.borderless)
                    TextEditor(text: $feedback)
                        .frame(minHeight: 140)
                    Button {
                        saveFeedbackAndFinal()
                        Task { await store.generateFinalReview(sessionId: sessionId, selectedCandidateIndexes: selectedCandidates) }
                    } label: {
                        if store.isGenerating {
                            ProgressView()
                        } else {
                            Label("選択してまとめる", systemImage: "text.bubble")
                        }
                    }
                    .disabled(store.isGenerating || session.candidateComments.isEmpty)
                }

                Section("現在のレビューコメント案") {
                    TextEditor(text: $finalComment)
                        .frame(minHeight: 160)
                    Text("\(finalComment.count)文字")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                Section("生成履歴") {
                    ForEach(session.drafts) { draft in
                        VStack(alignment: .leading, spacing: 4) {
                            Text("\(draft.provider.label) / \(draft.model)")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                            Text(draft.text)
                                .lineLimit(3)
                        }
                    }
                }

                Section {
                    Button {
                        saveFeedbackAndFinal()
                        store.path.append(.finalConfirmation(sessionId))
                    } label: {
                        Label("これで確定", systemImage: "checkmark")
                    }
                    .disabled(finalComment.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                }
            } else {
                ContentUnavailableView("レビューセッションがありません", systemImage: "questionmark.circle")
            }
        }
        .navigationTitle("AIレビュー作成")
        .onAppear {
            store.refreshFinalPromptIfDefault(sessionId: sessionId)
            if let session = store.session(id: sessionId) {
                feedback = session.finalGenerationText
                finalComment = session.finalComment
            }
        }
        .onChange(of: store.session(id: sessionId)?.finalComment ?? "") { _, newValue in
            finalComment = newValue
        }
        .onDisappear {
            saveFeedbackAndFinal()
        }
    }

    private func saveFeedbackAndFinal() {
        guard var session = store.session(id: sessionId) else { return }
        session.finalGenerationText = feedback
        session.finalComment = finalComment
        store.updateSession(session)
    }

    private func appendFeedbackPreset(_ preset: String) {
        let trimmed = feedback.trimmingCharacters(in: .whitespacesAndNewlines)
        feedback = trimmed.isEmpty ? preset : "\(trimmed)\n\(preset)"
    }

    private func toggleCandidateSelection(index: Int, session: ReviewSession) {
        if selectedCandidates.contains(index) {
            selectedCandidates.remove(index)
        } else {
            selectedCandidates.insert(index)
        }

        guard selectedCandidates.count == 1,
              let selectedIndex = selectedCandidates.first,
              session.candidateComments.indices.contains(selectedIndex) else {
            return
        }

        finalComment = session.candidateComments[selectedIndex]
    }
}

struct FinalConfirmationView: View {
    @EnvironmentObject private var store: AppStore
    let sessionId: UUID

    var body: some View {
        Form {
            if let session = store.session(id: sessionId), let wine = store.wine(id: session.wineId) {
                Section("保存内容") {
                    Text(wine.name)
                    DetailRow("Rating", session.rating)
                    DetailRow("評価", session.evaluation ? "オン" : "オフ")
                    DetailRow("Stock", session.markOutOfStock ? "falseへ更新" : "変更しない")
                    DetailRow("tasting date", dateText(session.tastingDate))
                }
                Section("最終コメント") {
                    Text(session.finalComment)
                }
                if let result = store.lastSaveResult, !result.succeeded {
                    Section("保存エラー") {
                        ForEach(result.failures) { failure in
                            Text("\(failure.operation): \(failure.message)")
                        }
                    }
                }
                Section {
                    Button {
                        Task { await store.saveReview(sessionId: sessionId) }
                    } label: {
                        if store.isSaving {
                            ProgressView()
                        } else {
                            Label("Notionへ保存", systemImage: "square.and.arrow.down")
                        }
                    }
                    .disabled(store.isSaving)
                }
            } else {
                ContentUnavailableView("保存対象がありません", systemImage: "questionmark.circle")
            }
        }
        .navigationTitle("最終確認")
    }
}

struct SaveCompleteView: View {
    @EnvironmentObject private var store: AppStore
    @Environment(\.openURL) private var openURL
    let wineId: String

    var body: some View {
        VStack(spacing: 18) {
            Image(systemName: "checkmark.circle.fill")
                .font(.system(size: 64))
                .foregroundStyle(.green)
            Text("保存が完了しました")
                .font(.title2.bold())
            if let session = store.sessions.values.first(where: { $0.wineId == wineId }) {
                Text(session.finalComment)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                    .lineLimit(4)
            }
            Button {
                if let url = store.wine(id: wineId)?.notionUrl {
                    openURL(url)
                }
            } label: {
                Label("Notionで開く", systemImage: "arrow.up.right.square")
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.bordered)
            Button {
                store.path = [.inventory]
                Task { await store.loadInventory(forceRefresh: true) }
            } label: {
                Label("在庫一覧へ戻る", systemImage: "list.bullet")
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.borderedProminent)
        }
        .padding()
        .readableContent(maxWidth: 640)
        .navigationTitle("保存完了")
        .navigationBarBackButtonHidden()
    }
}

struct SettingsView: View {
    @EnvironmentObject private var store: AppStore

    var body: some View {
        Form {
            Section("Notion") {
                SecureField("Notion API Key", text: $store.settings.notionApiKey)
                TextField("Wine Tracker Database ID", text: $store.settings.notionDatabaseId)
                    .textInputAutocapitalization(.never)
            }
            Section("生成AI") {
                Picker("Provider", selection: $store.settings.aiProvider) {
                    ForEach(AIProvider.allCases) { provider in
                        Text(provider.label).tag(provider)
                    }
                }
                SecureField("OpenAI API Key", text: $store.settings.openAIAPIKey)
                TextField("OpenAI Model", text: $store.settings.openAIModel)
                    .textInputAutocapitalization(.never)
                SecureField("Gemini API Key", text: $store.settings.geminiAPIKey)
                TextField("Gemini Model", text: $store.settings.geminiModel)
                    .textInputAutocapitalization(.never)
            }
            Section("プロパティマッピング") {
                TextField("Title", text: $store.settings.propertyMapping.title)
                TextField("Stock", text: $store.settings.propertyMapping.stock)
                TextField("Rating", text: $store.settings.propertyMapping.rating)
                TextField("評価", text: $store.settings.propertyMapping.evaluation)
                TextField("Type", text: $store.settings.propertyMapping.type)
                TextField("Country", text: $store.settings.propertyMapping.country)
                TextField("Region", text: $store.settings.propertyMapping.region)
                TextField("Cave", text: $store.settings.propertyMapping.cave)
                TextField("Cepage", text: $store.settings.propertyMapping.cepage)
                TextField("Price", text: $store.settings.propertyMapping.price)
                TextField("Detail", text: $store.settings.propertyMapping.detail)
                TextField("tasting date", text: $store.settings.propertyMapping.tastingDate)
                TextField("Purchase date", text: $store.settings.propertyMapping.purchaseDate)
            }
            Section("定型文") {
                Text("定型テキスト1")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                TextEditor(text: $store.settings.template1)
                    .frame(minHeight: 110)
                Text("定型テキスト2")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                TextEditor(text: $store.settings.template2)
                    .frame(minHeight: 90)
                Stepper("再生成上限: \(store.settings.maxRegenerationCount)", value: $store.settings.maxRegenerationCount, in: 1...30)
            }
            Section {
                Button {
                    store.saveSettings()
                    Task { await store.loadInventory(forceRefresh: true) }
                } label: {
                    Label("保存して接続", systemImage: "checkmark.circle")
                }
            }
        }
        .navigationTitle("設定")
    }
}

struct DetailRow: View {
    let title: String
    let value: String?

    init(_ title: String, _ value: String?) {
        self.title = title
        self.value = value
    }

    var body: some View {
        HStack(alignment: .firstTextBaseline) {
            Text(title)
                .foregroundStyle(.secondary)
            Spacer()
            Text(value?.isEmpty == false ? value! : "未設定")
                .multilineTextAlignment(.trailing)
        }
    }
}

func dateText(_ date: Date) -> String {
    let formatter = DateFormatter()
    formatter.locale = Locale(identifier: "ja_JP")
    formatter.dateStyle = .medium
    formatter.timeStyle = .none
    return formatter.string(from: date)
}

private struct ReadableContentModifier: ViewModifier {
    let maxWidth: CGFloat

    func body(content: Content) -> some View {
        content
            .frame(maxWidth: maxWidth)
            .frame(maxWidth: .infinity)
    }
}

private extension View {
    func readableContent(maxWidth: CGFloat = 720) -> some View {
        modifier(ReadableContentModifier(maxWidth: maxWidth))
    }
}
