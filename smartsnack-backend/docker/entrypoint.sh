#!/bin/sh
set -e

cd /var/www/html

if [ -f .env ]; then
  echo "Using existing .env"
elif [ -f .env.example ]; then
  cp .env.example .env
fi

if ! grep -q "^APP_KEY=base64:" .env 2>/dev/null; then
  php artisan key:generate --force || true
fi

mkdir -p \
  storage/framework/cache/data \
  storage/framework/sessions \
  storage/framework/testing \
  storage/framework/views \
  storage/logs \
  bootstrap/cache

chown -R www-data:www-data storage bootstrap/cache || true

php artisan config:clear || true

echo "Waiting MySQL..."
DB_WAIT_USER="${DB_WAIT_USER:-${DB_USERNAME:-smartsnack}}"
DB_WAIT_PASSWORD="${DB_WAIT_PASSWORD:-${DB_PASSWORD:-smartsnack}}"
DB_WAIT_HOST="${DB_HOST:-mysql}"
DB_WAIT_PORT="${DB_PORT:-3306}"
DB_WAIT_MAX_RETRY="${DB_WAIT_MAX_RETRY:-60}"

i=0
until mysql --skip-ssl -h"${DB_WAIT_HOST}" -P"${DB_WAIT_PORT}" -u"${DB_WAIT_USER}" -p"${DB_WAIT_PASSWORD}" -e "SELECT 1" >/dev/null 2>&1; do
  i=$((i + 1))
  if [ "$i" -ge "$DB_WAIT_MAX_RETRY" ]; then
    echo "MySQL not reachable after ${DB_WAIT_MAX_RETRY} retries."
    echo "DB wait target: ${DB_WAIT_HOST}:${DB_WAIT_PORT} user=${DB_WAIT_USER}"
    exit 1
  fi
  sleep 2
done

php artisan migrate --force || true
php artisan storage:link || true

exec apache2-foreground
