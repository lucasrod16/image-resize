SHELL := /usr/bin/env bash -o errexit -o pipefail -o nounset

IMAGE_VERSION := v0.0.1

LAMBDA_BIN := image-resize-lambda

BUILD_DIR := build

AWS_ACCOUNT_ID := 311065888708

IMAGE_NAME := $(AWS_ACCOUNT_ID).dkr.ecr.us-east-1.amazonaws.com/$(LAMBDA_BIN)

.PHONY: help
help: ## Display list of all targets
	@awk 'BEGIN {FS = ":.*##"; printf "\nUsage:\n  make \033[36m<target>\033[0m\n"} /^[a-zA-Z_-]+:.*?##/ { printf "  \033[36m%-15s\033[0m %s\n", $$1, $$2 } /^##@/ { printf "\n\033[1m%s\033[0m\n", substr($$0, 5) } ' $(MAKEFILE_LIST)

.PHONY: build-lambda
build-lambda: ## Compile the lambda binary
	GOOS=linux GOARCH=amd64 go build -o $(BUILD_DIR)/$(LAMBDA_BIN)

.PHONY: build-image
build-image: build-lambda ## Build container image
	docker build --platform linux/amd64 -t $(IMAGE_NAME):$(IMAGE_VERSION) .

.PHONY: login-ecr
login-ecr: ## Login to ECR repository
	aws ecr get-login-password --region us-east-1 | docker login --username AWS --password-stdin $(AWS_ACCOUNT_ID).dkr.ecr.us-east-1.amazonaws.com

.PHONY: push-image
push-image: login-ecr ## Push container image to registry
	docker push $(IMAGE_NAME):$(IMAGE_VERSION)

.PHONY: test-unit
test-unit: ## Run unit tests
	go test -count=1 -v ./lambda

.PHONY: test-e2e
test-e2e: build-image push-image ## Run e2e tests
	infra/test/e2e_test.sh
