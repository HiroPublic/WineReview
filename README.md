# Wine Review

Wine Reviewは、Notionで管理しているワイン在庫からレビュー対象を選び、生成AIを使ってテイスティングレビューを作成するSwiftUI製のユニバーサルアプリです。iPhoneとiPadの両方で動作します。

NotionのWine Trackerデータベースから在庫ありワインを取得し、OpenAIまたはGeminiでレビュー文を生成したうえで、最終コメント、Rating、試飲日、在庫状態をNotionへ書き戻します。S05では、ワインタイプ別のスライダー入力、印象タグ、料理相性タグ、自由メモを使って、AIへ渡すテースティング情報を構造化して入力できます。

レビュー文の言語化イメージを深める参考として、[「美味しい」の先を言葉にしたい | 南アフリカワインのティスティング言語化トレーニング](https://note.com/dr830821/n/nc06edfb216da) も参照できます。

## 主な機能

- Notionデータベースで`Stock`がチェックされているワインを一覧表示
- 購入日、ワイン名、価格による検索・並び替え
- ワイン詳細を確認してからレビュー作成へ進行
- タイプ別スライダーと印象タグでテースティング情報を構造化入力
- 料理相性タグの折りたたみ入力と自由メモ入力
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

S05の入力内容は次のように扱います。

- ワイン概要はNotion取得値を表示専用で表示
- Ratingと試飲日はS04で入力済みの値を表示
- ワインタイプに応じて7項目までのスライダーを1から5で入力
- 印象タグは最大3個、料理相性タグは最大2個まで選択
- 自由メモは任意入力
- これらの内容をAIプロンプトへ構造化して渡す

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

## レビュー作成フロー

1. 在庫ワイン一覧から対象ワインを選ぶ
2. S04でRating、評価補足、試飲日、在庫更新方針を入力する
3. S05でテースティング入力を行う
4. AIで5つのレビュー候補を作成する
5. 候補を選び、160文字前後の最終レビューへまとめる
6. Notionへ保存する

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

### 実機アプリの署名期限更新

Xcodeのローカル/限定的な開発用署名では、実機に入れたアプリが短期間で失効する場合があります。現在の署名期限を確認し、残り日数が少なければ自動で再ビルドして実機へ再インストールするには、次のコマンドを使います。

```sh
python3 scripts/refresh_ios_profile.py --threshold-days 2 --device-name "Your iPhone Name"
```

動作確認だけを行う場合は`--dry-run`を付けます。

```sh
python3 scripts/refresh_ios_profile.py --threshold-days 2 --device-name "Your iPhone Name" --dry-run
```

ビルドとインストールが完了してもprofile期限が延びなかった場合は、同じ期限に対して12時間は再試行しません。

ログイン時、1時間ごと、8:30に自動実行するLaunchAgentを作成する場合は、次のコマンドを使います。

```sh
python3 scripts/install_profile_refresh_agent.py --device-name "Your iPhone Name" --load
```

生成されるplistを確認するだけなら`--dry-run`を付けます。

```sh
python3 scripts/install_profile_refresh_agent.py --device-name "Your iPhone Name" --dry-run
```

端末名をコマンドに残したくない場合は、`WINE_REVIEW_DEVICE_NAME`または`WINE_REVIEW_DEVICE_ID`を環境変数で指定できます。

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

# License

This project is licensed under the MIT License - see the LICENSE file for details.

## Author

Copyright (c) 2026 HiroPublic

This project was developed with assistance from generative AI.
