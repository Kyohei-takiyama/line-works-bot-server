# 変数
ENV ?= dev
BACKEND_BUCKET ?= line-works-bot-terraform-state-$(ENV)
BACKEND_TABLE ?= line-works-bot-terraform-lock-$(ENV)
BACKEND_REGION ?= ap-northeast-1
TFVARS_FILE ?= environments/$(ENV)/$(ENV).tfvars

# Docker/ECR関連の変数
ECR_REGION ?= ap-northeast-1
ECR_ACCOUNT_ID ?= 876387127002
ECR_REPOSITORY ?= line-works-bot-$(ENV)
ECR_URL ?= $(ECR_ACCOUNT_ID).dkr.ecr.$(ECR_REGION).amazonaws.com
IMAGE_NAME ?= $(ECR_REPOSITORY)
IMAGE_TAG ?= latest

# ヘルプ
.PHONY: help
help:
	@echo "使用方法:"
	@echo "  make init ENV=<環境名>                  - Terraformを初期化します (デフォルト: dev)"
	@echo "  make plan ENV=<環境名>                  - 実行計画を表示します"
	@echo "  make apply ENV=<環境名>                 - インフラを適用します"
	@echo "  make destroy ENV=<環境名>               - インフラを破棄します"
	@echo "  make fmt                               - Terraformファイルをフォーマットします"
	@echo "  make validate ENV=<環境名>              - Terraformファイルを検証します"
	@echo "  make create-backend ENV=<環境名>        - S3バケットとDynamoDBテーブルを作成します"
	@echo "  make dev-init                          - 開発環境を初期化します"
	@echo "  make dev-plan                          - 開発環境の実行計画を表示します"
	@echo "  make dev-apply                         - 開発環境にインフラを適用します"
	@echo "  make dev-destroy                       - 開発環境のインフラを破棄します"
	@echo "  make stg-init                          - ステージング環境を初期化します"
	@echo "  make stg-plan                          - ステージング環境の実行計画を表示します"
	@echo "  make stg-apply                         - ステージング環境にインフラを適用します"
	@echo "  make stg-destroy                       - ステージング環境のインフラを破棄します"
	@echo "  make prd-init                          - 本番環境を初期化します"
	@echo "  make prd-plan                          - 本番環境の実行計画を表示します"
	@echo "  make prd-apply                         - 本番環境にインフラを適用します"
	@echo "  make prd-destroy                       - 本番環境のインフラを破棄します"
	@echo "  make ecr-login                         - ECRにログインします"
	@echo "  make docker-build                      - Dockerイメージをビルドします"
	@echo "  make docker-tag                        - Dockerイメージにタグを付けます"
	@echo "  make docker-push                       - Dockerイメージをプッシュします"
	@echo "  make ecr-push ENV=<環境名>              - 全ステップを実行してECRにプッシュします (デフォルト: dev)"
	@echo "  make dev-ecr-push                      - 開発環境のECRにプッシュします"
	@echo "  make stg-ecr-push                      - ステージング環境のECRにプッシュします"
	@echo "  make prd-ecr-push                      - 本番環境のECRにプッシュします"

# バックエンド（S3バケットとDynamoDBテーブル）の作成
.PHONY: create-backend
create-backend:
	@echo "Creating S3 bucket $(BACKEND_BUCKET) and DynamoDB table $(BACKEND_TABLE) for Terraform backend..."
	aws s3 mb s3://$(BACKEND_BUCKET) --region $(BACKEND_REGION)
	aws s3api put-bucket-versioning --bucket $(BACKEND_BUCKET) --versioning-configuration Status=Enabled
	aws s3api put-bucket-encryption --bucket $(BACKEND_BUCKET) --server-side-encryption-configuration '{"Rules": [{"ApplyServerSideEncryptionByDefault": {"SSEAlgorithm": "AES256"}}]}'
	aws dynamodb create-table \
		--table-name $(BACKEND_TABLE) \
		--attribute-definitions AttributeName=LockID,AttributeType=S \
		--key-schema AttributeName=LockID,KeyType=HASH \
		--billing-mode PAY_PER_REQUEST \
		--region $(BACKEND_REGION)
	@echo "Backend created successfully!"

# 初期化
.PHONY: init
init:
	@echo "Initializing Terraform for $(ENV) environment..."
	cd environments/$(ENV) && terraform init

# プラン
.PHONY: plan
plan:
	@echo "Planning Terraform for $(ENV) environment..."
	cd environments/$(ENV) && terraform plan -var-file=$(ENV).tfvars

# 適用
.PHONY: apply
apply:
	@echo "Applying Terraform for $(ENV) environment..."
	cd environments/$(ENV) && terraform apply -var-file=$(ENV).tfvars

# 破棄
.PHONY: destroy
destroy:
	@echo "Destroying Terraform for $(ENV) environment..."
	cd environments/$(ENV) && terraform destroy -var-file=$(ENV).tfvars

# フォーマット
.PHONY: fmt
fmt:
	@echo "Formatting Terraform files..."
	terraform fmt -recursive

# 検証
.PHONY: validate
validate:
	@echo "Validating Terraform files for $(ENV) environment..."
	cd environments/$(ENV) && terraform validate

# 開発環境
.PHONY: dev-init
dev-init:
	@$(MAKE) init ENV=dev

.PHONY: dev-plan
dev-plan:
	@$(MAKE) plan ENV=dev

.PHONY: dev-apply
dev-apply:
	@$(MAKE) apply ENV=dev

.PHONY: dev-destroy
dev-destroy:
	@$(MAKE) destroy ENV=dev

# ステージング環境
.PHONY: stg-init
stg-init:
	@$(MAKE) init ENV=stg

.PHONY: stg-plan
stg-plan:
	@$(MAKE) plan ENV=stg

.PHONY: stg-apply
stg-apply:
	@$(MAKE) apply ENV=stg

.PHONY: stg-destroy
stg-destroy:
	@$(MAKE) destroy ENV=stg

# 本番環境
.PHONY: prd-init
prd-init:
	@$(MAKE) init ENV=prd

.PHONY: prd-plan
prd-plan:
	@$(MAKE) plan ENV=prd

.PHONY: prd-apply
prd-apply:
	@$(MAKE) apply ENV=prd

.PHONY: prd-destroy
prd-destroy:
	@$(MAKE) destroy ENV=prd

# Docker/ECR関連のターゲット
# ECRにログイン
.PHONY: ecr-login
ecr-login:
	@echo "Logging in to ECR in $(ECR_REGION)..."
	aws ecr get-login-password --region $(ECR_REGION) | docker login --username AWS --password-stdin $(ECR_URL)

# Dockerイメージをビルド
.PHONY: docker-build
docker-build:
	@echo "Building Docker image $(IMAGE_NAME)..."
	docker build --platform=linux/amd64 -t $(IMAGE_NAME) ..

# Dockerイメージにタグを付ける
.PHONY: docker-tag
docker-tag:
	@echo "Tagging Docker image $(IMAGE_NAME):$(IMAGE_TAG) for ECR..."
	docker tag $(IMAGE_NAME):$(IMAGE_TAG) $(ECR_URL)/$(IMAGE_NAME):$(IMAGE_TAG)

# Dockerイメージをプッシュ
.PHONY: docker-push
docker-push:
	@echo "Pushing Docker image to ECR..."
	docker push $(ECR_URL)/$(IMAGE_NAME):$(IMAGE_TAG)

# 全ステップを実行してECRにプッシュ
.PHONY: ecr-push
ecr-push: ecr-login docker-build docker-tag docker-push
	@echo "Successfully pushed $(IMAGE_NAME):$(IMAGE_TAG) to $(ECR_URL)/$(IMAGE_NAME):$(IMAGE_TAG)"

# 開発環境のECRにプッシュ
.PHONY: dev-ecr-push
dev-ecr-push:
	@$(MAKE) ecr-push ENV=dev

# ステージング環境のECRにプッシュ
.PHONY: stg-ecr-push
stg-ecr-push:
	@$(MAKE) ecr-push ENV=stg

# 本番環境のECRにプッシュ
.PHONY: prd-ecr-push
prd-ecr-push:
	@$(MAKE) ecr-push ENV=prd