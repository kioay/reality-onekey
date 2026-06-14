# Xray REALITY One-Key Setup

One-key server-side installer for Xray VLESS + REALITY + Vision.

This project is designed for a fresh Linux VPS. It installs Xray, generates
REALITY credentials, writes the Xray config, starts `xray.service`, and prints a
client import link.

## Security Notice

The generated VLESS link is a credential. Anyone who has it can use your proxy.

Do not publish:

- `/root/reality-client.txt`
- generated VLESS links
- generated UUIDs
- REALITY private keys
- VPS root passwords
- provider panel screenshots that include passwords

After deploying on a VPS with a temporary root password, rotate the root password
or switch to SSH key login.

## Requirements

- Debian 11/12, Ubuntu 20.04/22.04/24.04, or another systemd-based Linux VPS
- Root or sudo access
- Public IPv4 or IPv6 address
- TCP port open in the provider firewall or security group, default `443`
- A client that supports VLESS + REALITY + Vision

Recommended OS: Debian 12.

## Quick Start

Run directly from GitHub:

```bash
curl -fsSL https://raw.githubusercontent.com/kioay/reality-onekey/main/reality-onekey.sh -o reality-onekey.sh
sudo bash reality-onekey.sh --host <server-ip-or-domain>
```

Or run it in one line:

```bash
curl -fsSL https://raw.githubusercontent.com/kioay/reality-onekey/main/reality-onekey.sh | sudo bash -s -- --host <server-ip-or-domain>
```

Upload the script to your VPS, then run:

```bash
sudo bash reality-onekey.sh --host <server-ip-or-domain>
```

Example:

```bash
sudo bash reality-onekey.sh --host 203.0.113.10
```

Use a custom port or SNI:

```bash
sudo bash reality-onekey.sh --host vpn.example.com --port 8443 --sni www.microsoft.com
```

The script saves client details to:

```text
/root/reality-client.txt
```

Keep this file private.

## Options

```text
--host <ip-or-domain>       Server address used in the client link.
--port <port>               Listen TCP port. Default: 443.
--sni <domain>              REALITY serverName/SNI. Default: www.cloudflare.com.
--dest <host:port>          REALITY target. Default: <sni>:443.
--remark <name>             Client link name. Default: reality.
--uuid <uuid>               Use an existing UUID instead of generating one.
--short-id <hex>            Use an existing REALITY shortId instead of generating one.
--skip-install              Do not run the official Xray installer.
--no-firewall               Do not touch ufw/firewalld.
--force                     Continue even if the listen port appears occupied.
-h, --help                  Show help.
```

## Verify

On the VPS:

```bash
systemctl status xray --no-pager
ss -ltnp | grep ':443'
```

From your local machine:

```bash
nc -vz <server-ip-or-domain> 443
```

## Notes

- REALITY does not require your own domain, but a domain can make client configs
  easier to read.
- `--sni` and `--dest` should point to a normal HTTPS site reachable from the VPS.
- Always confirm your usage complies with local laws and your VPS provider terms.
