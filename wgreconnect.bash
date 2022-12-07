#!/bin/bash

if [ -z "$1" ] || [ -z "$2" ]
  then
    echo "Supply wg server ip and wg device"
    exit 1
fi

while true
do
    sleep 15
    ping -c 1 $1
    if [ $? != 0 ]
    then
      systemctl restart wg-quick@$2
    fi
done
