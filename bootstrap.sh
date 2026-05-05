#!/usr/bin/env bash

set -Eeuo pipefail

REPO_URL="https://github.com/Akxios/3x-ui-setup.git"
INSTALL_DIR="/opt/3x-ui-setup"

if [[ $EUID -ne 0 ]]; then
    echo "ERROR: run as root"
    echo "Example: sudo bash -c \"\$(curl -fsSL https://raw.githubusercontent.com/akxios/3x-ui-setup/main/bootstrap.sh)\""
    exit 1
fi

apt-get update
apt-get install -y git curl nano ca-certificates

if [[ -d "$INSTALL_DIR/.git" ]]; then
    cd "$INSTALL_DIR"
    git pull
else
    rm -rf "$INSTALL_DIR"
    git clone "$REPO_URL" "$INSTALL_DIR"
    cd "$INSTALL_DIR"
fi

if [[ ! -f .env ]]; then
    cp .env.example .env
fi

echo
echo "Edit config now."
echo "After closing editor, installation will continue."
echo

nano .env

bash scripts/install.sh all
