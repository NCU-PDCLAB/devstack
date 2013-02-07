#!/bin/bash

#TODO

get_xenserver_management_ip()
{

    #TODO mgmt_ip=$(echo $XENAPI_CONNECTION_URL | tr -d -c '1234567890.')
    echo ${HOST_IP:-`ifconfig xenbr0 | grep "inet addr" | cut -d ":" -f2 | sed "s/ .*//"`}
}

get_management_network()
{
    echo "xenbr0"
}

get_vm_data_network()
{
}

get_public_network()
{
}

configure_xenserver_networks()
{
    # TODO
    # Get final bridge names
    if [ -z $VM_BR ]; then
        VM_BR=$(xe_min network-list  uuid=$VM_NET params=bridge)
    fi
    if [ -z $MGT_BR ]; then
        MGT_BR=$(xe_min network-list  uuid=$MGT_NET params=bridge)
    fi
    if [ -z $PUB_BR ]; then
        PUB_BR=$(xe_min network-list  uuid=$PUB_NET params=bridge)
    fi

    # Helper to create networks
    # Uses echo trickery to return network uuid
    function create_network() {
        br=$1
        dev=$2
        vlan=$3
        netname=$4
        if [ -z $br ]
        then
            pif=$(xe_min pif-list device=$dev VLAN=$vlan)
            if [ -z $pif ]
            then
                net=$(xe network-create name-label=$netname)
            else
                net=$(xe_min network-list  PIF-uuids=$pif)
            fi
            echo $net
            return 0
        fi
        if [ ! $(xe_min network-list  params=bridge | grep -w --only-matching $br) ]
        then
            echo "Specified bridge $br does not exist"
            echo "If you wish to use defaults, please keep the bridge name empty"
            exit 1
        else
            net=$(xe_min network-list  bridge=$br)
            echo $net
        fi
    }

    function errorcheck() {
        rc=$?
        if [ $rc -ne 0 ]
        then
            exit $rc
        fi
    }

    # Create host, vm, mgmt, pub networks on XenServer
    VM_NET=$(create_network "$VM_BR" "$VM_DEV" "$VM_VLAN" "vmbr")
    errorcheck
    MGT_NET=$(create_network "$MGT_BR" "$MGT_DEV" "$MGT_VLAN" "mgtbr")
    errorcheck
    PUB_NET=$(create_network "$PUB_BR" "$PUB_DEV" "$PUB_VLAN" "pubbr")
    errorcheck

    # Helper to create vlans
    function create_vlan() {
        dev=$1
        vlan=$2
        net=$3
        # VLAN -1 refers to no VLAN (physical network)
        if [ $vlan -eq -1 ]
        then
            return
        fi
        if [ -z $(xe_min vlan-list  tag=$vlan) ]
        then
            pif=$(xe_min pif-list  network-uuid=$net)
            # We created a brand new network this time
            if [ -z $pif ]
            then
                pif=$(xe_min pif-list  device=$dev VLAN=-1)
                xe vlan-create pif-uuid=$pif vlan=$vlan network-uuid=$net
            else
                echo "VLAN does not exist but PIF attached to this network"
                echo "How did we reach here?"
                exit 1
            fi
        fi
    }

    # Create vlans for vm and management
    create_vlan $PUB_DEV $PUB_VLAN $PUB_NET
    create_vlan $VM_DEV $VM_VLAN $VM_NET
    create_vlan $MGT_DEV $MGT_VLAN $MGT_NET

}
