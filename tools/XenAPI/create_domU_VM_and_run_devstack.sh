#!/bin/bash

set -o errexit
set -o xtrace

source xenrc
source ../../../stackrc

#THIS_DIR=$(cd $(dirname "$0") && pwd)
#. $THIS_DIR/../../functions
#. $THIS_DIR/scripts/on_exit.sh
#cd $THIS_DIR

source lib/xenapi_plugins.sh
install_nova_and_quantum_xenapi_plugins

mkdir -p /boot/guest

source lib/configure_xenserver_networks.sh
MGT_BR=$(get_management_network)
HOST_IP=$(get_xenserver_management_ip)

source lib/cleanup.sh

#
# Create Ubuntu VM template
# and/or create VM from template
#

GUEST_NAME=${GUEST_NAME:-"DevStackOSDomU"}
TNAME="devstack_template"
SNAME_PREPARED="template_prepared"
SNAME_FIRST_BOOT="before_first_boot"

function wait_for_VM_to_halt() {
    set +x
    echo "Waiting for the VM to halt.  Progress in-VM can be checked with vncviewer:"
    mgmt_ip=$(echo $XENAPI_CONNECTION_URL | tr -d -c '1234567890.')
    domid=$(xe vm-list name-label="$GUEST_NAME" params=dom-id minimal=true)
    port=$(xenstore-read /local/domain/$domid/console/vnc-port)
    echo "vncviewer -via $mgmt_ip localhost:${port:2}"
    while true
    do
        state=$(xe_min vm-list name-label="$GUEST_NAME" power-state=halted)
        if [ -n "$state" ]
        then
            break
        else
            echo -n "."
            sleep 20
        fi
    done
    set -x
}

templateuuid=$(xe template-list name-label="$TNAME")
if [ -z "$templateuuid" ]; then
    #
    # Install Ubuntu over network
    #

    # always update the preseed file, incase we have a newer one
    PRESEED_URL=${PRESEED_URL:-""}
    if [ -z "$PRESEED_URL" ]; then
        PRESEED_URL="${HOST_IP}/devstackubuntupreseed.cfg"
        HTTP_SERVER_LOCATION="/opt/xensource/www"
        if [ ! -e $HTTP_SERVER_LOCATION ]; then
            HTTP_SERVER_LOCATION="/var/www/html"
            mkdir -p $HTTP_SERVER_LOCATION
        fi
        cp -f $TOP_DIR/devstackubuntupreseed.cfg $HTTP_SERVER_LOCATION
        MIRROR=${MIRROR:-""}
        if [ -n "$MIRROR" ]; then
            sed -e "s,d-i mirror/http/hostname string .*,d-i mirror/http/hostname string $MIRROR," \
                -i "${HTTP_SERVER_LOCATION}/devstackubuntupreseed.cfg"
        fi
    fi

    # Update the template
    $TOP_DIR/scripts/install_ubuntu_template.sh $PRESEED_URL

    # create a new VM with the given template
    # creating the correct VIFs and metadata
    $TOP_DIR/scripts/install-os-vpx.sh -t "$UBUNTU_INST_TEMPLATE_NAME" -v $VM_BR -m $MGT_BR -p $PUB_BR -l $GUEST_NAME -r $OSDOMU_MEM_MB -k "flat_network_bridge=${VM_BR}"

    # wait for install to finish
    wait_for_VM_to_halt

    # set VM to restart after a reboot
    vm_uuid=$(xe_min vm-list name-label="$GUEST_NAME")
    xe vm-param-set actions-after-reboot=Restart uuid="$vm_uuid"

    #
    # Prepare VM for DevStack
    #

    # Install XenServer tools, and other such things
    $TOP_DIR/prepare_guest_template.sh "$GUEST_NAME"

    # start the VM to run the prepare steps
    xe vm-start vm="$GUEST_NAME"

    # Wait for prep script to finish and shutdown system
    wait_for_VM_to_halt

    # Make template from VM
    snuuid=$(xe vm-snapshot vm="$GUEST_NAME" new-name-label="$SNAME_PREPARED")
    xe snapshot-clone uuid=$snuuid new-name-label="$TNAME"
else
    #
    # Template already installed, create VM from template
    #
    vm_uuid=$(xe vm-install template="$TNAME" new-name-label="$GUEST_NAME")
fi


#
# Inject DevStack inside VM disk
#
$TOP_DIR/build_xva.sh "$GUEST_NAME"

# create a snapshot before the first boot
# to allow a quick re-run with the same settings
xe vm-snapshot vm="$GUEST_NAME" new-name-label="$SNAME_FIRST_BOOT"


#
# Run DevStack VM
#
xe vm-start vm="$GUEST_NAME"


#
# Find IP and optionally wait for stack.sh to complete
#

function find_ip_by_name() {
  local guest_name="$1"
  local interface="$2"
  local period=10
  max_tries=10
  i=0
  while true
  do
    if [ $i -ge $max_tries ]; then
      echo "Timed out waiting for devstack ip address"
      exit 11
    fi

    devstackip=$(xe vm-list --minimal \
                 name-label=$guest_name \
                 params=networks | sed -ne "s,^.*${interface}/ip: \([0-9.]*\).*\$,\1,p")
    if [ -z "$devstackip" ]
    then
      sleep $period
      ((i++))
    else
      echo $devstackip
      break
    fi
  done
}

function ssh_no_check() {
    ssh -o UserKnownHostsFile=/dev/null -o StrictHostKeyChecking=no "$@"
}

# Note the XenServer needs to be on the chosen
# network, so XenServer can access Glance API
if [ $HOST_IP_IFACE == "eth2" ]; then
    DOMU_IP=$MGT_IP
    if [ $MGT_IP == "dhcp" ]; then
        DOMU_IP=$(find_ip_by_name $GUEST_NAME 2)
    fi
else
    DOMU_IP=$PUB_IP
    if [ $PUB_IP == "dhcp" ]; then
        DOMU_IP=$(find_ip_by_name $GUEST_NAME 3)
    fi
fi

# If we have copied our ssh credentials, use ssh to monitor while the installation runs
WAIT_TILL_LAUNCH=${WAIT_TILL_LAUNCH:-1}
COPYENV=${COPYENV:-1}
if [ "$WAIT_TILL_LAUNCH" = "1" ]  && [ -e ~/.ssh/id_rsa.pub  ] && [ "$COPYENV" = "1" ]; then
    echo "We're done launching the vm, about to start tailing the"
    echo "stack.sh log. It will take a second or two to start."
    echo
    echo "Just CTRL-C at any time to stop tailing."

    # wait for log to appear
    while ! ssh_no_check -q stack@$DOMU_IP "[ -e run.sh.log ]"; do
        sleep 10
    done

    set +x
    echo -n "Waiting for startup script to finish"
    while [ `ssh_no_check -q stack@$DOMU_IP pgrep -c run.sh` -ge 1 ]
    do
        sleep 10
        echo -n "."
    done
    echo "done!"
    set -x

    # output the run.sh.log
    ssh_no_check -q stack@$DOMU_IP 'cat run.sh.log'

    # Fail if the expected text is not found
    ssh_no_check -q stack@$DOMU_IP 'cat run.sh.log' | grep -q 'stack.sh completed in'

    set +x
    echo "################################################################################"
    echo ""
    echo "All Finished!"
    echo "You can visit the OpenStack Dashboard"
    echo "at http://$DOMU_IP, and contact other services at the usual ports."
else
    set +x
    echo "################################################################################"
    echo ""
    echo "All Finished!"
    echo "Now, you can monitor the progress of the stack.sh installation by "
    echo "tailing /opt/stack/run.sh.log from within your domU."
    echo ""
    echo "ssh into your domU now: 'ssh stack@$DOMU_IP' using your password"
    echo "and then do: 'tail -f /opt/stack/run.sh.log'"
    echo ""
    echo "When the script completes, you can then visit the OpenStack Dashboard"
    echo "at http://$DOMU_IP, and contact other services at the usual ports."
fi
