# Wine Review

Wine Reviewは、Notionで管理しているワイン在庫からレビュー対象を選び、生成AIを使ってテイスティングレビューを作成するSwiftUI製のユニバーサルアプリです。iPhoneとiPadの両方で動作します。

NotionのWine Trackerデータベースから在庫ありワインを取得し、OpenAIまたはGeminiでレビュー文を生成したうえで、最終コメント、Rating、試飲日、在庫状態をNotionへ書き戻します。

## 主な機能

- Notionデータベースで`Stock`がチェックされているワインを一覧表示
- 購入日、ワイン名、価格による検索・並び替え
- ワイン詳細を確認してからレビュー作成へ進行
- 生成AIで5つのレビュー候補を作成
- 候補とフィードバックをもとに短い最終レビューを作成
- 最終レビュー、Rating、試飲日、在庫更新をNotionへ保存
- iPhoneとiPadに対応
- M4 iPad Proなどの大きい画面ではグリッドレイアウトを使用

## 必要なもの

- Xcode 16以降
- iOS 17.0以降
- Notion Integration Token
- NotionのWine Trackerデータベース
- OpenAI APIキーまたはGemini APIキー

## プロジェクト構成

```text
WineReview.xcodeproj
WineReview/
  AppDefaults.env
  AIReview.swift
  AppStore.swift
  Config.swift
  Models.swift
  Notion.swift
  Views.swift
  WineReviewApp.swift
WineReviewTests/
  SettingsRegressionTests.swift
docs/
```

## 設定

アプリを起動したら、設定画面で以下を入力します。

- Notion APIキー
- Wine Tracker DB ID
- 生成AIプロバイダ
- OpenAI APIキーとモデル、またはGemini APIキーとモデル
- Notionプロパティマッピング
- 定型テキスト1、定型テキスト2

生成AIプロバイダは`openai`または`gemini`です。OpenAIとGeminiは、利用する方のAPIキーとモデルが設定されていれば動作します。両方を設定しておくこともできます。

### .envの扱い

`.env`はローカル開発用の非公開ファイルです。Git管理対象に含めず、XcodeプロジェクトのResourceにも追加しません。

必要なキー名を確認したい場合は、`.env.example`を参照してください。実際の値は設定画面へ入力します。

```dotenv
NOTION_API_KEY=your_notion_api_key
NOTION_WINE_TRACKER_DATABASE_ID=your_wine_tracker_database_id

OPENAI_API_KEY=your_openai_api_key
OPENAI_MODEL=gpt-4.1-mini

GEMINI_API_KEY=your_gemini_api_key
GEMINI_MODEL=gemini-1.5-pro

GENAI_PROVIDER=openai
```

### 定型テキストの初期値

`WineReview/AppDefaults.env`には、秘密情報を含まない定型テキストの初期値だけを置きます。

```dotenv
WINE_REVIEW_TEMPLATE_1="このワインのテースティングの良い評価として５つの説明候補をあげてください\n言い振りは、ワイン中級者が販売店ソムリエに評価をつたえるためのレビューにしてください"
WINE_REVIEW_TEMPLATE_2="コメント案をまとめて160文字くらいのレビューコメントにしてください。"
```

このファイルはアプリに同梱され、初回起動時や設定の初期値として使われます。APIキーやDB IDなどの秘密情報は含めません。

## Notionデータベース

アプリは、次のようなプロパティを持つNotionデータベースを想定しています。

| プロパティ | 型 | 用途 |
| --- | --- | --- |
| Name / Title | title | ワイン名 |
| Stock | checkbox | 在庫状態 |
| Rating | selectまたはtext | 評価 |
| Type | select | 赤、白、泡など |
| Country | select | 生産国 |
| Region | select | 生産地域 |
| Cave | select | 購入店、セラー、保管場所 |
| Cepage | multi-select | 品種 |
| Price | number | 価格 |
| Detail | rich text | 既存メモ |
| tasting date | date | 試飲日 |
| Purchase date | date | 購入日 |

プロパティ名が異なる場合は、アプリの設定画面でマッピングを変更できます。

## アプリの起動

Xcodeでプロジェクトを開きます。

```sh
open WineReview.xcodeproj
```

`WineReview`スキームを選び、iPhoneまたはiPadのシミュレータ・実機で実行します。

コマンドラインでコード署名なしのビルド確認を行う場合は、次のコマンドを使います。

```sh
xcodebuild -project WineReview.xcodeproj \
  -scheme WineReview \
  -destination generic/platform=iOS \
  -derivedDataPath DerivedData/BuildCheck \
  CODE_SIGNING_ALLOWED=NO \
  build
```

## テスト

プロンプト設定まわりのリグレッションテストを含めています。

- `AppDefaults.env`から`WINE_REVIEW_TEMPLATE_2`を読み込めること
- バンドルされる定型テキスト初期値にAPIキーが含まれないこと
- 旧デフォルトの最終プロンプトを持つ既存セッションが更新されること
- ユーザーが編集した最終プロンプトは上書きされないこと

利用可能なシミュレータを指定してテストを実行します。

```sh
xcodebuild -project WineReview.xcodeproj \
  -scheme WineReview \
  -destination 'platform=iOS Simulator,name=iPhone 17,OS=26.4.1' \
  -derivedDataPath DerivedData/TestRun \
  CODE_SIGNING_ALLOWED=NO \
  test
```

テストのコンパイルだけ確認する場合は、次のコマンドを使います。

```sh
xcodebuild -project WineReview.xcodeproj \
  -scheme WineReview \
  -destination generic/platform=iOS \
  -derivedDataPath DerivedData/TestBuild \
  CODE_SIGNING_ALLOWED=NO \
  build-for-testing
```

## セキュリティ

- `.env`やAPIキーを含むファイルはコミットしない
- `.env.example`には実キーに見える値を書かない
- `AppDefaults.env`には定型テキストだけを置く
- APIキーやDB IDをログに出力しない
- 公開配布する場合は、Notionや生成AI APIの呼び出しをバックエンド経由にし、クライアントアプリにAPIキーを持たせない

## ドキュメント

- [アプリ仕様書](docs/wine-review-ios-app-spec.md)
- [技術説明書](docs/wine-review-ios-technical-design.md)
