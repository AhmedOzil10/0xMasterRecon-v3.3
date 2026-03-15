# 0xMasterRecon-v3.3
All-in-one automated recon framework for bug bounty hunters &amp; red teamers — 40+ tools orchestrated across 5 phases, 3 scan modes (passive/full/aggressive), CIDR/ASN mapping, Shodan intelligence, native Discord alerts, and a single-command workflow. 
# 0xMasterRecon v3.3

**All-in-one automated reconnaissance framework for bug bounty hunting and red team operations.**

```
 _____     ___  ___          _           ______
|  _  |    |  \/  |         | |          | ___ \
| |/' |_  _| .  . | __ _ ___| |_ ___ _ __| |_/ /___  ___ ___  _ __
|  /| \ \/ / |\/| |/ _` / __| __/ _ \ '__|    // _ \/ __/ _ \| '_ \
\ |_/ />  <| |  | | (_| \__ \ ||  __/ |  | |\ \  __/ (_| (_) | | | |
 \___//_/\_\_|  |_/\__,_|___/\__\___|_|  \_| \_\___|\___\___/|_| |_|
```

> Built by [@MrOz1l](https://twitter.com/MrOz1l) — 

---

## Features

| Phase | Modules | Tools |
|-------|---------|-------|
| **Discovery** | Passive subdomain enum | subfinder, assetfinder, amass, findomain, crt.sh, sublert |
| | Active bruteforce | puredns + Assetnote wordlist |
| | DNS resolution | shuffledns, massdns |
| | HTTP probing | ProjectDiscovery httpx, httprobe |
| | CIDR/ASN mapping | asnmap, Team Cymru DNS, RIPEstat API, mapcidr, amass intel |
| | Shodan intelligence | Host lookup, CVE detection, service banners, org search |
| **Recon** | WAF detection | wafw00f |
| | CMS fingerprinting | WhatWeb, CMSeeK |
| | Screenshots | gowitness, aquatone |
| | URL archiving | gau, waybackurls |
| | JS secret extraction | SecretFinder, Mantra, LinkFinder |
| | GitHub secret scanning | truffleHog, gitleaks |
| | Cloud bucket enum | cloud_enum, S3Scanner |
| | Social link hijacking | socialhunter |
| **Active** | OOB callback server | interactsh |
| | Web crawling | katana, hakrawler, ParamSpider |
| | Directory fuzzing | ffuf |
| | API discovery | kiterunner |
| **Vulns** | SSRF detection | gf + qsreplace + interactsh |
| | XSS detection | gf + airixss + XSStrike + findom-xss |
| | Open redirect | gf + qsreplace + httpx verification |
| | SQL injection | gf + sqlmap (sanitized input) |
| | Pattern scanning | gf (all patterns) |
| | Vuln scanning | nuclei (CVEs, misconfigs, exposures, panels, takeovers) |
| | Port scanning | naabu |
| **Report** | HTML report | Auto-generated dark-themed dashboard |
| | Discord alerts | Rich embeds + file uploads |
| | Notifications | ProjectDiscovery notify (Slack/Telegram) |

---

## Installation

```bash
git clone https://github.com/AhmedOzil10/0xMasterRecon.git
cd 0xMasterRecon
chmod +x install.sh recon.sh

# Full install (macOS or Kali Linux)
sudo ./install.sh

# Or just check what's missing
./install.sh --check
```

The installer handles **40+ tools** across both **macOS** (via Homebrew) and **Kali Linux** (via apt/pip/go), including Go installation, GF patterns, nuclei templates, wordlists, and config file templates.

---

## Configuration

Edit the **CONFIG** section at the top of `recon.sh`:

```bash
DISCORD_WEBHOOK="https://discord.com/api/webhooks/YOUR_ID/YOUR_TOKEN"
SHODAN_API_KEY="YOUR_SHODAN_API_KEY"
```

Or pass them via CLI:

```bash
./recon.sh target.com --shodan YOUR_KEY --discord https://discord.com/api/webhooks/...
```

For subfinder API keys (VirusTotal, SecurityTrails, Censys, etc.):
```bash
nano ~/.config/subfinder/provider-config.yaml
```

For ProjectDiscovery notify (Slack/Telegram):
```bash
nano ~/.config/notify/provider-config.yaml
```

---

## Usage

```bash
# Default (--full mode)
./recon.sh target.com

# Passive only — zero active probing
./recon.sh target.com --passive

# Full — passive + active scanning + vuln checks
./recon.sh target.com --full

# Aggressive — full + port scan + deep fuzzing + level 5 sqlmap
./recon.sh target.com --aggressive

# With Discord alerts
./recon.sh target.com --discord https://discord.com/api/webhooks/YOUR/WEBHOOK

# With Shodan enrichment
./recon.sh target.com --shodan YOUR_API_KEY

# Everything combined
./recon.sh target.com --aggressive --shodan KEY --discord URL --notify
```

---

## Scan Modes

| Feature | `--passive` | `--full` | `--aggressive` |
|---------|:-----------:|:--------:|:--------------:|
| Passive subdomain enum | ✅ | ✅ | ✅ |
| puredns bruteforce | ❌ | ✅ | ✅ |
| HTTP probing | ❌ | ✅ | ✅ |
| CIDR/ASN + Shodan | ✅ | ✅ | ✅ |
| WAF detection | ❌ | ✅ | ✅ |
| CMS detection | ✅ (passive) | ✅ | ✅ (deep) |
| JS secrets / GitHub / Cloud | ✅ | ✅ | ✅ |
| Spidering & crawling | ❌ | ✅ | ✅ |
| ffuf dir fuzzing | ❌ | ✅ (10 hosts) | ✅ (50 hosts, recursive) |
| kiterunner API discovery | ❌ | ✅ (5 hosts) | ✅ (20 hosts) |
| XSS / SQLi / SSRF | ❌ | ✅ (level 2) | ✅ (level 5, 200 targets) |
| Nuclei scanning | ❌ | ✅ | ✅ (+interactsh) |
| Port scanning (naabu) | ❌ | ❌ | ✅ |
| interactsh OOB server | ❌ | ✅ | ✅ |

---

## Output Structure

```
~/assets/target.com/
├── subdomains/          # All subdomain lists, alive subs, hosts
├── ips/                 # Resolved IPs, resolvers
├── cidr-asn/            # ASN numbers, CIDR ranges, BGP prefixes, reverse DNS
├── shodan/              # Shodan host data, CVEs, services, open ports
├── screenshots/         # gowitness/aquatone captures
├── archive/             # GAU/waybackurls, JS/PHP/ASPX URLs, paramlist
├── Spidering/           # ParamSpider, katana, hakrawler, SQLi endpoints
├── secrets/             # SecretFinder, LinkFinder, truffleHog, gitleaks
├── cloud/               # cloud_enum, S3Scanner results
├── api/                 # kiterunner API discovery
├── directories/         # ffuf results (JSON per host)
├── gfscan/              # GF pattern matches (XSS, SSRF, redirect, secrets)
├── nucleiscan/          # Nuclei findings by category
├── portscan/            # naabu port scan results
└── html/
    └── report.html      # Full HTML dashboard report
```

---

## Discord Integration

When `--discord` is set, you get:

- **Rich embeds** with color-coded severity (🔵 info, 🟡 warning, 🔴 critical)
- **Timestamps** and target/mode metadata on every alert
- **File uploads** at scan completion: HTML report, CIDR/ASN report, Shodan report
- **Real-time alerts** as findings come in (XSS hits, CVEs, cloud buckets, etc.)

---

## Credits & Acknowledgments

Built on the shoulders of incredible open-source tools by ProjectDiscovery, tomnomnom, hakluke, s0md3v, and many others a big credit for all of them.

---

## Disclaimer

This tool is intended for authorized security testing only. Always obtain written permission before scanning any target. The author assumes no liability for misuse.

## License

MIT License — see [LICENSE](LICENSE)
