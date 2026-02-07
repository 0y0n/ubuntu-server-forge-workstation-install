#!/usr/bin/env bash
# ==============================================================================
# Forge — Bootstrap installer for remote-workstation
# 
# SECURITY: Never pipe scripts directly to bash from the internet.
# 
# Recommended installation procedure:
#   1. curl -fsSL https://raw.githubusercontent.com/0y0n/forge/main/install.sh -o install.sh
#   2. less install.sh        # Review the script content
#   3. chmod +x install.sh
#   4. ./install.sh           # Run as regular user; script uses sudo internally when needed
# ==============================================================================
set -euo pipefail

# ── colours ──────────────────────────────────────────────────────────────────
RED='\033[0;31m'; GREEN='\033[0;32m'; YELLOW='\033[1;33m'; NC='\033[0m'
info()  { echo -e "${GREEN}[FORGE]${NC} $*"; }
warn()  { echo -e "${YELLOW}[FORGE WARN]${NC} $*"; }
abort() { echo -e "${RED}[FORGE ABORT]${NC} $*" >&2; exit 1; }

# ── constants ────────────────────────────────────────────────────────────────
REPO_URL="https://github.com/0y0n/forge.git"
REPO_DIR="${HOME}/dev/forge"
EXPECTED_OS_ID="ubuntu"
EXPECTED_VERSION_ID="25.10"

# ── 1. OS guard ──────────────────────────────────────────────────────────────
info "Checking OS …"
[[ -f /etc/os-release ]] || abort "/etc/os-release not found"
# shellcheck source=/dev/null
source /etc/os-release
[[ "${ID:-}" == "$EXPECTED_OS_ID" ]]             || abort "Expected Ubuntu, got '${ID:-unknown}'"
[[ "${VERSION_ID:-}" == "$EXPECTED_VERSION_ID" ]] || abort "Expected ${EXPECTED_VERSION_ID}, got '${VERSION_ID:-unknown}'"
# Ensure we are NOT running a desktop flavour
if dpkg -s ubuntu-desktop >/dev/null 2>&1; then
  abort "This installer targets Ubuntu Server, not a desktop edition."
fi
info "OS check passed  →  Ubuntu Server ${VERSION_ID}"

# ── 2. Privilege check ──────────────────────────────────────────────────────
# This script must NOT be run as root; it uses sudo internally when needed
if [[ $EUID -eq 0 ]]; then
  abort "This script must be run as a regular user, not as root.

Please run:
  ./install.sh

The script will use sudo internally for commands that require elevated privileges."
fi

# ── 3. Update & upgrade ─────────────────────────────────────────────────────
info "Updating package index …"
sudo apt-get update -qq

info "Upgrading installed packages …"
DEBIAN_FRONTEND=noninteractive sudo apt-get upgrade -y -qq

# ── 4. Install git ──────────────────────────────────────────────────────
info "Ensuring git is installed …"
sudo apt-get install -y -qq git

# ── 5. Clone Forge repository ────────────────────────────────────────────────
if [[ -d "$REPO_DIR/.git" ]]; then
  info "Repo already exists at ${REPO_DIR}, fetching latest …"
  # Discard any local changes and force update to match remote
  git -C "$REPO_DIR" fetch origin
  git -C "$REPO_DIR" reset --hard origin/main
else
  info "Cloning repo → ${REPO_DIR}"
  git clone --depth 1 "$REPO_URL" "$REPO_DIR"
fi

# ── 6. Install Ansible ──────────────────────────────────────────────────────
info "Installing Ansible …"
if ! command -v ansible-playbook &>/dev/null; then
  # Install pipx (lightweight, isolated Python app installer)
  sudo apt-get install -y -qq pipx
  pipx ensurepath
  
  # Install ansible via pipx (creates isolated venv automatically)
  export PIPX_HOME=/opt/pipx
  export PIPX_BIN_DIR=/usr/local/bin
  pipx install --include-deps ansible
  # Verify installation succeeded
  if ! command -v ansible-playbook &>/dev/null; then
    abort "Ansible installation failed. ansible-playbook not found in PATH."
  fi
fi

info "Ansible version: $(ansible --version | head -1)"

# ── 7. Launch the playbook ──────────────────────────────────────────────────
info "Starting Ansible playbook for remote-workstation …"
cd "$REPO_DIR"

if ! ansible-playbook \
  --ask-become-pass \
  -i inventory/hosts.yml \
  playbooks/remote_workstation.yml \
  --connection=local \
  -e "ansible_become=yes" \
  -v; then
  abort "Ansible playbook failed. Check the output above for errors."
fi

info "═══════════════════════════════════════════════════"
info " Forge bootstrap for remote-workstation complete.  "
info "═══════════════════════════════════════════════════"
