#!/bin/sh
set -eu

: "${VIEWER_DOMAIN:?Set VIEWER_DOMAIN, for example angio.su}"
: "${VIEWER_SERVER_IP:?Set VIEWER_SERVER_IP}"
project_dir=$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)
certbot_root=${VIEWER_CERTBOT_ROOT:-/opt/viewer/certbot}
tls_dir=${VIEWER_TLS_DIR:-/opt/viewer/tls}
certbot_image=${CERTBOT_IMAGE:-certbot/certbot:latest}

mkdir -p "$certbot_root/etc" "$certbot_root/lib" "$certbot_root/www" "$tls_dir"
docker run --rm \
  -v "$certbot_root/etc:/etc/letsencrypt" \
  -v "$certbot_root/lib:/var/lib/letsencrypt" \
  -v "$certbot_root/www:/var/www/certbot" \
  "$certbot_image" renew --quiet

domain_live_dir="$certbot_root/etc/live/$VIEWER_DOMAIN"
ip_live_dir="$certbot_root/etc/live/$VIEWER_SERVER_IP"
for file in \
  "$domain_live_dir/fullchain.pem" "$domain_live_dir/privkey.pem" \
  "$ip_live_dir/fullchain.pem" "$ip_live_dir/privkey.pem"; do
  test -r "$file"
done

install -o 101 -g 101 -m 0640 "$domain_live_dir/fullchain.pem" "$tls_dir/domain-fullchain.pem"
install -o 101 -g 101 -m 0640 "$domain_live_dir/privkey.pem" "$tls_dir/domain-privkey.pem"
install -o 101 -g 101 -m 0640 "$domain_live_dir/fullchain.pem" "$tls_dir/fullchain.pem"
install -o 101 -g 101 -m 0640 "$domain_live_dir/privkey.pem" "$tls_dir/privkey.pem"
install -o 101 -g 101 -m 0640 "$ip_live_dir/fullchain.pem" "$tls_dir/ip-fullchain.pem"
install -o 101 -g 101 -m 0640 "$ip_live_dir/privkey.pem" "$tls_dir/ip-privkey.pem"

cd "$project_dir"
docker compose up -d --force-recreate frontend
./scripts/check-compose.sh
