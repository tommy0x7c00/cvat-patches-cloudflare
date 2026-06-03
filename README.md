# CVAT Cloudflare Tunnel Patches

Patches for [CVAT](https://github.com/cvat-ai/cvat) to support deployment behind Cloudflare Tunnel with HTTPS.

## What's included

- `cvat/settings/cloudflare_tunnel.py` — Django security settings for reverse proxy
- `traefik/rules/force-https.yml` — Traefik middleware to forward HTTPS headers
- `docker-compose.yml.patch` — Adds traefik middleware label to CVAT's compose file
- `docker-compose.override.yml` — Environment variables and volume mounts
- `.env.example` — Environment template

## Usage

```bash
# Clone official CVAT
git clone https://github.com/cvat-ai/cvat.git
cd cvat

# Apply patches
git clone https://github.com/YOUR_USER/cvat-patches-cloudflare.git
./cvat-patches-cloudflare/apply.sh .

# Configure
cp .env.example .env
vim .env                          # set your domain
vim docker-compose.override.yml   # set your data path

# Start
docker compose up -d
```

## Requirements

- Docker & Docker Compose
- A Cloudflare Tunnel pointing to `cvat_server:8080`
- A domain configured in Cloudflare DNS
