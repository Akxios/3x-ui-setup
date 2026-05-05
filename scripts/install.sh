#!/usr/bin/env bash
        fail "Module not found: $module_path"
    fi

    log "Running module: ${module_path#$PROJECT_DIR/}"

    # shellcheck disable=SC1090
    source "$module_path"
}

usage() {
    cat <<EOF
Usage:
  sudo bash scripts/install.sh all
  sudo bash scripts/install.sh packages
  sudo bash scripts/install.sh nginx
  sudo bash scripts/install.sh firewall
  sudo bash scripts/install.sh fail2ban
  sudo bash scripts/install.sh 3x-ui
  sudo bash scripts/install.sh status

Before first run:
  cp .env.example .env
  nano .env
EOF
}

main() {
    local command="${1:-all}"

    require_root
    require_apt_system
    load_env

    case "$command" in
        all)
            run_module "${SCRIPT_DIR}/modules/00-packages.sh"
            run_module "${SCRIPT_DIR}/modules/20-nginx.sh"
            run_module "${SCRIPT_DIR}/modules/30-firewall.sh"
            run_module "${SCRIPT_DIR}/modules/40-fail2ban.sh"

            if [[ "${INSTALL_3X_UI:-false}" == "true" ]]; then
                run_module "${SCRIPT_DIR}/modules/50-3x-ui.sh"
            fi

            run_module "${SCRIPT_DIR}/modules/90-status.sh"
            ;;
        packages)
            run_module "${SCRIPT_DIR}/modules/00-packages.sh"
            ;;
        nginx)
            run_module "${SCRIPT_DIR}/modules/20-nginx.sh"
            ;;
        firewall|ufw)
            run_module "${SCRIPT_DIR}/modules/30-firewall.sh"
            ;;
        fail2ban)
            run_module "${SCRIPT_DIR}/modules/40-fail2ban.sh"
            ;;
        3x-ui|x-ui)
            run_module "${SCRIPT_DIR}/modules/50-3x-ui.sh"
            ;;
        status)
            run_module "${SCRIPT_DIR}/modules/90-status.sh"
            ;;
        help|-h|--help)
            usage
            ;;
        *)
            usage
            fail "Unknown command: $command"
            ;;
    esac
}

main "$@"
