SHELL := /bin/zsh
.DEFAULT_GOAL := help

UV ?= uv
NPM ?= npm
KANBOT ?= kanbot
# KanBot venv python'i (uv tool): himoya launcher'i kanbot paketini shu python bilan import qiladi.
KANBOT_PYTHON ?= $(shell k=$$(command -v $(KANBOT)) && print -r -- $${k:A:h}/python)
AGENT_HUB_PORT ?= 8700
KANBOT_PORT ?= 8787
LOG_LINES ?= 50
# make install FORCE=1: qo'lda ishlayotgan KanBot/runner yoki tirik pane'larga qaramay davom etish.
LABEL_PREFIX ?= local.agent-hub
PORT_ARGS = --agent-hub-port $(AGENT_HUB_PORT) --kanbot-port $(KANBOT_PORT) --label-prefix $(LABEL_PREFIX)
SERVICE_ARGS = $(PORT_ARGS)$(if $(FORCE), --force)

.PHONY: help sync build lint typecheck test test-integration check dev dev-web dev-kanbot dev-runner \
	install uninstall status logs

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

test: ## pytest (mock'lar bilan) + vitest
	$(UV) run pytest
	cd web && $(NPM) test

test-integration: ## Haqiqiy CLI bilan integratsion testlar
	$(UV) run pytest -m integration

check: lint typecheck test ## Barcha tekshiruvlar

dev: build ## Agent Hub backend (127.0.0.1:$(AGENT_HUB_PORT))
	AGENT_HUB_PORT=$(AGENT_HUB_PORT) AGENT_HUB_EXTRA_ORIGINS=http://127.0.0.1:5173,http://localhost:5173 \
		$(UV) run python -m agent_hub

dev-web: ## Vite dev server (127.0.0.1:5173, /api -> backend)
	cd web && AGENT_HUB_PORT=$(AGENT_HUB_PORT) $(NPM) run dev

dev-kanbot: ## KanBot server, Host/Origin himoyasi bilan (127.0.0.1:$(KANBOT_PORT))
	@test -x "$(KANBOT_PYTHON)" || { echo "KanBot python topilmadi: '$(KANBOT_PYTHON)'" >&2; exit 1; }
	$(KANBOT_PYTHON) scripts/kanbot_guarded_server.py --port $(KANBOT_PORT)

dev-runner: ## KanBot runner, SAFE rejim
	$(KANBOT) runner --safe --server http://127.0.0.1:$(KANBOT_PORT)

install: build ## launchd servislarini o'rnatish/yangilash (idempotent; FORCE=1)
	scripts/install-services.sh $(SERVICE_ARGS)

uninstall: ## launchd servislarini to'xtatish va o'chirish (loglar qoladi; FORCE=1)
	scripts/uninstall-services.sh $(SERVICE_ARGS)

status: ## Servislar, health, runner va auto_approve holati
	@test -x .venv/bin/python || { echo "Avval 'make sync'" >&2; exit 1; }
	@.venv/bin/python scripts/services.py status $(PORT_ARGS)

logs: ## Servis loglari (~/Library/Logs/agent-hub, tail -F)
	@logs=($$HOME/Library/Logs/agent-hub/*.log(N)); \
	if (( ! $${#logs} )); then echo "Loglar hali yo'q: $$HOME/Library/Logs/agent-hub" >&2; exit 1; fi; \
	tail -n $(LOG_LINES) -F $$logs
