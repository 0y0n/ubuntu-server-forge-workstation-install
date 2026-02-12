#!/usr/bin/env bash
# ==============================================================================
# Forge — Bootstrap installer for remote-workstation
# 
# SECURITY: Never pipe scripts directly to bash from the internet.
#
# Recommended secure installation procedure:
#   1. curl -fsSL https://raw.githubusercontent.com/0y0n/forge/main/install.sh -o install.sh
#   2. less install.sh        # Review the script content
#   3. chmod +x install.sh
#   4. ./install.sh           # Run as regular user; script uses sudo internally when needed
#
# Else Onliner install procedure (should not be done on internet source:
#   curl -fsSL https://raw.githubusercontent.com/0y0n/forge/main/install.sh | bash
# ==============================================================================
set -euo pipefail

# ── colours ──────────────────────────────────────────────────────────────────
RED='\033[0;31m'; GREEN='\033[0;32m'; YELLOW='\033[1;33m'; NC='\033[0m'
info()  { echo -e "${GREEN}[FORGE]${NC} $*"; }
warn()  { echo -e "${YELLOW}[FORGE WARN]${NC} $*"; }
abort() { echo -e "${RED}[FORGE ABORT]${NC} $*" >&2; exit 1; }

# Function to check and set Git config
check_git_config() {
    
    key=$1
    label=$2
    current_val=$(git config --global "$key" 2>/dev/null || true)
    
    if [ -z "$current_val" ]; then
        echo -e -n "${YELLOW}Missing configuration:${NC} Enter your $label: "
        # Use read -r to handle names with spaces properly
        read -r input
        
        if [ -n "$input" ]; then
            git config --global "$key" "$input"
            echo -e "${GREEN}✓ $label set successfully.${NC}"
        else
            echo -e "⚠️  No input provided. Skipping $label."
        fi
    else
        echo -e "${GREEN}✓ $label is already set:${NC} $current_val"
    fi
}

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
info "Check .bashrc presence in your home"
if [[ -f "~/.bashrc" ]]; then
  info "No present copy sekelon from /etc/skel/.bashrc"
  cp /etc/skel/.bashrc ~/
fi
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

info "Install required components if missing"
REQUIRED_PKGS=("gnome-keyring" "libsecret-tools" "libpam-gnome-keyring")
for pkg in "${REQUIRED_PKGS[@]}"; do
    if ! dpkg -s "$pkg" >/dev/null 2>&1; then
        info "--- Installing $pkg ---"
        apt-get install -y "$pkg"
    fi
done

KEYRING_DIR="$HOME/.local/share/keyrings"
LOGIN_KEYRING="$KEYRING_DIR/login.keyring"

info "Check if the 'login' keyring already exists"
if [ ! -f "$LOGIN_KEYRING" ]; then
    
    warn "No 'login' keyring detected."
    
    # Prompt for the session password
    # We use -s to prevent the password from being echoed in the terminal
    read -sp "Enter your session password (used to encrypt the keyring): " USER_PASS
    echo ""

    # Ensure the directory exists with correct permissions
    mkdir -p "$KEYRING_DIR"
    chmod 700 "$KEYRING_DIR"

    # Set 'login' as the default keyring
    echo "login" > "$KEYRING_DIR/default"

    # Launch the daemon and initialize/unlock the keyring
    # The --unlock flag creates the keyring if it doesn't exist by reading stdin
    if echo "$USER_PASS" | gnome-keyring-daemon --unlock --components=secrets --start > /dev/null; then
        # Validation test using secret-tool
        if echo "$USER_PASS" | secret-tool store --label="Initialization Task" OS setup 2>/dev/null; then
            info " 'login' keyring successfully created and unlocked."
        else
            abort "  Keyring created, but validation failed. Ensure you are in a valid DBus session."
        fi
    else
        abort "Failed to initialize gnome-keyring-daemon."
    fi
    
    # Clear the password variable for security
    unset USER_PASS
else
    info " 'login' keyring already exists. Skipping initialization."
fi

# ── 4. Install git ──────────────────────────────────────────────────────
info "Ensuring git is installed …"
sudo apt-get install -y -qq git

# Check for Git Name and Email
check_git_config "user.name" "Git User Name"
check_git_config "user.email" "Git Email Address"

# ── 5. Clone Forge repository ────────────────────────────────────────────────
if [[ -d "$REPO_DIR/.git" ]]; then
  info "Repo already exists at ${REPO_DIR}, fetching latest …"
  # Discard any local changes and force update to match remote
  # DONTCOMIT git -C "$REPO_DIR" fetch origin
  # DONTCOMIT git -C "$REPO_DIR" reset --hard origin/main
else
  info "Cloning repo → ${REPO_DIR}"
  git clone --depth 1 "$REPO_URL" "$REPO_DIR"
fi

# ── 6. Install Ansible ──────────────────────────────────────────────────────
info "Installing Ansible …"
if ! command -v ansible-playbook &>/dev/null; then
  # Install pipx (lightweight, isolated Python app installer)
  sudo apt-get install -y -qq pipx
    
  # Install ansible via pipx (creates isolated venv automatically)
  pipx install --include-deps ansible
  pipx ensurepath
  source ~/.bashrc
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
  playbooks/remote_workstation.yml \
  --verbose; then
  abort "Ansible playbook failed. Check the output above for errors."
fi

info "═══════════════════════════════════════════════════"
info " Forge bootstrap for remote-workstation complete.  "
info "═══════════════════════════════════════════════════"
