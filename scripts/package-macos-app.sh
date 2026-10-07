#!/bin/sh
# Builds Agent Hub.app and packages it as a zip release artifact.
set -eu

repo=$(cd "$(dirname "$0")/.." && pwd)
dist="$repo/dist"
app="$dist/Agent Hub.app"
python="$repo/.venv/bin/python"

if [ ! -x "$python" ]; then
	python=$(command -v python3 || true)
fi
if [ -z "$python" ]; then
	echo "package-macos-app: python topilmadi; avval make sync bajaring" >&2
	exit 1
fi

"$repo/scripts/build-macos-app.sh"

version=$(
	"$python" - "$repo/pyproject.toml" <<'PY'
import re
import sys
text = open(sys.argv[1], encoding="utf-8").read()
match = re.search(r'^version = "([^"]+)"', text, re.MULTILINE)
print(match.group(1) if match else "0.1.0")
PY
)

artifact="$dist/AgentHub-macos-$version.zip"
rm -f "$artifact"
cd "$dist"
/usr/bin/ditto -c -k --norsrc --keepParent "$(basename "$app")" "$artifact"
echo "Packaged: $artifact"
