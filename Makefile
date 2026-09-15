SHELL := /bin/zsh
.DEFAULT_GOAL := help

UV ?= uv
NPM ?= npm
KANBOT ?= kanbot
AGENT_HUB_PORT ?= 8700
KANBOT_PORT ?= 8787

.PHONY: help sync build lint typecheck test test-integration check dev dev-web dev-kanbot dev-runner

help: ## Buyruqlar ro'yxati
	@grep -E '^[a-z-]+:.*## ' $(MAKEFILE_LIST) | awk 'BEGIN {FS = ":.*## "}; {printf "  %-18s %s\n", $$1, $$2}'

sync: ## Python va npm bog'liqliklarini o'rnatish
	$(UV) sync
	cd web && $(NPM) ci

build: ## Frontend build (src/agent_hub/static)
	cd web && $(NPM) run build

lint: ## ruff + eslint
	$(UV) run ruff check
	$(UV) run ruff format --check
	cd web && $(NPM) run lint

typecheck: ## mypy --strict + tsc --noEmit
	$(UV) run mypy
	cd web && $(NPM) run typecheck

test: ## pytest (mock'lar bilan)
	$(UV) run pytest

test-integration: ## Haqiqiy CLI bilan integratsion testlar
	$(UV) run pytest -m integration

check: lint typecheck test ## Barcha tekshiruvlar

dev: build ## Agent Hub backend (127.0.0.1:$(AGENT_HUB_PORT))
	AGENT_HUB_PORT=$(AGENT_HUB_PORT) $(UV) run python -m agent_hub

dev-web: ## Vite dev server (127.0.0.1:5173, /api -> backend)
	cd web && AGENT_HUB_PORT=$(AGENT_HUB_PORT) $(NPM) run dev

dev-kanbot: ## KanBot server (127.0.0.1:$(KANBOT_PORT))
	$(KANBOT) server --host 127.0.0.1 --port $(KANBOT_PORT)

dev-runner: ## KanBot runner, SAFE rejim
	$(KANBOT) runner --safe --server http://127.0.0.1:$(KANBOT_PORT)
