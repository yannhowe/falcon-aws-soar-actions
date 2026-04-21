.PHONY: setup deploy-accounts deploy-ou test cleanup validate help

SHELL := /bin/bash
PARAMS ?= cloudformation-stacksets/examples/parameters-basic.json
ACCOUNTS ?=
OUS ?=
REGIONS ?= us-east-1
ROLE_NAME ?= CrowdStrikeAutomatedResponse

help: ## Show this help
	@grep -E '^[a-zA-Z_-]+:.*?## .*$$' $(MAKEFILE_LIST) | sort | awk 'BEGIN {FS = ":.*?## "}; {printf "\033[36m%-20s\033[0m %s\n", $$1, $$2}'

setup: ## Interactive setup — prompts for config and deploys
	@./setup.sh

deploy-accounts: ## Deploy to specific accounts (ACCOUNTS=111,222 PARAMS=file)
	@if [ -z "$(ACCOUNTS)" ]; then echo "Usage: make deploy-accounts ACCOUNTS=111111111111,222222222222"; exit 1; fi
	cd cloudformation-stacksets/scripts && ./deploy-stackset.sh -m accounts -p ../../$(PARAMS) -a "$(ACCOUNTS)" -r "$(REGIONS)"

deploy-ou: ## Deploy to an OU (OUS=ou-xxxx-yyyy PARAMS=file)
	@if [ -z "$(OUS)" ]; then echo "Usage: make deploy-ou OUS=ou-xxxx-yyyyyyyy"; exit 1; fi
	cd cloudformation-stacksets/scripts && ./deploy-stackset.sh -m ou -p ../../$(PARAMS) -a "$(OUS)" -r "$(REGIONS)"

test: ## Run deployment tests (ROLE_NAME=CrowdStrikeAutomatedResponse)
	@./scripts/test-soar-deployment.sh $(ROLE_NAME)

test-quick: ## Quick validation — role exists and has policies
	@echo "Checking role $(ROLE_NAME)..."
	@aws iam get-role --role-name $(ROLE_NAME) --query 'Role.Arn' --output text
	@aws iam list-role-policies --role-name $(ROLE_NAME) --query 'PolicyNames' --output text

cleanup: ## Remove StackSet and all instances (interactive confirmation)
	cd cloudformation-stacksets/scripts && ./cleanup-stackset.sh

validate: ## Lint CloudFormation templates with cfn-lint
	@command -v cfn-lint >/dev/null 2>&1 || { echo "Install cfn-lint: pip install cfn-lint"; exit 1; }
	cfn-lint cloudformation-stacksets/templates/*.yaml

status: ## Show StackSet deployment status
	@aws cloudformation list-stack-instances --stack-set-name CrowdStrike-SOAR-Actions --query 'Summaries[*].[Account,Region,Status]' --output table 2>/dev/null || echo "No StackSet found"
