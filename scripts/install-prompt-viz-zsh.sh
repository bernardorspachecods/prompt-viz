#!/bin/zsh
set -euo pipefail

project_root="$(cd "$(dirname "$0")/.." && pwd)"
zshrc_path="${ZDOTDIR:-$HOME}/.zshrc"
source_line="source \"$project_root/scripts/prompt-viz-zsh.zsh\""

if [[ -f "$zshrc_path" ]] && /usr/bin/grep -Fqx "$source_line" "$zshrc_path"; then
    echo "A integração Prompt Viz já está instalada em $zshrc_path"
    exit 0
fi

{
    /usr/bin/printf '\n# Prompt Viz — sincronização Terminal → app\n'
    /usr/bin/printf '%s\n' "$source_line"
} >> "$zshrc_path"

echo "Integração Prompt Viz adicionada a $zshrc_path"
echo "Abre um novo tab do Terminal ou executa: source $zshrc_path"
