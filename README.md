# CVAT Cloudflare Tunnel Patches

Patches for [CVAT](https://github.com/cvat-ai/cvat) to support deployment behind Cloudflare Tunnel with HTTPS.

## What's included

- `patches/cvat/settings/cloudflare_tunnel.py` — Django security settings for reverse proxy
- `patches/traefik/rules/force-https.yml` — Traefik middleware to forward HTTPS headers
- `patches/docker-compose.yml.patch` — Adds traefik middleware label to CVAT's compose file
- `templates/docker-compose.override.yml` — Environment variables and volume mounts
- `templates/.env.example` — Environment template

## Usage

```bash
git clone https://github.com/cvat-ai/cvat.git
git clone https://github.com/YOUR_USER/cvat-patches-cloudflare.git

cd cvat-patches-cloudflare

# Apply with all options
./apply.sh ../cvat --domain cvat.example.com --data-dir /data/cvat

# Or apply interactively (will prompt for domain and data path)
./apply.sh ../cvat

# Start CVAT
cd ../cvat && docker compose up -d
```

## Options

```
./apply.sh <cvat_path> [options]

Arguments:
  <cvat_path>            Path to CVAT repository (required)

Options:
  -d, --domain DOMAIN    Set CVAT domain (e.g. cvat.example.com)
  -D, --data-dir DIR     Set host data directory for cvat_share volume
  -r, --revert           Revert all patches, restore localhost access
  -h, --help             Show this help
```

### Examples

```bash
# Apply patches with domain and data directory
./apply.sh ../cvat -d cvat.example.com -D /data/cvat

# Apply patches, then manually edit .env and override
./apply.sh ../cvat

# Revert all patches, restore localhost access
./apply.sh ../cvat --revert
```

## Requirements

- Docker & Docker Compose
- A Cloudflare Tunnel pointing to `cvat_server:8080`
- A domain configured in Cloudflare DNS
