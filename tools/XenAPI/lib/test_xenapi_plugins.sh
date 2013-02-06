#!/bin/bash

set -eux

source ../../stackrc

XAPI_PLUGIN_DIR=$(mktemp -d)
#ENABLED_SERVICES="q-agt"
#Q_PLUGIN="openvswitch"

source lib/xenapi_plugins.sh
install_nova_and_quantum_xenapi_plugins

echo "temp dir is:"
echo $XAPI_PLUGIN_DIR
