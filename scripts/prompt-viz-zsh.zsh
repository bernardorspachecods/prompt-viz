# Prompt Viz shell integration.
# Source this file from ~/.zshrc to mirror the current zsh line into Prompt Viz.

if [[ ${PROMPT_VIZ_ZSH_INTEGRATION_VERSION:-} == 2 ]]; then
    return 0
fi

typeset -g PROMPT_VIZ_ZSH_INTEGRATION_VERSION=2
typeset -g PROMPT_VIZ_SYNC_DIR=${PROMPT_VIZ_SYNC_DIR:-/tmp/prompt-viz}
typeset -g PROMPT_VIZ_LAST_BUFFER=''
typeset -g PROMPT_VIZ_LAST_CURSOR=''

function _prompt_viz_publish_line() {
    emulate -L zsh

    local buffer="${1-}"
    local cursor="${2-0}"
    local force="${3-0}"

    [[ -n ${TTY:-} ]] || return 0

    if [[ "$force" != 1 && "$buffer" == "$PROMPT_VIZ_LAST_BUFFER" && "$cursor" == "$PROMPT_VIZ_LAST_CURSOR" ]]; then
        return 0
    fi

    /bin/mkdir -p -m 700 "$PROMPT_VIZ_SYNC_DIR" 2>/dev/null || return 0

    local tty_id="${TTY:t}"
    local target="$PROMPT_VIZ_SYNC_DIR/${tty_id}.state"
    local temporary="$target.$$"
    local encoded_buffer
    encoded_buffer="$(builtin print -rn -- "$buffer" | /usr/bin/base64 | /usr/bin/tr -d '\n')" || return 0

    {
        builtin print -r -- "tty=$TTY"
        builtin print -r -- "cursor=$cursor"
        builtin print -r -- "buffer=$encoded_buffer"
    } >| "$temporary" 2>/dev/null || return 0

    /bin/mv -f "$temporary" "$target" 2>/dev/null || return 0

    PROMPT_VIZ_LAST_BUFFER="$buffer"
    PROMPT_VIZ_LAST_CURSOR="$cursor"
}

function _prompt_viz_line_init() {
    _prompt_viz_publish_line "${BUFFER-}" "${CURSOR-0}" 1
}

function _prompt_viz_line_pre_redraw() {
    _prompt_viz_publish_line "${BUFFER-}" "${CURSOR-0}"
}

function _prompt_viz_line_finish() {
    _prompt_viz_publish_line '' 0 1
}

function _prompt_viz_line_abort() {
    _prompt_viz_publish_line '' 0 1
}

autoload -Uz add-zle-hook-widget
add-zle-hook-widget line-init _prompt_viz_line_init
add-zle-hook-widget line-pre-redraw _prompt_viz_line_pre_redraw
add-zle-hook-widget line-finish _prompt_viz_line_finish
