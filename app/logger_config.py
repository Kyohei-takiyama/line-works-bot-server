# app/logger_config.py
import logging
import sys

LOG_LEVEL = logging.INFO  # ログレベルを定数として定義


def setup_logger():
    """アプリケーションのルートロガーを設定する関数"""
    # 既に設定済みかチェック (多重設定を防ぐ)
    # ここではルートロガーにハンドラがあるかで簡易的に判断
    root_logger = logging.getLogger()
    if root_logger.handlers:
        # print("Logger already configured.") # デバッグ用
        return

    # フォーマッターを作成
    log_formatter = logging.Formatter(
        "%(asctime)s - %(name)s - %(levelname)s - [%(filename)s:%(lineno)d] - %(message)s",
        datefmt="%Y-%m-%d %H:%M:%S",  # 日付フォーマットも指定
    )

    # ハンドラーを作成 (標準出力)
    log_handler = logging.StreamHandler(sys.stdout)
    log_handler.setFormatter(log_formatter)
    log_handler.setLevel(LOG_LEVEL)  # ハンドラーにもレベル設定が可能

    # ルートロガーにハンドラーを追加
    root_logger.addHandler(log_handler)
    # ルートロガーのレベルを設定 (ハンドラーのレベルより優先される)
    root_logger.setLevel(LOG_LEVEL)

    # Uvicornのロガーにも設定を適用する (オプション)
    # これによりUvicornのログも同じフォーマット・レベルで出力される
    # for name in ["uvicorn", "uvicorn.error", "uvicorn.access"]:
    #     uv_logger = logging.getLogger(name)
    #     uv_logger.handlers = [log_handler] # 既存のハンドラを置き換える
    #     uv_logger.propagate = False # ルートへの伝播は不要にする
    #     uv_logger.setLevel(LOG_LEVEL) # レベルを設定

    logging.getLogger(__name__).info("Logger configured successfully.")


# 必要に応じて、ファイルへのログ出力ハンドラなどを追加することも可能
# def add_file_handler(filename="app.log"):
#     root_logger = logging.getLogger()
#     log_formatter = logging.Formatter(...)
#     file_handler = logging.FileHandler(filename, encoding='utf-8')
#     file_handler.setFormatter(log_formatter)
#     file_handler.setLevel(LOG_LEVEL)
#     root_logger.addHandler(file_handler)
