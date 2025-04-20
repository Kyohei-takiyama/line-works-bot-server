# LINE WORKS Bot Server

LINE WORKS Bot Server は FastAPI を使用した Webhook サーバーで、LINE WORKS のボットメッセージを処理し、Anthropic API を使用して応答を生成します。

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

# Anthropic API設定
ANTHROPIC_API_KEY=your_anthropic_api_key
ANTHROPIC_MODEL=claude-3-haiku-20240307

# Salesforce設定（必要な場合）
SF_CLIENT_ID=your_sf_client_id
SF_CLIENT_SECRET=your_sf_client_secret
SF_TOKEN_URL=your_sf_token_url
SF_API_VERSION=v59.0
```

また、`private.key`ファイルをプロジェクトルートに配置してください。

## 起動方法

### 通常の起動（開発環境）

```bash
uvicorn app.main:app --host 0.0.0.0 --port 8000 --reload
```

### Docker を使用した起動

```bash
docker-compose up -d
```

サーバーは http://localhost:8000 でアクセスできます。

## API エンドポイント

- `GET /`: ヘルスチェックエンドポイント
- `POST /callback`: LINE WORKS からの Webhook を受け取るエンドポイント

## Redis 統合

このアプリケーションは Redis を使用してアクセストークンをキャッシュします。これにより、複数のワーカーがある場合でもトークンを共有できます。

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

# キーの値を取得
GET lw_bot:access_token

# キーの有効期限（秒）を確認
TTL lw_bot:access_token
```

### Redis に保存されるデータ

このアプリケーションでは、以下のキーが Redis に保存されます：

- `lw_bot:access_token`: LINE WORKS API のアクセストークン
- `lw_bot:expires_at`: アクセストークンの有効期限（UNIX タイムスタンプ）
- `sf_agent:session_key:{agent_id}`: Salesforce Copilot Agent のセッションキー
- `sf_agent:session_id:{agent_id}`: Salesforce Copilot Agent のセッション ID

セッションキーとセッション ID は、1 回の問い合わせ単位で生成され、セッションが切れるまで（デフォルトでは 1 時間）同じキーが再利用されます。これにより、複数のリクエストにわたって同じセッションを維持できます。
