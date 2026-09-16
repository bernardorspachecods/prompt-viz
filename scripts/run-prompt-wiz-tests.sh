#!/bin/zsh
set -euo pipefail

project_root="$(cd "$(dirname "$0")/.." && pwd)"
test_dir="$(mktemp -d /private/tmp/prompt-wiz-tests.XXXXXX)"
trap 'rm -rf "$test_dir"' EXIT
module_cache_dir="$test_dir/module-cache"
mkdir -p "$module_cache_dir"
export CLANG_MODULE_CACHE_PATH="$module_cache_dir"

cd "$project_root"

swiftc \
    -parse-as-library \
    -module-name PromptWizCore \
    -emit-module \
    -emit-library \
    -emit-module-path "$test_dir/PromptWizCore.swiftmodule" \
    -o "$test_dir/libPromptWizCore.dylib" \
    Sources/PromptWizCore/*.swift

app_sources=()
for source in Sources/PromptWiz/*.swift; do
    [[ "$source" == "Sources/PromptWiz/PromptWizApp.swift" ]] && continue
    app_sources+=("$source")
done

swiftc \
    -module-name PromptWizSeamTests \
    -I "$test_dir" \
    -L "$test_dir" \
    -Xlinker -rpath -Xlinker "$test_dir" \
    -lPromptWizCore \
    -framework AppKit \
    -framework SwiftUI \
    -framework ApplicationServices \
    -framework ServiceManagement \
    -o "$test_dir/PromptWizSeamTests" \
    "${app_sources[@]}" \
    Tests/PromptWizTests/PromptWizModelTests.swift

"$test_dir/PromptWizSeamTests"
