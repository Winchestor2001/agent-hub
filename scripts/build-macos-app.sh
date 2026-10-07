#!/bin/sh
# Builds the native macOS wrapper at dist/Agent Hub.app.
set -eu

repo=$(cd "$(dirname "$0")/.." && pwd)
package="$repo/macos/AgentHubApp"
dist="$repo/dist"
app="$dist/Agent Hub.app"
contents="$app/Contents"
configuration="${CONFIGURATION:-release}"
agent_hub_port="${AGENT_HUB_PORT:-8700}"
agent_hub_url="${AGENT_HUB_APP_URL:-http://127.0.0.1:$agent_hub_port}"
python="$repo/.venv/bin/python"

if [ ! -x "$python" ]; then
	python=$(command -v python3 || true)
fi
if [ -z "$python" ]; then
	echo "build-macos-app: python topilmadi; avval make sync bajaring" >&2
	exit 1
fi

swift build --package-path "$package" -c "$configuration"
bin_dir=$(swift build --package-path "$package" -c "$configuration" --show-bin-path)
binary="$bin_dir/AgentHubApp"
if [ ! -x "$binary" ]; then
	echo "build-macos-app: Swift binary topilmadi: $binary" >&2
	exit 1
fi

version=$(
	"$python" - "$repo/pyproject.toml" <<'PY'
import re
import sys
text = open(sys.argv[1], encoding="utf-8").read()
match = re.search(r'^version = "([^"]+)"', text, re.MULTILINE)
print(match.group(1) if match else "0.1.0")
PY
)

rm -rf "$app"
mkdir -p "$contents/MacOS" "$contents/Resources"
cp "$binary" "$contents/MacOS/AgentHub"
chmod 755 "$contents/MacOS/AgentHub"
"$python" "$repo/scripts/generate-macos-icon.py" "$contents/Resources/AgentHub.icns"

"$python" - "$contents/Info.plist" "$version" "$agent_hub_url" "$repo" <<'PY'
import plistlib
import sys

plist_path, version, agent_hub_url, repo = sys.argv[1:5]
data = {
    "CFBundleDevelopmentRegion": "en",
    "CFBundleDisplayName": "Agent Hub",
    "CFBundleExecutable": "AgentHub",
    "CFBundleIconFile": "AgentHub",
    "CFBundleIdentifier": "local.agent-hub.app",
    "CFBundleInfoDictionaryVersion": "6.0",
    "CFBundleName": "Agent Hub",
    "CFBundlePackageType": "APPL",
    "CFBundleShortVersionString": version,
    "CFBundleVersion": version,
    "LSMinimumSystemVersion": "14.0",
    "NSAppTransportSecurity": {"NSAllowsLocalNetworking": True},
    "NSHighResolutionCapable": True,
    "AgentHubURL": agent_hub_url,
    "AgentHubRepositoryPath": repo,
}
with open(plist_path, "wb") as handle:
    plistlib.dump(data, handle, sort_keys=False)
PY

/usr/bin/plutil -lint "$contents/Info.plist" >/dev/null
echo "Built: $app"
