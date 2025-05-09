# Lambdaオーソライザー関数の例 (抜粋)
import os
import json
import hmac
import hashlib
import base64
import boto3

secrets_manager = boto3.client("secretsmanager")


def get_bot_secret():
    secret_name = os.environ[
        "LW_BOT_SECRET_NAME"
    ]  # Lambdaの環境変数でSecretの名前を指定
    response = secrets_manager.get_secret_value(SecretId=secret_name)
    secret_string = response["SecretString"]
    return json.loads(secret_string)["LW_API_BOT_SECRET"]  # Secretの形式に合わせて調整


def lambda_handler(event, context):
    signature = event["headers"].get(
        "x-works-signature"
    )  # ヘッダー名は大文字・小文字区別なしでAPI Gatewayが正規化してくれる場合がある
    request_body = event["body"]  # API Gatewayが渡す形式に依存
    bot_secret = get_bot_secret()

    if not signature or not request_body or not bot_secret:
        return generate_policy("user", "Deny", event["methodArn"])

    try:
        hashed = hmac.new(
            bot_secret.encode("utf-8"), request_body.encode("utf-8"), hashlib.sha256
        ).digest()
        expected_signature = base64.b64encode(hashed).decode("utf-8")

        if hmac.compare_digest(expected_signature, signature):
            return generate_policy("user", "Allow", event["methodArn"])
        else:
            # print(f"Invalid signature. Expected: {expected_signature}, Got: {signature}") # CloudWatch Logsで確認
            return generate_policy("user", "Deny", event["methodArn"])
    except Exception as e:
        # print(f"Error during signature validation: {e}")
        return generate_policy("user", "Deny", event["methodArn"])


def generate_policy(principal_id, effect, resource):
    auth_response = {"principalId": principal_id}
    if effect and resource:
        policy_document = {
            "Version": "2012-10-17",
            "Statement": [
                {"Action": "execute-api:Invoke", "Effect": effect, "Resource": resource}
            ],
        }
        auth_response["policyDocument"] = policy_document
    return auth_response
