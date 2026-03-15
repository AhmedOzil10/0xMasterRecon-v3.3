#!/bin/bash
# ============================================================================
# 0xMasterRecon v3.3 - Bug Bounty & Red Team Reconnaissance Framework
# Author: @MrOz1l
#
# Modes:
#   --passive     : No active probing. OSINT, archive, JS secrets, GitHub, cloud.
#   --full        : (default) Passive + active scanning, fuzzing, vuln checks.
#   --aggressive  : Full + port scan, deeper fuzzing, higher sqlmap levels.
#
# Usage:
#   ./recon.sh <domain.tld>                                 # --full default
#   ./recon.sh <domain.tld> --passive
#   ./recon.sh <domain.tld> --aggressive
#   ./recon.sh <domain.tld> --discord <webhook_url>         # Discord alerts
#   ./recon.sh <domain.tld> --full --notify --discord <url> # both
# ============================================================================

set -euo pipefail

# ── Colors & Globals ────────────────────────────────────────────────────────
RED="\033[0;31m"
YELLOW="\033[1;33m"
GREEN="\033[0;32m"
CYAN="\033[0;36m"
BOLD="\033[1m"
DIM="\033[2m"
RESET="\033[0m"

VERSION="3.3"
HOMEDIR="$HOME"
MODE="full"
NOTIFY_ENABLED=false
domain=""

# ════════════════════════════════════════════════════════════════════════════
# CONFIG — Set your API keys and webhooks here (or pass via CLI flags)
# ════════════════════════════════════════════════════════════════════════════
DISCORD_WEBHOOK="https://discord.com/api/webhooks/YOUR_WEBHOOK_ID/YOUR_WEBHOOK_TOKEN"
SHODAN_API_KEY="YOUR_SHODAN_API_KEY_HERE"
# ════════════════════════════════════════════════════════════════════════════

# Directories (set after argument parsing)
RESULTDIR="" ; SUBS="" ; SCREENSHOTS="" ; DIRSCAN="" ; HTML=""
GFSCAN="" ; IPS="" ; SPIDERING="" ; PORTSCAN="" ; ARCHIVE=""
NUCLEISCAN="" ; WORDLIST="" ; SECRETS="" ; CLOUD="" ; APIRECON=""
CIDR_ASN=""

# httpx detection
HAS_PD_HTTPX=false
HTTPX_BIN=""

# Interactsh
INTERACTSH_URL=""
INTERACTSH_PID=""

# ── Logging ─────────────────────────────────────────────────────────────────
log_info()  { echo -e "[${GREEN}+${RESET}] $1"; }
log_warn()  { echo -e "[${YELLOW}!${RESET}] $1"; }
log_err()   { echo -e "[${RED}✗${RESET}] $1"; }
log_start() { echo -e "[${CYAN}→${RESET}] Starting ${BOLD}$1${RESET}"; }

send_notify() {
    local msg="$1"
    local severity="${2:-info}"  # info, warn, critical

    # Native Discord webhook (rich embeds)
    if [[ -n "$DISCORD_WEBHOOK" ]]; then
        local color=3447003   # blue
        [[ "$severity" == "warn" ]] && color=16776960     # yellow
        [[ "$severity" == "critical" ]] && color=15158332  # red

        local payload
        payload=$(cat <<DISCORD_EOF
{
  "embeds": [{
    "title": "0xMasterRecon v${VERSION}",
    "description": "${msg}",
    "color": ${color},
    "footer": {"text": "Target: ${domain} | Mode: ${MODE}"},
    "timestamp": "$(date -u +%Y-%m-%dT%H:%M:%SZ)"
  }]
}
DISCORD_EOF
)
        curl -s -H "Content-Type: application/json" \
            -d "$payload" "$DISCORD_WEBHOOK" >/dev/null 2>&1 || true
    fi

    # ProjectDiscovery notify tool (Slack/Telegram/etc)
    if [[ "$NOTIFY_ENABLED" == true ]] && cmd_exists "notify"; then
        echo "$msg" | notify -silent 2>/dev/null || true
    fi
}

# Discord: send a file as attachment (for final report)
send_discord_file() {
    local filepath="$1"
    local message="${2:-Scan results attached}"
    [[ -z "$DISCORD_WEBHOOK" ]] && return 0
    [[ ! -f "$filepath" ]] && return 0

    curl -s -F "file=@${filepath}" \
        -F "payload_json={\"content\":\"${message}\"}" \
        "$DISCORD_WEBHOOK" >/dev/null 2>&1 || true
}

# ── Banner ──────────────────────────────────────────────────────────────────
displayLogo() {
    echo -e "
${CYAN} _____     ___  ___          _           ______                     
|  _  |    |  \\/  |         | |          | ___ \\                    
| |/' |_  _| .  . | __ _ ___| |_ ___ _ __| |_/ /___  ___ ___  _ __  
|  /| \\ \\/ / |\\/| |/ _\` / __| __/ _ \\ '__|    // _ \\/ __/ _ \\| '_ \\ 
\\ |_/ />  <| |  | | (_| \\__ \\ ||  __/ |  | |\\ \\  __/ (_| (_) | | | |
 \\___//_/\\_\\_|  |_/\\__,_|___/\\__\\___|_|  \\_| \\_\\___|\\___\\___/|_| |_|${RESET}

                  ${YELLOW}v${VERSION}${RESET} — ${GREEN}@MrOz1l${RESET}
    "
}

# ── Argument Parsing ────────────────────────────────────────────────────────
showHelp() {
    displayLogo
    echo -e "${BOLD}USAGE${RESET}"
    echo -e "  $0 <domain.tld> [OPTIONS]"
    echo ""
    echo -e "${BOLD}SCAN MODES${RESET}"
    echo -e "  ${GREEN}--passive${RESET}              OSINT only. Zero active probing against target."
    echo -e "  ${GREEN}--full${RESET}                 ${DIM}(default)${RESET} Passive + active scanning + vuln checks."
    echo -e "  ${GREEN}--aggressive${RESET}           Full + port scan, deep fuzzing, level 5 sqlmap."
    echo ""
    echo -e "${BOLD}INTEGRATIONS${RESET}"
    echo -e "  ${GREEN}--discord <url>${RESET}        Send rich alerts to Discord webhook."
    echo -e "  ${GREEN}--shodan <key>${RESET}         Shodan API key for host/CVE/service intel."
    echo -e "  ${GREEN}--notify${RESET}               Send via ProjectDiscovery notify (Slack/Telegram)."
    echo ""
    echo -e "${BOLD}OTHER${RESET}"
    echo -e "  ${GREEN}-h, --help${RESET}             Show this help message."
    echo ""
    echo -e "${BOLD}EXAMPLES${RESET}"
    echo -e "  ${DIM}# Default full scan${RESET}"
    echo -e "  $0 target.com"
    echo ""
    echo -e "  ${DIM}# Passive recon only${RESET}"
    echo -e "  $0 target.com --passive"
    echo ""
    echo -e "  ${DIM}# Aggressive with Shodan + Discord${RESET}"
    echo -e "  $0 target.com --aggressive --shodan YOUR_KEY --discord https://discord.com/api/webhooks/..."
    echo ""
    echo -e "  ${DIM}# Full scan with all notifications${RESET}"
    echo -e "  $0 target.com --full --notify --discord https://discord.com/api/webhooks/..."
    echo ""
    echo -e "${BOLD}CONFIG${RESET}"
    echo -e "  You can hardcode DISCORD_WEBHOOK and SHODAN_API_KEY in the CONFIG"
    echo -e "  section at the top of this script so you don't need flags every run."
    echo ""
    echo -e "${BOLD}SCAN PHASES${RESET}"
    echo -e "  ${CYAN}Phase 1${RESET} — Discovery     subfinder, amass, findomain, crt.sh, puredns,"
    echo -e "                          shuffledns, httpx, CIDR/ASN, Shodan"
    echo -e "  ${CYAN}Phase 2${RESET} — Recon         wafw00f, WhatWeb/CMSeeK, screenshots, GAU,"
    echo -e "                          SecretFinder, truffleHog, cloud_enum, socialhunter"
    echo -e "  ${CYAN}Phase 3${RESET} — Active        interactsh, katana, hakrawler, ParamSpider,"
    echo -e "                          ffuf, kiterunner"
    echo -e "  ${CYAN}Phase 4${RESET} — Vulns         SSRF, XSS, open redirect, SQLi, gf patterns,"
    echo -e "                          nuclei, port scan"
    echo -e "  ${CYAN}Phase 5${RESET} — Report        HTML dashboard, Discord uploads, summary"
    echo ""
    echo -e "${BOLD}OUTPUT${RESET}"
    echo -e "  Results saved to: ${CYAN}~/assets/<domain>/${RESET}"
    echo -e "  HTML report:      ${CYAN}~/assets/<domain>/html/report.html${RESET}"
    echo ""
}

parseArguments() {
    # Handle -h/--help before anything else (even without a domain)
    for arg in "$@"; do
        case "$arg" in
            -h|--help) showHelp; exit 0 ;;
        esac
    done

    if [[ $# -eq 0 ]]; then
        showHelp
        exit 1
    fi

    domain="$1"
    shift

    while [[ $# -gt 0 ]]; do
        case "$1" in
            --passive)    MODE="passive" ;;
            --full)       MODE="full" ;;
            --aggressive) MODE="aggressive" ;;
            --notify)     NOTIFY_ENABLED=true ;;
            -h|--help)    showHelp; exit 0 ;;
            --discord)
                shift
                if [[ $# -gt 0 ]] && [[ "$1" == https://* ]]; then
                    DISCORD_WEBHOOK="$1"
                else
                    log_err "Missing or invalid Discord webhook URL after --discord"
                    exit 1
                fi
                ;;
            --shodan)
                shift
                if [[ $# -gt 0 ]] && [[ -n "$1" ]]; then
                    SHODAN_API_KEY="$1"
                else
                    log_err "Missing Shodan API key after --shodan"
                    exit 1
                fi
                ;;
            *)            log_warn "Unknown flag: $1 (use -h for help)" ;;
        esac
        shift
    done

    # ── Validate placeholders — disable if still default ──
    if [[ "$DISCORD_WEBHOOK" == *"YOUR_WEBHOOK"* ]]; then
        DISCORD_WEBHOOK=""
    fi
    if [[ "$SHODAN_API_KEY" == *"YOUR_SHODAN"* ]]; then
        SHODAN_API_KEY=""
    fi

    RESULTDIR="$HOMEDIR/assets/$domain"
    SUBS="$RESULTDIR/subdomains"
    SCREENSHOTS="$RESULTDIR/screenshots"
    DIRSCAN="$RESULTDIR/directories"
    HTML="$RESULTDIR/html"
    GFSCAN="$RESULTDIR/gfscan"
    IPS="$RESULTDIR/ips"
    SPIDERING="$RESULTDIR/Spidering"
    PORTSCAN="$RESULTDIR/portscan"
    ARCHIVE="$RESULTDIR/archive"
    NUCLEISCAN="$RESULTDIR/nucleiscan"
    WORDLIST="$RESULTDIR/wordlists"
    SECRETS="$RESULTDIR/secrets"
    CLOUD="$RESULTDIR/cloud"
    APIRECON="$RESULTDIR/api"
    CIDR_ASN="$RESULTDIR/cidr-asn"
    SHODAN_DIR="$RESULTDIR/shodan"
}

# ── Mode Helpers ────────────────────────────────────────────────────────────
is_active()     { [[ "$MODE" == "full" || "$MODE" == "aggressive" ]]; }
is_aggressive() { [[ "$MODE" == "aggressive" ]]; }

# ── Utility ─────────────────────────────────────────────────────────────────
cmd_exists()     { command -v "$1" &>/dev/null; }
check_and_warn() { cmd_exists "$1" || { log_warn "$1 not found — skipping."; return 1; }; }
safe_wc()        { wc -l < "$1" 2>/dev/null || echo 0; }

# ── PD httpx Detection ─────────────────────────────────────────────────────
detect_httpx() {
    if ! cmd_exists "httpx"; then
        HAS_PD_HTTPX=false; return
    fi
    local v
    v=$(httpx -version 2>&1 || true)
    if echo "$v" | grep -qi "projectdiscovery\|Current httpx version"; then
        HAS_PD_HTTPX=true; HTTPX_BIN="httpx"
        log_info "Detected ProjectDiscovery httpx."
        return
    fi
    v=$(httpx --version 2>&1 || true)
    if echo "$v" | grep -qiP "^httpx,\s*version"; then
        HAS_PD_HTTPX=false
        log_warn "Detected Python httpx — NOT ProjectDiscovery httpx."
    fi
    if [[ "$HAS_PD_HTTPX" == false ]]; then
        for candidate in "$HOME/go/bin/httpx" "/usr/local/bin/httpx" "${GOPATH:-/nonexistent}/bin/httpx"; do
            [[ -x "$candidate" ]] || continue
            local cv
            cv=$("$candidate" -version 2>&1 || true)
            if echo "$cv" | grep -qi "projectdiscovery\|Current httpx version"; then
                HAS_PD_HTTPX=true; HTTPX_BIN="$candidate"
                log_info "Found PD httpx at: $HTTPX_BIN"
                break
            fi
        done
    fi
}

run_pd_httpx() {
    [[ "$HAS_PD_HTTPX" == true ]] && "$HTTPX_BIN" "$@" || return 1
}

# ── Python Deps ─────────────────────────────────────────────────────────────
fix_python_deps() {
    log_info "Checking Python dependencies..."
    for pkg in uro paramspider; do
        python3 -c "import $pkg" 2>/dev/null || \
            pip3 install "$pkg" --break-system-packages --quiet 2>/dev/null || true
    done
}

# ── Directory Setup ─────────────────────────────────────────────────────────
checkDirectories() {
    log_info "Creating output directories for ${GREEN}${domain}${RESET}..."
    mkdir -p "$SUBS" "$SCREENSHOTS" "$DIRSCAN" "$HTML" "$WORDLIST" \
             "$IPS" "$PORTSCAN" "$ARCHIVE" "$NUCLEISCAN" "$GFSCAN" \
             "$SPIDERING" "$SECRETS" "$CLOUD" "$APIRECON" "$CIDR_ASN" "$SHODAN_DIR"
}

# ── Resolvers ───────────────────────────────────────────────────────────────
gatherResolvers() {
    log_start "Fresh Resolvers"
    if wget -q "https://raw.githubusercontent.com/trickest/resolvers/main/resolvers.txt" \
        -O "$IPS/resolvers.txt" 2>/dev/null; then
        log_info "Downloaded trickest resolvers ($(safe_wc "$IPS/resolvers.txt") entries)."
    elif wget -q "https://raw.githubusercontent.com/janmasarik/resolvers/master/resolvers.txt" \
        -O "$IPS/resolvers.txt" 2>/dev/null; then
        log_info "Downloaded janmasarik resolvers."
    else
        printf '%s\n' 8.8.8.8 8.8.4.4 1.1.1.1 1.0.0.1 9.9.9.9 > "$IPS/resolvers.txt"
        log_warn "Using built-in default resolvers."
    fi
}

# ════════════════════════════════════════════════════════════════════════════
# PHASE 1: SUBDOMAIN DISCOVERY
# ════════════════════════════════════════════════════════════════════════════

gatherSubdomains() {
    log_start "Passive Subdomain Enumeration"

    cmd_exists "subfinder" && {
        subfinder -d "$domain" -all -o "$SUBS/subfinder.txt" 2>/dev/null || true
        log_info "subfinder: $(safe_wc "$SUBS/subfinder.txt") subs"
    }
    cmd_exists "assetfinder" && {
        assetfinder --subs-only "$domain" 2>/dev/null | sort -u > "$SUBS/assetfinder.txt" || true
    }
    cmd_exists "amass" && {
        amass enum -passive -d "$domain" -o "$SUBS/amassp.txt" 2>/dev/null || true
    }
    if cmd_exists "findomain"; then
        findomain -t "$domain" -u "$SUBS/findomain_subdomains.txt" 2>/dev/null || true
    elif [[ -x "$HOMEDIR/tools/findomain" ]]; then
        "$HOMEDIR/tools/findomain" -t "$domain" -u "$SUBS/findomain_subdomains.txt" 2>/dev/null || true
    fi

    # crt.sh
    local crtsh_raw
    crtsh_raw=$(curl -s "https://crt.sh/?q=%25.${domain}&output=json" 2>/dev/null || echo "")
    if [[ -n "$crtsh_raw" ]] && [[ "$crtsh_raw" != "[]" ]]; then
        if cmd_exists "jq"; then
            echo "$crtsh_raw" | jq -r '.[].name_value' 2>/dev/null \
                | sed 's/\*\.//g' | grep -v '^$' | sort -u > "$SUBS/crtsh_subdomains.txt" || true
        else
            echo "$crtsh_raw" | grep -oE '"name_value"[[:space:]]*:[[:space:]]*"[^"]+"' \
                | sed 's/"name_value"[[:space:]]*:[[:space:]]*"//;s/"$//' \
                | sed 's/\\n/\n/g;s/\*\.//g' | grep -v '^$' | sort -u > "$SUBS/crtsh_subdomains.txt" || true
        fi
    else
        touch "$SUBS/crtsh_subdomains.txt"
    fi

    # sublert
    if [[ -d "$HOMEDIR/tools/sublert" ]]; then
        (cd "$HOMEDIR/tools/sublert" && yes | python3 sublert.py -u "$domain" 2>/dev/null) || true
        [[ -f "$HOMEDIR/tools/sublert/output/${domain}.txt" ]] && \
            cp "$HOMEDIR/tools/sublert/output/${domain}.txt" "$SUBS/sublert.txt" 2>/dev/null || true
    fi

    cat "$SUBS"/*.txt 2>/dev/null | grep -v '^$' | sort -u > "$SUBS/subdomains"
    log_info "Total passive subdomains: ${GREEN}$(safe_wc "$SUBS/subdomains")${RESET}"
    send_notify "[0xMasterRecon] $domain — $(safe_wc "$SUBS/subdomains") passive subdomains"
}

# ── NEW: puredns active bruteforce (full + aggressive) ─────────────────────
bruteforceSubdomains() {
    is_active || return 0
    check_and_warn "puredns" || return 0

    log_start "Active Subdomain Bruteforce (puredns)"

    local brute_wordlist="$WORDLIST/best-dns-wordlist.txt"
    if [[ ! -f "$brute_wordlist" ]]; then
        log_info "Downloading Assetnote best-dns-wordlist..."
        wget -q "https://wordlists-cdn.assetnote.io/data/manual/best-dns-wordlist.txt" \
            -O "$brute_wordlist" 2>/dev/null || true
    fi
    [[ ! -s "$brute_wordlist" ]] && { log_warn "No wordlist — skipping bruteforce."; return; }

    puredns bruteforce "$brute_wordlist" "$domain" \
        -r "$IPS/resolvers.txt" --wildcard-batch 1000000 \
        -q -w "$SUBS/puredns_brute.txt" 2>/dev/null || true

    cat "$SUBS/puredns_brute.txt" >> "$SUBS/subdomains" 2>/dev/null || true
    sort -u -o "$SUBS/subdomains" "$SUBS/subdomains"
    log_info "After bruteforce: ${GREEN}$(safe_wc "$SUBS/subdomains")${RESET} total subs"
    send_notify "[0xMasterRecon] $domain — puredns added $(safe_wc "$SUBS/puredns_brute.txt") subs"
}

resolveSubdomains() {
    log_start "Resolving Subdomains"
    if cmd_exists "shuffledns"; then
        shuffledns -mode resolve -d "$domain" -list "$SUBS/subdomains" \
            -r "$IPS/resolvers.txt" -o "$SUBS/alive_subdomains" 2>/dev/null || true
    else
        cp "$SUBS/subdomains" "$SUBS/alive_subdomains"
    fi
    touch "$SUBS/alive_subdomains"
    log_info "Resolved: $(safe_wc "$SUBS/alive_subdomains") alive"
}

probeHosts() {
    is_active || return 0
    log_start "HTTP Probing"
    if [[ "$HAS_PD_HTTPX" == true ]]; then
        run_pd_httpx -l "$SUBS/alive_subdomains" -silent -threads 100 -timeout 10 \
            -o "$SUBS/hosts" 2>/dev/null || true
    elif cmd_exists "httprobe"; then
        cat "$SUBS/alive_subdomains" | httprobe -c 100 | sort -u > "$SUBS/hosts" 2>/dev/null || true
    else
        while IFS= read -r sub; do
            for s in http https; do
                curl -s -o /dev/null -w "%{http_code}" --max-time 5 "${s}://${sub}" 2>/dev/null \
                    | grep -qE '^[23]' && echo "${s}://${sub}"
            done
        done < "$SUBS/alive_subdomains" | sort -u > "$SUBS/hosts"
    fi
    touch "$SUBS/hosts"
    log_info "Live hosts: ${GREEN}$(safe_wc "$SUBS/hosts")${RESET}"
    send_notify "[0xMasterRecon] $domain — $(safe_wc "$SUBS/hosts") live hosts"
}

gatherIPs() {
    log_start "IP Resolution"
    if cmd_exists "dnsx"; then
        dnsx -l "$SUBS/alive_subdomains" -a -resp-only -silent | sort -u > "$IPS/${domain}-ips.txt" 2>/dev/null || true
    elif cmd_exists "dnsprobe"; then
        cat "$SUBS/alive_subdomains" | dnsprobe -silent -f ip | sort -u > "$IPS/${domain}-ips.txt" 2>/dev/null || true
    else
        while read -r sub; do dig +short "$sub" A 2>/dev/null; done < "$SUBS/alive_subdomains" \
            | grep -oP '^\d+\.\d+\.\d+\.\d+$' | sort -u > "$IPS/${domain}-ips.txt"
    fi
    log_info "IPs: $(safe_wc "$IPS/${domain}-ips.txt")"
}

# ════════════════════════════════════════════════════════════════════════════
# NEW MODULE: CIDR & ASN ENUMERATION (all modes)
# Discovers ASN ownership, CIDR ranges, and related netblocks for the target.
# Tools: asnmap, amass, whois, bgp.he.net scraping, asnlookup
# ════════════════════════════════════════════════════════════════════════════
enumCIDR_ASN() {
    log_start "CIDR & ASN Enumeration"

    local org_name
    org_name=$(echo "$domain" | sed 's/\..*//')

    # ── Step 1: ASN Discovery ──
    # Method A: asnmap (ProjectDiscovery — best method)
    if cmd_exists "asnmap"; then
        log_info "Running asnmap for $domain..."

        # By domain
        asnmap -d "$domain" -json 2>/dev/null | tee "$CIDR_ASN/asnmap-domain.json" || true

        # By org keyword
        asnmap -org "$org_name" -json 2>/dev/null | tee "$CIDR_ASN/asnmap-org.json" || true

        # Extract ASNs
        if cmd_exists "jq"; then
            jq -r '.asn // empty' "$CIDR_ASN"/asnmap-*.json 2>/dev/null \
                | sort -u > "$CIDR_ASN/asns.txt" || true
            jq -r '.cidr // empty' "$CIDR_ASN"/asnmap-*.json 2>/dev/null \
                | sort -u > "$CIDR_ASN/cidrs.txt" || true
            jq -r '.as_name // empty' "$CIDR_ASN"/asnmap-*.json 2>/dev/null \
                | sort -u > "$CIDR_ASN/as-names.txt" || true
        else
            grep -oP '"asn"\s*:\s*"\K[^"]+' "$CIDR_ASN"/asnmap-*.json 2>/dev/null \
                | sort -u > "$CIDR_ASN/asns.txt" || true
            grep -oP '"cidr"\s*:\s*"\K[^"]+' "$CIDR_ASN"/asnmap-*.json 2>/dev/null \
                | sort -u > "$CIDR_ASN/cidrs.txt" || true
        fi

        log_info "asnmap found $(safe_wc "$CIDR_ASN/asns.txt") ASNs, $(safe_wc "$CIDR_ASN/cidrs.txt") CIDRs."
    fi

    # Method B: whois + IP-to-ASN lookup (fallback)
    if [[ ! -s "$CIDR_ASN/asns.txt" ]] && [[ -s "$IPS/${domain}-ips.txt" ]]; then
        log_info "Falling back to whois/IP-based ASN lookup..."
        touch "$CIDR_ASN/asns.txt" "$CIDR_ASN/cidrs.txt" "$CIDR_ASN/as-names.txt"

        while IFS= read -r ip; do
            # Team Cymru DNS-based ASN lookup (fastest, most reliable)
            local reversed
            reversed=$(echo "$ip" | awk -F. '{print $4"."$3"."$2"."$1}')
            local asn_result
            asn_result=$(dig +short "$reversed.origin.asn.cymru.com" TXT 2>/dev/null | tr -d '"' || true)

            if [[ -n "$asn_result" ]]; then
                local asn cidr
                asn=$(echo "$asn_result" | awk -F'|' '{gsub(/ /,"",$1); print "AS"$1}')
                cidr=$(echo "$asn_result" | awk -F'|' '{gsub(/^ +| +$/,"",$2); print $2}')
                [[ -n "$asn" ]] && echo "$asn" >> "$CIDR_ASN/asns.txt"
                [[ -n "$cidr" ]] && echo "$cidr" >> "$CIDR_ASN/cidrs.txt"

                # Get ASN name
                local asn_num=${asn#AS}
                local asn_name
                asn_name=$(dig +short "AS${asn_num}.asn.cymru.com" TXT 2>/dev/null \
                    | tr -d '"' | awk -F'|' '{gsub(/^ +| +$/,"",$NF); print $NF}' || true)
                [[ -n "$asn_name" ]] && echo "$asn_name" >> "$CIDR_ASN/as-names.txt"
            fi
        done < <(head -20 "$IPS/${domain}-ips.txt")  # cap at 20 IPs to avoid rate limiting

        sort -u -o "$CIDR_ASN/asns.txt" "$CIDR_ASN/asns.txt"
        sort -u -o "$CIDR_ASN/cidrs.txt" "$CIDR_ASN/cidrs.txt"
        sort -u -o "$CIDR_ASN/as-names.txt" "$CIDR_ASN/as-names.txt"

        log_info "Whois/Cymru found $(safe_wc "$CIDR_ASN/asns.txt") ASNs, $(safe_wc "$CIDR_ASN/cidrs.txt") CIDRs."
    fi

    # Method C: amass intel ASN (if amass supports it)
    if cmd_exists "amass" && [[ -s "$CIDR_ASN/asns.txt" ]]; then
        log_info "Expanding ASN ranges via amass..."
        while IFS= read -r asn; do
            local asn_num=${asn#AS}
            amass intel -asn "$asn_num" 2>/dev/null >> "$CIDR_ASN/amass-asn-domains.txt" || true
        done < "$CIDR_ASN/asns.txt"

        if [[ -s "$CIDR_ASN/amass-asn-domains.txt" ]]; then
            sort -u -o "$CIDR_ASN/amass-asn-domains.txt" "$CIDR_ASN/amass-asn-domains.txt"
            log_info "amass ASN intel: $(safe_wc "$CIDR_ASN/amass-asn-domains.txt") related domains."
        fi
    fi

    # ── Step 2: Expand CIDRs → live hosts (full + aggressive) ──
    if is_active && [[ -s "$CIDR_ASN/cidrs.txt" ]]; then
        log_info "Scanning CIDR ranges for live hosts..."

        if cmd_exists "mapcidr"; then
            # mapcidr expands CIDR to individual IPs
            mapcidr -l "$CIDR_ASN/cidrs.txt" -silent \
                > "$CIDR_ASN/cidr-expanded-ips.txt" 2>/dev/null || true
            log_info "Expanded CIDRs to $(safe_wc "$CIDR_ASN/cidr-expanded-ips.txt") IPs."

            # Reverse DNS on expanded IPs to find hidden subdomains
            if cmd_exists "dnsx" && is_aggressive; then
                log_info "Reverse DNS on CIDR IPs (aggressive)..."
                dnsx -l "$CIDR_ASN/cidr-expanded-ips.txt" -ptr -resp-only -silent \
                    | grep -i "$domain" \
                    | sort -u > "$CIDR_ASN/reverse-dns-subs.txt" 2>/dev/null || true

                if [[ -s "$CIDR_ASN/reverse-dns-subs.txt" ]]; then
                    local new_subs
                    new_subs=$(safe_wc "$CIDR_ASN/reverse-dns-subs.txt")
                    log_info "Reverse DNS found $new_subs new subdomains from CIDR ranges!"

                    # Merge into main subdomain list
                    cat "$CIDR_ASN/reverse-dns-subs.txt" >> "$SUBS/subdomains"
                    sort -u -o "$SUBS/subdomains" "$SUBS/subdomains"
                fi
            fi
        elif cmd_exists "nmap" && is_aggressive; then
            # nmap ping sweep on CIDRs
            log_info "nmap ping sweep on CIDR ranges..."
            while IFS= read -r cidr; do
                nmap -sn -T4 "$cidr" -oG - 2>/dev/null \
                    | grep "Up" | awk '{print $2}'
            done < "$CIDR_ASN/cidrs.txt" | sort -u > "$CIDR_ASN/cidr-live-hosts.txt" || true
            log_info "nmap found $(safe_wc "$CIDR_ASN/cidr-live-hosts.txt") live IPs in CIDR ranges."
        fi
    fi

    # ── Step 3: BGP/RIR information ──
    if [[ -s "$CIDR_ASN/asns.txt" ]]; then
        log_info "Fetching BGP/RIR details..."
        while IFS= read -r asn; do
            local asn_num=${asn#AS}
            # RIPEstat API (works for all RIRs)
            curl -s "https://stat.ripe.net/data/announced-prefixes/data.json?resource=AS${asn_num}" 2>/dev/null \
                | grep -oP '"prefix"\s*:\s*"\K[^"]+' \
                >> "$CIDR_ASN/bgp-prefixes.txt" 2>/dev/null || true
        done < "$CIDR_ASN/asns.txt"

        if [[ -s "$CIDR_ASN/bgp-prefixes.txt" ]]; then
            sort -u -o "$CIDR_ASN/bgp-prefixes.txt" "$CIDR_ASN/bgp-prefixes.txt"
            log_info "BGP announced prefixes: $(safe_wc "$CIDR_ASN/bgp-prefixes.txt")"
        fi
    fi

    # ── Summary file ──
    {
        echo "═══════════════════════════════════════════"
        echo "CIDR/ASN Report — $domain"
        echo "Generated: $(date -u '+%Y-%m-%d %H:%M UTC')"
        echo "═══════════════════════════════════════════"
        echo ""
        echo "── ASN Numbers ──"
        cat "$CIDR_ASN/asns.txt" 2>/dev/null || echo "None found"
        echo ""
        echo "── AS Names ──"
        cat "$CIDR_ASN/as-names.txt" 2>/dev/null || echo "None found"
        echo ""
        echo "── CIDR Ranges ──"
        cat "$CIDR_ASN/cidrs.txt" 2>/dev/null || echo "None found"
        echo ""
        echo "── BGP Prefixes ──"
        cat "$CIDR_ASN/bgp-prefixes.txt" 2>/dev/null || echo "None found"
        echo ""
        if [[ -s "$CIDR_ASN/amass-asn-domains.txt" ]]; then
            echo "── Related Domains from ASN ──"
            head -50 "$CIDR_ASN/amass-asn-domains.txt"
            echo "($(safe_wc "$CIDR_ASN/amass-asn-domains.txt") total)"
        fi
    } > "$CIDR_ASN/cidr-asn-report.txt"

    # Notify
    local asn_count cidr_count
    asn_count=$(safe_wc "$CIDR_ASN/asns.txt")
    cidr_count=$(safe_wc "$CIDR_ASN/cidrs.txt")
    if [[ "$asn_count" -gt 0 ]] || [[ "$cidr_count" -gt 0 ]]; then
        send_notify "CIDR/ASN: ${asn_count} ASNs, ${cidr_count} CIDR ranges discovered for ${domain}" "info"
    fi

    log_info "CIDR/ASN enumeration complete. Report: $CIDR_ASN/cidr-asn-report.txt"
}

# ════════════════════════════════════════════════════════════════════════════
# MODULE: SHODAN RECONNAISSANCE (all modes — requires API key)
# Host lookup, domain search, open ports, CVEs, tech fingerprinting
# ════════════════════════════════════════════════════════════════════════════
shodanRecon() {
    if [[ -z "$SHODAN_API_KEY" ]]; then
        log_warn "Shodan API key not set — skipping. Set it in the CONFIG section or use --shodan <key>"
        return 0
    fi

    log_start "Shodan Reconnaissance"

    local api="https://api.shodan.io"

    # ── 1. Domain search — find IPs, ports, and services ──
    log_info "Shodan: searching domain $domain..."
    curl -s "${api}/dns/domain/${domain}?key=${SHODAN_API_KEY}" 2>/dev/null \
        > "$SHODAN_DIR/domain-info.json" || true

    if cmd_exists "jq" && [[ -s "$SHODAN_DIR/domain-info.json" ]]; then
        # Extract subdomains Shodan knows about
        jq -r '.subdomains[]? // empty' "$SHODAN_DIR/domain-info.json" 2>/dev/null \
            | sed "s/$/.${domain}/" \
            | sort -u > "$SHODAN_DIR/shodan-subdomains.txt" || true

        local shodan_subs
        shodan_subs=$(safe_wc "$SHODAN_DIR/shodan-subdomains.txt")
        if [[ "$shodan_subs" -gt 0 ]]; then
            log_info "Shodan found $shodan_subs subdomains — merging into main list."
            cat "$SHODAN_DIR/shodan-subdomains.txt" >> "$SUBS/subdomains"
            sort -u -o "$SUBS/subdomains" "$SUBS/subdomains"
        fi
    fi

    # ── 2. Host lookup — enumerate each discovered IP ──
    if [[ -s "$IPS/${domain}-ips.txt" ]]; then
        log_info "Shodan: looking up $(safe_wc "$IPS/${domain}-ips.txt") IPs..."

        # Cap at 30 IPs to stay within API rate limits
        head -30 "$IPS/${domain}-ips.txt" | while IFS= read -r ip; do
            local host_data
            host_data=$(curl -s "${api}/shodan/host/${ip}?key=${SHODAN_API_KEY}" 2>/dev/null || true)
            [[ -z "$host_data" ]] && continue

            echo "$host_data" >> "$SHODAN_DIR/hosts-raw.json"

            if cmd_exists "jq"; then
                local org ports vulns hostnames
                org=$(echo "$host_data" | jq -r '.org // "N/A"' 2>/dev/null)
                ports=$(echo "$host_data" | jq -r '[.ports[]?] | join(",")' 2>/dev/null)
                vulns=$(echo "$host_data" | jq -r '[.vulns[]?] | join(",")' 2>/dev/null)
                hostnames=$(echo "$host_data" | jq -r '[.hostnames[]?] | join(",")' 2>/dev/null)

                echo "${ip} | Org: ${org} | Ports: ${ports} | Vulns: ${vulns} | Hosts: ${hostnames}" \
                    >> "$SHODAN_DIR/shodan-summary.txt"

                # Extract open ports for port scanning enrichment
                if [[ -n "$ports" ]] && [[ "$ports" != "null" ]]; then
                    echo "$ports" | tr ',' '\n' | while read -r port; do
                        echo "${ip}:${port}" >> "$SHODAN_DIR/shodan-open-ports.txt"
                    done
                fi

                # Extract CVEs
                if [[ -n "$vulns" ]] && [[ "$vulns" != "null" ]] && [[ "$vulns" != "" ]]; then
                    echo "${ip}: ${vulns}" >> "$SHODAN_DIR/shodan-cves.txt"
                fi

                # Extract technology/banner info
                echo "$host_data" | jq -r '.data[]? | "\(.port)/\(.transport // "tcp") — \(.product // "unknown") \(.version // "") [\(.http.title // "")] "' 2>/dev/null \
                    | sed "s/^/${ip} → /" >> "$SHODAN_DIR/shodan-services.txt" || true
            fi

            # Rate limit: Shodan free tier = 1 req/sec
            sleep 1.2
        done

        # Deduplicate
        [[ -f "$SHODAN_DIR/shodan-open-ports.txt" ]] && sort -u -o "$SHODAN_DIR/shodan-open-ports.txt" "$SHODAN_DIR/shodan-open-ports.txt"
        [[ -f "$SHODAN_DIR/shodan-cves.txt" ]] && sort -u -o "$SHODAN_DIR/shodan-cves.txt" "$SHODAN_DIR/shodan-cves.txt"
    fi

    # ── 3. Search query — broader org/network exposure ──
    log_info "Shodan: searching for org-level exposure..."
    local org_keyword
    org_keyword=$(echo "$domain" | sed 's/\..*//')

    curl -s "${api}/shodan/host/search?key=${SHODAN_API_KEY}&query=hostname:${domain}" 2>/dev/null \
        > "$SHODAN_DIR/search-hostname.json" || true

    curl -s "${api}/shodan/host/search?key=${SHODAN_API_KEY}&query=org:${org_keyword}" 2>/dev/null \
        > "$SHODAN_DIR/search-org.json" || true

    if cmd_exists "jq"; then
        # Count total results
        local hostname_total org_total
        hostname_total=$(jq -r '.total // 0' "$SHODAN_DIR/search-hostname.json" 2>/dev/null || echo 0)
        org_total=$(jq -r '.total // 0' "$SHODAN_DIR/search-org.json" 2>/dev/null || echo 0)
        log_info "Shodan exposure: ${hostname_total} results for hostname, ${org_total} for org."

        # Extract IPs from search to merge with our IP list
        for f in "$SHODAN_DIR/search-hostname.json" "$SHODAN_DIR/search-org.json"; do
            jq -r '.matches[]?.ip_str // empty' "$f" 2>/dev/null \
                >> "$SHODAN_DIR/shodan-extra-ips.txt" || true
        done
        [[ -f "$SHODAN_DIR/shodan-extra-ips.txt" ]] && sort -u -o "$SHODAN_DIR/shodan-extra-ips.txt" "$SHODAN_DIR/shodan-extra-ips.txt"
    fi

    # ── Generate Shodan report ──
    {
        echo "═══════════════════════════════════════════"
        echo "Shodan Report — $domain"
        echo "Generated: $(date -u '+%Y-%m-%d %H:%M UTC')"
        echo "═══════════════════════════════════════════"
        echo ""
        if [[ -s "$SHODAN_DIR/shodan-summary.txt" ]]; then
            echo "── Host Summary ──"
            cat "$SHODAN_DIR/shodan-summary.txt"
            echo ""
        fi
        if [[ -s "$SHODAN_DIR/shodan-cves.txt" ]]; then
            echo "── Known CVEs ──"
            cat "$SHODAN_DIR/shodan-cves.txt"
            echo ""
        fi
        if [[ -s "$SHODAN_DIR/shodan-services.txt" ]]; then
            echo "── Services & Banners ──"
            head -100 "$SHODAN_DIR/shodan-services.txt"
            echo ""
        fi
        if [[ -s "$SHODAN_DIR/shodan-open-ports.txt" ]]; then
            echo "── Open Ports ──"
            cat "$SHODAN_DIR/shodan-open-ports.txt"
            echo ""
        fi
    } > "$SHODAN_DIR/shodan-report.txt"

    # Notify
    local cve_count
    cve_count=$(safe_wc "$SHODAN_DIR/shodan-cves.txt")
    local port_count
    port_count=$(safe_wc "$SHODAN_DIR/shodan-open-ports.txt")

    if [[ "$cve_count" -gt 0 ]]; then
        send_notify "Shodan: ${cve_count} CVEs found across target IPs for ${domain}!" "critical"
    fi
    send_notify "Shodan: ${port_count} open ports, $(safe_wc "$SHODAN_DIR/shodan-summary.txt") hosts profiled for ${domain}" "info"

    log_info "Shodan recon complete. Report: $SHODAN_DIR/shodan-report.txt"
}

# ════════════════════════════════════════════════════════════════════════════
# PHASE 2: RECONNAISSANCE
# ════════════════════════════════════════════════════════════════════════════

# ── NEW: wafw00f — WAF Detection (full + aggressive) ──────────────────────
detectWAF() {
    is_active || return 0
    check_and_warn "wafw00f" || return 0
    [[ -s "$SUBS/hosts" ]] || return 0

    log_start "WAF Detection (wafw00f)"
    while IFS= read -r host; do
        wafw00f "$host" -a 2>/dev/null
    done < "$SUBS/hosts" | tee "$RESULTDIR/waf-results.txt"

    if grep -qi "is behind" "$RESULTDIR/waf-results.txt" 2>/dev/null; then
        send_notify "[0xMasterRecon] $domain — WAFs detected!"
    fi
    log_info "WAF detection done."
}

# ── NEW: WhatWeb / CMSeeK — CMS Detection (all modes) ─────────────────────
detectCMS() {
    log_start "CMS & Tech Detection"

    local target_list="$SUBS/hosts"
    if [[ ! -s "$target_list" ]]; then
        echo "http://${domain}" > "$RESULTDIR/cms-targets.txt"
        target_list="$RESULTDIR/cms-targets.txt"
    fi

    if cmd_exists "whatweb"; then
        local agg=1; is_aggressive && agg=3
        while IFS= read -r host; do
            whatweb -a "$agg" "$host" --colour=never 2>/dev/null
        done < "$target_list" | tee "$RESULTDIR/whatweb-results.txt"
    fi

    if is_active; then
        if cmd_exists "cmseek"; then
            while IFS= read -r host; do
                cmseek -u "$host" --batch --random-agent 2>/dev/null || true
            done < "$target_list"
        elif [[ -f "$HOMEDIR/tools/CMSeeK/cmseek.py" ]]; then
            while IFS= read -r host; do
                python3 "$HOMEDIR/tools/CMSeeK/cmseek.py" -u "$host" --batch --random-agent 2>/dev/null || true
            done < "$target_list"
        fi
    fi
    log_info "CMS detection done."
}

gatherScreenshots() {
    is_active || return 0
    [[ -s "$SUBS/hosts" ]] || return 0
    log_start "Screenshots"
    if cmd_exists "gowitness"; then
        gowitness file -f "$SUBS/hosts" --screenshot-path "$SCREENSHOTS" --timeout 15 2>/dev/null || true
    elif cmd_exists "aquatone"; then
        cat "$SUBS/hosts" | aquatone -http-timeout 10000 -out "$SCREENSHOTS" 2>/dev/null || true
    fi
    log_info "Screenshots done."
}

fetchArchive() {
    log_start "URL Archive Gathering"
    if cmd_exists "gau"; then
        if [[ -s "$SUBS/hosts" ]]; then
            cat "$SUBS/hosts" | sed 's|https\?://||' | sort -u | gau --threads 50 > "$ARCHIVE/getallurls.txt" 2>/dev/null || true
        else
            echo "$domain" | gau --threads 50 > "$ARCHIVE/getallurls.txt" 2>/dev/null || true
        fi
    elif cmd_exists "waybackurls"; then
        if [[ -s "$SUBS/hosts" ]]; then
            cat "$SUBS/hosts" | sed 's|https\?://||' | sort -u | waybackurls > "$ARCHIVE/getallurls.txt" 2>/dev/null || true
        else
            echo "$domain" | waybackurls > "$ARCHIVE/getallurls.txt" 2>/dev/null || true
        fi
    else
        touch "$ARCHIVE/getallurls.txt"
    fi
    log_info "Archived URLs: $(safe_wc "$ARCHIVE/getallurls.txt")"

    cmd_exists "unfurl" && sort -u "$ARCHIVE/getallurls.txt" | unfurl --unique keys > "$ARCHIVE/paramlist.txt" 2>/dev/null || true

    if [[ -s "$ARCHIVE/getallurls.txt" ]]; then
        for ext in js php aspx jsp; do
            sort -u "$ARCHIVE/getallurls.txt" | grep -iP "\w+\.${ext}(\?|$)" | sort -u > "$ARCHIVE/${ext}urls.txt" 2>/dev/null || true
        done
        if [[ "$HAS_PD_HTTPX" == true ]] && is_active; then
            for ext in js php aspx jsp; do
                [[ -s "$ARCHIVE/${ext}urls.txt" ]] && run_pd_httpx -l "$ARCHIVE/${ext}urls.txt" -silent -mc 200 -threads 100 \
                    -o "$ARCHIVE/${ext}urls-live.txt" 2>/dev/null || true
            done
        fi
    fi
}

# ── NEW: SecretFinder — JS Secret Extraction (all modes) ──────────────────
extractSecrets() {
    log_start "JS Secret Extraction"
    local js_source="$ARCHIVE/jsurls-live.txt"
    [[ ! -s "$js_source" ]] && js_source="$ARCHIVE/jsurls.txt"
    [[ ! -s "$js_source" ]] && { log_info "No JS files — skipping."; return; }

    if [[ -f "$HOMEDIR/tools/SecretFinder/SecretFinder.py" ]]; then
        log_info "Running SecretFinder on $(safe_wc "$js_source") JS files..."
        while IFS= read -r js_url; do
            python3 "$HOMEDIR/tools/SecretFinder/SecretFinder.py" -i "$js_url" -o cli 2>/dev/null
        done < "$js_source" | sort -u > "$SECRETS/secretfinder-results.txt" || true
        local sc; sc=$(safe_wc "$SECRETS/secretfinder-results.txt")
        [[ "$sc" -gt 0 ]] && send_notify "[0xMasterRecon] $domain — $sc JS secrets found!"
    fi

    cmd_exists "mantra" && mantra -f "$js_source" -o "$SECRETS/mantra-results.txt" 2>/dev/null || true

    if [[ -f "$HOMEDIR/tools/LinkFinder/linkfinder.py" ]]; then
        while IFS= read -r js_url; do
            python3 "$HOMEDIR/tools/LinkFinder/linkfinder.py" -i "$js_url" -o cli 2>/dev/null
        done < "$js_source" | sort -u > "$SECRETS/linkfinder-endpoints.txt" || true
    fi
    log_info "Secret extraction done."
}

# ── NEW: truffleHog / gitleaks — GitHub Secrets (all modes) ───────────────
scanGitHubSecrets() {
    log_start "GitHub Secret Scanning"
    local org; org=$(echo "$domain" | sed 's/\..*//')

    if cmd_exists "trufflehog"; then
        log_info "truffleHog scanning org: $org..."
        trufflehog github --org="$org" --only-verified --json \
            > "$SECRETS/trufflehog-results.json" 2>/dev/null || true
        local tc; tc=$(safe_wc "$SECRETS/trufflehog-results.json")
        [[ "$tc" -gt 0 ]] && send_notify "[0xMasterRecon] $domain — $tc VERIFIED GitHub secrets!"
    fi

    if cmd_exists "gitleaks"; then
        gitleaks detect --source "https://github.com/${org}" \
            --report-format json --report-path "$SECRETS/gitleaks-results.json" \
            --no-git 2>/dev/null || true
    fi

    cmd_exists "trufflehog" || cmd_exists "gitleaks" || log_warn "No GitHub scanning tools found."
}

# ── NEW: cloud_enum / S3Scanner — Cloud Buckets (all modes) ───────────────
enumCloud() {
    log_start "Cloud Bucket Enumeration"
    local kw; kw=$(echo "$domain" | sed 's/\..*//')

    if cmd_exists "cloud_enum"; then
        cloud_enum -k "$kw" -l "$CLOUD/cloud_enum_results.txt" 2>/dev/null || true
    elif [[ -f "$HOMEDIR/tools/cloud_enum/cloud_enum.py" ]]; then
        python3 "$HOMEDIR/tools/cloud_enum/cloud_enum.py" -k "$kw" -l "$CLOUD/cloud_enum_results.txt" 2>/dev/null || true
    fi

    if cmd_exists "s3scanner"; then
        printf '%s\n' "$kw" "${kw}-dev" "${kw}-staging" "${kw}-prod" "${kw}-backup" \
            "${kw}-assets" "${kw}-data" "${kw}-internal" "${kw}-private" > "$CLOUD/bucket-names.txt"
        s3scanner scan -f "$CLOUD/bucket-names.txt" -o "$CLOUD/s3scanner-results.txt" 2>/dev/null || true
    fi

    [[ -s "$CLOUD/cloud_enum_results.txt" ]] && send_notify "[0xMasterRecon] $domain — Cloud buckets found!"
    log_info "Cloud enumeration done."
}

# ── NEW: socialhunter — Broken Social Links (all modes) ───────────────────
checkSocialHunter() {
    check_and_warn "socialhunter" || return 0
    log_start "Broken Social Link Detection"
    if [[ -s "$SUBS/hosts" ]]; then
        cat "$SUBS/hosts" | socialhunter -o "$RESULTDIR/socialhunter-results.txt" 2>/dev/null || true
    else
        echo "http://${domain}" | socialhunter -o "$RESULTDIR/socialhunter-results.txt" 2>/dev/null || true
    fi
    [[ -s "$RESULTDIR/socialhunter-results.txt" ]] && send_notify "[0xMasterRecon] $domain — Broken social links!"
    log_info "Social hunter done."
}

# ════════════════════════════════════════════════════════════════════════════
# PHASE 3: ACTIVE SCANNING
# ════════════════════════════════════════════════════════════════════════════

# ── NEW: Interactsh — OOB Callback (full + aggressive) ───────────────────
startInteractsh() {
    is_active || return 0
    if ! cmd_exists "interactsh-client"; then
        INTERACTSH_URL="http://BURP_COLLABORATOR_PLACEHOLDER.com"
        return
    fi

    log_start "Interactsh OOB Server"
    local interactsh_log="$RESULTDIR/interactsh.log"
    interactsh-client -v 2>&1 | tee "$interactsh_log" &
    INTERACTSH_PID=$!

    local counter=0
    while [[ $counter -lt 10 ]]; do
        INTERACTSH_URL=$(grep -oP '[a-z0-9]+\.oast\.\w+' "$interactsh_log" 2>/dev/null | head -1 || true)
        [[ -n "$INTERACTSH_URL" ]] && { INTERACTSH_URL="http://${INTERACTSH_URL}"; break; }
        sleep 1; ((counter++))
    done

    if [[ -n "$INTERACTSH_URL" ]]; then
        log_info "Interactsh URL: ${GREEN}${INTERACTSH_URL}${RESET}"
    else
        INTERACTSH_URL="http://BURP_COLLABORATOR_PLACEHOLDER.com"
        kill "$INTERACTSH_PID" 2>/dev/null || true; INTERACTSH_PID=""
    fi
}

stopInteractsh() {
    [[ -n "${INTERACTSH_PID:-}" ]] || return 0
    kill "$INTERACTSH_PID" 2>/dev/null || true
    wait "$INTERACTSH_PID" 2>/dev/null || true
    local ic; ic=$(grep -c "interaction" "$RESULTDIR/interactsh.log" 2>/dev/null || echo 0)
    [[ "$ic" -gt 0 ]] && {
        log_info "${RED}${BOLD}$ic OOB interactions detected!${RESET}"
        send_notify "[0xMasterRecon] $domain — $ic OOB interactions!"
    }
}

startSpidering() {
    is_active || return 0
    log_start "Spidering & Crawling"

    # ParamSpider
    if cmd_exists "paramspider"; then
        paramspider -d "$domain" -o "$SPIDERING/paramspider_raw.txt" 2>/dev/null || true
        [[ -f "output/${domain}.txt" ]] && mv "output/${domain}.txt" "$SPIDERING/paramspider.txt" 2>/dev/null || true
        [[ -f "$SPIDERING/paramspider_raw.txt" ]] && mv "$SPIDERING/paramspider_raw.txt" "$SPIDERING/paramspider.txt" 2>/dev/null || true
    elif [[ -f "$HOMEDIR/tools/ParamSpider/paramspider.py" ]]; then
        python3 "$HOMEDIR/tools/ParamSpider/paramspider.py" --domain "$domain" \
            --exclude woff,css,js,png,svg,jpg --level high \
            --output "$SPIDERING/paramspider.txt" 2>/dev/null || true
    fi
    touch "$SPIDERING/paramspider.txt"

    # Katana
    touch "$SPIDERING/katana.txt"
    if cmd_exists "katana"; then
        if [[ -s "$SUBS/hosts" ]]; then
            katana -list "$SUBS/hosts" -d 3 -jc -timeout 15 -o "$SPIDERING/katana.txt" 2>/dev/null || true
        else
            katana -u "http://${domain}" -d 3 -jc -timeout 15 -o "$SPIDERING/katana.txt" 2>/dev/null || true
        fi
    fi

    # Hakrawler
    touch "$SPIDERING/hakrawler.txt"
    cmd_exists "hakrawler" && [[ -s "$SUBS/hosts" ]] && \
        cat "$SUBS/hosts" | hakrawler -d 3 -t 10 > "$SPIDERING/hakrawler.txt" 2>/dev/null || true

    cat "$SPIDERING"/*.txt 2>/dev/null | grep -vE '^$|^#' | sort -u > "$SPIDERING/spidering-all.txt" || true
    log_info "Spidered URLs: $(safe_wc "$SPIDERING/spidering-all.txt")"

    if [[ "$HAS_PD_HTTPX" == true ]] && [[ -s "$SPIDERING/spidering-all.txt" ]]; then
        run_pd_httpx -l "$SPIDERING/spidering-all.txt" -silent -mc 200 -threads 100 \
            -o "$SPIDERING/sorted-spidering.txt" 2>/dev/null || true
    else
        cp "$SPIDERING/spidering-all.txt" "$SPIDERING/sorted-spidering.txt" 2>/dev/null || true
    fi
    touch "$SPIDERING/sorted-spidering.txt"
}

# ── NEW: ffuf — Directory Fuzzing (full + aggressive) ─────────────────────
runFfuf() {
    is_active || return 0
    check_and_warn "ffuf" || return 0
    [[ -s "$SUBS/hosts" ]] || return 0

    log_start "Directory Fuzzing (ffuf)"

    local dir_wl="$WORDLIST/raft-medium-directories.txt"
    if [[ ! -f "$dir_wl" ]]; then
        local sl="$HOMEDIR/tools/SecLists/Discovery/Web-Content/raft-medium-directories.txt"
        if [[ -f "$sl" ]]; then ln -sf "$sl" "$dir_wl"
        else wget -q "https://raw.githubusercontent.com/danielmiessler/SecLists/master/Discovery/Web-Content/raft-medium-directories.txt" \
            -O "$dir_wl" 2>/dev/null || true; fi
    fi
    [[ ! -s "$dir_wl" ]] && { log_warn "No wordlist — skipping ffuf."; return; }

    local threads=50 recursion_args=""
    is_aggressive && { threads=100; recursion_args="-recursion -recursion-depth 2"; }

    local max_hosts=10; is_aggressive && max_hosts=50

    head -"$max_hosts" "$SUBS/hosts" | while IFS= read -r host; do
        local safe_host; safe_host=$(echo "$host" | sed 's|https\?://||;s|/|_|g;s|:|-|g')
        log_info "ffuf → $host"
        ffuf -u "${host}/FUZZ" -w "$dir_wl" -mc 200,201,301,302,403 -fc 404 \
            -t "$threads" -timeout 10 $recursion_args \
            -o "$DIRSCAN/ffuf-${safe_host}.json" -of json -sf 2>/dev/null || true
    done

    local total=0
    for f in "$DIRSCAN"/ffuf-*.json; do
        [[ -f "$f" ]] || continue
        total=$((total + $(grep -c '"status"' "$f" 2>/dev/null || echo 0)))
    done
    log_info "ffuf: $total total paths."
    [[ "$total" -gt 0 ]] && send_notify "[0xMasterRecon] $domain — ffuf: $total paths"
}

# ── NEW: kiterunner — API Discovery (full + aggressive) ──────────────────
runKiterunner() {
    is_active || return 0
    cmd_exists "kr" || { log_warn "kiterunner (kr) not found — skipping."; return; }
    [[ -s "$SUBS/hosts" ]] || return 0

    log_start "API Discovery (kiterunner)"
    local api_wl=""
    for p in "$HOMEDIR/tools/kiterunner/routes-large.kite" "/opt/kiterunner/routes-large.kite" "$WORDLIST/routes-large.kite"; do
        [[ -f "$p" ]] && { api_wl="$p"; break; }
    done

    local max_hosts=5; is_aggressive && max_hosts=20

    head -"$max_hosts" "$SUBS/hosts" | while IFS= read -r host; do
        log_info "kiterunner → $host"
        if [[ -n "$api_wl" ]]; then
            kr scan "$host" -w "$api_wl" --fail-status-codes 400,404,500 -o json \
                >> "$APIRECON/kiterunner-results.json" 2>/dev/null || true
        else
            kr brute "$host" --fail-status-codes 400,404,500 \
                >> "$APIRECON/kiterunner-brute.txt" 2>/dev/null || true
        fi
    done
    log_info "API discovery done."
}

startMeg() {
    is_active || return 0
    cmd_exists "meg" || return 0
    log_start "meg"
    cd "$SUBS/" || return
    meg -d 1000 -v / 2>/dev/null || true
    cd "$HOMEDIR" || return
}

# ════════════════════════════════════════════════════════════════════════════
# PHASE 4: VULNERABILITY DETECTION
# ════════════════════════════════════════════════════════════════════════════

checkSSRF() {
    is_active || return 0
    log_start "SSRF Detection"
    local collab="${INTERACTSH_URL:-http://BURP_COLLABORATOR_PLACEHOLDER.com}"

    cmd_exists "qsreplace" && [[ -s "$ARCHIVE/getallurls.txt" ]] && \
        cat "$ARCHIVE/getallurls.txt" | grep "=" | qsreplace "$collab" | sort -u > "$GFSCAN/SSRF-scan.txt" 2>/dev/null || true

    cmd_exists "gf" && cmd_exists "qsreplace" && [[ -s "$SPIDERING/paramspider.txt" ]] && \
        cat "$SPIDERING/paramspider.txt" | gf ssrf 2>/dev/null | qsreplace "$collab" | sort -u > "$SPIDERING/ssrf-spidering.txt" 2>/dev/null || true

    log_info "SSRF candidates saved (callback: $collab)."
}

checkXSS() {
    is_active || return 0
    log_start "XSS Detection"
    dedup_urls() { if cmd_exists "uro"; then uro; else sort -u; fi; }

    if cmd_exists "gf" && cmd_exists "qsreplace"; then
        for src in "$ARCHIVE/getallurls.txt" "$SPIDERING/sorted-spidering.txt"; do
            [[ -s "$src" ]] || continue
            local base; base=$(basename "$src" .txt)
            cat "$src" | gf xss 2>/dev/null | dedup_urls | qsreplace '"><svg onload=confirm(1)>' \
                > "$GFSCAN/xss-candidates-${base}.txt" 2>/dev/null || true

            cmd_exists "airixss" && [[ -s "$GFSCAN/xss-candidates-${base}.txt" ]] && \
                cat "$GFSCAN/xss-candidates-${base}.txt" | airixss -payload "confirm(1)" \
                >> "$GFSCAN/xss-vulnerable.txt" 2>/dev/null || true
        done
    fi

    if [[ -f "$HOMEDIR/tools/XSStrike/xsstrike.py" ]]; then
        pip3 install fuzzywuzzy python-Levenshtein --break-system-packages --quiet 2>/dev/null || true
        local xi; xi=$(find "$GFSCAN" -name "xss-candidates-*" -size +0 2>/dev/null | head -1 || true)
        [[ -s "${xi:-/dev/null}" ]] && python3 "$HOMEDIR/tools/XSStrike/xsstrike.py" --seeds "$xi" --blind 2>/dev/null \
            | tee "$GFSCAN/xss-strike-output.txt" || true
    fi

    [[ -s "$GFSCAN/xss-vulnerable.txt" ]] && send_notify "[0xMasterRecon] $domain — XSS hits: $(safe_wc "$GFSCAN/xss-vulnerable.txt")" "critical"
    log_info "XSS detection complete."
}

checkOpenRedirect() {
    is_active || return 0
    log_start "Open Redirect Detection"
    if cmd_exists "gf" && cmd_exists "qsreplace"; then
        for src in "$ARCHIVE/getallurls.txt" "$SPIDERING/sorted-spidering.txt"; do
            [[ -s "$src" ]] || continue
            cat "$src" | gf redirect 2>/dev/null | sort -u | qsreplace 'https://evil.com' \
                >> "$GFSCAN/openredirect-all.txt" 2>/dev/null || true
        done
        [[ "$HAS_PD_HTTPX" == true ]] && [[ -s "$GFSCAN/openredirect-all.txt" ]] && \
            run_pd_httpx -l "$GFSCAN/openredirect-all.txt" -silent -mc 301,302 \
            >> "$GFSCAN/redirected-confirmed.txt" 2>/dev/null || true
    fi
    log_info "Open Redirect done."
}

checkSQLInjection() {
    is_active || return 0
    cmd_exists "sqlmap" || return 0
    log_start "SQLi Detection"

    local raw="$SPIDERING/sqli-raw.txt"; touch "$raw"
    cmd_exists "gf" && {
        [[ -s "$SPIDERING/paramspider.txt" ]] && cat "$SPIDERING/paramspider.txt" | gf sqli 2>/dev/null >> "$raw" || true
        [[ -s "$ARCHIVE/getallurls.txt" ]] && cat "$ARCHIVE/getallurls.txt" | gf sqli 2>/dev/null >> "$raw" || true
    }

    if [[ -s "$raw" ]]; then
        cat "$raw" | grep -v '??' \
            | grep -vi 'UNION\|SELECT\|CONCAT\|CHAR(\|SLEEP(\|EXTRACTVALUE\|UPDATEXML\|information_schema\|GTID_SUBSET\|JSON_KEYS\|ELT(' \
            | grep -v 'FUZZ' | grep -v '<script\|<svg\|<img\|onerror=\|onload=' \
            | grep -v "base64," | grep -v 'wget\|DROP\+TABLE' \
            | grep -E '^https?://' | sort -u > "$SPIDERING/sqli-spidering.txt"
    else
        touch "$SPIDERING/sqli-spidering.txt"
    fi

    local sc; sc=$(safe_wc "$SPIDERING/sqli-spidering.txt")
    if [[ "$sc" -gt 0 ]]; then
        local max=50 level=2; is_aggressive && { max=200; level=5; }
        [[ "$sc" -gt "$max" ]] && head -"$max" "$SPIDERING/sqli-spidering.txt" > "$SPIDERING/sqli-capped.txt" \
            || cp "$SPIDERING/sqli-spidering.txt" "$SPIDERING/sqli-capped.txt"

        log_info "Testing $(safe_wc "$SPIDERING/sqli-capped.txt") SQLi endpoints (level $level)..."
        sqlmap -m "$SPIDERING/sqli-capped.txt" --batch --banner --dbs --fresh-queries \
            --random-agent --level "$level" --timeout 30 --retries 1 --threads 5 \
            --output-dir "$SPIDERING/sqlmap-results" 2>&1 | tee "$SPIDERING/sqlmap-output.txt" || true
        rm -f "$raw" "$SPIDERING/sqli-capped.txt" 2>/dev/null
    fi
    log_info "SQLi done."
}

startGfScan() {
    cmd_exists "gf" || return 0
    log_start "GF Patterns"
    if [[ -s "$ARCHIVE/getallurls.txt" ]]; then
        for p in $(gf -list 2>/dev/null); do
            cat "$ARCHIVE/getallurls.txt" | gf "$p" 2>/dev/null >> "$GFSCAN/${p}.txt" || true
        done
    fi
}

runNuclei() {
    is_active || return 0
    cmd_exists "nuclei" || return 0
    [[ -s "$SUBS/hosts" ]] || return 0
    log_start "Nuclei Scan"

    local nt="$HOMEDIR/tools/nuclei-templates"
    [[ ! -d "$nt" ]] && nt="$HOMEDIR/nuclei-templates"
    nuclei -update-templates 2>/dev/null || true

    local args=(-l "$SUBS/hosts" -c 100 -timeout 10 -retries 2)
    is_aggressive && [[ "${INTERACTSH_URL:-}" != *"PLACEHOLDER"* ]] && args+=(-iserver "$INTERACTSH_URL")

    local -A scans=(
        ["cves"]="http/cves/" ["exposures"]="http/exposures/"
        ["misconfiguration"]="http/misconfiguration/" ["technologies"]="http/technologies/"
        ["takeovers"]="http/takeovers/" ["default-logins"]="default-logins/"
        ["panels"]="http/exposed-panels/" ["vulnerabilities"]="http/vulnerabilities/" ["ssl"]="ssl/"
    )
    for name in "${!scans[@]}"; do
        [[ -d "${nt}/${scans[$name]}" ]] || continue
        nuclei "${args[@]}" -t "${nt}/${scans[$name]}" -o "$NUCLEISCAN/${name}.txt" 2>/dev/null || true
        [[ -s "$NUCLEISCAN/${name}.txt" ]] && send_notify "[0xMasterRecon] Nuclei $name: $(safe_wc "$NUCLEISCAN/${name}.txt") hits"
    done
}

portScan() {
    is_aggressive || return 0
    cmd_exists "naabu" || return 0
    log_start "Port Scan (naabu)"
    naabu -list "$SUBS/alive_subdomains" -p 80,443,8080,8443,7001,3000,5000,9090,8888,8000,4443 \
        -exclude-cdn -o "$PORTSCAN/ports.txt" 2>/dev/null || true
    log_info "Ports: $(safe_wc "$PORTSCAN/ports.txt")"
    send_notify "[0xMasterRecon] $domain — $(safe_wc "$PORTSCAN/ports.txt") open ports"
}

# ════════════════════════════════════════════════════════════════════════════
# PHASE 5: REPORT
# ════════════════════════════════════════════════════════════════════════════

makePage() {
    log_start "Generating Report"
    cat > "$HTML/report.html" <<HTMLEOF
<!DOCTYPE html>
<html><head><title>0xMasterRecon — $domain</title>
<style>
*{box-sizing:border-box}body{font-family:'Courier New',monospace;background:#0a0a1a;color:#c0c0d0;padding:2em;max-width:1200px;margin:0 auto}
h1{color:#00d4ff}h2{color:#ff4d6d;border-bottom:1px solid #2a2a4a;padding-bottom:.3em;margin-top:2em}
pre{background:#12122a;padding:1em;border-radius:6px;overflow-x:auto;font-size:.85em;border:1px solid #2a2a4a}
.stats{display:flex;flex-wrap:wrap;gap:.5em;margin:1em 0}.stat{background:#1a1a3a;padding:.7em 1.2em;border-radius:6px;border:1px solid #2a2a5a}
.stat b{color:#00d4ff}.mode{background:#ff4d6d;color:#fff;padding:.2em .8em;border-radius:12px;font-weight:bold}
</style></head><body>
<h1>0xMasterRecon v${VERSION} — ${domain}</h1>
<p>$(date -u '+%Y-%m-%d %H:%M UTC') | Mode: <span class="mode">${MODE}</span></p>
<div class="stats">
<div class="stat"><b>$(safe_wc "$SUBS/subdomains")</b> subs</div>
<div class="stat"><b>$(safe_wc "$SUBS/hosts")</b> hosts</div>
<div class="stat"><b>$(safe_wc "$IPS/${domain}-ips.txt")</b> IPs</div>
<div class="stat"><b>$(safe_wc "$ARCHIVE/getallurls.txt")</b> URLs</div>
<div class="stat"><b>$(safe_wc "$SPIDERING/spidering-all.txt")</b> spidered</div>
</div>
<h2>Hosts</h2><pre>$(cat "$SUBS/hosts" 2>/dev/null || echo "None")</pre>
<h2>WAF</h2><pre>$(head -20 "$RESULTDIR/waf-results.txt" 2>/dev/null || echo "N/A")</pre>
<h2>JS Secrets</h2><pre>$(head -30 "$SECRETS/secretfinder-results.txt" 2>/dev/null || echo "None")</pre>
<h2>GitHub Secrets</h2><pre>$(head -20 "$SECRETS/trufflehog-results.json" 2>/dev/null || echo "None")</pre>
<h2>Cloud</h2><pre>$(head -20 "$CLOUD/cloud_enum_results.txt" 2>/dev/null || echo "None")</pre>
<h2>SSRF</h2><pre>$(head -20 "$GFSCAN/SSRF-scan.txt" 2>/dev/null || echo "None")</pre>
<h2>XSS</h2><pre>$(head -20 "$GFSCAN/xss-vulnerable.txt" 2>/dev/null || echo "None")</pre>
<h2>SQLi</h2><pre>$(head -20 "$SPIDERING/sqli-spidering.txt" 2>/dev/null || echo "None")</pre>
<h2>Social</h2><pre>$(cat "$RESULTDIR/socialhunter-results.txt" 2>/dev/null || echo "None")</pre>
<h2>CIDR / ASN</h2><pre>$(cat "$CIDR_ASN/cidr-asn-report.txt" 2>/dev/null || echo "Not scanned")</pre>
<h2>Shodan Intelligence</h2><pre>$(cat "$SHODAN_DIR/shodan-report.txt" 2>/dev/null || echo "No API key configured")</pre>
</body></html>
HTMLEOF
    log_info "Report: $HTML/report.html"
    if [[ -d /var/www/html ]]; then
        sudo mkdir -p "/var/www/html/$domain" 2>/dev/null || true
        sudo cp "$HTML/report.html" "/var/www/html/$domain/" 2>/dev/null || true
    fi
}

printSummary() {
    echo ""
    echo -e "${BOLD}═══════════════════════════════════════════════════════════════${RESET}"
    echo -e "${GREEN} 0xMasterRecon v${VERSION} — SCAN COMPLETE${RESET}"
    echo -e "${BOLD}═══════════════════════════════════════════════════════════════${RESET}"
    local discord_status="${DIM}OFF${RESET}"
    [[ -n "$DISCORD_WEBHOOK" ]] && discord_status="${GREEN}ON${RESET}"
    local notify_status="${DIM}OFF${RESET}"
    [[ "$NOTIFY_ENABLED" == true ]] && notify_status="${GREEN}ON${RESET}"
    local shodan_status="${DIM}NO KEY${RESET}"
    [[ -n "$SHODAN_API_KEY" ]] && shodan_status="${GREEN}ACTIVE${RESET}"

    echo -e " Target:   ${CYAN}${domain}${RESET}  |  Mode: ${YELLOW}${MODE}${RESET}"
    echo -e " Discord:  ${discord_status}  |  Notify: ${notify_status}  |  Shodan: ${shodan_status}"
    echo -e "${BOLD}───────────────────────────────────────────────────────────────${RESET}"
    echo -e " Subdomains:  $(safe_wc "$SUBS/subdomains")  |  Live hosts: $(safe_wc "$SUBS/hosts")  |  IPs: $(safe_wc "$IPS/${domain}-ips.txt")"
    echo -e " ASNs:        $(safe_wc "$CIDR_ASN/asns.txt")  |  CIDRs: $(safe_wc "$CIDR_ASN/cidrs.txt")  |  BGP Prefixes: $(safe_wc "$CIDR_ASN/bgp-prefixes.txt")"
    echo -e " Shodan:      $(safe_wc "$SHODAN_DIR/shodan-open-ports.txt") ports  |  $(safe_wc "$SHODAN_DIR/shodan-cves.txt") CVEs  |  $(safe_wc "$SHODAN_DIR/shodan-services.txt") services"
    echo -e " URLs:        $(safe_wc "$ARCHIVE/getallurls.txt") archived  |  $(safe_wc "$SPIDERING/spidering-all.txt") spidered"
    echo -e "${BOLD}───────────────────────────────────────────────────────────────${RESET}"
    echo -e " ${YELLOW}→${RESET} $SHODAN_DIR/       Shodan hosts, ports, CVEs, services"
    echo -e " ${YELLOW}→${RESET} $CIDR_ASN/        ASN, CIDR ranges, BGP prefixes"
    echo -e " ${YELLOW}→${RESET} $GFSCAN/         XSS, SSRF, redirects"
    echo -e " ${YELLOW}→${RESET} $SECRETS/         JS secrets, GitHub leaks"
    echo -e " ${YELLOW}→${RESET} $CLOUD/           Cloud buckets"
    echo -e " ${YELLOW}→${RESET} $DIRSCAN/         ffuf paths"
    echo -e " ${YELLOW}→${RESET} $APIRECON/        API endpoints"
    echo -e " ${YELLOW}→${RESET} $NUCLEISCAN/      Nuclei findings"
    echo -e " ${YELLOW}→${RESET} $HTML/report.html Full report"
    echo -e "${BOLD}═══════════════════════════════════════════════════════════════${RESET}"

    # Final notification
    local summary_msg="Scan complete for ${domain}!
Mode: ${MODE}
Subdomains: $(safe_wc "$SUBS/subdomains") | Hosts: $(safe_wc "$SUBS/hosts") | IPs: $(safe_wc "$IPS/${domain}-ips.txt")
ASNs: $(safe_wc "$CIDR_ASN/asns.txt") | CIDRs: $(safe_wc "$CIDR_ASN/cidrs.txt")
Shodan: $(safe_wc "$SHODAN_DIR/shodan-open-ports.txt") ports, $(safe_wc "$SHODAN_DIR/shodan-cves.txt") CVEs
URLs: $(safe_wc "$ARCHIVE/getallurls.txt") archived | $(safe_wc "$SPIDERING/spidering-all.txt") spidered"

    send_notify "$summary_msg" "info"

    # Upload reports to Discord
    send_discord_file "$HTML/report.html" "Full recon report for $domain (v${VERSION}, mode: ${MODE})"
    send_discord_file "$CIDR_ASN/cidr-asn-report.txt" "CIDR/ASN report for $domain"
    send_discord_file "$SHODAN_DIR/shodan-report.txt" "Shodan intelligence report for $domain"
}

# ============================================================================
# MAIN — Mode-aware pipeline
# ============================================================================
main() {
    parseArguments "$@"
    displayLogo
    echo -e "[${CYAN}▶${RESET}] Mode: ${BOLD}${YELLOW}$MODE${RESET}  |  Discord: $([[ -n "$DISCORD_WEBHOOK" ]] && echo "${GREEN}ON${RESET}" || echo "${DIM}OFF${RESET}")  |  Shodan: $([[ -n "$SHODAN_API_KEY" ]] && echo "${GREEN}ON${RESET}" || echo "${DIM}OFF${RESET}")"
    checkDirectories
    detect_httpx
    fix_python_deps
    gatherResolvers

    # Send scan-start notification
    send_notify "Scan started for ${domain} | Mode: ${MODE}" "info"

    # Phase 1: Discovery
    gatherSubdomains                    # all
    bruteforceSubdomains                # full + aggressive
    resolveSubdomains                   # all
    probeHosts                          # full + aggressive
    gatherIPs                           # all
    enumCIDR_ASN                        # all (CIDR expansion: full+aggressive)
    shodanRecon                         # all (requires API key)

    # Phase 2: Recon
    detectWAF                           # full + aggressive
    detectCMS                           # all
    gatherScreenshots                   # full + aggressive
    fetchArchive                        # all
    extractSecrets                      # all
    scanGitHubSecrets                   # all
    enumCloud                           # all
    checkSocialHunter                   # all

    # Phase 3: Active
    startInteractsh                     # full + aggressive
    startSpidering                      # full + aggressive
    startMeg                            # full + aggressive
    runFfuf                             # full + aggressive
    runKiterunner                       # full + aggressive

    # Phase 4: Vulns
    checkSSRF                           # full + aggressive
    checkXSS                            # full + aggressive
    checkOpenRedirect                   # full + aggressive
    checkSQLInjection                   # full + aggressive
    startGfScan                         # all
    runNuclei                           # full + aggressive
    portScan                            # aggressive only

    # Phase 5: Report
    stopInteractsh
    makePage
    printSummary
}

main "$@"
