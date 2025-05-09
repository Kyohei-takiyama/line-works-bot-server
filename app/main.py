# main.py
import os
import json
from pathlib import Path
import time
import hmac
import hashlib
import base64
import logging
import asyncio

import httpx
import jwt
import redis.asyncio as redis
from cryptography.hazmat.primitives import serialization
from cryptography.hazmat.primitives.asymmetric import padding
from cryptography.hazmat.primitives import (
    hashes,
)  # JWT署名アルゴリズム検証用ではないが、一般的なハッシュ操作で使う可能性あり

from fastapi import FastAPI, Request, Header, HTTPException, status, Depends
from fastapi.responses import JSONResponse
from dotenv import load_dotenv
from .logger_config import setup_logger
from .anthropic import call_anthropic_api
from .salesforce_client import SalesforceClient
from .anthropic import (
    summarize_message,
    generate_response_from_agent_reply,
)


# --- 定数 ---
# BASE_API_URL = "https://www.worksapis.com/v1.0" # メッセージ送信時に直接組み立てる
BASE_AUTH_URL = "https://auth.worksmobile.com/b"  # Server Token 取得用 Base URL
DEFAULT_SCOPE = "bot"  # アクセストークンのデフォルトスコープ
RETRY_COUNT_MAX = 3  # リトライ最大回数 (元のコードより少し減らす)
RETRY_WAIT_BASE = 1  # リトライ待機時間の基本秒数 (2の冪乗)

# --- 環境変数読み込み ---
load_dotenv()
LW_API_ID = os.getenv("LW_API_ID")
LW_API_BOT_ID = os.getenv("LW_API_BOT_ID")
LW_API_BOT_SECRET = os.getenv("LW_API_BOT_SECRET")
LW_API_SERVICE_ACCOUNT = os.getenv("LW_API_SERVICE_ACCOUNT")
LW_API_PRIVATEKEY_PATH = os.getenv("LW_API_PRIVATEKEY_PATH")
SCOPE = os.getenv("SCOPE", DEFAULT_SCOPE)
CLIENT_ID = os.getenv("CLIENT_ID")
CLIENT_SECRET = os.getenv("CLIENT_SECRET")

# 署名検証モード: strict（厳格）, warn（警告のみ）, skip（スキップ）
SIGNATURE_VERIFICATION_MODE = os.getenv("SIGNATURE_VERIFICATION_MODE", "strict").lower()

# Redis設定
REDIS_HOST = os.getenv("REDIS_HOST", "localhost")
REDIS_PORT = int(os.getenv("REDIS_PORT", "6379"))
REDIS_DB = int(os.getenv("REDIS_DB", "0"))
REDIS_PREFIX = "lw_bot:"  # Redisキーのプレフィックス

# 環境変数チェック (重要なものがなければ起動時にエラー)
required_env_vars = {
    "LW_API_ID": LW_API_ID,
    "LW_API_BOT_ID": LW_API_BOT_ID,
    "LW_API_BOT_SECRET": LW_API_BOT_SECRET,
    "LW_API_SERVICE_ACCOUNT": LW_API_SERVICE_ACCOUNT,
    "LW_API_PRIVATEKEY_PATH": LW_API_PRIVATEKEY_PATH,
}
missing_vars = [k for k, v in required_env_vars.items() if v is None]
if missing_vars:
    raise EnvironmentError(
        f"Missing required environment variables: {', '.join(missing_vars)}"
    )

# --- ロガー設定 ---
setup_logger()
logger = logging.getLogger(__name__)

# 環境変数のログ出力 (デバッグ用)
logger.info(
    f"Environment Variables: LW_API_ID={LW_API_ID}, LW_API_BOT_ID={LW_API_BOT_ID}, LW_API_SERVICE_ACCOUNT={LW_API_SERVICE_ACCOUNT}"
)
# ログ出力の確認 (デバッグ用)
logger.info(
    f"Anthropic API Key: {os.getenv('ANTHROPIC_API_KEY')}, Model: {os.getenv('ANTHROPIC_MODEL')}"
)

# --- FastAPI アプリケーションインスタンス ---
app = FastAPI(title="LINE WORKS Bot Server (Inspired)", version="0.2.0")

# --- Redis接続 ---
# Redisクライアントをグローバル変数として初期化
redis_client = None
# SalesforceClientインスタンスをグローバル変数として初期化
sf_client = None


@app.on_event("startup")
async def startup_db_client():
    global redis_client, sf_client
    redis_client = redis.Redis(
        host=REDIS_HOST,
        port=REDIS_PORT,
        db=REDIS_DB,
        decode_responses=True,  # 文字列をUTF-8でデコード
    )
    logger.info(f"Redis connection established to {REDIS_HOST}:{REDIS_PORT}/{REDIS_DB}")

    # SalesforceClientの初期化
    sf_client = SalesforceClient()
    # RedisクライアントをSalesforceClientに設定
    await sf_client.set_redis_client(redis_client)
    logger.info("SalesforceClient initialized with Redis client")


@app.on_event("shutdown")
async def shutdown_db_client():
    global redis_client, sf_client
    if redis_client:
        await redis_client.close()
        logger.info("Redis connection closed")

    if sf_client:
        await sf_client.close()
        logger.info("SalesforceClient closed")


# --- LINE WORKS API 連携ヘルパー関数 ---


async def validate_request(body_raw: bytes, signature: str, bot_secret: str) -> bool:
    """Webhookリクエストの署名を検証する"""
    # 署名検証モードがskipの場合は常にTrueを返す（ローカル開発環境用）
    if SIGNATURE_VERIFICATION_MODE == "skip":
        logger.info(
            "Signature validation skipped due to SIGNATURE_VERIFICATION_MODE=skip"
        )
        return True

    if signature is None:
        logger.warning("Missing X-Works-Signature header.")
        return False
    if not bot_secret:
        logger.error("LW_API_BOT_SECRET is not configured. Cannot validate signature.")
        # 本番環境では False を返すか、エラーを発生させるべき
        return False  # または raise ValueError("Bot Secret not configured")

    try:
        hashed = hmac.new(bot_secret.encode("utf-8"), body_raw, hashlib.sha256).digest()
        expected_signature = base64.b64encode(hashed).decode("utf-8")
        is_valid = hmac.compare_digest(expected_signature, signature)
        if not is_valid:
            logger.warning(
                f"Invalid signature. Expected: {expected_signature}, Got: {signature}"
            )
        return is_valid
    except Exception as e:
        logger.exception(f"Error during signature validation: {e}")
        return False


async def get_access_token() -> str:
    """
    Service Account 認証 (JWT) を使用してアクセストークンを取得またはRedisキャッシュから返す。
    (LINE WORKS 公式ドキュメント準拠)
    """
    global redis_client
    current_time = time.time()

    # Redisからトークン情報を取得
    token_key = f"{REDIS_PREFIX}access_token"
    expires_key = f"{REDIS_PREFIX}expires_at"

    access_token = await redis_client.get(token_key)
    expires_at_str = await redis_client.get(expires_key)
    expires_at = float(expires_at_str) if expires_at_str else 0

    # キャッシュが有効かチェック (有効期限の60秒前になったら更新)
    if access_token and current_time < (expires_at - 60):
        logger.info("Using cached access token from Redis.")
        return access_token

    logger.info("Attempting to get new access token using Service Account JWT.")

    # Private Keyの読み込み
    try:
        logger.info(f"Reading private key from {LW_API_PRIVATEKEY_PATH}")
        current_dir = Path.cwd()
        key_path_obj = current_dir / LW_API_PRIVATEKEY_PATH
        logger.info(f"Resolved private key path: {key_path_obj.resolve()}")
        with open(key_path_obj.resolve(), "rb") as key_file:
            private_key_data = key_file.read()
            # PEM形式の秘密鍵をロード
            private_key = serialization.load_pem_private_key(
                private_key_data,
                password=None,  # パスワードがない場合
            )
    except FileNotFoundError as e:
        logger.error(f"Private key file not found at {LW_API_PRIVATEKEY_PATH} : {e}")
        return None
    except Exception as e:
        logger.error(f"Error reading or parsing private key: {e}")
        return None

    # --- JWTペイロード作成 ---
    issued_at = int(current_time)
    expires_in = 3600  # 1時間
    jwt_payload = {
        "iss": CLIENT_ID,  # ★ Client ID を使う
        "sub": LW_API_SERVICE_ACCOUNT,  # ★ Service Account ID を使う
        "iat": issued_at,
        "exp": issued_at + expires_in,
    }

    # --- JWT生成と署名 ---
    try:
        # pyjwt は秘密鍵オブジェクトを直接受け取れる (cryptography のキーオブジェクト)
        generated_jwt = jwt.encode(jwt_payload, private_key, algorithm="RS256")
        logger.info("JWT generated and signed successfully.")
    except Exception as e:
        logger.error(f"Error generating or signing JWT: {e}")
        return None

    # --- Access Token 発行リクエスト ---
    token_url = "https://auth.worksmobile.com/oauth2/v2.0/token"  # ★ 公式エンドポイント
    headers = {
        "Content-Type": "application/x-www-form-urlencoded; charset=UTF-8",
    }
    data = {
        "assertion": generated_jwt,  # 生成したJWT
        "grant_type": "urn:ietf:params:oauth:grant-type:jwt-bearer",  # 固定値
        "client_id": CLIENT_ID,  # ★ Client ID
        "client_secret": CLIENT_SECRET,  # ★ Client Secret
        "scope": SCOPE,  # 必要なスコープ
    }

    async with httpx.AsyncClient() as client:
        try:
            response = await client.post(token_url, headers=headers, data=data)
            response.raise_for_status()  # HTTPエラーがあれば例外発生
            token_data = response.json()

            if "access_token" not in token_data:
                logger.error(f"Access token not found in response: {token_data}")
                return None
            logger.info(f"Access token obtained successfully. {token_data}")
            # Redisキャッシュを更新
            access_token = token_data["access_token"]
            # expires_in を取得し、安全に int に変換してから加算
            expires_in_value = token_data.get("expires_in", "3600")
            expires_at = current_time + int(expires_in_value)

            # Redisに保存
            token_key = f"{REDIS_PREFIX}access_token"
            expires_key = f"{REDIS_PREFIX}expires_at"

            await redis_client.set(token_key, access_token)
            await redis_client.set(expires_key, str(expires_at))
            # 有効期限よりも少し長めにRedisのキー自体の有効期限を設定
            await redis_client.expire(token_key, int(expires_in_value) + 300)
            await redis_client.expire(expires_key, int(expires_in_value) + 300)

            logger.info(
                f"New access token obtained and stored in Redis. Expires in {token_data.get('expires_in', 3600)} seconds."
            )
            return access_token

        except Exception as e:
            logger.exception(f"Unexpected error getting access token: {e}")
            return None


async def send_message_to_user(content: dict, user_id: str) -> httpx.Response:
    """指定されたユーザーに応答メッセージを送信する（リトライ付き）"""
    send_url = (
        f"https://www.worksapis.com/v1.0/bots/{LW_API_BOT_ID}/users/{user_id}/messages"
    )

    for i in range(RETRY_COUNT_MAX + 1):  # 初回実行 + リトライ回数
        access_token = await get_access_token()
        if not access_token:
            logger.error("Cannot send message: Failed to get access token.")
            # トークン取得失敗時はリトライしても無駄な可能性が高いので中断
            return None

        headers = {
            "Authorization": f"Bearer {access_token}",
            "Content-Type": "application/json; charset=UTF-8",
        }

        async with httpx.AsyncClient() as client:
            try:
                logger.info(
                    f"Attempting to send message to user {user_id} (Attempt {i+1})"
                )
                response = await client.post(send_url, headers=headers, json=content)
                response.raise_for_status()  # Check for HTTP errors (4xx or 5xx)
                logger.info(
                    f"Message sent successfully to {user_id}. Response: {response.text}"
                )
                return response  # 成功したらループを抜ける

            except httpx.HTTPStatusError as e:
                logger.warning(
                    f"HTTP error sending message (Attempt {i+1}): Status {e.response.status_code}, Response: {e.response.text}"
                )
                status_code = e.response.status_code
                try:
                    body = e.response.json()
                    error_code = body.get("code")
                except json.JSONDecodeError:
                    body = {}
                    error_code = None

                # トークン期限切れの場合 (401 Unauthorized または 403 Forbidden で特定のコード)
                # LINE WORKS APIは401を返すことが多い
                if status_code == 401 or (
                    status_code == 403 and error_code == "UNAUTHORIZED"
                ):  # Unauthorizedは例
                    logger.info(
                        "Access token might be expired or invalid. Forcing refresh."
                    )
                    # Redisキャッシュをクリアして次のループで再取得を試みる
                    token_key = f"{REDIS_PREFIX}access_token"
                    expires_key = f"{REDIS_PREFIX}expires_at"
                    await redis_client.delete(token_key)
                    await redis_client.delete(expires_key)

                    if i < RETRY_COUNT_MAX:
                        wait_time = RETRY_WAIT_BASE * (2**i)
                        logger.info(
                            f"Retrying after {wait_time} seconds due to authorization error."
                        )
                        await asyncio.sleep(wait_time)
                        continue  # 次のリトライへ
                    else:
                        logger.error(
                            "Failed to send message after retries due to authorization error."
                        )
                        return e.response  # 最後の失敗レスポンスを返す

                # レート制限の場合
                elif status_code == 429:
                    logger.info("Rate limit exceeded.")
                    if i < RETRY_COUNT_MAX:
                        # ヘッダーからリトライ時間を取得しようと試みる (なければデフォルト待機)
                        retry_after = e.response.headers.get("Retry-After")
                        wait_time = RETRY_WAIT_BASE * (2**i)
                        if retry_after and retry_after.isdigit():
                            wait_time = max(
                                wait_time, int(retry_after)
                            )  # ヘッダー指定があればそれに従う

                        logger.info(
                            f"Retrying after {wait_time} seconds due to rate limit."
                        )
                        await asyncio.sleep(wait_time)  # asyncio をインポート
                        continue  # 次のリトライへ
                    else:
                        logger.error(
                            "Failed to send message after retries due to rate limit."
                        )
                        return e.response  # 最後の失敗レスポンスを返す

                # その他のクライアントエラーやサーバーエラー
                else:
                    logger.error(
                        f"Unhandled HTTP error sending message: {status_code}. Aborting."
                    )
                    return e.response  # リトライせずに失敗レスポンスを返す

            except httpx.RequestError as e:
                logger.exception(
                    f"Network or request error sending message (Attempt {i+1}): {e}"
                )
                if i < RETRY_COUNT_MAX:
                    wait_time = RETRY_WAIT_BASE * (2**i)
                    logger.info(
                        f"Retrying after {wait_time} seconds due to request error."
                    )
                    await asyncio.sleep(wait_time)  # asyncio をインポート
                    continue
                else:
                    logger.error(
                        "Failed to send message after retries due to request error."
                    )
                    return None  # httpx.Response オブジェクトがないため None を返す

            except Exception as e:
                logger.exception(
                    f"Unexpected error sending message (Attempt {i+1}): {e}"
                )
                # 予期せぬエラーの場合はリトライしない
                return None

    # リトライ上限に達した場合
    logger.error(
        f"Failed to send message to user {user_id} after {RETRY_COUNT_MAX + 1} attempts."
    )
    return None  # 最終的に失敗


# --- Webhook エンドポイント ---
@app.post("/callback")
async def callback(request: Request, x_works_signature: str = Header(None)):
    """LINE WORKSからのCallback Eventを受信するエンドポイント"""
    logger.info("Callback received.")
    body_raw = await request.body()
    headers = request.headers  # FastAPIのHeadersはCase-insensitive

    # ヘッダーのBot IDを検証 (オプションだが推奨)
    header_bot_id = headers.get("x-works-botid")
    if header_bot_id != LW_API_BOT_ID:
        logger.warning(
            f"Received Bot ID '{header_bot_id}' does not match expected Bot ID '{LW_API_BOT_ID}'."
        )
        # 不一致の場合でも処理を続けるか、エラーにするかは要件による
        # return JSONResponse(status_code=status.HTTP_400_BAD_REQUEST, content={"error": "Invalid Bot ID"})

    # 署名検証
    if not await validate_request(body_raw, x_works_signature, LW_API_BOT_SECRET):
        logger.warning("Invalid signature.")

        # 署名検証モードに応じた処理
        if SIGNATURE_VERIFICATION_MODE == "strict":
            # 厳格モード: 署名検証に失敗した場合はリクエストを拒否（本番環境向け）
            logger.error(
                "Rejecting request due to invalid signature (SIGNATURE_VERIFICATION_MODE=strict)"
            )
            raise HTTPException(
                status_code=status.HTTP_401_UNAUTHORIZED, detail="Invalid signature"
            )
        else:
            # 警告モード: 署名検証に失敗した場合は警告ログを出力するが処理は続行
            logger.warning(
                "Proceeding despite invalid signature (SIGNATURE_VERIFICATION_MODE=warn)"
            )
            return JSONResponse(
                status_code=status.HTTP_200_OK,
                content={"message": "Signature validation failed, but acknowledged."},
            )

    logger.info("Signature validated.")

    # リクエストボディをJSONとしてパース
    try:
        body_json = json.loads(body_raw.decode("utf-8"))
        logger.info(f"Received event data: {json.dumps(body_json, indent=2)}")
    except json.JSONDecodeError:
        logger.error("Invalid JSON received.")
        # 不正なJSONは処理できないのでエラーレスポンス
        return JSONResponse(
            status_code=status.HTTP_400_BAD_REQUEST,
            content={"error": "Invalid JSON body"},
        )
    except Exception as e:
        logger.exception(f"Error processing request body: {e}")
        return JSONResponse(
            status_code=status.HTTP_500_INTERNAL_SERVER_ERROR,
            content={"error": "Error processing request"},
        )

    # イベント処理 (ここではメッセージイベントのみ対応)
    try:
        event_type = body_json.get("type")
        source = body_json.get("source", {})
        # userIdではなくaccountIdを使うのが推奨されている
        user_id = source.get("userId")  # または source.get("userId") 必要に応じて

        if event_type == "message":
            content = body_json.get("content", {})
            message_type = content.get("type")

            if message_type == "text" and user_id:
                received_text = content.get("text")
                logger.info(f"Received text message from {user_id}: '{received_text}'")

                # 1. ユーザーからのメッセージを要約
                summarized_text = await summarize_message(received_text)
                logger.info(f"Summarized message: '{summarized_text}'")

                # 2. Salesforce Agent APIを呼び出す
                # Salesforce Agent IDを設定（環境変数から取得するか、固定値を使用）
                agent_id = os.getenv("SF_AGENT_ID", "0Xx0000000000000000")

                try:
                    # セッションを開始または既存のセッションを取得
                    session_result = await sf_client.start_agent_session(
                        agent_id=agent_id,
                        user_id=user_id,  # ユーザーIDを追加
                        use_cached_session=True,  # キャッシュされたセッションを使用
                    )

                    if not session_result:
                        logger.error(
                            f"Failed to start or get Agent session for user {user_id}"
                        )
                        reply_to_send = "申し訳ありません、現在応答を生成できません。しばらくしてからもう一度お試しください。"
                    else:
                        session_id, session_response = session_result

                        # 要約したメッセージをAgentに送信
                        # シーケンスIDはsend_sync_message_to_agentメソッド内で自動的に管理される
                        agent_response = await sf_client.send_sync_message_to_agent(
                            session_id=session_id,
                            text=summarized_text,
                        )

                        logger.info(
                            f"Agent response: {json.dumps(agent_response, indent=2)}"
                        )

                        if not agent_response:
                            logger.error(
                                f"Failed to get response from Agent for user {user_id}"
                            )
                            reply_to_send = "申し訳ありません、現在応答を生成できません。しばらくしてからもう一度お試しください。"
                        else:
                            # 3. Agent APIの返信文を受け取る
                            agent_reply = ""

                            # レスポンスからメッセージテキストを抽出
                            if (
                                "message" in agent_response
                                and "text" in agent_response["message"]
                            ):
                                agent_reply = agent_response["message"]["text"]
                            elif (
                                "messages" in agent_response
                                and agent_response["messages"]
                            ):
                                for msg in agent_response["messages"]:
                                    if "text" in msg:
                                        agent_reply += msg["text"] + "\n"

                            logger.info(
                                f"Received reply from Agent: '{agent_reply[:100]}...'"
                            )

                            # 4. Agent APIの返信を使用してメッセージを生成
                            reply_to_send = await generate_response_from_agent_reply(
                                agent_reply, received_text
                            )
                except Exception as e:
                    logger.exception(f"Error processing Agent API request: {e}")
                    # エラーが発生した場合は、通常のAnthropicレスポンスにフォールバック
                    claude_reply_text = await call_anthropic_api(received_text)
                    if claude_reply_text:
                        reply_to_send = claude_reply_text
                    else:
                        reply_to_send = "申し訳ありません、現在応答を生成できません。しばらくしてからもう一度お試しください。"

                # 応答メッセージを作成
                res_content = {
                    "content": {
                        "type": "text",
                        "text": f"{reply_to_send}",
                    }
                }

                # 応答メッセージを非同期で送信
                send_response = await send_message_to_user(res_content, user_id)

                # 送信結果のログ（成功・失敗に関わらず）
                if send_response:
                    logger.info(
                        f"Message send attempt completed for user {user_id}. Status: {send_response.status_code if hasattr(send_response, 'status_code') else 'Unknown'}"
                    )
                else:
                    logger.error(
                        f"Message send attempt failed definitively for user {user_id}."
                    )

                    # 会話が終了したら、セッションを終了する
                    # 実際のアプリケーションでは、会話の終了条件を適切に判断する必要がある
                    # ここでは例として、特定のキーワードがあれば終了するなどの条件を設定できる
                    if "終了" in received_text or "さようなら" in received_text:
                        logger.info(f"Ending session for user {user_id}")
                        await sf_client.end_agent_session(
                            session_id=session_id, agent_id=agent_id, user_id=user_id
                        )
                        logger.info(f"Session ended for user {user_id}")

            else:
                logger.info(
                    f"Ignoring non-text message or message without user ID. Type: {message_type}"
                )

        elif event_type == "postback":
            logger.info(f"Received postback: {body_json.get('data')}")
            # Postback処理をここに追加

        else:
            logger.info(f"Ignoring event type: {event_type}")

    except Exception as e:
        # イベント処理中に予期せぬエラーが発生した場合
        logger.exception(f"Error processing event: {e}")
        # LINE WORKSにはエラーがあったことを伝えず、200 OKを返すことで再送を防ぐことが多い
        # エラーを通知したい場合は500系エラーを返すことも検討

    # LINE WORKSには常に200 OKを返す (Webhook仕様)
    # エラーが発生した場合でも、再送ループを防ぐために基本的に200を返すのが一般的
    return JSONResponse(
        status_code=status.HTTP_200_OK, content={"message": "Callback processed"}
    )


# --- ヘルスチェックエンドポイント ---
@app.get("/")
async def root():
    logger.info("Health check endpoint accessed.")
    return {"message": "LINE WORKS Bot Server is running!"}
