# LINE WORKS Bot Server

LINE WORKS Bot Server は、LINE WORKS のボットサービスと連携する FastAPI ベースの Webhook サーバーアプリケーションです。このサーバーは、ユーザーからのメッセージを受け取り、Anthropic Claude API と Salesforce Einstein Agent API を活用して、キャリアアドバイザーボットとして機能します。

## アプリケーション概要

このアプリケーションは以下の主要機能を提供します：

- LINE WORKS からの Webhook イベント受信と署名検証
- ユーザーメッセージの要約（Anthropic Claude API 使用）
- Salesforce Einstein Agent API との連携によるインテリジェントな応答生成
- Anthropic Claude API を使用した自然な会話応答の生成
- LINE WORKS へのメッセージ送信（リトライロジック付き）
- Redis を使用したセッション管理とトークンキャッシュ

## 技術スタック

### バックエンド

- **言語**: Python 3.11
- **Web フレームワーク**: FastAPI
- **ASGI サーバー**: Uvicorn
- **HTTP クライアント**: httpx

### AI・機械学習

- **テキスト生成**: Anthropic Claude API
- **エージェント**: Salesforce Einstein Agent API

### データストレージ

- **キャッシュ/セッション管理**: Redis

### 認証・セキュリティ

- **JWT**: PyJWT, cryptography
- **署名検証**: hmac, hashlib

### デプロイメント

- **コンテナ化**: Docker, Docker Compose

## ディレクトリ構成

```
line-works-bot-server/
├── app/                      # アプリケーションコード
│   ├── anthropic.py          # Anthropic Claude API連携
│   ├── logger_config.py      # ロギング設定
│   ├── main.py               # メインアプリケーションエントリーポイント
│   └── salesforce_client.py  # Salesforce API連携
├── .env                      # 環境変数設定ファイル
├── .gitignore                # Gitの除外ファイル設定
├── docker-compose.yml        # Docker Compose設定
├── Dockerfile                # Dockerイメージ定義
├── private.key               # LINE WORKS API認証用の秘密鍵
├── README.md                 # このドキュメント
└── requirements.txt          # 依存ライブラリ
```

## 主要コンポーネント

### 1. LINE WORKS 連携 (main.py)

- LINE WORKS の Webhook イベント処理
- JWT 認証によるアクセストークン取得
- メッセージ送信機能

### 2. Anthropic 連携 (anthropic.py)

- ユーザーメッセージの要約
- Salesforce Agent 応答からの自然な会話応答生成
- 直接的な AI 応答生成（フォールバック用）

### 3. Salesforce 連携 (salesforce_client.py)

- OAuth 2.0 クライアントクレデンシャルズフローによる認証
- Einstein Agent API との連携
- セッション管理とシーケンス ID 追跡

### 4. Redis 統合

- アクセストークンのキャッシュ
- セッション情報の保存
- 分散環境でのデータ共有

## 環境構築

### 必要なもの

- Docker
- Docker Compose

### 環境変数の設定

`.env`ファイルを作成し、必要な環境変数を設定してください：

```
# LINE WORKS API設定
LW_API_ID=your_api_id
LW_API_BOT_ID=your_bot_id
LW_API_BOT_SECRET=your_bot_secret
LW_API_SERVICE_ACCOUNT=your_service_account
LW_API_PRIVATEKEY_PATH=private.key
CLIENT_ID=your_client_id
CLIENT_SECRET=your_client_secret

# 署名検証モード設定
# strict: 署名検証に失敗した場合はリクエストを拒否（本番環境向け、デフォルト）
# warn: 署名検証に失敗した場合は警告ログを出力するが処理は続行（開発/テスト環境向け）
# skip: 署名検証を完全にスキップ（ローカル開発環境向け）
SIGNATURE_VERIFICATION_MODE=strict

# Anthropic API設定
ANTHROPIC_API_KEY=your_anthropic_api_key
ANTHROPIC_MODEL=claude-3-5-sonnet-20240620

# Salesforce設定
SF_CLIENT_ID=your_sf_client_id
SF_CLIENT_SECRET=your_sf_client_secret
SF_BASE_URL=your_sf_base_url
SF_API_VERSION=v59.0
SF_AGENT_ID=your_agent_id
```

また、`private.key`ファイルをプロジェクトルートに配置してください。これは LINE WORKS API の認証に使用されます。

## 起動方法

### 通常の起動（開発環境）

```bash
uvicorn app.main:app --host 0.0.0.0 --port 8000 --reload
```

### Docker を使用した起動

```bash
docker-compose up -d

# 外部からアクセスするためのトンネリング（オプション）
ngrok http http://localhost:8000
```

サーバーは http://localhost:8000 でアクセスできます。

## API エンドポイント

- `GET /`: ヘルスチェックエンドポイント
- `POST /callback`: LINE WORKS からの Webhook を受け取るエンドポイント

## Redis 統合

このアプリケーションは Redis を使用してアクセストークンとセッション情報をキャッシュします。これにより、複数のワーカーがある場合でもデータを共有できます。

### Redis サーバーへのアクセス方法

#### redis-cli を使用する方法

1. redis-cli をインストールする（Docker を使用している場合は不要）

```bash
# Ubuntu の場合
sudo apt-get install redis-tools

# macOS の場合（Homebrew を使用）
brew install redis
```

2. Docker で実行している Redis サーバーに接続する

```bash
redis-cli -h localhost -p 6379
```

3. 基本的な Redis コマンド

```
# キーの一覧を表示
KEYS *

# 特定のプレフィックスを持つキーを表示
KEYS lw_bot:*
KEYS sf_agent:*

# キーの値を取得
GET lw_bot:access_token

# キーの有効期限（秒）を確認
TTL lw_bot:access_token
```

### Redis に保存されるデータ

このアプリケーションでは、以下のキーが Redis に保存されます：

- `lw_bot:access_token`: LINE WORKS API のアクセストークン
- `lw_bot:expires_at`: アクセストークンの有効期限（UNIX タイムスタンプ）
- `sf_agent:session:{user_id}`: Salesforce Agent セッション情報
- `sf_agent:sequence:{session_id}`: メッセージシーケンス ID

セッション情報は、1 回の問い合わせ単位で生成され、セッションが切れるまで（デフォルトでは 1 時間）同じキーが再利用されます。これにより、複数のリクエストにわたって同じセッションを維持できます。

## 開発とデバッグ

### ログの確認

アプリケーションのログは標準出力に出力されます。Docker Compose を使用している場合は、以下のコマンドでログを確認できます：

```bash
docker-compose logs -f api
```

### 環境変数の更新

環境変数を更新した場合は、アプリケーションを再起動する必要があります：

```bash
docker-compose down
docker-compose up -d
```

## セキュリティ上の注意点

- `private.key`ファイルは機密情報です。適切に保護し、リポジトリにコミットしないでください。
- 環境変数ファイル(`.env`)も機密情報を含むため、リポジトリにコミットしないでください。
- 本番環境では、適切なネットワークセキュリティ対策を講じてください。
- 本番環境では`SIGNATURE_VERIFICATION_MODE`を`strict`に設定し、署名検証を厳格に行ってください。`warn`や`skip`モードは開発環境でのみ使用してください。
