#!/bin/bash


find_network()
{
  result=$(xe_min network-list bridge="$1")
  if [ "$result" = "" ]
  then
    result=$(xe_min network-list name-label="$1")
  fi
  echo "$result"
}

get_xenserver_management_ip()
{
    #TODO mgmt_ip=$(echo $XENAPI_CONNECTION_URL | tr -d -c '1234567890.')
    echo ${HOST_IP:-`ifconfig xenbr0 | grep "inet addr" | cut -d ":" -f2 | sed "s/ .*//"`}
}

get_management_network()
{
    # TODO - should discover the correct one
    echo "xenbr0"
}

create_network_if_required()
{
    network="$1"
    $data_network_uuid=$(find_network $network)
    if [ -z "$data_network_uuid" ]; then
        $data_network_uuid=$(xe network-create name-label=$network)
    fi
    echo "$data_network_uuid"
}

get_vm_data_network()
{
    MGT_BR=${MGT_BR:-"OS_VM_Data_Network"}
    echo "$(create_network_if_required $MGT_BR)"
}

get_public_network()
{
    PUB_BR=${PUB_BR:-"OS_Public_Network"}
    echo "$(create_network_if_required $PUB_BR)"
}

