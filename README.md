# CVAT Cloudflare Tunnel Patches

Patches for [CVAT](https://github.com/cvat-ai/cvat) to support deployment behind Cloudflare Tunnel with HTTPS, while preserving local network access.

## What's included

<<<<<<< HEAD
- `cvat/settings/cloudflare_tunnel.py` — Django security settings for reverse proxy
- `traefik/rules/force-https.yml` — Traefik middleware to forward HTTPS headers
- `docker-compose.yml.patch` — Adds traefik middleware label to CVAT's compose file
- `docker-compose.override.yml` — Environment variables and volume mounts
- `.env.example` — Environment template with CSRF trusted origins for LAN IP
- LAN IP routing — Adds local network IP to Traefik Host rules and CSRF trusted origins (auto-detected or manual)
=======
- `patches/cvat/settings/cloudflare_tunnel.py` — Django security settings for reverse proxy
- `patches/traefik/rules/force-https.yml` — Traefik middleware to forward HTTPS headers
- `patches/docker-compose.yml.patch` — Adds traefik middleware label to CVAT's compose file
- `templates/docker-compose.override.yml` — Environment variables and volume mounts
- `templates/.env.example` — Environment template
>>>>>>> a888d2f2c679aeef398d40b2807711eee22c179f

## Usage

```bash
git clone https://github.com/cvat-ai/cvat.git
<<<<<<< HEAD
cd cvat

# Apply patches (with auto-detected LAN IP)
git clone https://github.com/YOUR_USER/cvat-patches-cloudflare.git
./cvat-patches-cloudflare/apply.sh . --domain cvat.example.com --data-dir /data/cvat

# Or specify LAN IP manually
./cvat-patches-cloudflare/apply.sh . --domain cvat.example.com --data-dir /data/cvat --lan-ip 192.168.2.88
=======
git clone https://github.com/YOUR_USER/cvat-patches-cloudflare.git

cd cvat-patches-cloudflare
>>>>>>> a888d2f2c679aeef398d40b2807711eee22c179f

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

## Access methods

After applying patches, CVAT is accessible via:

| Method | URL | Notes |
|--------|-----|-------|
| Tunnel domain | `https://cvat.example.com` | Primary access via Cloudflare Tunnel |
| Localhost | `http://localhost:8080` | Direct local access |
| LAN IP | `http://192.168.2.88:8080` | Local network access (auto-detected or set via `--lan-ip`) |

## Options

```
Usage: apply.sh <cvat_path> [options]

Arguments:
  <cvat_path>            Path to CVAT repository (required)

Options:
  -d, --domain DOMAIN    Set CVAT domain (e.g. cvat.example.com)
  -D, --data-dir DIR     Set host data directory for cvat_share volume
  -i, --lan-ip IP        Set LAN IP for local network access (auto-detected if omitted)
  -r, --revert           Revert all patches, restore localhost access
  -h, --help             Show this help
```

## Requirements

- Docker & Docker Compose
- A Cloudflare Tunnel pointing to `cvat_server:8080`
- A domain configured in Cloudflare DNS

## Note on LAN IP

The LAN IP is added to both Traefik routing rules and Django's `CSRF_TRUSTED_ORIGINS`. If your machine's IP changes, re-run `apply.sh` with the new IP:

```bash
./cvat-patches-cloudflare/apply.sh ../cvat --domain cvat.example.com --data-dir /data/cvat --lan-ip 192.168.2.100
```

## Reverting

```bash
./cvat-patches-cloudflare/apply.sh ../cvat --revert
```
