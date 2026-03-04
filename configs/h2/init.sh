#!/bin/sh
set -e
ip addr flush dev eth1 || true
ip addr add 192.168.102.12/24 dev eth1
ip link set eth1 up
ip route replace default via 192.168.102.1
