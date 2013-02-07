#!/bin/bash

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

monitor_stack_sh_progress()
{
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
}
