import os
import logging
import anthropic
from dotenv import load_dotenv
import httpx

# --- System Prompt for Anthropic API ---
SYSTEM_PROMPT = """
あなたは、求職者のキャリア相談に乗り、適切な求人を紹介するキャリアアドバイザーBotです。
以下の点を考慮して、丁寧かつ親身に対応してください。

*   **あなたの役割:** 求職者の希望やスキル、経験などをヒアリングし、最適な求人情報を提供することです。求人紹介に関連しない雑談にも応じますが、最終的には求人の話につなげるように意識してください。
*   **応答スタイル:** 親しみやすく、プロフェッショナルなトーンで応答してください。専門用語は避け、分かりやすい言葉で説明してください。感嘆符や絵文字を使って、フレンドリーな雰囲気を出してください。
*   **情報収集:** ユーザーから具体的な希望（職種、勤務地、年収、スキルなど）を引き出すように努めてください。どのような情報があればより良い提案ができるかを考えて質問してください。
*   **求人紹介:** 現時点では具体的な求人データベースとの連携はありませんが、「もし求人があるとすれば、〇〇のようなものが合いそうですね」といった形で、ユーザーの希望に合致する求人のイメージを提示してください。具体的な求人情報そのものを提示することは避けてください。
*   **将来の連携:** (内部情報: 将来的にはSalesforceと連携し、よりパーソナライズされた情報を提供できるようになりますが、現時点ではその機能はありません。ユーザーにその期待を持たせるような発言は避けてください。)
*   **禁止事項:** 個人を特定できる機密情報（具体的な企業名など、公開されていない情報）を要求したり、提供したりしないでください。不確かな情報は伝えず、「一般的には〜」や「〜の可能性があります」のような表現を使ってください。医療や法律に関するアドバイスは行わないでください。

ユーザーからのメッセージに対して、上記の役割に基づき、最適な応答を生成してください。
"""

load_dotenv()
logger = logging.getLogger(__name__)

ANTHROPIC_API_KEY = os.getenv("ANTHROPIC_API_KEY")
ANTHROPIC_MODEL = os.getenv(
    "ANTHROPIC_MODEL", "claude-3-5-sonnet-20240620"
)  # .envから読み込む

# APIキーがない場合は初期化しない、またはエラーハンドリング
anthropic_client = None
if ANTHROPIC_API_KEY:
    try:
        # 非同期クライアントを初期化
        anthropic_client = anthropic.AsyncAnthropic(
            api_key=ANTHROPIC_API_KEY,
        )
        logger.info("Anthropic async client initialized.")
    except Exception as e:
        logger.error(f"Failed to initialize Anthropic client: {e}")
else:
    logger.warning("ANTHROPIC_API_KEY is not set. Anthropic client not initialized.")


async def summarize_message(user_message: str) -> str:
    """
    ユーザーからのメッセージを要約する

    Args:
        user_message: 要約するユーザーメッセージ

    Returns:
        要約されたメッセージ
    """
    if not anthropic_client:  # クライアントが初期化されていない場合
        logger.error("Anthropic client is not available.")
        return user_message  # 要約できない場合は元のメッセージを返す

    try:
        logger.info(
            f"Summarizing message using Anthropic API: '{user_message[:50]}...'"
        )

        # 要約用のシステムプロンプト
        summary_system_prompt = """
        あなたはユーザーのメッセージを簡潔に要約するアシスタントです。
        ユーザーからのメッセージを、重要なポイントを保持したまま、簡潔に要約してください。
        *   **業種の扱い（重要）**
            - ユーザーが次のいずれかの業種のどれを求めているかを判断してください。「Chemicals,Communications,Construction,Consulting,Education,Electronics,Energy,Engineering,Entertainment,Environmental,Finance,Food,Government,Healthcare,Hospitality,Insurance,Machinery,Manufacturing,Media,Not,Other,Recreation,Retail,Shipping,Technology,Telecommunications,Transportation,Utilities,IT」
            - 選択した「業種」は必ず要約文に含めてください。
            - 例：「ユーザーは業種が『IT』の求人を探しています。」のように言及してください。
        要約は100文字以内に収めてください。
        """

        # ライブラリを使ってメッセージを作成・送信
        message = await anthropic_client.messages.create(
            model=ANTHROPIC_MODEL,
            max_tokens=150,
            system=summary_system_prompt,
            messages=[{"role": "user", "content": user_message}],
        )

        # message オブジェクトから応答テキストを取得
        if message.content and isinstance(message.content, list):
            first_content_block = message.content[0]
            if (
                hasattr(first_content_block, "type")
                and first_content_block.type == "text"
            ):
                summary = first_content_block.text
                if summary:
                    logger.info(f"Successfully summarized message: '{summary}'")
                    return summary.strip()

        logger.warning("Failed to summarize message, returning original message")
        return user_message  # 要約に失敗した場合は元のメッセージを返す

    except Exception as e:
        logger.exception(f"Error summarizing message: {e}")
        return user_message  # エラーが発生した場合は元のメッセージを返す


async def generate_response_from_agent_reply(
    agent_reply: str, user_message: str
) -> str:
    """
    Salesforce Agent APIの返信を使用して、ユーザー向けの応答を生成する

    Args:
        agent_reply: Salesforce Agent APIからの返信
        user_message: 元のユーザーメッセージ

    Returns:
        生成された応答
    """
    if not anthropic_client:  # クライアントが初期化されていない場合
        logger.error("Anthropic client is not available.")
        return "申し訳ありません、現在AIによる応答生成機能を利用できません。設定を確認中です。"

    try:
        logger.info(f"Generating response from agent reply using Anthropic API")

        # 応答生成用のシステムプロンプト
        response_system_prompt = """
        あなたは、求職者のキャリア相談に乗り、適切な求人を紹介するキャリアアドバイザーBotです。
        以下の点を考慮して、丁寧かつ親身に対応してください。

        *   **あなたの役割:** 求職者の希望やスキル、経験などをヒアリングし、最適な求人情報を提供することです。求人紹介に関連しない雑談にも応じますが、最終的には求人の話につなげるように意識してください。
        *   **応答スタイル:** 親しみやすく、プロフェッショナルなトーンで応答してください。専門用語は避け、分かりやすい言葉で説明してください。感嘆符や絵文字を使って、フレンドリーな雰囲気を出してください。
        *   **会社名の扱い（重要）**
            - エージェントから「株式会社ITカンパニー」など具体的な会社名が返ってきた場合、必ずあなたの返信文中にその会社名を含めてください。
            - 例：「現在『株式会社ITカンパニー』が見つかっていますので、こちらのほかにも…」のように言及してください。
            - エージェントからの返信に会社名が含まれていない場合は、あなたの判断で会社名を入れないでください。

        ユーザーからのメッセージと、Salesforceのエージェントからの返信情報をもとに、最適な応答を生成してください。
        エージェントからの返信情報を参考にしつつ、自然な会話になるように応答を作成してください。
        """

        # ライブラリを使ってメッセージを作成・送信
        message = await anthropic_client.messages.create(
            model=ANTHROPIC_MODEL,
            max_tokens=1024,
            system=response_system_prompt,
            messages=[
                {
                    "role": "user",
                    "content": f"ユーザーメッセージ: {user_message}\n\nエージェント返信: {agent_reply}",
                }
            ],
        )

        # message オブジェクトから応答テキストを取得
        if message.content and isinstance(message.content, list):
            first_content_block = message.content[0]
            if (
                hasattr(first_content_block, "type")
                and first_content_block.type == "text"
            ):
                response = first_content_block.text
                if response:
                    logger.info(
                        f"Successfully generated response from agent reply: '{response[:100]}...'"
                    )
                    return response.strip()

        logger.warning("Failed to generate response from agent reply")
        return "申し訳ありません、現在応答を生成できません。しばらくしてからもう一度お試しください。"

    except Exception as e:
        logger.exception(f"Error generating response from agent reply: {e}")
        return "申し訳ありません、現在応答を生成できません。しばらくしてからもう一度お試しください。"


async def call_anthropic_api(user_message: str) -> str:
    """Anthropic APIを呼び出し、応答テキストを取得する (anthropic ライブラリ使用)"""
    if not anthropic_client:  # クライアントが初期化されていない場合
        logger.error("Anthropic client is not available.")
        return "申し訳ありません、現在AIによる応答生成機能を利用できません。設定を確認中です。"

    try:
        logger.info(
            f"Calling Anthropic API ({ANTHROPIC_MODEL}) using library for: '{user_message[:50]}...'"
        )

        # ライブラリを使ってメッセージを作成・送信
        message = await anthropic_client.messages.create(
            model=ANTHROPIC_MODEL,
            max_tokens=1024,
            system=SYSTEM_PROMPT,
            messages=[{"role": "user", "content": user_message}],
        )
        # message オブジェクトから応答テキストを取得
        # message.content はリスト形式: [TextBlock(text='...', type='text')]
        logger.info(f"Received response from Anthropic library: {message}")
        if message.content and isinstance(message.content, list):
            first_content_block = message.content[0]
            # TextBlock かどうか、typeがtextかを確認 (より安全に)
            if (
                hasattr(first_content_block, "type")
                and first_content_block.type == "text"
            ):
                claude_response = first_content_block.text
                if claude_response:
                    logger.info(
                        f"Received response via library: '{claude_response[:100]}...'"
                    )
                    return claude_response.strip()
            else:
                logger.warning(
                    f"Received non-text block from Anthropic library: {type(first_content_block)}"
                )
        else:
            logger.warning(
                f"Unexpected response structure from Anthropic library: {message}"
            )

        return "申し訳ありません、応答を正しく解析できませんでした。"

    except anthropic.APIConnectionError as e:
        logger.error(f"Anthropic API connection error: {e.__cause__}")
        return "申し訳ありません、AIサーバーへの接続に失敗しました。ネットワークを確認してください。"
    except anthropic.RateLimitError as e:
        logger.error(f"Anthropic API rate limit exceeded: {e}")
        return "申し訳ありません、現在リクエストが混み合っています。少し時間をおいて再度お試しください。"
    except anthropic.AuthenticationError as e:
        logger.error(f"Anthropic API authentication error: {e}")
        return "申し訳ありません、AI機能の認証に問題が発生しました。APIキーを確認してください。"
    except anthropic.BadRequestError as e:
        logger.error(f"Anthropic API bad request error: {e}")
        # プロンプトが長すぎる、形式が不正などの可能性
        return (
            "申し訳ありません、リクエスト内容に問題があり、AIが応答できませんでした。"
        )
    except anthropic.APIStatusError as e:
        logger.error(
            f"Anthropic API non-200 status error: status_code={e.status_code}, response={e.response}"
        )
        return f"申し訳ありません、AI応答の取得中にエラーが発生しました。(Status: {e.status_code})"
    except Exception as e:
        # httpx.TimeoutException など、ライブラリが内部でラップしないエラーも捕捉
        logger.exception(f"Unexpected error calling Anthropic API via library: {e}")
        if isinstance(e, httpx.TimeoutException):
            return "申し訳ありません、AIからの応答が時間内に得られませんでした。再度お試しください。"
        return (
            "申し訳ありません、予期せぬエラーが発生し、AI応答を取得できませんでした。"
        )
