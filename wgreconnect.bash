#!/bin/bash
while true
do
    sleep 15
    ping -c 1 <your_wireguard_server_ip>
    if [ $? != 0 ]
    then
      sudo systemctl restart wg-quick@wg0 #change wg device if needed
    fi
done
