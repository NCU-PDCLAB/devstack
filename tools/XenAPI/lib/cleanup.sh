#!/bin/bash

do_cleanup()
{
    DO_SHUTDOWN=${DO_SHUTDOWN:-1}
    CLEAN_TEMPLATES=${CLEAN_TEMPLATES:-false}
    if [ "$DO_SHUTDOWN" = "1" ]; then
        # Shutdown all domU's that created previously
        clean_templates_arg=""
        if $CLEAN_TEMPLATES; then
            clean_templates_arg="--remove-templates"
        fi
        ./scripts/uninstall-os-vpx.sh $clean_templates_arg

        # Destroy any instances that were launched
        for uuid in `xe vm-list | grep -1 instance | grep uuid | sed "s/.*\: //g"`; do
            echo "Shutting down nova instance $uuid"
            xe vm-unpause uuid=$uuid || true
            xe vm-shutdown uuid=$uuid || true
            xe vm-destroy uuid=$uuid
        done

        # Destroy orphaned vdis
        for uuid in `xe vdi-list | grep -1 Glance | grep uuid | sed "s/.*\: //g"`; do
            xe vdi-destroy uuid=$uuid
        done
    fi
}
