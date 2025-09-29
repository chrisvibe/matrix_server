#!/bin/bash

set -a
source ../.env
set +a

sed "s/SYNAPSE_SERVER_NAME/$SYNAPSE_SERVER_NAME/g" element-config.json.template > element-config.json

echo "Generated element-config.json for $SYNAPSE_SERVER_NAME"
