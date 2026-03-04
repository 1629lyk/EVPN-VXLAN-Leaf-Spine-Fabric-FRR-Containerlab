#!/bin/sh
set -e

# Tenant VRF
ip link add vrf-ten1 type vrf table 10 2>/dev/null || true
ip link set vrf-ten1 up

# Tenant L2 segment (VNI 10100) - br101 + access port eth3
ip link add br101 type bridge 2>/dev/null || true
ip link set br101 up
ip link set dev br101 address 02:00:00:00:01:01
ip addr replace 192.168.101.1/24 dev br101
ip link set br101 master vrf-ten1 || true

ip link set eth3 up
ip link set eth3 master br101

# L2VNI VXLAN interface (EVPN Type-2 will handle MAC/IP control plane)
ip link add vxlan101 type vxlan id 10100 dstport 4789 local 10.255.1.1 2>/dev/null || true
ip link set vxlan101 up
ip link set vxlan101 master br101

# L3VNI (VNI 50100) - br50100 is L3-SVI (no IP)
ip link add vxlan50100 type vxlan id 50100 dstport 4789 local 10.255.1.1 2>/dev/null || true
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
sysctl -w net.ipv4.conf.br101.rp_filter=0 >/dev/null 2>&1 || true

exit 0

# --- L3VNI RMAC resolution helper (workaround for timing issues) ---
# Wait until leaf2 RMAC is visible via EVPN, then program neighbor/FDB for L3VNI.
for i in $(seq 1 30); do
  RM2=$(vtysh -c "show bgp l2vpn evpn route type 5" 2>/dev/null | awk '/Rmac:/{print $NF}' | tail -n 1)
  echo "$RM2" | grep -Eq '([0-9a-f]{2}:){5}[0-9a-f]{2}' && break
  sleep 0.2
done

if echo "$RM2" | grep -Eq '([0-9a-f]{2}:){5}[0-9a-f]{2}'; then
  ip neigh replace 10.255.1.2 lladdr "$RM2" dev br50100 nud permanent || true
  bridge fdb replace "$RM2" dev vxlan50100 dst 10.255.1.2 self permanent || true
fi

# L3VNI RMAC/FDB repair (run once at boot)
for i in $(seq 1 50); do
  RM2=$(vtysh -c "show bgp l2vpn evpn route type 5" 2>/dev/null | awk '/Rmac:/{print $NF}' | tail -n 1)
  echo "$RM2" | grep -Eq '([0-9a-f]{2}:){5}[0-9a-f]{2}' && break
  sleep 0.2
done
if echo "$RM2" | grep -Eq '([0-9a-f]{2}:){5}[0-9a-f]{2}'; then
  ip neigh replace 10.255.1.2 lladdr "$RM2" dev br50100 nud permanent || true
  bridge fdb replace "$RM2" dev vxlan50100 dst 10.255.1.2 self permanent || true
fi

# --- L3VNI RMAC/FDB repair (boot-time) ---
# Find remote RMAC from Type-5 and program neighbor/FDB so br50100 next-hop doesn't go FAILED.
for i in $(seq 1 60); do
  RM2=$(vtysh -c "show bgp l2vpn evpn route type 5" 2>/dev/null | awk '/Rmac:/{print $NF}' | tail -n 1)
  echo "$RM2" | grep -Eq '([0-9a-f]{2}:){5}[0-9a-f]{2}' && break
  sleep 0.2
done
if echo "$RM2" | grep -Eq '([0-9a-f]{2}:){5}[0-9a-f]{2}'; then
  ip neigh replace 10.255.1.2 lladdr "$RM2" dev br50100 nud permanent || true
  bridge fdb replace "$RM2" dev vxlan50100 dst 10.255.1.2 self permanent || true
fi

# --- L3VNI watchdog: keep remote VTEP next-hop from staying FAILED ---
(
  while true; do
    if ip neigh show dev br50100 2>/dev/null | grep -q "10.255.1.2 FAILED"; then
      RM2=$(vtysh -c "show bgp l2vpn evpn route type 5" 2>/dev/null | awk '/Rmac:/{print $NF}' | tail -n 1)
      if echo "$RM2" | grep -Eq '([0-9a-f]{2}:){5}[0-9a-f]{2}'; then
        ip neigh replace 10.255.1.2 lladdr "$RM2" dev br50100 nud permanent || true
        bridge fdb replace "$RM2" dev vxlan50100 dst 10.255.1.2 self permanent || true
      fi
    fi
    sleep 1
  done
) >/tmp/l3vni-watchdog.log 2>&1 &

# --- L3VNI watchdog (leaf1) using robust RMAC extraction ---
(
  while true; do
    if ip neigh show dev br50100 2>/dev/null | grep -q "10.255.1.2 FAILED"; then
      RM2=$(vtysh -c "show bgp l2vpn evpn route type 5" 2>/dev/null \
        | tr -d '\r' \
        | sed -n 's/.*Rmac:\([0-9a-f:]\{17\}\).*/\1/p' \
        | tail -n 1)

      if echo "$RM2" | grep -Eq '^([0-9a-f]{2}:){5}[0-9a-f]{2}$'; then
        ip neigh replace 10.255.1.2 lladdr "$RM2" dev br50100 nud permanent || true
        bridge fdb replace "$RM2" dev vxlan50100 dst 10.255.1.2 self permanent || true
      fi
    fi
    sleep 1
  done
) >/tmp/l3vni-watchdog.log 2>&1 &
# --- Ensure L3VNI bridge exists and is in the VRF ---
ip link add br50100 type bridge 2>/dev/null || true
ip link set br50100 up
ip link set vxlan50100 up 2>/dev/null || true
ip link set vxlan50100 master br50100 2>/dev/null || true
ip link set br50100 master vrf-ten1 2>/dev/null || true

# --- Kernel VRF route to remote tenant subnet (leaf2) ---
ip route replace 192.168.102.0/24 via 10.255.1.2 dev br50100 table 10 onlink || true

# --- Ensure L3VNI bridge exists and is in the VRF ---
ip link add br50100 type bridge 2>/dev/null || true
ip link set br50100 up
ip link set vxlan50100 up 2>/dev/null || true
ip link set vxlan50100 master br50100 2>/dev/null || true
ip link set br50100 master vrf-ten1 2>/dev/null || true

# --- Kernel VRF route to remote tenant subnet (leaf2) ---
ip route replace 192.168.102.0/24 via 10.255.1.2 dev br50100 table 10 onlink || true
