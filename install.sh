#!/bin/bash
# ============================================================================
# 0xMasterRecon v3.3 — Tool Installer
# Author: @MrOz1l
#
# Installs ALL dependencies for 0xMasterRecon on macOS and Kali Linux.
#
# Usage:
#   chmod +x install.sh
#   sudo ./install.sh            # full install
#   sudo ./install.sh --check    # only check what's missing
# ============================================================================

set -uo pipefail

# ── Colors ──────────────────────────────────────────────────────────────────
RED="\033[0;31m"
GREEN="\033[0;32m"
YELLOW="\033[1;33m"
CYAN="\033[0;36m"
BOLD="\033[1m"
DIM="\033[2m"
RESET="\033[0m"

TOOLS_DIR="$HOME/tools"
GO_BIN="$HOME/go/bin"
CHECK_ONLY=false

# ── Logging ─────────────────────────────────────────────────────────────────
ok()    { echo -e "  [${GREEN}✓${RESET}] $1"; }
fail()  { echo -e "  [${RED}✗${RESET}] $1"; }
warn()  { echo -e "  [${YELLOW}!${RESET}] $1"; }
info()  { echo -e "  [${CYAN}→${RESET}] $1"; }
header(){ echo -e "\n${BOLD}═══ $1 ═══${RESET}"; }

# ── OS Detection ────────────────────────────────────────────────────────────
detect_os() {
    if [[ "$(uname)" == "Darwin" ]]; then
        OS="macos"
    elif [[ -f /etc/os-release ]]; then
        if grep -qi "kali\|debian\|ubuntu" /etc/os-release; then
            OS="linux"
        else
            OS="linux"
        fi
    else
        OS="linux"
    fi
    echo -e "${BOLD}Detected OS:${RESET} ${CYAN}${OS}${RESET}"
}

# ── Argument Parsing ────────────────────────────────────────────────────────
if [[ "${1:-}" == "--check" ]]; then
    CHECK_ONLY=true
fi

# ── Helpers ─────────────────────────────────────────────────────────────────
cmd_exists() { command -v "$1" &>/dev/null; }

ensure_dir() { mkdir -p "$1" 2>/dev/null || true; }

# Install Go tool via go install
go_install() {
    local name="$1"
    local pkg="$2"
    if cmd_exists "$name"; then
        ok "$name already installed"
    elif [[ "$CHECK_ONLY" == true ]]; then
        fail "$name — NOT installed (go install $pkg)"
    else
        info "Installing $name..."
        go install -v "$pkg" 2>/dev/null && ok "$name installed" || fail "$name install failed"
    fi
}

# Install pip package
pip_install() {
    local pkg="$1"
    local bin_name="${2:-$1}"
    if cmd_exists "$bin_name" || python3 -c "import $pkg" 2>/dev/null; then
        ok "$pkg already installed"
    elif [[ "$CHECK_ONLY" == true ]]; then
        fail "$pkg — NOT installed (pip3 install $pkg)"
    else
        info "Installing $pkg..."
        pip3 install "$pkg" --break-system-packages --quiet 2>/dev/null && ok "$pkg installed" || fail "$pkg install failed"
    fi
}

# Clone a git repo into ~/tools/
git_clone() {
    local name="$1"
    local url="$2"
    local dir="$TOOLS_DIR/$name"
    if [[ -d "$dir" ]]; then
        ok "$name already cloned"
    elif [[ "$CHECK_ONLY" == true ]]; then
        fail "$name — NOT cloned ($url)"
    else
        info "Cloning $name..."
        git clone --depth 1 "$url" "$dir" 2>/dev/null && ok "$name cloned" || fail "$name clone failed"
    fi
}

# Download a binary release
download_binary() {
    local name="$1"
    local url="$2"
    local dest="$3"
    if [[ -f "$dest" ]]; then
        ok "$name already downloaded"
    elif [[ "$CHECK_ONLY" == true ]]; then
        fail "$name — NOT downloaded"
    else
        info "Downloading $name..."
        wget -q "$url" -O "$dest" 2>/dev/null && chmod +x "$dest" && ok "$name downloaded" || fail "$name download failed"
    fi
}

# ════════════════════════════════════════════════════════════════════════════
# BANNER
# ════════════════════════════════════════════════════════════════════════════
echo -e "
${CYAN} _____     ___  ___          _           ______                     
|  _  |    |  \\/  |         | |          | ___ \\                    
| |/' |_  _| .  . | __ _ ___| |_ ___ _ __| |_/ /___  ___ ___  _ __  
|  /| \\ \\/ / |\\/| |/ _\` / __| __/ _ \\ '__|    // _ \\/ __/ _ \\| '_ \\ 
\\ |_/ />  <| |  | | (_| \\__ \\ ||  __/ |  | |\\ \\  __/ (_| (_) | | | |
 \\___//_/\\_\\_|  |_/\\__,_|___/\\__\\___|_|  \\_| \\_\\___|\\___\\___/|_| |_|${RESET}

           ${YELLOW}INSTALLER v3.3${RESET} — ${GREEN}@MrOz1l${RESET}
"

detect_os
ensure_dir "$TOOLS_DIR"
ensure_dir "$GO_BIN"

if [[ "$CHECK_ONLY" == true ]]; then
    echo -e "${YELLOW}Running in CHECK-ONLY mode — no installations will be performed.${RESET}"
fi

# ════════════════════════════════════════════════════════════════════════════
# SECTION 1: SYSTEM PREREQUISITES
# ════════════════════════════════════════════════════════════════════════════
header "System Prerequisites"

if [[ "$CHECK_ONLY" == false ]]; then
    if [[ "$OS" == "macos" ]]; then
        # Homebrew
        if ! cmd_exists "brew"; then
            info "Installing Homebrew..."
            /bin/bash -c "$(curl -fsSL https://raw.githubusercontent.com/Homebrew/install/HEAD/install.sh)" || fail "Homebrew install failed"
        fi
        ok "Homebrew available"

        info "Updating Homebrew..."
        brew update --quiet 2>/dev/null || true

        # Core deps via brew
        for pkg in git curl wget jq nmap python3 massdns; do
            if cmd_exists "$pkg"; then
                ok "$pkg already installed"
            else
                info "Installing $pkg..."
                brew install "$pkg" --quiet 2>/dev/null && ok "$pkg installed" || fail "$pkg failed"
            fi
        done

        # pip3
        if ! cmd_exists "pip3"; then
            python3 -m ensurepip --upgrade 2>/dev/null || true
        fi

    else
        # Kali/Debian/Ubuntu
        info "Updating apt..."
        apt update -qq 2>/dev/null || true

        apt_pkgs="git curl wget jq nmap python3 python3-pip massdns libpcap-dev build-essential chromium sqlmap whatweb wafw00f"
        for pkg in $apt_pkgs; do
            if dpkg -l "$pkg" 2>/dev/null | grep -q "^ii"; then
                ok "$pkg already installed"
            else
                info "Installing $pkg..."
                apt install -y -qq "$pkg" 2>/dev/null && ok "$pkg installed" || warn "$pkg may need manual install"
            fi
        done
    fi
else
    for cmd in git curl wget jq nmap python3 pip3 massdns; do
        cmd_exists "$cmd" && ok "$cmd" || fail "$cmd — NOT found"
    done
fi

# ── Go Language ─────────────────────────────────────────────────────────────
header "Go Language"

if cmd_exists "go"; then
    ok "Go already installed ($(go version 2>/dev/null | awk '{print $3}'))"
elif [[ "$CHECK_ONLY" == true ]]; then
    fail "Go — NOT installed"
else
    info "Installing Go..."
    if [[ "$OS" == "macos" ]]; then
        brew install go --quiet 2>/dev/null && ok "Go installed" || fail "Go install failed"
    else
        GO_VERSION="1.22.5"
        GO_ARCH="amd64"
        [[ "$(uname -m)" == "aarch64" ]] && GO_ARCH="arm64"
        wget -q "https://go.dev/dl/go${GO_VERSION}.linux-${GO_ARCH}.tar.gz" -O /tmp/go.tar.gz
        rm -rf /usr/local/go
        tar -C /usr/local -xzf /tmp/go.tar.gz
        rm /tmp/go.tar.gz
        ok "Go ${GO_VERSION} installed"
    fi
fi

# Ensure Go paths
if [[ "$CHECK_ONLY" == false ]]; then
    export GOPATH="$HOME/go"
    export PATH="$PATH:/usr/local/go/bin:$GOPATH/bin"

    # Persist Go paths
    for rc in "$HOME/.bashrc" "$HOME/.zshrc"; do
        if [[ -f "$rc" ]]; then
            grep -q 'GOPATH' "$rc" 2>/dev/null || {
                echo '' >> "$rc"
                echo '# Go paths (added by 0xMasterRecon installer)' >> "$rc"
                echo 'export GOPATH="$HOME/go"' >> "$rc"
                echo 'export PATH="$PATH:/usr/local/go/bin:$GOPATH/bin"' >> "$rc"
            }
        fi
    done
    ok "Go PATH configured"
fi

# ════════════════════════════════════════════════════════════════════════════
# SECTION 2: GO TOOLS (ProjectDiscovery + Community)
# ════════════════════════════════════════════════════════════════════════════
header "Go Tools — ProjectDiscovery"

go_install "subfinder"          "github.com/projectdiscovery/subfinder/v2/cmd/subfinder@latest"
go_install "httpx"              "github.com/projectdiscovery/httpx/cmd/httpx@latest"
go_install "dnsx"               "github.com/projectdiscovery/dnsx/cmd/dnsx@latest"
go_install "nuclei"             "github.com/projectdiscovery/nuclei/v3/cmd/nuclei@latest"
go_install "naabu"              "github.com/projectdiscovery/naabu/v2/cmd/naabu@latest"
go_install "katana"             "github.com/projectdiscovery/katana/cmd/katana@latest"
go_install "shuffledns"         "github.com/projectdiscovery/shuffledns/cmd/shuffledns@latest"
go_install "notify"             "github.com/projectdiscovery/notify/cmd/notify@latest"
go_install "interactsh-client"  "github.com/projectdiscovery/interactsh/cmd/interactsh-client@latest"
go_install "asnmap"             "github.com/projectdiscovery/asnmap/cmd/asnmap@latest"
go_install "mapcidr"            "github.com/projectdiscovery/mapcidr/cmd/mapcidr@latest"
go_install "uncover"            "github.com/projectdiscovery/uncover/cmd/uncover@latest"

header "Go Tools — Community"

go_install "assetfinder"        "github.com/tomnomnom/assetfinder@latest"
go_install "httprobe"           "github.com/tomnomnom/httprobe@latest"
go_install "waybackurls"        "github.com/tomnomnom/waybackurls@latest"
go_install "unfurl"             "github.com/tomnomnom/unfurl@latest"
go_install "qsreplace"          "github.com/tomnomnom/qsreplace@latest"
go_install "meg"                "github.com/tomnomnom/meg@latest"
go_install "gf"                 "github.com/tomnomnom/gf@latest"
go_install "anew"               "github.com/tomnomnom/anew@latest"
go_install "ffuf"               "github.com/ffuf/ffuf/v2@latest"
go_install "hakrawler"          "github.com/hakluke/hakrawler@latest"
go_install "gau"                "github.com/lc/gau/v2/cmd/gau@latest"
go_install "gowitness"          "github.com/sensepost/gowitness@latest"
go_install "puredns"            "github.com/d3mondev/puredns/v2@latest"
go_install "airixss"            "github.com/ferreiraklet/airixss@latest"
go_install "socialhunter"       "github.com/utkusen/socialhunter@latest"

# ── GF Patterns ─────────────────────────────────────────────────────────────
header "GF Patterns"

GF_DIR="$HOME/.gf"
if [[ -d "$GF_DIR" ]] && [[ "$(ls -A "$GF_DIR" 2>/dev/null)" ]]; then
    ok "GF patterns already installed"
elif [[ "$CHECK_ONLY" == true ]]; then
    fail "GF patterns — NOT installed"
else
    ensure_dir "$GF_DIR"
    info "Installing GF patterns (tomnomnom + 1ndianl33t)..."

    # tomnomnom examples
    git clone --depth 1 https://github.com/tomnomnom/gf.git /tmp/gf-repo 2>/dev/null || true
    cp /tmp/gf-repo/examples/*.json "$GF_DIR/" 2>/dev/null || true
    rm -rf /tmp/gf-repo

    # 1ndianl33t extended patterns (XSS, SQLi, SSRF, LFI, redirect, etc.)
    git clone --depth 1 https://github.com/1ndianl33t/Gf-Patterns.git /tmp/gf-patterns 2>/dev/null || true
    cp /tmp/gf-patterns/*.json "$GF_DIR/" 2>/dev/null || true
    rm -rf /tmp/gf-patterns

    ok "GF patterns installed ($(ls "$GF_DIR"/*.json 2>/dev/null | wc -l) patterns)"
fi

# ── Nuclei Templates ────────────────────────────────────────────────────────
header "Nuclei Templates"

if [[ -d "$TOOLS_DIR/nuclei-templates" ]]; then
    ok "Nuclei templates already present"
    if [[ "$CHECK_ONLY" == false ]]; then
        info "Updating nuclei templates..."
        nuclei -update-templates 2>/dev/null || true
    fi
elif [[ "$CHECK_ONLY" == true ]]; then
    fail "Nuclei templates — NOT installed"
else
    info "Downloading nuclei templates..."
    git clone --depth 1 https://github.com/projectdiscovery/nuclei-templates.git "$TOOLS_DIR/nuclei-templates" 2>/dev/null \
        && ok "Nuclei templates installed" || fail "Nuclei templates failed"
fi

# ════════════════════════════════════════════════════════════════════════════
# SECTION 3: PYTHON TOOLS
# ════════════════════════════════════════════════════════════════════════════
header "Python Tools (pip)"

pip_install "uro" "uro"
pip_install "paramspider" "paramspider"
pip_install "fuzzywuzzy" "fuzzywuzzy"
pip_install "python-Levenshtein" "Levenshtein"

# ── wafw00f (Kali usually has it, macOS needs pip) ──
if cmd_exists "wafw00f"; then
    ok "wafw00f already installed"
elif [[ "$CHECK_ONLY" == true ]]; then
    fail "wafw00f — NOT installed"
else
    info "Installing wafw00f..."
    pip3 install wafw00f --break-system-packages --quiet 2>/dev/null && ok "wafw00f installed" || fail "wafw00f failed"
fi

# ── whatweb (Kali usually has it, macOS via brew) ──
if cmd_exists "whatweb"; then
    ok "whatweb already installed"
elif [[ "$CHECK_ONLY" == true ]]; then
    fail "whatweb — NOT installed"
elif [[ "$OS" == "macos" ]]; then
    brew install whatweb --quiet 2>/dev/null && ok "whatweb installed" || fail "whatweb failed"
fi

# ── sqlmap ──
if cmd_exists "sqlmap"; then
    ok "sqlmap already installed"
elif [[ "$CHECK_ONLY" == true ]]; then
    fail "sqlmap — NOT installed"
else
    if [[ "$OS" == "macos" ]]; then
        brew install sqlmap --quiet 2>/dev/null && ok "sqlmap installed" || fail "sqlmap failed"
    else
        apt install -y -qq sqlmap 2>/dev/null && ok "sqlmap installed" || fail "sqlmap failed"
    fi
fi

# ════════════════════════════════════════════════════════════════════════════
# SECTION 4: GIT-CLONED TOOLS
# ════════════════════════════════════════════════════════════════════════════
header "Git-Cloned Tools"

git_clone "SecretFinder"    "https://github.com/m4ll0k/SecretFinder.git"
git_clone "LinkFinder"      "https://github.com/dark-warlord14/LinkFinder.git"
git_clone "XSStrike"        "https://github.com/s0md3v/XSStrike.git"
git_clone "CMSeeK"          "https://github.com/Tuhinshubhra/CMSeeK.git"
git_clone "cloud_enum"      "https://github.com/initstring/cloud_enum.git"
git_clone "ParamSpider"     "https://github.com/devanshbatham/ParamSpider.git"
git_clone "findom-xss"      "https://github.com/dwisiswant0/findom-xss.git"
git_clone "sublert"         "https://github.com/yassineaboukir/sublert.git"
git_clone "SecLists"        "https://github.com/danielmiessler/SecLists.git"

# Install Python dependencies for cloned tools
if [[ "$CHECK_ONLY" == false ]]; then
    for tool_dir in SecretFinder LinkFinder XSStrike CMSeeK cloud_enum sublert; do
        if [[ -f "$TOOLS_DIR/$tool_dir/requirements.txt" ]]; then
            info "Installing $tool_dir Python deps..."
            pip3 install -r "$TOOLS_DIR/$tool_dir/requirements.txt" --break-system-packages --quiet 2>/dev/null || true
        fi
    done
    ok "Python dependencies installed for cloned tools"
fi

# Make findom-xss executable
[[ -f "$TOOLS_DIR/findom-xss/findom-xss.sh" ]] && chmod +x "$TOOLS_DIR/findom-xss/findom-xss.sh" 2>/dev/null

# ════════════════════════════════════════════════════════════════════════════
# SECTION 5: STANDALONE BINARIES
# ════════════════════════════════════════════════════════════════════════════
header "Standalone Binaries"

# ── findomain ──
if cmd_exists "findomain"; then
    ok "findomain already installed"
elif [[ "$CHECK_ONLY" == true ]]; then
    fail "findomain — NOT installed"
else
    info "Installing findomain..."
    if [[ "$OS" == "macos" ]]; then
        FINDOMAIN_URL="https://github.com/Findomain/Findomain/releases/latest/download/findomain-osx-x86_64.zip"
        wget -q "$FINDOMAIN_URL" -O /tmp/findomain.zip 2>/dev/null
        unzip -o -q /tmp/findomain.zip -d /tmp/findomain_extract 2>/dev/null
        find /tmp/findomain_extract -name 'findomain*' -type f | head -1 | xargs -I{} cp {} "$TOOLS_DIR/findomain"
        chmod +x "$TOOLS_DIR/findomain"
        rm -rf /tmp/findomain.zip /tmp/findomain_extract
    else
        ARCH="amd64"
        [[ "$(uname -m)" == "aarch64" ]] && ARCH="aarch64"
        wget -q "https://github.com/Findomain/Findomain/releases/latest/download/findomain-linux-${ARCH}.zip" \
            -O /tmp/findomain.zip 2>/dev/null
        unzip -o -q /tmp/findomain.zip -d /tmp/ 2>/dev/null
        mv /tmp/findomain "$TOOLS_DIR/findomain" 2>/dev/null || true
        chmod +x "$TOOLS_DIR/findomain"
        rm -f /tmp/findomain.zip
    fi
    [[ -x "$TOOLS_DIR/findomain" ]] && ok "findomain installed" || fail "findomain failed"
fi

# ── truffleHog ──
if cmd_exists "trufflehog"; then
    ok "trufflehog already installed"
elif [[ "$CHECK_ONLY" == true ]]; then
    fail "trufflehog — NOT installed"
else
    info "Installing trufflehog..."
    if [[ "$OS" == "macos" ]]; then
        brew install trufflehog --quiet 2>/dev/null && ok "trufflehog installed" || fail "trufflehog failed"
    else
        curl -sSfL https://raw.githubusercontent.com/trufflesecurity/trufflehog/main/scripts/install.sh \
            | sh -s -- -b /usr/local/bin 2>/dev/null && ok "trufflehog installed" || fail "trufflehog failed"
    fi
fi

# ── gitleaks ──
if cmd_exists "gitleaks"; then
    ok "gitleaks already installed"
elif [[ "$CHECK_ONLY" == true ]]; then
    fail "gitleaks — NOT installed"
else
    info "Installing gitleaks..."
    if [[ "$OS" == "macos" ]]; then
        brew install gitleaks --quiet 2>/dev/null && ok "gitleaks installed" || fail "gitleaks failed"
    else
        go_install "gitleaks" "github.com/gitleaks/gitleaks/v8@latest"
    fi
fi

# ── kiterunner ──
if cmd_exists "kr"; then
    ok "kiterunner (kr) already installed"
elif [[ "$CHECK_ONLY" == true ]]; then
    fail "kiterunner (kr) — NOT installed"
else
    info "Installing kiterunner..."
    KR_ARCH="amd64"
    [[ "$(uname -m)" == "aarch64" || "$(uname -m)" == "arm64" ]] && KR_ARCH="arm64"

    if [[ "$OS" == "macos" ]]; then
        KR_URL="https://github.com/assetnote/kiterunner/releases/latest/download/kiterunner_darwin_${KR_ARCH}.tar.gz"
    else
        KR_URL="https://github.com/assetnote/kiterunner/releases/latest/download/kiterunner_linux_${KR_ARCH}.tar.gz"
    fi

    wget -q "$KR_URL" -O /tmp/kr.tar.gz 2>/dev/null
    tar -xzf /tmp/kr.tar.gz -C /tmp/ 2>/dev/null
    mv /tmp/kr /usr/local/bin/kr 2>/dev/null || mv /tmp/kr "$GO_BIN/kr" 2>/dev/null
    chmod +x /usr/local/bin/kr 2>/dev/null || chmod +x "$GO_BIN/kr" 2>/dev/null
    rm -f /tmp/kr.tar.gz
    cmd_exists "kr" && ok "kiterunner installed" || fail "kiterunner failed — install manually from github.com/assetnote/kiterunner"

    # Download kiterunner wordlist
    ensure_dir "$TOOLS_DIR/kiterunner"
    if [[ ! -f "$TOOLS_DIR/kiterunner/routes-large.kite" ]]; then
        info "Downloading kiterunner routes-large wordlist..."
        wget -q "https://raw.githubusercontent.com/assetnote/kiterunner/main/dist/routes-large.kite" \
            -O "$TOOLS_DIR/kiterunner/routes-large.kite" 2>/dev/null || true
    fi
fi

# ── s3scanner ──
if cmd_exists "s3scanner"; then
    ok "s3scanner already installed"
elif [[ "$CHECK_ONLY" == true ]]; then
    fail "s3scanner — NOT installed"
else
    info "Installing s3scanner..."
    pip3 install s3scanner --break-system-packages --quiet 2>/dev/null && ok "s3scanner installed" || \
        go_install "s3scanner" "github.com/sa7mon/S3Scanner@latest"
fi

# ── aquatone (legacy, gowitness preferred) ──
if cmd_exists "aquatone"; then
    ok "aquatone already installed"
elif cmd_exists "gowitness"; then
    ok "gowitness installed (aquatone not needed)"
elif [[ "$CHECK_ONLY" == true ]]; then
    fail "aquatone — NOT installed (gowitness also missing)"
else
    info "aquatone is deprecated — gowitness is already installed as the replacement."
fi

# ── mantra ──
if cmd_exists "mantra"; then
    ok "mantra already installed"
elif [[ "$CHECK_ONLY" == true ]]; then
    fail "mantra — NOT installed"
else
    go_install "mantra" "github.com/MrEmpy/mantra@latest"
fi

# ════════════════════════════════════════════════════════════════════════════
# SECTION 6: WORDLISTS
# ════════════════════════════════════════════════════════════════════════════
header "Wordlists"

# SecLists (already cloned above, just verify)
if [[ -d "$TOOLS_DIR/SecLists" ]]; then
    ok "SecLists available"
else
    warn "SecLists not found — some fuzzing features will download wordlists on-the-fly"
fi

# Assetnote best-dns-wordlist
DNS_WL="$TOOLS_DIR/wordlists/best-dns-wordlist.txt"
ensure_dir "$TOOLS_DIR/wordlists"
if [[ -f "$DNS_WL" ]]; then
    ok "Assetnote DNS wordlist available"
elif [[ "$CHECK_ONLY" == true ]]; then
    warn "Assetnote DNS wordlist — will be downloaded on first run"
else
    info "Downloading Assetnote best-dns-wordlist..."
    wget -q "https://wordlists-cdn.assetnote.io/data/manual/best-dns-wordlist.txt" \
        -O "$DNS_WL" 2>/dev/null && ok "DNS wordlist downloaded ($(wc -l < "$DNS_WL") entries)" || warn "Download failed — will retry on first run"
fi

# ════════════════════════════════════════════════════════════════════════════
# SECTION 7: CONFIGURATION FILES
# ════════════════════════════════════════════════════════════════════════════
header "Configuration"

# notify config template
NOTIFY_CONF="$HOME/.config/notify/provider-config.yaml"
if [[ -f "$NOTIFY_CONF" ]]; then
    ok "notify config exists"
else
    if [[ "$CHECK_ONLY" == false ]]; then
        ensure_dir "$HOME/.config/notify"
        cat > "$NOTIFY_CONF" <<'NOTIFYEOF'
# notify provider configuration
# Docs: https://github.com/projectdiscovery/notify

# Uncomment and configure the providers you want to use:

# discord:
#   - id: "recon-alerts"
#     discord_channel: "recon"
#     discord_username: "0xMasterRecon"
#     discord_format: "{{data}}"
#     discord_webhook_url: "https://discord.com/api/webhooks/YOUR_WEBHOOK_ID/YOUR_WEBHOOK_TOKEN"

# slack:
#   - id: "recon-slack"
#     slack_channel: "recon"
#     slack_username: "0xMasterRecon"
#     slack_format: "{{data}}"
#     slack_webhook_url: "https://hooks.slack.com/services/YOUR/SLACK/WEBHOOK"

# telegram:
#   - id: "recon-telegram"
#     telegram_api_key: "YOUR_TELEGRAM_BOT_TOKEN"
#     telegram_chat_id: "YOUR_CHAT_ID"
#     telegram_format: "{{data}}"
NOTIFYEOF
        ok "notify config template created at $NOTIFY_CONF"
    else
        warn "notify config not found — create at $NOTIFY_CONF"
    fi
fi

# subfinder provider config
SUBFINDER_CONF="$HOME/.config/subfinder/provider-config.yaml"
if [[ -f "$SUBFINDER_CONF" ]]; then
    ok "subfinder provider config exists"
else
    if [[ "$CHECK_ONLY" == false ]]; then
        ensure_dir "$HOME/.config/subfinder"
        cat > "$SUBFINDER_CONF" <<'SUBEOF'
# subfinder provider configuration
# Add your API keys here for better results

# shodan:
#   - YOUR_SHODAN_API_KEY

# securitytrails:
#   - YOUR_SECURITYTRAILS_KEY

# virustotal:
#   - YOUR_VIRUSTOTAL_KEY

# censys:
#   - YOUR_CENSYS_ID:YOUR_CENSYS_SECRET

# chaos:
#   - YOUR_CHAOS_KEY

# github:
#   - YOUR_GITHUB_TOKEN
SUBEOF
        ok "subfinder config template created at $SUBFINDER_CONF"
    else
        warn "subfinder provider config not found"
    fi
fi

# ════════════════════════════════════════════════════════════════════════════
# FINAL CHECK — Verify all tools
# ════════════════════════════════════════════════════════════════════════════
header "Final Verification"

TOTAL=0
INSTALLED=0
MISSING=0
MISSING_LIST=""

check_tool() {
    local name="$1"
    local alt="${2:-}"
    TOTAL=$((TOTAL + 1))
    if cmd_exists "$name"; then
        ok "$name"
        INSTALLED=$((INSTALLED + 1))
    elif [[ -n "$alt" ]] && cmd_exists "$alt"; then
        ok "$name (via $alt)"
        INSTALLED=$((INSTALLED + 1))
    elif [[ -n "$alt" ]] && [[ -x "$TOOLS_DIR/$alt" ]]; then
        ok "$name (at $TOOLS_DIR/$alt)"
        INSTALLED=$((INSTALLED + 1))
    elif [[ -f "$TOOLS_DIR/$name/$name.py" ]] || [[ -f "$TOOLS_DIR/$name/$(echo "$name" | tr '[:upper:]' '[:lower:]').py" ]]; then
        ok "$name (Python in $TOOLS_DIR/$name/)"
        INSTALLED=$((INSTALLED + 1))
    else
        fail "$name"
        MISSING=$((MISSING + 1))
        MISSING_LIST="${MISSING_LIST}\n  - $name"
    fi
}

echo ""
echo -e "${DIM}Checking all 40+ tools...${RESET}"
echo ""

# Core system
check_tool "git"
check_tool "curl"
check_tool "wget"
check_tool "jq"
check_tool "nmap"
check_tool "python3"
check_tool "go"
check_tool "massdns"

# ProjectDiscovery
check_tool "subfinder"
check_tool "httpx"
check_tool "dnsx"
check_tool "nuclei"
check_tool "naabu"
check_tool "katana"
check_tool "shuffledns"
check_tool "notify"
check_tool "interactsh-client"
check_tool "asnmap"
check_tool "mapcidr"

# tomnomnom suite
check_tool "assetfinder"
check_tool "httprobe"
check_tool "waybackurls"
check_tool "unfurl"
check_tool "qsreplace"
check_tool "meg"
check_tool "gf"
check_tool "anew"

# Scanners & fuzzers
check_tool "ffuf"
check_tool "hakrawler"
check_tool "gau"
check_tool "gowitness"
check_tool "puredns"
check_tool "airixss"
check_tool "sqlmap"
check_tool "wafw00f"
check_tool "whatweb"

# Recon & OSINT
check_tool "findomain" "findomain"
check_tool "socialhunter"
check_tool "trufflehog"
check_tool "gitleaks"
check_tool "kr"
check_tool "s3scanner"
check_tool "uro"
check_tool "paramspider"

# Python tools (check as directories)
for pt in SecretFinder LinkFinder XSStrike CMSeeK cloud_enum ParamSpider findom-xss sublert; do
    TOTAL=$((TOTAL + 1))
    if [[ -d "$TOOLS_DIR/$pt" ]]; then
        ok "$pt (in ~/tools/)"
        INSTALLED=$((INSTALLED + 1))
    else
        fail "$pt"
        MISSING=$((MISSING + 1))
        MISSING_LIST="${MISSING_LIST}\n  - $pt"
    fi
done

# Wordlists
TOTAL=$((TOTAL + 1))
if [[ -d "$TOOLS_DIR/SecLists" ]]; then
    ok "SecLists wordlists"
    INSTALLED=$((INSTALLED + 1))
else
    fail "SecLists"
    MISSING=$((MISSING + 1))
fi

# ════════════════════════════════════════════════════════════════════════════
# SUMMARY
# ════════════════════════════════════════════════════════════════════════════
echo ""
echo -e "${BOLD}═══════════════════════════════════════════════════════════════${RESET}"
echo -e "${GREEN} Installation Summary${RESET}"
echo -e "${BOLD}═══════════════════════════════════════════════════════════════${RESET}"
echo -e " Tools checked:   ${BOLD}${TOTAL}${RESET}"
echo -e " Installed:       ${GREEN}${INSTALLED}${RESET}"
echo -e " Missing:         ${RED}${MISSING}${RESET}"

if [[ $MISSING -gt 0 ]]; then
    echo -e ""
    echo -e " ${YELLOW}Missing tools:${RESET}"
    echo -e "$MISSING_LIST"
fi

echo -e "${BOLD}───────────────────────────────────────────────────────────────${RESET}"
echo -e " ${CYAN}Next steps:${RESET}"
echo -e "  1. Edit ${BOLD}recon.sh${RESET} CONFIG section — set your Discord webhook & Shodan key"
echo -e "  2. Edit ${BOLD}~/.config/subfinder/provider-config.yaml${RESET} — add API keys"
echo -e "  3. Edit ${BOLD}~/.config/notify/provider-config.yaml${RESET} — configure notifications"
echo -e "  4. Run: ${GREEN}source ~/.bashrc${RESET} (or ~/.zshrc) to load Go paths"
echo -e "  5. Test: ${GREEN}./recon.sh testdomain.com --passive${RESET}"
echo -e "${BOLD}═══════════════════════════════════════════════════════════════${RESET}"
echo ""
