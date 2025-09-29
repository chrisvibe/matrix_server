#!/bin/bash

set -a
source ../.env
set +a

mkdir -p conf.d
sed "s/SYNAPSE_SERVER_NAME/$SYNAPSE_SERVER_NAME/g" nginx.conf.template > conf.d/nginx.conf

echo "Generated nginx.conf for $SYNAPSE_SERVER_NAME"
