#!/bin/sh
set -eu

: "${VIEWER_DOMAIN:?Set VIEWER_DOMAIN, for example angio.su}"
certbot_root=${VIEWER_CERTBOT_ROOT:-/opt/viewer/certbot}
tls_dir=${VIEWER_TLS_DIR:-/opt/viewer/tls}
certbot_image=${CERTBOT_IMAGE:-certbot/certbot:latest}

if [ -n "${VIEWER_SERVER_IP:-}" ]; then
  resolved=$(getent ahostsv4 "$VIEWER_DOMAIN" 2>/dev/null | awk '{print $1}' | sort -u || true)
  if ! printf '%s\n' "$resolved" | grep -Fxq "$VIEWER_SERVER_IP"; then
    printf 'DNS for %s does not resolve to %s (resolved: %s)\n' \
      "$VIEWER_DOMAIN" "$VIEWER_SERVER_IP" "${resolved:-none}" >&2
    exit 1
  fi
fi

mkdir -p "$certbot_root/etc" "$certbot_root/lib" "$certbot_root/www" "$tls_dir"

set -- --domain "$VIEWER_DOMAIN"
for alias in ${VIEWER_DOMAIN_ALIASES:-}; do
  set -- "$@" --domain "$alias"
done

docker run --rm \
  -v "$certbot_root/etc:/etc/letsencrypt" \
  -v "$certbot_root/lib:/var/lib/letsencrypt" \
  -v "$certbot_root/www:/var/www/certbot" \
  "$certbot_image" certonly \
  --webroot --webroot-path /var/www/certbot \
  --cert-name "$VIEWER_DOMAIN" \
  "$@" \
  --non-interactive --agree-tos --register-unsafely-without-email

live_dir="$certbot_root/etc/live/$VIEWER_DOMAIN"
install -o 101 -g 101 -m 0640 "$live_dir/fullchain.pem" "$tls_dir/fullchain.pem"
install -o 101 -g 101 -m 0640 "$live_dir/privkey.pem" "$tls_dir/privkey.pem"
