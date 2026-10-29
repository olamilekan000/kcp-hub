SHELL := /usr/bin/env bash
.DEFAULT_GOAL := help

ISSUES := https://github.com/olamilekan000/kcp-hub/issues

define not-yet
	@echo "$@ is not implemented yet, see $(ISSUES)/$(1)" >&2; exit 1
endef

##@ Platform

.PHONY: up
up: ## Create a kind cluster running kcp at https://kcp.localhost:8443
	hack/up.sh

.PHONY: down
down: ## Delete the kind cluster and everything in .hub/
	hack/down.sh

##@ Checks

.PHONY: test
test: ## Smoke test a running platform (not implemented yet)
	$(call not-yet,8)

.PHONY: lint
lint: lint-yaml lint-shell ## Run all linters

.PHONY: lint-yaml
lint-yaml: ## Lint YAML files (needs yamllint)
	yamllint --strict .

.PHONY: lint-shell
lint-shell: ## Lint shell scripts (needs shellcheck)
	@scripts=$$(git ls-files '*.sh'); \
	if [ -n "$$scripts" ]; then shellcheck $$scripts; else echo "no shell scripts to check"; fi

##@ Help

.PHONY: help
help: ## Show this help
	@awk 'BEGIN {FS = ":.*##"; printf "Usage: make <target>\n"} \
		/^[a-zA-Z_-]+:.*##/ { printf "  %-12s %s\n", $$1, $$2 } \
		/^##@/ { printf "\n%s\n", substr($$0, 5) }' $(MAKEFILE_LIST)
	@printf '%s\n' \
		'' \
		'make up needs docker, kind, kubectl, helm and curl. Afterwards:' \
		'  export KUBECONFIG=$$PWD/.hub/admin.kubeconfig' \
		'  kubectl get workspaces' \
		'' \
		'Set CLUSTER_NAME to use a cluster name other than kcp-hub.'
