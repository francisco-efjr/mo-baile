# Mo baile — atalhos de desenvolvimento.
#
# `make setup` uma vez; depois `make check` antes de qualquer commit.

SHELL := /bin/bash
PYTHON ?= python3
VENV := .venv
VENV_PY := $(VENV)/bin/python
SWIFT_APP := apps/MoBaile

.DEFAULT_GOAL := help
.PHONY: help setup test test-engine test-ui test-swift lint format security audit fixtures check run run-engine install-app build-native clean

help: ## Lista os alvos disponiveis
	@grep -E '^[a-zA-Z_-]+:.*?## .*$$' $(MAKEFILE_LIST) | awk 'BEGIN {FS = ":.*?## "}; {printf "  \033[36m%-14s\033[0m %s\n", $$1, $$2}'

setup: ## Cria o ambiente virtual e instala motor + UI em modo editavel
	$(PYTHON) -m venv $(VENV)
	$(VENV_PY) -m pip install --upgrade pip
	$(VENV_PY) -m pip install -e "engine[dev,macos]"
	$(VENV_PY) -m pip install -e apps/tk-legacy
	@echo "pronto. Ative com: source $(VENV)/bin/activate"

test: test-engine test-ui ## Roda as suites Python

test-engine: ## Suite do motor (nao precisa de aparelho nem de servidor grafico)
	cd engine && $(abspath $(VENV_PY)) -m pytest

test-ui: ## Suite da UI Tkinter (precisa de sessao grafica)
	cd apps/tk-legacy && PYTHONPATH=.:../../engine/src $(abspath $(VENV_PY)) -m pytest

test-swift: ## Suite do front nativo (so no macOS, com Swift instalado)
	cd $(SWIFT_APP) && swift test

coverage: ## Cobertura do motor
	cd engine && $(abspath $(VENV_PY)) -m pytest --cov --cov-report=term-missing

lint: ## Analise estatica
	$(VENV_PY) -m ruff check engine apps tools

format: ## Corrige o que o lint sabe corrigir sozinho
	$(VENV_PY) -m ruff check --fix engine apps tools

security: ## Varredura de padroes inseguros no codigo
	$(VENV_PY) -m bandit -q -r engine/src apps/tk-legacy -ll

audit: ## Vulnerabilidades conhecidas nas dependencias
	$(VENV_PY) -m pip_audit --skip-editable

fixtures: ## Regera as fixtures do contrato usadas pela suite Swift
	$(PYTHON) tools/generate_fixtures.py

check: lint security test ## Portao antes do commit

run: ## Sobe a interface Tkinter a partir do codigo-fonte
	$(VENV_PY) apps/tk-legacy/main.py

run-engine: ## Sobe o motor em modo JSON-RPC (util para depurar o contrato)
	PYTHONPATH=engine/src $(VENV_PY) -m mobaile.rpc

install-app: ## Instala o "Mo baile.app" com a interface Python (a que funciona)
	bash tools/install_tk_app.sh

build-native: ## Empacota o front SwiftUI como app SEPARADO, apos swift test passar
	bash tools/package_macos_app.sh

clean: ## Remove artefatos de build e cache
	find . -name "__pycache__" -type d -prune -exec rm -rf {} + 2>/dev/null || true
	rm -rf .pytest_cache .ruff_cache engine/.pytest_cache .coverage htmlcov
	rm -rf $(SWIFT_APP)/.build
