#!/bin/zsh
set -euo pipefail

project_root="$(cd "$(dirname "$0")/.." && pwd)"
app_path="$project_root/dist/PromptWiz.app"

echo "A fechar instâncias antigas..."
pkill -x PromptWiz 2>/dev/null || true

echo "A compilar Prompt Wiz..."
cd "$project_root"
./scripts/build-app.sh

build_number="$(plutil -extract CFBundleVersion raw -o - "$app_path/Contents/Info.plist")"
echo "A abrir Prompt Wiz build $build_number..."
open -n "$app_path"
