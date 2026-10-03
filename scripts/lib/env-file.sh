#!/usr/bin/env bash

declare -ag _3XUI_LOADED_ENV_KEYS=()

load_env_file() {
    local env_path="$1" pairs name value previous
    [[ -f "$env_path" && ! -L "$env_path" ]] || {
        printf 'ОШИБКА: .env не найден или является символьной ссылкой: %s\n' "$env_path" >&2
        return 1
    }
    command -v python3 >/dev/null 2>&1 || {
        printf 'ОШИБКА: для безопасного чтения .env нужен python3\n' >&2
        return 1
    }
    chmod 600 -- "$env_path" || return 1
    pairs="$(mktemp)" || return 1
    if ! python3 "$(dirname "${BASH_SOURCE[0]}")/env_file.py" "$env_path" > "$pairs"; then
        rm -f -- "$pairs"
        return 1
    fi
    for previous in "${_3XUI_LOADED_ENV_KEYS[@]}"; do
        unset "$previous"
    done
    _3XUI_LOADED_ENV_KEYS=()
    while IFS= read -r -d '' name && IFS= read -r -d '' value; do
        [[ "$name" =~ ^[A-Z][A-Z0-9_]*$ ]] || {
            rm -f -- "$pairs"
            printf 'ОШИБКА: некорректное имя настройки из parser\n' >&2
            return 1
        }
        printf -v "$name" '%s' "$value"
        # The parser has already restricted this to supported configuration keys.
        # shellcheck disable=SC2163
        export "$name"
        _3XUI_LOADED_ENV_KEYS+=("$name")
    done < "$pairs"
    rm -f -- "$pairs"
}
