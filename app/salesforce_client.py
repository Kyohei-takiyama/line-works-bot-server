# salesforce_client.py

import os
import logging
import time
import asyncio  # リトライ待機用
import uuid
from typing import Optional, Dict, Any, List, Tuple

import httpx
import redis.asyncio as redis
from dotenv import load_dotenv

# 環境変数のロード (main.py と同じ .env を使う想定)
# このファイルが main.py と同じディレクトリ階層か、
# 適切なパスで .env が読み込めるようにしてください。
load_dotenv()

# --- Salesforce 設定 (環境変数から取得) ---
SF_CLIENT_ID = os.getenv("SF_CLIENT_ID")
SF_CLIENT_SECRET = os.getenv("SF_CLIENT_SECRET")
SF_BASE_URL = os.getenv("SF_BASE_URL")
# APIバージョン (デフォルトまたは環境変数から)
SF_API_VERSION = os.getenv("SF_API_VERSION", "v59.0")

# Redis設定
REDIS_HOST = os.getenv("REDIS_HOST", "localhost")
REDIS_PORT = int(os.getenv("REDIS_PORT", "6379"))
REDIS_DB = int(os.getenv("REDIS_DB", "0"))
REDIS_PREFIX = "sf_agent:"  # Redisキーのプレフィックス

# --- 環境変数チェック ---
required_sf_vars = {
    "SF_CLIENT_ID": SF_CLIENT_ID,
    "SF_CLIENT_SECRET": SF_CLIENT_SECRET,
    "SF_BASE_URL": SF_BASE_URL,
}
missing_sf_vars = [k for k, v in required_sf_vars.items() if v is None]
if missing_sf_vars:
    # 起動時にエラーを発生させる
    raise EnvironmentError(
        f"Missing required Salesforce environment variables: {', '.join(missing_sf_vars)}"
    )

# --- ロガー設定 ---
# main.py で設定されたロガーを共有することを想定
# このファイル単体でテストする場合は、基本的な設定を行う
# logging.basicConfig(level=logging.INFO) # 必要に応じてコメント解除
logger = logging.getLogger(__name__)


class SalesforceClient:
    """
    Salesforce APIと非同期で通信するためのクライアントクラス。
    OAuth 2.0 クライアントクレデンシャルズフローを使用します。
    """

    def __init__(
        self,
        client_id: str = SF_CLIENT_ID,
        client_secret: str = SF_CLIENT_SECRET,
        token_url: str = SF_BASE_URL + "/services/oauth2/token",
        api_version: str = SF_API_VERSION,
        # 外部から httpx.AsyncClient を渡せるようにする (推奨)
        client: Optional[httpx.AsyncClient] = None,
        # トークン有効期限の何秒前に更新を試みるか (エラーベース更新が主になる)
        token_cache_padding: int = 300,  # 5分
        max_retries: int = 2,  # API呼び出しリトライ回数
        retry_delay_base: float = 1.0,  # リトライ基本待機秒数
        # Redisクライアント（オプション）
        redis_client: Optional[redis.Redis] = None,
        # セッションの有効期限（秒）
        session_ttl: int = 3600,  # 1時間
    ):
        """
        SalesforceClientを初期化します。

        Args:
            client_id: Salesforce接続アプリケーションのクライアントID。
            client_secret: Salesforce接続アプリケーションのクライアントシークレット。
            token_url: Salesforce OAuthトークンエンドポイントURL。
            api_version: 使用するSalesforce APIのバージョン (例: "v59.0")。
            client: (オプション) 外部で作成された httpx.AsyncClient インスタンス。
                    指定しない場合、内部で新しいインスタンスが作成されます。
            token_cache_padding: アクセストークンの有効期限とみなす期間（秒）。
                                 クライアントクレデンシャルズフローではexpires_inが返されないため、
                                 この値は参考程度とし、主にエラー発生時の再取得に依存します。
            max_retries: API呼び出し失敗時の最大リトライ回数。
            retry_delay_base: リトライ時の基本待機時間（秒）。指数バックオフで使用。
        """
        if not all([client_id, client_secret, token_url]):
            raise ValueError("Client ID, Client Secret, and Token URL are required.")

        self.client_id = client_id
        self.client_secret = client_secret
        self.token_url = token_url
        self.api_version = api_version
        self.token_cache_padding = token_cache_padding
        self.max_retries = max_retries
        self.retry_delay_base = retry_delay_base

        # Salesforce Einstein Copilot Agent API のベースURL
        self.copilot_api_base_url = "https://api.salesforce.com/einstein/ai-agent/v1"

        # httpx.AsyncClient を初期化または外部から受け取る
        self._client = (
            client if client else httpx.AsyncClient(timeout=30.0)
        )  # タイムアウト設定
        # 自身で生成したClientかどうかのフラグ (クローズ処理のため)
        self._should_close_client = client is None

        self._access_token: Optional[str] = None
        self._instance_url: Optional[str] = None
        # トークンの有効期限 (Unixタイムスタンプ)。エラーベース更新が主。
        self._token_expires_at: float = 0

        # 同時にトークン取得処理が走らないようにするためのロック
        self._token_lock = asyncio.Lock()

        # Redisクライアント
        self._redis_client = redis_client
        self._session_ttl = session_ttl

    async def close(self):
        """
        内部で生成された httpx.AsyncClient を閉じる必要がある場合に呼び出します。
        FastAPIのシャットダウンイベントなどで使用します。
        """
        if self._should_close_client and not self._client.is_closed:
            await self._client.aclose()
            logger.info("Internal httpx.AsyncClient closed.")

    async def set_redis_client(self, redis_client: redis.Redis):
        """
        Redisクライアントを設定します。
        アプリケーション起動時に呼び出すことを想定しています。
        """
        self._redis_client = redis_client
        logger.info("Redis client set for SalesforceClient")

    async def _refresh_access_token(self) -> bool:
        """
        新しいアクセストークンを取得し、キャッシュを更新します。
        ロック内で呼び出されることを想定しています。
        """
        logger.info(
            "Attempting to get new Salesforce access token via client credentials flow."
        )
        headers = {"Content-Type": "application/x-www-form-urlencoded"}
        data = {
            "grant_type": "client_credentials",
            "client_id": self.client_id,
            "client_secret": self.client_secret,
        }

        try:
            response = await self._client.post(
                self.token_url, headers=headers, data=data
            )
            response.raise_for_status()  # HTTPエラーチェック
            token_data = response.json()

            if "access_token" not in token_data or "instance_url" not in token_data:
                logger.error(
                    f"Invalid token response received from Salesforce: {token_data}"
                )
                self._access_token = None
                self._instance_url = None
                self._token_expires_at = 0
                return False

            self._access_token = token_data["access_token"]
            self._instance_url = token_data["instance_url"]
            # クライアントクレデンシャルズフローでは expires_in は通常返されない
            # 有効期限は接続アプリ設定に依存するため、固定値やキャッシュは不安定
            # ここでは取得時刻 + padding で仮の有効期限を設定するが、
            # 主な更新トリガーはAPI呼び出し時の認証エラーとする
            current_time = time.time()
            self._token_expires_at = current_time + self.token_cache_padding

            logger.info(
                f"Successfully obtained Salesforce access token. Instance URL: {self._instance_url}"
            )
            return True

        except httpx.HTTPStatusError as e:
            logger.error(
                f"HTTP error getting Salesforce access token: Status {e.response.status_code}, Response: {e.response.text}"
            )
        except httpx.RequestError as e:
            logger.error(f"Request error getting Salesforce access token: {e}")
        except Exception as e:
            logger.exception(f"Unexpected error getting Salesforce access token: {e}")

        # エラー時はキャッシュをクリア
        self._access_token = None
        self._instance_url = None
        self._token_expires_at = 0
        return False

    async def _get_valid_access_token(self) -> Optional[str]:
        """
        有効なアクセストークンを取得します。必要であれば更新します。
        """
        current_time = time.time()
        # まずキャッシュを確認（有効期限前か？）
        if self._access_token and current_time < self._token_expires_at:
            logger.debug("Using cached Salesforce access token.")
            return self._access_token

        # キャッシュが無効または期限切れの可能性がある場合、ロックを取得して更新を試みる
        async with self._token_lock:
            # ロック取得後、再度キャッシュを確認 (他のタスクが更新した可能性)
            current_time = time.time()
            if self._access_token and current_time < self._token_expires_at:
                logger.debug(
                    "Using cached Salesforce access token (checked after lock)."
                )
                return self._access_token

            # トークン更新処理
            if await self._refresh_access_token():
                return self._access_token
            else:
                logger.error("Failed to obtain a valid Salesforce access token.")
                return None

    async def _request(
        self,
        method: str,
        url: str,  # 完全なURLを受け取るように変更
        params: Optional[Dict[str, Any]] = None,
        json_data: Optional[Dict[str, Any]] = None,
        is_copilot_api: bool = False,  # Copilot APIかどうかを判定するフラグ
    ) -> Optional[httpx.Response]:
        """
        指定されたURLへのAPIリクエストを実行するコアメソッド（リトライロジック含む）。

        Args:
            method: HTTPメソッド (GET, POST, PATCH, DELETE 등).
            url: リクエスト先の完全なURL。
            params: URLクエリパラメータ。
            json_data: リクエストボディ (JSON)。
            is_copilot_api: Copilot Agent APIへのリクエストかどうかのフラグ。

        Returns:
            成功した場合は httpx.Response オブジェクト、失敗した場合は None。
        """
        access_token = await self._get_valid_access_token()
        if not access_token:
            logger.error(
                f"Cannot make API request ({method} {url}): No valid access token."
            )
            return None
        # Copilot APIの場合、リクエストボディにinstance_urlが必要な場合があるが、
        # _requestメソッド自体はそれを意識しない。呼び出し元でjson_dataに含める。
        # instance_url自体はトークン取得時に得られる必要がある。
        if not self._instance_url and is_copilot_api:
            # Copilot APIのセッション開始には instance_url が必要
            logger.warning(
                "Instance URL not available, which might be required for some Copilot API calls."
            )
            # ここでエラーにするか、処理を続けるかは要件による
            # return None

        api_url = url  # 完全なURLをそのまま使用
        headers = {
            "Authorization": f"Bearer {access_token}",
            "Content-Type": "application/json; charset=UTF-8",
            "Accept": "application/json",  # レスポンス形式としてJSONを期待
        }

        last_exception = None

        for attempt in range(self.max_retries + 1):
            wait_time = self.retry_delay_base * (2**attempt)
            try:
                logger.debug(
                    f"API Request ({method} {api_url}): Attempt {attempt + 1}/{self.max_retries + 1}"
                )
                response = await self._client.request(
                    method,
                    api_url,
                    headers=headers,
                    params=params,
                    json=json_data,
                )
                response.raise_for_status()
                logger.debug(f"API Response: Status {response.status_code}")
                return response

            except httpx.HTTPStatusError as e:
                last_exception = e
                logger.warning(
                    f"HTTP error during API request ({method} {api_url}): {e.response.status_code} - {e.response.text} (Attempt {attempt + 1})"
                )
                # 認証エラー (401/403) の処理
                if e.response.status_code in [401, 403]:
                    logger.info(
                        "Authorization error detected. Attempting to refresh token."
                    )
                    async with self._token_lock:
                        self._access_token = None
                        self._token_expires_at = 0
                        # instance_urlも再取得が必要かもしれないのでクリア
                        self._instance_url = None

                    if attempt < self.max_retries:
                        logger.info(
                            f"Retrying after {wait_time:.2f} seconds due to authorization error."
                        )
                        await asyncio.sleep(wait_time)
                        # 次のループ開始時にトークン再取得が試みられる
                        continue  # ここで再取得を試みるのではなく、次のループの最初に任せる
                    else:
                        logger.error(
                            "Failed API request after retries due to persistent authorization error."
                        )
                        break
                # その他のHTTPエラーのリトライ処理 (変更なし)
                elif attempt < self.max_retries:
                    logger.info(
                        f"Retrying after {wait_time:.2f} seconds due to HTTP error {e.response.status_code}."
                    )
                    await asyncio.sleep(wait_time)
                    continue
                else:
                    logger.error(
                        f"Failed API request after retries due to HTTP error {e.response.status_code}."
                    )
                    break

            except (
                httpx.RequestError
            ) as e:  # ネットワークエラー等のリトライ処理 (変更なし)
                last_exception = e
                logger.warning(
                    f"Network or request error during API request ({method} {api_url}): {e} (Attempt {attempt + 1})"
                )
                if attempt < self.max_retries:
                    logger.info(
                        f"Retrying after {wait_time:.2f} seconds due to request error."
                    )
                    await asyncio.sleep(wait_time)
                    continue
                else:
                    logger.error(
                        "Failed API request after retries due to request error."
                    )
                    break

            except Exception as e:  # その他の予期せぬエラー (変更なし)
                last_exception = e
                logger.exception(
                    f"Unexpected error during API request ({method} {api_url}): {e} (Attempt {attempt + 1})"
                )
                break

        logger.error(
            f"API request failed definitively ({method} {url}). Last known error: {last_exception}"
        )
        if isinstance(last_exception, httpx.HTTPStatusError):
            return last_exception.response
        return None

    # --- Public API Methods ---

    async def get_records(
        self,
        sobject_name: str,
        fields: Optional[List[str]] = None,
        limit: Optional[int] = None,
    ) -> Optional[Dict[str, Any]]:
        """
        指定されたSObjectのレコードリストを取得します。

        Args:
            sobject_name: SObjectのAPI名 (例: "Account", "Contact").
            fields: 取得する項目のAPI名のリスト。Noneの場合はデフォルト項目。
            limit: 取得する最大レコード数。

        Returns:
            成功した場合はAPIレスポンスのJSON辞書、失敗した場合は None。
        """
        path = f"/services/data/{self.api_version}/sobjects/{sobject_name}"
        params = {}
        if fields:
            params["fields"] = ",".join(fields)
        if limit is not None:
            params["limit"] = str(limit)

        response = await self._request("GET", path, params=params)

        if response and response.status_code == 200:
            try:
                return response.json()
            except Exception as e:
                logger.error(
                    f"Failed to decode JSON response for get_records({sobject_name}): {e}"
                )
                return None
        elif response:
            logger.error(
                f"Failed to get records for {sobject_name}. Status: {response.status_code}, Body: {response.text}"
            )
            return None  # エラーレスポンスの内容を返す選択肢もある
        else:
            logger.error(
                f"Failed to get records for {sobject_name}. No response received."
            )
            return None

    async def query(self, soql_query: str) -> Optional[Dict[str, Any]]:
        """
        SOQLクエリを実行します。

        Args:
            soql_query: 実行するSOQLクエリ文字列。

        Returns:
            成功した場合はAPIレスポンスのJSON辞書、失敗した場合は None。
        """
        path = f"/services/data/{self.api_version}/query"
        # SOQLクエリはURLパラメータとして渡すため、URLエンコードされる
        params = {"q": soql_query}

        response = await self._request("GET", path, params=params)

        if response and response.status_code == 200:
            try:
                return response.json()
            except Exception as e:
                logger.error(f"Failed to decode JSON response for query: {e}")
                return None
        elif response:
            logger.error(
                f"Failed to execute SOQL query. Status: {response.status_code}, Body: {response.text}"
            )
            return None
        else:
            logger.error("Failed to execute SOQL query. No response received.")
            return None

    async def create_record(
        self, sobject_name: str, data: Dict[str, Any]
    ) -> Optional[Dict[str, Any]]:
        """
        新しいSObjectレコードを作成します。

        Args:
            sobject_name: 作成するSObjectのAPI名。
            data: 作成するレコードのデータ (項目API名: 値 の辞書)。

        Returns:
            成功した場合は作成結果 (IDなど) を含むJSON辞書、失敗した場合は None。
        """
        path = f"/services/data/{self.api_version}/sobjects/{sobject_name}"
        response = await self._request("POST", path, json_data=data)

        # Salesforceの作成成功は通常 201 Created
        if response and response.status_code == 201:
            try:
                return response.json()
            except Exception as e:
                logger.warning(
                    f"Record created ({sobject_name}), but failed to decode response JSON: {e}"
                )
                # 成功したがレスポンス解析失敗の場合、最低限の情報を示す辞書を返すこともできる
                return {
                    "success": True,
                    "id": None,
                    "errors": [],
                    "message": "JSON decode failed",
                }
        elif response:
            logger.error(
                f"Failed to create {sobject_name} record. Status: {response.status_code}, Body: {response.text}"
            )
            # エラーレスポンスを解析して返すことも可能
            try:
                return response.json()  # Salesforceのエラー詳細が含まれる場合がある
            except:
                return None  # JSONデコード失敗
        else:
            logger.error(
                f"Failed to create {sobject_name} record. No response received."
            )
            return None

    async def update_record(
        self, sobject_name: str, record_id: str, data: Dict[str, Any]
    ) -> bool:
        """
        既存のSObjectレコードを更新します。

        Args:
            sobject_name: 更新するSObjectのAPI名。
            record_id: 更新するレコードのID。
            data: 更新するデータ (項目API名: 値 の辞書)。

        Returns:
            成功した場合は True、失敗した場合は False。
        """
        path = f"/services/data/{self.api_version}/sobjects/{sobject_name}/{record_id}"
        # 更新は PATCH メソッドが推奨される
        response = await self._request("PATCH", path, json_data=data)

        # Salesforceの更新成功は通常 204 No Content
        if response and response.status_code == 204:
            logger.info(f"Successfully updated record {sobject_name}/{record_id}.")
            return True
        elif response:
            logger.error(
                f"Failed to update record {sobject_name}/{record_id}. Status: {response.status_code}, Body: {response.text}"
            )
            return False
        else:
            logger.error(
                f"Failed to update record {sobject_name}/{record_id}. No response received."
            )
            return False

    async def delete_record(self, sobject_name: str, record_id: str) -> bool:
        """
        SObjectレコードを削除します。

        Args:
            sobject_name: 削除するSObjectのAPI名。
            record_id: 削除するレコードのID。

        Returns:
            成功した場合は True、失敗した場合は False。
        """
        path = f"/services/data/{self.api_version}/sobjects/{sobject_name}/{record_id}"
        response = await self._request("DELETE", path)

        # Salesforceの削除成功は通常 204 No Content
        if response and response.status_code == 204:
            logger.info(f"Successfully deleted record {sobject_name}/{record_id}.")
            return True
        elif response:
            logger.error(
                f"Failed to delete record {sobject_name}/{record_id}. Status: {response.status_code}, Body: {response.text}"
            )
            return False
        else:
            logger.error(
                f"Failed to delete record {sobject_name}/{record_id}. No response received."
            )
            return False

    async def get_cached_session(
        self, agent_id: str, user_id: str
    ) -> Optional[Tuple[str, str]]:
        """
        Redisからキャッシュされたセッション情報を取得します。

        Args:
            agent_id: Agentの18桁のID
            user_id: ユーザーID

        Returns:
            キャッシュが存在する場合は (session_key, session_id) のタプル、存在しない場合は None
        """
        if not self._redis_client:
            logger.warning("Redis client not available, cannot get cached session")
            return None

        try:
            # セッションキーとセッションIDを取得（ユーザーIDを含む）
            session_key_redis_key = f"{REDIS_PREFIX}session_key:{agent_id}:{user_id}"
            session_id_redis_key = f"{REDIS_PREFIX}session_id:{agent_id}:{user_id}"

            session_key = await self._redis_client.get(session_key_redis_key)
            session_id = await self._redis_client.get(session_id_redis_key)

            if session_key and session_id:
                logger.info(
                    f"Found cached session for agent_id={agent_id}, user_id={user_id}: session_key={session_key}, session_id={session_id}"
                )
                return session_key, session_id
            else:
                logger.debug(
                    f"No cached session found for agent_id={agent_id}, user_id={user_id}"
                )
                return None
        except Exception as e:
            logger.warning(f"Error getting cached session from Redis: {e}")
            # Redisエラーの場合はキャッシュスキップとして処理し、セッション生成ロジックにフォールバック
            return None

    async def cache_session(
        self, agent_id: str, user_id: str, session_key: str, session_id: str
    ):
        """
        セッション情報をRedisにキャッシュします。

        Args:
            agent_id: Agentの18桁のID
            user_id: ユーザーID
            session_key: セッションキー
            session_id: セッションID
        """
        if not self._redis_client:
            logger.warning("Redis client not available, cannot cache session")
            return

        try:
            # セッションキーとセッションIDを保存（ユーザーIDを含む）
            session_key_redis_key = f"{REDIS_PREFIX}session_key:{agent_id}:{user_id}"
            session_id_redis_key = f"{REDIS_PREFIX}session_id:{agent_id}:{user_id}"

            await self._redis_client.set(session_key_redis_key, session_key)
            await self._redis_client.set(session_id_redis_key, session_id)

            # 有効期限を設定
            await self._redis_client.expire(session_key_redis_key, self._session_ttl)
            await self._redis_client.expire(session_id_redis_key, self._session_ttl)

            # 初期シーケンスIDを設定
            seq_redis_key = f"{REDIS_PREFIX}seq:{session_id}"
            await self._redis_client.set(seq_redis_key, "1")
            await self._redis_client.expire(seq_redis_key, self._session_ttl)

            logger.info(
                f"Cached session for agent_id={agent_id}, user_id={user_id}: session_key={session_key}, session_id={session_id}, ttl={self._session_ttl}s"
            )
        except Exception as e:
            logger.warning(f"Error caching session in Redis: {e}")

    async def delete_cached_session(
        self, agent_id: str, user_id: str, session_id: Optional[str] = None
    ):
        """
        Redisからキャッシュされたセッション情報を削除します。

        Args:
            agent_id: Agentの18桁のID
            user_id: ユーザーID
            session_id: セッションID（オプション）
        """
        if not self._redis_client:
            logger.warning("Redis client not available, cannot delete cached session")
            return

        try:
            # セッションキーとセッションIDを削除（ユーザーIDを含む）
            session_key_redis_key = f"{REDIS_PREFIX}session_key:{agent_id}:{user_id}"
            session_id_redis_key = f"{REDIS_PREFIX}session_id:{agent_id}:{user_id}"

            # セッションIDが指定されている場合は、シーケンスIDも削除
            if session_id:
                seq_redis_key = f"{REDIS_PREFIX}seq:{session_id}"
                await self._redis_client.delete(seq_redis_key)
                logger.debug(f"Deleted sequence ID for session_id={session_id}")

            await self._redis_client.delete(session_key_redis_key)
            await self._redis_client.delete(session_id_redis_key)

            logger.info(
                f"Deleted cached session for agent_id={agent_id}, user_id={user_id}"
            )
        except Exception as e:
            logger.warning(f"Error deleting cached session from Redis: {e}")

    async def get_sequence_id(self, session_id: str) -> int:
        """
        セッションの現在のシーケンスIDを取得します。
        存在しない場合は1を返します。

        Args:
            session_id: セッションID

        Returns:
            現在のシーケンスID
        """
        if not self._redis_client:
            logger.warning("Redis client not available, cannot get sequence ID")
            return 1

        try:
            seq_redis_key = f"{REDIS_PREFIX}seq:{session_id}"
            seq_id_str = await self._redis_client.get(seq_redis_key)

            if seq_id_str:
                return int(seq_id_str)
            else:
                logger.debug(
                    f"No sequence ID found for session_id={session_id}, using default 1"
                )
                return 1
        except Exception as e:
            logger.warning(f"Error getting sequence ID from Redis: {e}")
            return 1

    async def update_sequence_id(self, session_id: str, sequence_id: int):
        """
        セッションのシーケンスIDを更新します。

        Args:
            session_id: セッションID
            sequence_id: 新しいシーケンスID
        """
        if not self._redis_client:
            logger.warning("Redis client not available, cannot update sequence ID")
            return

        try:
            seq_redis_key = f"{REDIS_PREFIX}seq:{session_id}"
            await self._redis_client.set(seq_redis_key, str(sequence_id))
            # セッションと同じTTLを設定
            await self._redis_client.expire(seq_redis_key, self._session_ttl)
            logger.debug(
                f"Updated sequence ID for session_id={session_id} to {sequence_id}"
            )
        except Exception as e:
            logger.warning(f"Error updating sequence ID in Redis: {e}")

    async def start_agent_session(
        self,
        agent_id: str,  # 18桁のAgent ID
        user_id: str,  # ユーザーID
        external_session_key: Optional[str] = None,
        bypass_user: bool = True,
        chunk_types: Optional[list[str]] = None,  # 例: ["Text"]
        use_cached_session: bool = True,  # キャッシュされたセッションを使用するかどうか
    ) -> Optional[Tuple[str, Dict[str, Any]]]:
        """
        Einstein Copilot Agentとの新しいセッションを開始します。

        Args:
            agent_id: Agentの18桁のID (Salesforce Setup URLの末尾)。
            external_session_key: (オプション) 外部システムでセッションを追跡するためのキー。指定しない場合はUUIDを生成。
            bypass_user: クライアントクレデンシャルズフローの場合は通常 True。
            chunk_types: (オプション) ストリーミングで受け取りたいメッセージタイプ。

        Returns:
            成功した場合は (セッションID, 初期レスポンスJSON) のタプル、失敗した場合は None。
            初期レスポンスには最初の挨拶メッセージなどが含まれることがあります。
        """
        # instance_url が必要なので、なければトークン取得を試みる
        if not self._instance_url:
            logger.info("Instance URL not found, attempting to get access token first.")
            await self._get_valid_access_token()  # これで instance_url が設定されるはず
            if not self._instance_url:
                logger.error(
                    "Failed to get instance URL required for starting agent session."
                )
                return None

        # キャッシュされたセッションを確認
        cached_session = None
        if use_cached_session and self._redis_client:
            cached_session = await self.get_cached_session(agent_id, user_id)
            if cached_session:
                session_key, session_id = cached_session
                logger.info(
                    f"Using cached session for agent_id={agent_id}, user_id={user_id}: session_id={session_id}"
                )
                # セッションIDとダミーレスポンスを返す
                dummy_response = {
                    "sessionId": session_id,
                    "fromCache": True,
                    "message": "Using cached session",
                }
                return session_id, dummy_response

        # URLを構築
        session_url = f"{self.copilot_api_base_url}/agents/{agent_id}/sessions"

        # リクエストボディを構築
        session_key = (
            external_session_key if external_session_key else str(uuid.uuid4())
        )
        request_body: Dict[str, Any] = {
            "externalSessionKey": session_key,
            "instanceConfig": {"endpoint": self._instance_url},
            "featureSupport": "Sync",
            "bypassUser": bypass_user,
        }
        if chunk_types:
            request_body["streamingCapabilities"] = {"chunkTypes": chunk_types}

        logger.info(
            f"Starting new Copilot Agent session for agentId='{agent_id}' with key='{session_key}'"
        )
        # logger.debug(f"Start session request body: {request_body}")

        response = await self._request(
            "POST", session_url, json_data=request_body, is_copilot_api=True
        )

        if response and response.status_code == 200:  # 成功は 200 OK
            try:
                response_json = response.json()
                logger.info(
                    f"Successfully started Copilot Agent session for agentId='{agent_id}'."
                )
                session_id = response_json.get("sessionId")
                if not session_id:
                    logger.error(
                        f"Session ID not found in the start session response for agentId='{agent_id}'."
                    )
                    return None
                logger.info(
                    f"Successfully started Copilot Agent session: sessionId='{session_id}'"
                )
                # logger.debug(f"Start session response: {response_json}")

                # セッション情報をRedisにキャッシュ
                if self._redis_client:
                    await self.cache_session(agent_id, user_id, session_key, session_id)

                return session_id, response_json  # セッションIDとレスポンス全体を返す
            except Exception as e:
                logger.error(
                    f"Failed to decode JSON response for start_agent_session (agentId='{agent_id}'): {e}"
                )
                return None
        elif response:
            logger.error(
                f"Failed to start Copilot Agent session for agentId='{agent_id}'. Status: {response.status_code}, Body: {response.text}"
            )
            return None
        else:
            logger.error(
                f"Failed to start Copilot Agent session for agentId='{agent_id}'. No response received."
            )
            return None

    async def send_sync_message_to_agent(
        self, session_id: str, text: str, sequence_id: Optional[int] = None
    ) -> Optional[Dict[str, Any]]:
        """
        既存のAgentセッションに同期メッセージを送信します。

        Args:
            session_id: start_agent_session で取得したセッションID。
            sequence_id: セッション内でのメッセージのシーケンス番号 (1から開始し、送信ごとにインクリメント)。
            text: Agentに送信するメッセージテキスト。

        Returns:
            成功した場合はAgentからの応答メッセージを含むJSON辞書、失敗した場合は None。
        """
        # URLを構築
        message_url = f"{self.copilot_api_base_url}/sessions/{session_id}/messages"

        # シーケンスIDが指定されていない場合は、Redisから取得してインクリメント
        if sequence_id is None:
            sequence_id = await self.get_sequence_id(session_id)
            # 次回用にインクリメント
            next_sequence_id = sequence_id + 1
            await self.update_sequence_id(session_id, next_sequence_id)
            logger.debug(
                f"Using sequence_id={sequence_id} for session_id={session_id}, next will be {next_sequence_id}"
            )

        # リクエストボディを構築
        request_body = {
            "message": {
                "sequenceId": sequence_id,
                "type": "Text",  # 現在はTextのみサポートされていることが多い
                "text": text,
            }
        }

        logger.info(
            f"Sending sync message to Copilot Agent session='{session_id}', sequenceId={sequence_id}, text='{text[:50]}...'"
        )
        # logger.debug(f"Send sync message request body: {request_body}")

        response = await self._request(
            "POST", message_url, json_data=request_body, is_copilot_api=True
        )

        if response and response.status_code == 200:  # 成功は 200 OK
            try:
                response_json = response.json()
                logger.info(
                    f"Successfully received sync response from Copilot Agent session='{session_id}'."
                )
                # logger.debug(f"Sync message response: {response_json}")
                return response_json
            except Exception as e:
                logger.error(
                    f"Failed to decode JSON response for send_sync_message (session='{session_id}'): {e}"
                )
                return None
        elif response:
            logger.error(
                f"Failed to send sync message to Copilot Agent session='{session_id}'. Status: {response.status_code}, Body: {response.text}"
            )
            # エラーレスポンスを返す試み
            try:
                return response.json()
            except:
                return None
        else:
            logger.error(
                f"Failed to send sync message to Copilot Agent session='{session_id}'. No response received."
            )
            return None

    async def end_agent_session(
        self,
        session_id: str,
        agent_id: Optional[str] = None,
        user_id: Optional[str] = None,
    ) -> bool:
        """
        Einstein Copilot Agentセッションを終了します。

        Args:
            session_id: 終了するセッションのID。

        Returns:
            成功した場合は True、失敗した場合は False。
        """
        end_session_url = f"{self.copilot_api_base_url}/sessions/{session_id}"
        logger.info(f"Ending Copilot Agent session: sessionId='{session_id}'")

        # DELETEメソッドを使用する
        response = await self._request("DELETE", end_session_url, is_copilot_api=True)

        # 成功は 204 No Content または 200 OK の場合がある (API仕様による)
        # ドキュメントには明記されていないが、一般的にDELETEは204が多い
        if response and (response.status_code == 204 or response.status_code == 200):
            logger.info(
                f"Successfully ended Copilot Agent session: sessionId='{session_id}'. Status: {response.status_code}"
            )

            # セッション情報をRedisから削除
            if self._redis_client and agent_id and user_id:
                await self.delete_cached_session(agent_id, user_id, session_id)

            return True
        elif response:
            logger.error(
                f"Failed to end Copilot Agent session='{session_id}'. Status: {response.status_code}, Body: {response.text}"
            )
            return False
        else:
            logger.error(
                f"Failed to end Copilot Agent session='{session_id}'. No response received."
            )
            return False

    # --- 他のSalesforce APIメソッド (例: get_records, query など) ---
    # これらは /services/data/vXX.0 を使うため、呼び出し方を修正する必要がある

    async def get_records(
        self,
        sobject_name: str,
        fields: Optional[List[str]] = None,
        limit: Optional[int] = None,
    ) -> Optional[Dict[str, Any]]:
        if not self._instance_url:  # instance_urlが必要
            logger.info(
                "Instance URL not found for get_records, attempting to get access token first."
            )
            await self._get_valid_access_token()
            if not self._instance_url:
                logger.error("Failed to get instance URL required for get_records.")
                return None

        path = f"/services/data/{self.api_version}/sobjects/{sobject_name}"
        url = f"{self._instance_url}{path}"  # 完全なURLを組み立てる
        params = {}
        if fields:
            params["fields"] = ",".join(fields)
        if limit is not None:
            params["limit"] = str(limit)

        response = await self._request(
            "GET", url, params=params, is_copilot_api=False
        )  # is_copilot_api=False

        if response and response.status_code == 200:
            try:
                return response.json()
            except Exception as e:
                logger.error(
                    f"Failed to decode JSON response for get_records({sobject_name}): {e}"
                )
                return None
        # ... (エラー処理は同様) ...
        elif response:
            logger.error(
                f"Failed to get records for {sobject_name}. Status: {response.status_code}, Body: {response.text}"
            )
            return None
        else:
            logger.error(
                f"Failed to get records for {sobject_name}. No response received."
            )
            return None

    # query, create_record, update_record, delete_record も同様に
    # url を self._instance_url + path で組み立て、_request を呼び出すように修正する。
    # 例: query メソッド
    async def query(self, soql_query: str) -> Optional[Dict[str, Any]]:
        if not self._instance_url:
            logger.info(
                "Instance URL not found for query, attempting to get access token first."
            )
            await self._get_valid_access_token()
            if not self._instance_url:
                logger.error("Failed to get instance URL required for query.")
                return None

        path = f"/services/data/{self.api_version}/query"
        url = f"{self._instance_url}{path}"
        params = {"q": soql_query}
        response = await self._request("GET", url, params=params, is_copilot_api=False)

        # ... (レスポンス処理は同様) ...
        if response and response.status_code == 200:
            # ...
            pass  # 以下同様
        elif response:
            logger.error(
                f"Failed to execute SOQL query. Status: {response.status_code}, Body: {response.text}"
            )
            return None
        else:
            logger.error("Failed to execute SOQL query. No response received.")
            return None
