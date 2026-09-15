#!/bin/sh
# Agent Hub launchd servislarini o'rnatadi yoki yangilaydi (idempotent).
# Parametrlar: --force, --agent-hub-port, --kanbot-port, --label-prefix (scripts/services.py).
set -eu
repo=$(cd "$(dirname "$0")/.." && pwd)
python="$repo/.venv/bin/python"
if [ ! -x "$python" ]; then
	echo "install-services: $python topilmadi, avval 'make sync'" >&2
	exit 1
fi
exec "$python" "$repo/scripts/services.py" install "$@"
