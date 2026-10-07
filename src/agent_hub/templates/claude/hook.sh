#!/bin/sh
# PreToolUse hook: Bash buyrug'ini ishga tushishdan oldin tekshiradi.
# Claude hook'ga JSON'ni stdin orqali beradi; buyruq `.tool_input.command` da.
# Chiqish kodi 0 — ruxsat, 2 — bloklash (stderr matni Claude'ga ko'rsatiladi).
# Ro'yxatdan o'tkazish: settings.json -> hooks.PreToolUse (Agent Hub'dagi "settings + hook" shablonini ko'ring).
set -eu

input=$(cat)
command=$(printf '%s' "$input" | python3 -c 'import json, sys; print(json.load(sys.stdin).get("tool_input", {}).get("command", ""))')

case "$command" in
  *"rm -rf /"*|*"git push --force"*)
    echo "Bloklandi: xavfli buyruq ($command)" >&2
    exit 2
    ;;
esac
exit 0
