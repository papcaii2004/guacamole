#!/bin/bash
set -e

if [ ! -f .env ]; then
    echo "ERROR: .env not found."
    exit 1
fi
source .env

if [ "$POSTGRES_PASSWORD" = "CHANGE_ME" ]; then
    PASS=$(openssl rand -base64 24)
    sed -i "s/POSTGRES_PASSWORD=CHANGE_ME/POSTGRES_PASSWORD=$PASS/" .env
    echo "Generated random POSTGRES_PASSWORD in .env"
fi

docker compose up -d

echo ""
echo "====================================="
echo "  Guacamole is ready!"
echo "  URL:  http://guac.duyhn.id.vn:3389/"
echo "  User: guacadmin"
echo "  Pass: guacadmin"
echo "  ** Change the default password! **"
echo "====================================="
