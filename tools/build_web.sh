#!/usr/bin/env bash
# Export the web build to build/web. Needs Godot 4.7 + its web export templates.
#   GODOT=/path/to/godot  ./tools/build_web.sh
#   OUT=some/dir          export somewhere else (default build/web)
#   PUBLIC_URL=https://example.com/fragline   make the og:image link absolute (social-card scrapers want that)
# The branded loading page is tools/web/shell.html (export preset: html/custom_html_shell).
set -euo pipefail
cd "$(dirname "$0")/.."
GODOT="${GODOT:-godot}"
OUT="${OUT:-build/web}"
mkdir -p "$OUT"
touch build/.gdignore                 # keep Godot from importing the build output
"$GODOT" --headless --path . --import
"$GODOT" --headless --path . --export-release "Web" "$OUT/index.html"

# Static files the shell references (icons + social card). Regenerate them with tools/web/make_assets.py.
for f in og-image.png icon-192.png icon-512.png favicon-32.png; do
	cp tools/web/$f "$OUT/$f"
done
if [ -n "${PUBLIC_URL:-}" ]; then
	url="${PUBLIC_URL%/}"
	sed -i -e "s#content=\"og-image.png\"#content=\"$url/og-image.png\"#g" \
		-e "s#<meta property=\"og:type\"#<meta property=\"og:url\" content=\"$url/\">\n<meta property=\"og:type\"#" "$OUT/index.html"
fi
grep -q 'id="fl-boot"' "$OUT/index.html" || echo "WARNING: $OUT/index.html is not the FRAGLINE shell (check html/custom_html_shell)." >&2

echo "Built $OUT ($(du -sh "$OUT" | cut -f1)). Serve it with: python3 tools/serve.py"
