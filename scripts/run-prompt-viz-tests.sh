#!/bin/zsh
set -euo pipefail

project_root="$(cd "$(dirname "$0")/.." && pwd)"
test_dir="$(mktemp -d /private/tmp/prompt-viz-tests.XXXXXX)"
trap 'rm -rf "$test_dir"' EXIT
module_cache_dir="$test_dir/module-cache"
mkdir -p "$module_cache_dir"
export CLANG_MODULE_CACHE_PATH="$module_cache_dir"

cd "$project_root"

swiftc \
    -parse-as-library \
    -module-name PromptVizCore \
    -emit-module \
    -emit-library \
    -emit-module-path "$test_dir/PromptVizCore.swiftmodule" \
    -o "$test_dir/libPromptVizCore.dylib" \
    Sources/PromptVizCore/*.swift

app_sources=()
for source in Sources/PromptViz/*.swift; do
    [[ "$source" == "Sources/PromptViz/PromptVizApp.swift" ]] && continue
    app_sources+=("$source")
done

swiftc \
    -module-name PromptVizSeamTests \
    -I "$test_dir" \
    -L "$test_dir" \
    -Xlinker -rpath -Xlinker "$test_dir" \
    -lPromptVizCore \
    -framework AppKit \
    -framework SwiftUI \
    -framework ApplicationServices \
    -framework ServiceManagement \
    -o "$test_dir/PromptVizSeamTests" \
    "${app_sources[@]}" \
    Tests/PromptVizTests/PromptVizModelTests.swift

"$test_dir/PromptVizSeamTests"
