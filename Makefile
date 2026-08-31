# Task runner for terraform-aws-skill-workbench.
#
# Targets that read Terraform outputs use TF_DIR, which defaults to the example
# assuming a VPC that already has the endpoints. Point it at your own root
# configuration:
#
#   make frontend TF_DIR=../my-infra

TF      ?= terraform
TFLINT  ?= tflint
PYTHON  ?= python3
TF_DIR  ?= examples/vpc-and-endpoints-already-exist
MODULE_ADDRESS ?= module.skill_workbench
TEST_VENV ?= .venv

FRONTEND_DIR := frontend
EXAMPLES     := $(wildcard examples/*)

.DEFAULT_GOAL := help
.PHONY: help fmt fmt-check validate validate-modules validate-examples test test-tf \
        lint docs docs-check scan scan-container scan-report \
        frontend-install frontend-check frontend-serve \
        frontend-dev frontend-env frontend user refresh-service-model clean

help: ## Show this help
	@grep -hE '^[a-zA-Z_-]+:.*?## ' $(MAKEFILE_LIST) | awk 'BEGIN {FS = ":.*?## "}; {printf "  \033[36m%-22s\033[0m %s\n", $$1, $$2}'
	@echo ""
	@echo "  TF_DIR is currently '$(TF_DIR)' — the root configuration outputs are read from."

# --- Gates. Every target in this section runs with no AWS credentials. --------

fmt: ## Rewrite all Terraform files in canonical format
	$(TF) fmt -recursive .

fmt-check: ## Fail if any Terraform file is not canonically formatted
	$(TF) fmt -check -recursive .

validate: ## Validate the module itself
	TF_DATA_DIR=.terraform/validate $(TF) init -backend=false -input=false >/dev/null
	TF_DATA_DIR=.terraform/validate $(TF) validate

validate-modules: ## Validate every nested module under modules/
	@for d in modules/*/; do \
	  echo "== $$d"; \
	  ( cd $$d && TF_DATA_DIR=.terraform/validate $(TF) init -backend=false -input=false >/dev/null \
	    && TF_DATA_DIR=.terraform/validate $(TF) validate ) || exit 1; \
	done

validate-examples: ## Validate every root configuration under examples/
	@for d in $(EXAMPLES); do \
	  echo "== $$d"; \
	  ( cd $$d && TF_DATA_DIR=.terraform/validate $(TF) init -backend=false -input=false >/dev/null \
	    && TF_DATA_DIR=.terraform/validate $(TF) validate ) || exit 1; \
	done

test: ## Run the proxy Lambda unit tests
	cd tests && $(PYTHON) -m venv $(TEST_VENV) \
	  && $(TEST_VENV)/bin/pip install -q -r requirements-test.txt \
	  && $(TEST_VENV)/bin/python -m pytest . -q

test-tf: ## Run the plan-only Terraform tests
	# init is needed even though the tests mock the provider: mock_provider borrows the
	# real provider's schema, so the plugin still has to be installed. -backend=false
	# keeps it credential-free.
	$(TF) init -backend=false -input=false >/dev/null
	$(TF) test -test-directory=tests

lint: ## Run tflint against the module and every nested module
	$(TFLINT) --init
	$(TFLINT) --recursive --config "$(CURDIR)/.tflint.hcl"

docs: ## Regenerate the README input and output tables. Commit the result.
	terraform-docs .

docs-check: ## Fail if the README tables are stale
	terraform-docs --output-check .

# --- Security scanning -------------------------------------------------------
# ASH (awslabs/automated-security-helper) orchestrates several scanners over the
# whole repository at once, which is what makes it a good fit here: this is not
# one language. Checkov reads the Terraform, Bandit the proxy Lambda, npm-audit
# the frontend's lock file, and detect-secrets everything.
#
# No AWS credentials and nothing deployed — the scanners read source. Unlike the
# gates above it does need network access, because uvx fetches ASH and ASH fetches
# each scanner into an isolated environment on first run. Later runs hit the cache.
#
# ASH respects .gitignore, so .terraform, node_modules, dist, the venvs and
# frontend/.env.local are all out of scope without configuring anything.
#
# Exit codes: 0 clean, 1 ASH itself failed, 2 findings at or above ASH_MIN_SEVERITY.
# 2 is a failed make target on purpose — this is a gate, not a report.

ASH_VERSION      ?= v3.7.0
ASH              ?= uvx --from git+https://github.com/awslabs/automated-security-helper.git@$(ASH_VERSION) ash
ASH_OUTPUT_DIR   ?= .ash/ash_output
ASH_MIN_SEVERITY ?= medium
ASH_OCI_RUNNER   ?= docker

scan: ## Run an ASH security scan in local mode. Needs network on first run, no AWS credentials.
	@command -v $(firstword $(ASH)) >/dev/null || { \
	  echo "error: $(firstword $(ASH)) not found on PATH."; \
	  echo "       Install uv:  curl -sSfL https://astral.sh/uv/install.sh | sh"; \
	  echo "       Or point ASH at an existing install:  make scan ASH=ash"; \
	  exit 1; }
	$(ASH) --mode local \
	  --source-dir . \
	  --output-dir $(ASH_OUTPUT_DIR) \
	  --min-severity $(ASH_MIN_SEVERITY)

scan-container: ## Run the same scan in container mode, which adds the scanners local mode skips
	# Local mode only runs what it can install through uv. cfn-nag needs Ruby, and
	# Grype and Syft are separate binaries, so container mode is the only way to get
	# the full set without installing them yourself. Costs an image build the first time.
	@command -v $(ASH_OCI_RUNNER) >/dev/null || { \
	  echo "error: $(ASH_OCI_RUNNER) not found on PATH."; \
	  echo "       Any OCI runtime works:  make scan-container ASH_OCI_RUNNER=finch"; \
	  exit 1; }
	$(ASH) --mode container \
	  --oci-runner $(ASH_OCI_RUNNER) \
	  --source-dir . \
	  --output-dir $(ASH_OUTPUT_DIR) \
	  --min-severity $(ASH_MIN_SEVERITY)

scan-report: ## Summarise the last scan's findings without re-scanning
	@[ -f "$(ASH_OUTPUT_DIR)/ash_aggregated_results.json" ] || { \
	  echo "error: no scan results in $(ASH_OUTPUT_DIR). Run make scan first."; exit 1; }
	$(ASH) report --output-dir $(ASH_OUTPUT_DIR) --format markdown
	@echo ""
	@echo "  HTML report: $(ASH_OUTPUT_DIR)/reports/ash.html"
	@echo "  SARIF:       $(ASH_OUTPUT_DIR)/reports/ash.sarif"

# --- Frontend. Terraform cannot build a React application. -------------------

frontend-install: ## Install frontend dependencies
	@cd $(FRONTEND_DIR) && if [ -f package-lock.json ]; then \
	  npm ci --no-audit --no-fund; \
	else \
	  echo "no package-lock.json yet — running npm install to create one. Commit it."; \
	  npm install --no-audit --no-fund; \
	fi

frontend-check: frontend-install ## Type-check and build the frontend. No AWS credentials, nothing deployed.
	cd $(FRONTEND_DIR) && npx tsc --noEmit && npm run build
	@echo "built $(FRONTEND_DIR)/dist"

frontend-serve: frontend-install ## Serve the frontend with no backend. Layout only — sign-in cannot work.
	@echo "No .env.local is written, so Cognito is unconfigured and sign-in will fail."
	cd $(FRONTEND_DIR) && npm run dev

frontend-env: ## Write frontend/.env.local from TF_DIR's Terraform outputs
	TF_DIR=$(TF_DIR) ./scripts/frontend-env.sh

frontend-dev: frontend-env frontend-install ## Serve the frontend against the deployed backend
	cd $(FRONTEND_DIR) && npm run dev

frontend: ## Build the frontend and deploy it to Amplify
	TF_DIR=$(TF_DIR) ./scripts/deploy-frontend.sh

# --- Apply and teardown ------------------------------------------------------
# These act on TF_DIR, which is a root configuration — by default the complete
# example. A module is never applied directly. Point TF_DIR at your own root
# configuration to use these against it:
#
#   make plan TF_DIR=../my-infra

init: ## terraform init in TF_DIR
	cd $(TF_DIR) && $(TF) init -input=false

plan: init ## terraform plan in TF_DIR
	cd $(TF_DIR) && $(TF) plan

apply: init ## terraform apply in TF_DIR, interactively. Creates billable resources.
	@echo "This creates billable resources. The harness bills per second of session time,"
	@echo "and any VPC endpoints this creates bill hourly whether used or not."
	@echo ""
	cd $(TF_DIR) && $(TF) apply

output: ## terraform output for TF_DIR
	cd $(TF_DIR) && $(TF) output

destroy: ## terraform destroy for TF_DIR
	@echo "A single-pass destroy fails, and that is not a defect in this module."
	@echo "AgentCore's service-owned ENIs persist for up to eight hours after the harness"
	@echo "is deleted, and a security group cannot be deleted while an ENI references it."
	@echo "Just re-run make destroy again after eight hours."
	cd $(TF_DIR) && $(TF) destroy

# --- Operations --------------------------------------------------------------

user: ## Create or reset a Cognito user, interactively
	TF_DIR=$(TF_DIR) ./scripts/create-user.sh

refresh-service-model: ## Re-fetch the vendored botocore service model from upstream
	./scripts/refresh-service-model.sh

clean: ## Remove build artefacts and validation state
	rm -rf .terraform/validate modules/*/.terraform examples/*/.terraform
	rm -rf $(FRONTEND_DIR)/dist tests/$(TEST_VENV) tests/.pytest_cache
	rm -rf $(ASH_OUTPUT_DIR)
	find . -name __pycache__ -type d -prune -exec rm -rf {} +
