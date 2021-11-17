#!/bin/bash
#sends wol packet to specified MAC until it has woken up
if [ -z "$1" ] || [ -z "$2" ] || [ -z "$3" ]
  then
    echo "Specify MAC address to wake up, IP address to ping and your source interface; i.e. wake.sh FF:FF:FF:FF:FF:FF 192.168.1.6 eth0"
    exit 1
fi

if ! wakeonlan -v wakeonlan &> /dev/null
then
    echo "wakeonlan could not be found"
    exit
fi

etherwake="$(which etherwake)"

if ! etherwake -v etherwake &> /dev/null
then
    echo "etherwake could not be found"
    exit
fi

status=0
while [ $status -eq 0 ];
do
    ping -c 1 $2 >/dev/null && status=1
    etherwake -i $3 $1
    wakeonlan $1
    sleep 4
done

exit 0