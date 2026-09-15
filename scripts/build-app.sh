#!/bin/zsh
set -euo pipefail

project_root="$(cd "$(dirname "$0")/.." && pwd)"
configuration="${1:-release}"
build_dir="$project_root/.build/$configuration"
app_dir="$project_root/dist/PromptViz.app"
swiftpm_dir="$project_root/.swiftpm"
signing_identity="${PROMPT_VIZ_SIGNING_IDENTITY:-Apple Development: bernardopinvesfore@gmail.com (YA46UAZ7YP)}"

mkdir -p "$swiftpm_dir/config" "$swiftpm_dir/cache"

cd "$project_root"
swift build \
    --configuration "$configuration" \
    --config-path "$swiftpm_dir/config" \
    --cache-path "$swiftpm_dir/cache" \
    --manifest-cache local \
    --disable-dependency-cache \
    --product PromptViz

rm -rf "$app_dir"
mkdir -p "$app_dir/Contents/MacOS" "$app_dir/Contents/Resources"
cp "$build_dir/PromptViz" "$app_dir/Contents/MacOS/PromptViz"
chmod +x "$app_dir/Contents/MacOS/PromptViz"

cat > "$app_dir/Contents/Info.plist" <<'PLIST'
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>CFBundleDisplayName</key>
    <string>Prompt Viz</string>
    <key>CFBundleExecutable</key>
    <string>PromptViz</string>
    <key>CFBundleIdentifier</key>
    <string>local.prompt-viz.app</string>
    <key>CFBundleName</key>
    <string>Prompt Viz</string>
    <key>CFBundlePackageType</key>
    <string>APPL</string>
    <key>CFBundleShortVersionString</key>
    <string>0.1.0</string>
    <key>CFBundleVersion</key>
    <string>20</string>
    <key>LSMinimumSystemVersion</key>
    <string>13.0</string>
    <key>LSUIElement</key>
    <true/>
    <key>NSAppleEventsUsageDescription</key>
    <string>Prompt Viz sends prompts to the active Terminal.app session.</string>
</dict>
</plist>
PLIST

if ! security find-identity -v -p codesigning | grep -Fq "\"$signing_identity\""; then
    echo "Não encontrei a identidade de assinatura: $signing_identity" >&2
    echo "Define PROMPT_VIZ_SIGNING_IDENTITY ou instala uma identidade Apple Development neste Mac." >&2
    exit 1
fi

codesign --force --deep --sign "$signing_identity" --identifier local.prompt-viz.app "$app_dir"

echo "Built $app_dir"
