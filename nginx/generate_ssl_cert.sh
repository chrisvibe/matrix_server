#!/bin/bash

# Generate self-signed SSL certificate for nginx federation port
# This is only used between nginx and Cloudflare Tunnel
# Cloudflare handles the public-facing SSL certificate

set -e

# Load environment for server name
set -a
source ../.env
set +a

SSL_DIR="ssl"
mkdir -p "$SSL_DIR"

echo "Generating self-signed SSL certificate for $SYNAPSE_SERVER_NAME..."

openssl req -x509 -nodes -days 365 -newkey rsa:2048 \
    -keyout "$SSL_DIR/key.pem" \
    -out "$SSL_DIR/cert.pem" \
    -subj "/CN=$SYNAPSE_SERVER_NAME" \
    2>/dev/null

chmod 600 "$SSL_DIR/key.pem"
chmod 644 "$SSL_DIR/cert.pem"

echo "SSL certificate generated in nginx/$SSL_DIR/"
echo "This certificate is only used between nginx and Cloudflare Tunnel"
