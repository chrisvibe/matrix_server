#!/bin/bash

set -e

# Load environment
set -a
source ../.env
set +a

# Fetch current Cloudflare IP ranges
echo "Fetching current Cloudflare IP ranges..."
CF_IPV4=$(curl -s https://www.cloudflare.com/ips-v4)
CF_IPV6=$(curl -s https://www.cloudflare.com/ips-v6)

# Create conf.d directory
mkdir -p conf.d

# Generate nginx.conf with actual IPs
echo "Generating nginx.conf for $SYNAPSE_SERVER_NAME..."

# Start with the template
cp nginx.conf.template conf.d/nginx.conf

# Replace server name
sed -i "s/SYNAPSE_SERVER_NAME/$SYNAPSE_SERVER_NAME/g" conf.d/nginx.conf

# Build the IP list
IP_LIST=""
while IFS= read -r ip; do
    IP_LIST="${IP_LIST}    set_real_ip_from $ip;\n"
done <<< "$CF_IPV4"
while IFS= read -r ip; do
    IP_LIST="${IP_LIST}    set_real_ip_from $ip;\n"
done <<< "$CF_IPV6"

# Replace the placeholder with actual IPs
sed -i "s|# CLOUDFLARE_IPS_PLACEHOLDER|$IP_LIST|g" conf.d/nginx.conf

echo "✅ Generated nginx.conf with current Cloudflare IPs"
