#!/bin/sh
# Agent Hub launchd servislarini to'xtatadi va plist'larini o'chiradi. Loglar qoladi.
set -eu
repo=$(cd "$(dirname "$0")/.." && pwd)
python="$repo/.venv/bin/python"
if [ ! -x "$python" ]; then
	echo "uninstall-services: $python topilmadi, avval 'make sync'" >&2
	exit 1
fi
exec "$python" "$repo/scripts/services.py" uninstall "$@"
