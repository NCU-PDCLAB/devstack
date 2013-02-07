#!/bin/bash

set -o errexit
set -o xtrace

source xenrc
source ../../../stackrc

source lib/xenapi_plugins.sh
install_nova_and_quantum_xenapi_plugins

mkdir -p /boot/guest

source lib/configure_xenserver_networks.sh
MGT_BR=$(get_management_network)
HOST_IP=$(get_xenserver_management_ip)

source lib/cleanup.sh
clean_previous_runs

GUEST_NAME=${GUEST_NAME:-"DevStackOSDomU"}
source lib/ubuntu_template.sh
#TODO create_ubuntu_template
create_ubuntu_vm

source lib/devstack_injection.sh
inject_devstack_into_vm

VM_BR=$(get_vm_data_network)
PUB_BR=$(get_public_network)
source lib/configure_devstack_vm_netorks.sh
configure_vifs $GUEST_NAME $MGT_BR $VM_BR $PUB_BR

SNAME_FIRST_BOOT="before_first_boot"
xe vm-snapshot vm="$GUEST_NAME" new-name-label="$SNAME_FIRST_BOOT"
xe vm-start vm="$GUEST_NAME"

source lib/monitor_progress
monitor_stack_sh_progress
