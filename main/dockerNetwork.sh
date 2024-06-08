#/bin/bash

docker network create --driver bridge --subnet 192.168.10.0/24 --gateway 192.168.10.1 --ip-range 192.168.10.0/26 default-nw
