#!/bin/bash

add_additional_vifs()
{
    vm_name="$1"
    data_net="$2"
    public_net="$3"
    
    xe vif-create vm="$GUEST_NAME" network-uuid="$data_net" device="1"
    xe vif-create vm="$GUEST_NAME" network-uuid="$public_net" device="2"
}
