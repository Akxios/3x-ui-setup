#!/usr/bin/env bash

# Runs only in a disposable CI container. Exercises the real nginx package and
# project template installer without contacting ACME or installing 3x-ui.
set -Eeuo pipefail
umask 077

[[ "${CI_SMOKE:-}" == "1" && $EUID -eq 0 && -f /.dockerenv ]] || {
    echo "CI nginx smoke test requires a disposable Docker container" >&2
    exit 1
}

project_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$project_dir"
[[ ! -e .env && ! -L .env ]] || {
    echo "Refusing to replace an existing .env" >&2
    exit 1
}

smoke_dir="$(mktemp -d)"
cleanup() {
    rm -f -- "$project_dir/.env" "$smoke_dir/systemctl" "$smoke_dir/getent" "$smoke_dir/page.html"
    rmdir -- "$smoke_dir"
}
trap cleanup EXIT

cat > "$smoke_dir/systemctl" <<'EOF'
#!/bin/sh
case "$1" in
    is-active|reload) exit 0 ;;
    *) exit 1 ;;
esac
EOF
chmod 700 "$smoke_dir/systemctl"
cat > "$smoke_dir/getent" <<'EOF'
#!/bin/sh
if [ "$1" = ahosts ] && [ "$2" = smoke.example.org ]; then
    printf '127.0.0.1 STREAM smoke.example.org\n'
    exit 0
fi
exec /usr/bin/getent "$@"
EOF
chmod 700 "$smoke_dir/getent"
export PATH="$smoke_dir:$PATH"

for template in tribe numbers notepad; do
    cat > .env <<EOF
DOMAIN="smoke.example.org"
SITE_TEMPLATE="$template"
NGINX_AUTO_HTTPS="false"
NGINX_USE_HTTPS="false"
INSTALL_3X_UI="false"
ENABLE_UFW="false"
ENABLE_FAIL2BAN="false"
EOF
    bash scripts/install.sh nginx
    nginx -t
    if ! nginx -s reload >/dev/null 2>&1; then
        nginx
    fi
    curl --noproxy '*' --fail --silent --show-error --max-time 5 \
        --resolve smoke.example.org:80:127.0.0.1 \
        http://smoke.example.org/ > "$smoke_dir/page.html"
    case "$template" in
        tribe) title='Племя' ;;
        numbers) title='Генератор чисел' ;;
        notepad) title='Блокнот' ;;
    esac
    grep -Fq "<title>${title} · smoke.example.org</title>" "$smoke_dir/page.html"
    bash scripts/install.sh doctor
    echo "OK: nginx serves $template"
done
