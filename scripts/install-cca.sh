#!/bin/sh
# Install the `cca` terminal command (Claude accounts) as a small shim that
# runs the built AI Island binary. Build the app first: scripts/build-ai-island-app.sh
set -eu

repo=$(cd "$(dirname "$0")/.." && pwd)
binary="$repo/dist/AI Island.app/Contents/MacOS/AIIsland"
target="${CCA_BIN_DIR:-$HOME/.local/bin}/cca"

[ -x "$binary" ] || { echo "AI Island is not built: $binary" >&2; exit 1; }
if [ -e "$target" ] && ! grep -q -- "--cca" "$target" 2>/dev/null; then
  echo "$target exists and is not a cca shim; leaving it alone." >&2; exit 1
fi
mkdir -p "$(dirname "$target")"
printf '#!/bin/sh\nexec "%s" --cca "$@"\n' "$binary" > "$target"
chmod 755 "$target"
echo "Installed $target"
case ":$PATH:" in *":$(dirname "$target"):"*) ;; *) echo "Add $(dirname "$target") to PATH." ;; esac
