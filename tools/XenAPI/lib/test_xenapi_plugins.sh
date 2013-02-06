#!/bin/bash

set -eux

XAPI_PLUGIN_DIR=$(mktemp -d)
source lib/xenapi_plugins.sh
install_nova_and_quantum_xenapi_plugins

echo "temp dir is:"
echo $XAPI_PLUGIN_DIR
