#!/usr/bin/env bash
# ======================================================
#  Fixam — Nginx Reverse Proxy + Let's Encrypt SSL Setup
#  Reads DOMAIN from .env file
# ======================================================
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ENV_FILE="${SCRIPT_DIR}/.env"

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m'

log()  { echo -e "${GREEN}[+]${NC} $1"; }
warn() { echo -e "${YELLOW}[!]${NC} $1"; }
err()  { echo -e "${RED}[x]${NC} $1"; exit 1; }

# ── Ensure root ────────────────────────────────────
if [[ $EUID -ne 0 ]]; then
    err "This script must be run as root (use sudo)."
fi

# ── Load .env ──────────────────────────────────────
if [[ ! -f "$ENV_FILE" ]]; then
    err "No .env file found at ${ENV_FILE}. Create one with DOMAIN=yourdomain.com"
fi

log "Loading configuration from ${ENV_FILE}..."
set -a
source "$ENV_FILE"
set +a

# ── Validate required vars ─────────────────────────
if [[ -z "${DOMAIN:-}" ]]; then
    err "DOMAIN is not set in ${ENV_FILE}. Add: DOMAIN=yourdomain.com"
fi

APP_PORT="${APP_PORT:-6000}"
EMAIL="${EMAIL:-privacy@${DOMAIN}}"
NGINX_AVAILABLE="/etc/nginx/sites-available"
NGINX_ENABLED="/etc/nginx/sites-enabled"
WEBROOT="/var/www/html"

log "DOMAIN    = ${DOMAIN}"
log "APP_PORT  = ${APP_PORT}"
log "EMAIL     = ${EMAIL}"
echo ""

# ── Install dependencies ───────────────────────────
log "Updating package lists..."
apt-get update -qq

log "Installing nginx and certbot..."
apt-get install -y -qq nginx certbot python3-certbot-nginx

# ── Create webroot ─────────────────────────────────
mkdir -p "$WEBROOT"

# ── Generate nginx config ──────────────────────────
log "Creating nginx config for ${DOMAIN}..."

cat > "${NGINX_AVAILABLE}/${DOMAIN}.conf" << NGINX
# ── HTTP → HTTPS Redirect ──────────────────────────
server {
    listen 80;
    listen [::]:80;
    server_name ${DOMAIN} www.${DOMAIN};

    # Let's Encrypt ACME challenge
    location ^~ /.well-known/acme-challenge/ {
        root ${WEBROOT};
        default_type text/plain;
    }

    # Redirect everything else to HTTPS
    location / {
        return 301 https://\$host\$request_uri;
    }
}

# ── HTTPS Reverse Proxy ────────────────────────────
server {
    # SSL config injected by certbot — placeholder
    listen 443 ssl http2;
    listen [::]:443 ssl http2;
    server_name ${DOMAIN} www.${DOMAIN};

    # Temporary self-signed cert (replaced by certbot)
    ssl_certificate     /etc/ssl/certs/ssl-cert-snakeoil.pem;
    ssl_certificate_key /etc/ssl/private/ssl-cert-snakeoil.key;

    # Security headers
    add_header Strict-Transport-Security "max-age=63072000; includeSubDomains; preload" always;
    add_header X-Content-Type-Options "nosniff" always;
    add_header X-Frame-Options "SAMEORIGIN" always;
    add_header X-XSS-Protection "1; mode=block" always;
    add_header Referrer-Policy "strict-origin-when-cross-origin" always;

    # Reverse proxy to Node.js app
    location / {
        proxy_pass http://127.0.0.1:${APP_PORT};
        proxy_http_version 1.1;
        proxy_set_header Upgrade \$http_upgrade;
        proxy_set_header Connection "upgrade";
        proxy_set_header Host \$host;
        proxy_set_header X-Real-IP \$remote_addr;
        proxy_set_header X-Forwarded-For \$proxy_add_x_forwarded_for;
        proxy_set_header X-Forwarded-Proto \$scheme;
        proxy_cache_bypass \$http_upgrade;

        # Timeouts
        proxy_connect_timeout 60s;
        proxy_send_timeout 60s;
        proxy_read_timeout 60s;
    }

    # Gzip compression
    gzip on;
    gzip_vary on;
    gzip_min_length 1024;
    gzip_types text/plain text/css text/javascript application/javascript application/json image/svg+xml;
}
NGINX

# ── Enable site ────────────────────────────────────
log "Enabling site..."
ln -sf "${NGINX_AVAILABLE}/${DOMAIN}.conf" "${NGINX_ENABLED}/${DOMAIN}.conf"
rm -f "${NGINX_ENABLED}/default"

# ── Test & reload nginx ────────────────────────────
log "Testing nginx configuration..."
nginx -t || err "Nginx configuration test failed."

log "Reloading nginx..."
systemctl reload nginx

# ── Obtain SSL certificate ─────────────────────────
log "Requesting SSL certificate for ${DOMAIN}..."
certbot --nginx \
    --non-interactive \
    --agree-tos \
    --email "${EMAIL}" \
    --domains "${DOMAIN},www.${DOMAIN}" \
    --redirect \
    --keep-until-expiring \
    --expand \
    || warn "Certbot auto-config failed. Falling back to webroot method..."

# ── Fallback: webroot method ───────────────────────
if ! certbot certificates 2>/dev/null | grep -q "${DOMAIN}"; then
    log "Retrying with certonly webroot method..."
    certbot certonly \
        --webroot \
        --webroot-path="${WEBROOT}" \
        --non-interactive \
        --agree-tos \
        --email "${EMAIL}" \
        --domains "${DOMAIN},www.${DOMAIN}" \
        || warn "Certificate acquisition failed. Check DNS for ${DOMAIN}."
fi

# ── Final nginx reload ─────────────────────────────
log "Performing final nginx reload..."
systemctl reload nginx

# ── Enable auto-renewal ────────────────────────────
log "Enabling certbot auto-renewal timer..."
systemctl enable certbot.timer 2>/dev/null || true

# ── Verify ─────────────────────────────────────────
echo ""
log "═══════════════════════════════════════════════"
log "  Setup complete for ${DOMAIN}!"
log "  App proxied to http://127.0.0.1:${APP_PORT}"
log "  HTTP  → auto-redirects to HTTPS"
log "  HTTPS → Let's Encrypt SSL (auto-renewing)"
log ""
log "  Test:  curl -I https://${DOMAIN}"
log "═══════════════════════════════════════════════"
echo ""
