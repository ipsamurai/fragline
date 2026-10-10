#!/usr/bin/env bash
# Export the web build to build/web. Needs Godot 4.7 + its web export templates.
set -euo pipefail
cd "$(dirname "$0")/.."
GODOT="${GODOT:-godot}"
mkdir -p build/web
"$GODOT" --headless --path . --import
"$GODOT" --headless --path . --export-release "Web" build/web/index.html
echo "Built build/web ($(du -sh build/web | cut -f1)). Serve it with: python3 tools/serve.py"
