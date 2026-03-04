#!/bin/sh
set -e

# Tenant VRF
ip link add vrf-ten1 type vrf table 10 2>/dev/null || true
ip link set vrf-ten1 up

# Tenant L2 segment for subnet102 is local bridge br102 + access port eth3
ip link add br102 type bridge 2>/dev/null || true
ip link set br102 up
ip link set dev br102 address 02:00:00:00:01:02
ip addr replace 192.168.102.1/24 dev br102
ip link set br102 master vrf-ten1 || true

ip link set eth3 up
ip link set eth3 master br102

# L3VNI (VNI 50100)
ip link add vxlan50100 type vxlan id 50100 dstport 4789 local 10.255.1.2 2>/dev/null || true
ip link set vxlan50100 up

ip link add br50100 type bridge 2>/dev/null || true
ip link set br50100 up
ip link set vxlan50100 master br50100
ip link set br50100 master vrf-ten1 || true

# Reduce asymmetric-path drops
sysctl -w net.ipv4.conf.all.rp_filter=0 >/dev/null
sysctl -w net.ipv4.conf.default.rp_filter=0 >/dev/null
sysctl -w net.ipv4.conf.vxlan50100.rp_filter=0 >/dev/null 2>&1 || true
sysctl -w net.ipv4.conf.br50100.rp_filter=0 >/dev/null 2>&1 || true
sysctl -w net.ipv4.conf.br102.rp_filter=0 >/dev/null 2>&1 || true

exit 0

# --- L3VNI RMAC resolution helper (workaround for timing issues) ---
for i in $(seq 1 30); do
  RM1=$(vtysh -c "show bgp l2vpn evpn route type 5" 2>/dev/null | awk '/Rmac:/{print $NF}' | head -n 1)
  echo "$RM1" | grep -Eq '([0-9a-f]{2}:){5}[0-9a-f]{2}' && break
  sleep 0.2
done

if echo "$RM1" | grep -Eq '([0-9a-f]{2}:){5}[0-9a-f]{2}'; then
  ip neigh replace 10.255.1.1 lladdr "$RM1" dev br50100 nud permanent || true
  bridge fdb replace "$RM1" dev vxlan50100 dst 10.255.1.1 self permanent || true
fi

# L3VNI RMAC/FDB repair (run once at boot)
for i in $(seq 1 50); do
  RM1=$(vtysh -c "show bgp l2vpn evpn route type 5" 2>/dev/null | awk '/Rmac:/{print $NF}' | head -n 1)
  echo "$RM1" | grep -Eq '([0-9a-f]{2}:){5}[0-9a-f]{2}' && break
  sleep 0.2
done
if echo "$RM1" | grep -Eq '([0-9a-f]{2}:){5}[0-9a-f]{2}'; then
  ip neigh replace 10.255.1.1 lladdr "$RM1" dev br50100 nud permanent || true
  bridge fdb replace "$RM1" dev vxlan50100 dst 10.255.1.1 self permanent || true
fi

# --- L3VNI RMAC/FDB repair (boot-time) ---
for i in $(seq 1 60); do
  RM1=$(vtysh -c "show bgp l2vpn evpn route type 5" 2>/dev/null | awk '/Rmac:/{print $NF}' | head -n 1)
  echo "$RM1" | grep -Eq '([0-9a-f]{2}:){5}[0-9a-f]{2}' && break
  sleep 0.2
done
if echo "$RM1" | grep -Eq '([0-9a-f]{2}:){5}[0-9a-f]{2}'; then
  ip neigh replace 10.255.1.1 lladdr "$RM1" dev br50100 nud permanent || true
  bridge fdb replace "$RM1" dev vxlan50100 dst 10.255.1.1 self permanent || true
fi

# --- L3VNI watchdog: keep remote VTEP next-hop from staying FAILED ---
(
  while true; do
    if ip neigh show dev br50100 2>/dev/null | grep -q "10.255.1.1 FAILED"; then
      RM1=$(vtysh -c "show bgp l2vpn evpn route type 5" 2>/dev/null | awk '/Rmac:/{print $NF}' | head -n 1)
      if echo "$RM1" | grep -Eq '([0-9a-f]{2}:){5}[0-9a-f]{2}'; then
        ip neigh replace 10.255.1.1 lladdr "$RM1" dev br50100 nud permanent || true
        bridge fdb replace "$RM1" dev vxlan50100 dst 10.255.1.1 self permanent || true
      fi
    fi
    sleep 1
  done
) >/tmp/l3vni-watchdog.log 2>&1 &

# --- L3VNI watchdog (leaf2) using robust RMAC extraction ---
(
  while true; do
    if ip neigh show dev br50100 2>/dev/null | grep -q "10.255.1.1 FAILED"; then
      RM1=$(vtysh -c "show bgp l2vpn evpn route type 5" 2>/dev/null \
        | tr -d '\r' \
        | sed -n 's/.*Rmac:\([0-9a-f:]\{17\}\).*/\1/p' \
        | head -n 1)

      if echo "$RM1" | grep -Eq '^([0-9a-f]{2}:){5}[0-9a-f]{2}$'; then
        ip neigh replace 10.255.1.1 lladdr "$RM1" dev br50100 nud permanent || true
        bridge fdb replace "$RM1" dev vxlan50100 dst 10.255.1.1 self permanent || true
      fi
    fi
    sleep 1
  done
) >/tmp/l3vni-watchdog.log 2>&1 &