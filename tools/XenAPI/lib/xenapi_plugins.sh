#!/bin/bash

generate_zipball_url()
{
    REPO=$1
    BRANCH=$2
    echo $REPO | sed "s:\.git$::;s:$:/zipball/$BRANCH:g"
}

install_xenapi_plugin()
{
    ZIPBALL_URL=$1
    PLUGIN_LOCATION=$2


    tmp_dir=$(mktemp -d)
    (
        cd $tmp_dir
        wget $ZIPBALL_URL -O zipball --no-check-certificate
        unzip -o zipball -d ./

        XAPI_PLUGIN_DIR=${XAPI_PLUGIN_DIR:-"/etc/xapi.d/plugins/"}
        if [ ! -d $XAPI_PLUGIN_DIR ]; then
            XAPI_PLUGIN_DIR="/usr/lib/xcp/plugins/"
        fi

        cp -pr $tmp_dir/*/$PLUGIN_LOCATION $XAPI_PLUGIN_DIR
    )
    rm -rf $tmp_dir

    chmod a+x ${XAPI_PLUGIN_DIR}*
    mkdir -p /boot/guest
}

install_nova_and_quantum_xenapi_plugins()
{
    NOVA_ZIPBALL_URL=${NOVA_ZIPBALL_URL:-$(generate_zipball_url $NOVA_REPO $NOVA_BRANCH)}
    install_xenapi_plugin $NOVA_ZIPBALL_URL "plugins/xenserver/xenapi/etc/xapi.d/plugins/*"

    if [[ "$ENABLED_SERVICES" =~ "q-agt" && "$Q_PLUGIN" = "openvswitch" ]]; then
        QUANTUM_ZIPBALL_URL=${QUANTUM_ZIPBALL_URL:-$(generate_zipball_url $QUANTUM_REPO $QUANTUM_BRANCH)}
        install_xenapi_plugin $QUANTUM_ZIPBALL_URL "quantum/plugins/openvswitch/agent/xenapi/etc/xapi.d/plugins/*"
    fi
}
