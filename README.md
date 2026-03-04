# EVPN/VXLAN Leaf-Spine Fabric (FRR + Containerlab) - Type-2 / Type-5, L3VNI, BFD, Failure Testing

This project implements a fully functional EVPN/VXLAN-based leaf-spine data center fabric using FRRouting (FRR) inside Containerlab. The lab demonstrates an industry-aligned control-plane and data-plane architecture featuring eBGP underlay, BGP EVPN overlay, VXLAN encapsulation, L2VNI and L3VNI segmentation, BFD-based fast failure detection, and tenant VRF-based inter-subnet routing using EVPN Type-5 routes.

The goal of this implementation is to model modern data center networking principles in a reproducible, automation-friendly lab environment while validating operational behaviors such as convergence, neighbor resolution, route installation, and encapsulation correctness.

This repository contains a reproducible EVPN/VXLAN leaf-spine fabric lab implemented with **Containerlab** and **FRRouting (FRR)** containers. The lab demonstrates modern data-center routing constructs switching/routing, including:

- eBGP underlay in a leaf-spine topology
- BGP EVPN control-plane
- VXLAN overlay with:
  - **EVPN Type-2** (MAC/IP advertisement)
  - **EVPN Type-5** (IP Prefix route advertisement for inter-subnet routing via L3VNI)
- Tenant VRF with L3VNI and RMAC handling
- **BFD** for fast failure detection
- Repeatable failure testing and convergence measurement

---

## Architectural Context and Objective

Traditional data center networks relied on Layer 2 VLAN-based designs with spanning tree, resulting in scalability limits, suboptimal forwarding paths, and slow convergence. Modern architectures use a **leaf-spine topology** with Layer 3 routing in the underlay and VXLAN overlays to achieve horizontal scalability, multipath utilization, and tenant isolation.

The objective of this project is to:

1. Build a scalable Layer 3 leaf-spine fabric.
2. Use BGP EVPN as a control plane for VXLAN.
3. Support inter-subnet routing across tenants using L3VNI.
4. Validate fast failure detection and convergence using BFD.
5. Analyze kernel-level dataplane behavior in a Linux-based implementation.
6. Troubleshoot real-world operational edge cases (neighbor resolution failures, VRF route table inconsistencies, RMAC programming issues).

This implementation closely models how enterprise and cloud providers deploy modern fabrics in production environments.

---

## Core Technologies and Concepts

### Leaf-Spine Topology

A leaf-spine topology is a Clos-based architecture where:

- **Spines** act as high-speed transit switches.
- **Leaves** connect to servers and spines.
- Every leaf connects to every spine.
- There is no leaf-to-leaf or spine-to-spine connectivity.

This design provides:
- Predictable latency
- Equal-cost multipath (ECMP)
- Horizontal scalability
- Deterministic failure domains

In this lab:
- Two spines
- Two leaves
- Hosts attached to leaves
- Full-mesh leaf-to-spine connectivity via eBGP

---

### Underlay Network (eBGP IPv4 Unicast)

The underlay is the routed IP fabric providing transport between VTEPs (VXLAN Tunnel Endpoints).

Key characteristics:
- eBGP between leaf and spine nodes
- Loopback addresses used as VTEP source addresses
- ECMP load balancing across spine uplinks

The underlay ensures:
- Reachability between VTEP loopbacks
- Stability and scalability without Layer 2 loops
- Fast convergence when paired with BFD

---

## Topology

- **Spines:** sp1, sp2  
- **Leaves:** leaf1, leaf2  
- **Hosts:** h1, h2 

High-level links:
- sp1 ↔ leaf1, sp1 ↔ leaf2
- sp2 ↔ leaf1, sp2 ↔ leaf2
- leaf1 ↔ h1
- leaf2 ↔ h2

---

### VXLAN (Virtual Extensible LAN)

VXLAN is an encapsulation protocol (UDP 4789) used to extend Layer 2 domains across Layer 3 networks.

Key properties:
- 24-bit VNI (VXLAN Network Identifier)
- Supports 16 million segments
- Encapsulates Layer 2 frames inside UDP

VXLAN decouples:
- Overlay logical topology
- Underlay transport fabric

In this lab:
- L2VNI is used for bridging.
- L3VNI is used for inter-subnet routing.

---

### BGP EVPN (Ethernet VPN)

EVPN is the control plane for VXLAN. Instead of relying on flood-and-learn behavior, EVPN uses BGP to advertise MAC and IP information.

Key route types used:

#### Type-2 (MAC/IP Advertisement Route)
Advertises:
- MAC address
- Optional IP address
- VNI association

Purpose:
- Distributed MAC learning
- ARP suppression
- Eliminates unknown unicast flooding

#### Type-5 (IP Prefix Route)
Advertises:
- IP prefix (subnet)
- Associated VNI
- Router MAC (RMAC)

Purpose:
- Enables inter-subnet routing using L3VNI
- Avoids leaking subnets into the underlay
- Provides scalable tenant routing

Type-5 routes allow tenant subnet routing without redistributing routes into the underlay routing table.

---

### VRF (Virtual Routing and Forwarding)

A VRF creates isolated routing tables within a device.

In this lab:
- `vrf-ten1` represents a tenant routing domain.
- Linux kernel table 10 is associated with the VRF.
- Each leaf performs distributed routing for its locally attached subnet.

VRFs enable:
- Multi-tenancy
- Overlapping IP support
- Isolation between routing domains

---

### L3VNI (Layer 3 VXLAN Network Identifier)

L3VNI extends VXLAN from pure Layer 2 bridging to routed inter-subnet forwarding.

Workflow:
1. Host sends packet to default gateway (leaf SVI).
2. Leaf routes packet within VRF.
3. Packet is encapsulated into L3VNI.
4. Remote leaf decapsulates and forwards locally.

L3VNI allows distributed anycast gateway behavior in scalable fabrics.

---

### RMAC (Router MAC)

RMAC is advertised in EVPN Type-5 routes and represents the MAC address used for routed VXLAN encapsulation.

In Linux-based EVPN implementations:
- RMAC must be properly programmed in:
  - `ip neigh`
  - `bridge fdb`

Incorrect RMAC programming leads to blackholing or packet loss, which was observed and resolved during this project.

---

### BFD (Bidirectional Forwarding Detection)

BFD provides rapid failure detection independent of routing protocol timers.

Characteristics:
- Millisecond-level detection
- Multiplier-based detection logic
- Works alongside BGP

In this project:
- BFD sessions monitor leaf-spine links.
- Failure injection tests validate detection and convergence.

---


## Repository Layout (What each file does)

- `vxlan-static.clab.yml`
  - Containerlab topology definition for the full fabric.
  - Binds FRR configuration into each network node.
  - Runs node init scripts at boot to create Linux dataplane objects and apply host IPs/routes.

- `configs/daemons`
  - Enables required FRR daemons (notably `bgpd`, `zebra`, and `bfdd` where needed).

- `configs/*/frr.conf` (sp1, sp2, leaf1, leaf2)
  - FRR integrated configuration per device.
  - Implements underlay eBGP, EVPN address-family, tenant VRF and Type-5 advertisement/import.

- `configs/vtysh.conf`
  - Enables non-interactive `vtysh` usage (scripting/exec).

- `configs/leaf1/init.sh`, `configs/leaf2/init.sh`
  - Creates/ensures Linux dataplane objects (VRF, bridges, VXLAN interfaces).
  - Ensures VRF kernel routing table is correct (table 10).
  - Includes operational “repair” logic used to stabilize L3VNI behavior in containerized Linux dataplane environments.

- `configs/h1/init.sh`, `configs/h2/init.sh`
  - Applies host IP configuration and default routes automatically on deploy (no manual host setup required).

- (Optional artifacts you may generate)
  - `vxlan-static.svg` / `vxlan-static.png`: topology diagram created from `containerlab graph`.

---

## Operational Workflow

The full packet journey (h1 → h2):

1. h1 sends packet to default gateway.
2. Leaf1 routes packet inside `vrf-ten1`.
3. Leaf1 finds Type-5 route for remote subnet.
4. Leaf1 encapsulates packet into VXLAN (L3VNI).
5. Underlay forwards encapsulated packet via ECMP.
6. Leaf2 decapsulates packet.
7. Leaf2 forwards packet to h2.

Control-plane advertisements (Type-2, Type-5) ensure correct forwarding decisions without flooding.

---


## Installation

### 1) Install Docker
Follow the official Docker installation method for your platform. 
```bash
docker version
docker ps
````

### 2) Install Containerlab

```bash
containerlab version
```

### 3) (Optional) Install Graphviz for diagrams

```bash
sudo apt-get update
sudo apt-get install -y graphviz
```

---

## Quickstart

<!-- ### 1) Clone repo

```bash
git clone <your-github-repo-url>
cd <repo-directory> -->
```

### 2) Deploy the lab

```bash
sudo containerlab deploy -t vxlan-static.clab.yml
```

### 3) Validate host-to-host reachability

```bash
sudo containerlab exec -t vxlan-static.clab.yml --name vxlan-static --label clab-node-name=h1 --cmd "ping -c 3 192.168.102.12"
```

Expected: 0% packet loss.

### 4) Destroy the lab

```bash
sudo containerlab destroy -t vxlan-static.clab.yml
```

---

## Diagram (GUI)

```bash
sudo containerlab graph -t vxlan-static.clab.yml 
```

---

## Interacting with Devices

### Open an interactive FRR CLI (vtysh)

```bash
sudo docker exec -it clab-vxlan-static-leaf1 vtysh
sudo docker exec -it clab-vxlan-static-leaf2 vtysh
sudo docker exec -it clab-vxlan-static-sp1 vtysh
sudo docker exec -it clab-vxlan-static-sp2 vtysh
```

### Run one-off commands inside nodes (recommended for automation)

Use `containerlab exec` with `--cmd`:

```bash
sudo containerlab exec -t vxlan-static.clab.yml --name vxlan-static --label clab-node-name=leaf1 --cmd 'vtysh -c "show ip bgp summary"'
```

Important note: `containerlab exec --cmd` does not invoke a shell. If you need pipes (`|`), `||`, redirects, etc., wrap in `sh -c`:

```bash
sudo containerlab exec -t vxlan-static.clab.yml --name vxlan-static --label clab-node-name=leaf1 --cmd 'sh -c "ip route show table 10 | head -n 20"'
```

---

## Verification Checklist

### A) Underlay (eBGP IPv4 unicast)

**BGP adjacency state (leaf and spine):**

```bash
sudo docker exec -it clab-vxlan-static-leaf1 vtysh -c "show ip bgp summary"
sudo docker exec -it clab-vxlan-static-leaf2 vtysh -c "show ip bgp summary"
sudo docker exec -it clab-vxlan-static-sp1  vtysh -c "show ip bgp summary"
sudo docker exec -it clab-vxlan-static-sp2  vtysh -c "show ip bgp summary"
```

**Underlay reachability to loopbacks (source from loopback):**

```bash
sudo docker exec -it clab-vxlan-static-leaf1 ping -c 3 -I 10.255.1.1 10.255.1.2
```

*Used `-I` because loopback reachability tests are sensitive to source selection.*

---

### B) BFD

**BFD peer status and timers:**

```bash
sudo docker exec -it clab-vxlan-static-leaf1 vtysh -c "show bfd peers"
```

---

### C) EVPN control-plane

**EVPN session status:**

```bash
sudo docker exec -it clab-vxlan-static-leaf1 vtysh -c "show bgp l2vpn evpn summary"
sudo docker exec -it clab-vxlan-static-leaf2 vtysh -c "show bgp l2vpn evpn summary"
```

**EVPN Type-2 (MAC/IP):**

```bash
sudo docker exec -it clab-vxlan-static-leaf1 vtysh -c "show bgp l2vpn evpn route type 2"
```

**EVPN Type-5 (IP Prefix / L3VNI):**

```bash
sudo docker exec -it clab-vxlan-static-leaf1 vtysh -c "show bgp l2vpn evpn route type 5"
```

---

### D) Tenant VRF and kernel dataplane

**FRR view (VRF routes):**

```bash
sudo docker exec -it clab-vxlan-static-leaf1 vtysh -c "show ip route vrf vrf-ten1"
sudo docker exec -it clab-vxlan-static-leaf2 vtysh -c "show ip route vrf vrf-ten1"
```

**VRF VNI and RMAC:**

```bash
sudo docker exec -it clab-vxlan-static-leaf1 vtysh -c "show vrf vni"
sudo docker exec -it clab-vxlan-static-leaf2 vtysh -c "show vrf vni"
```

**Kernel VRF routing table (table 10):**

```bash
sudo containerlab exec -t vxlan-static.clab.yml --name vxlan-static --label clab-node-name=leaf1 --cmd "ip route show table 10"
```

**Flush route cache when validating route decisions:**

```bash
sudo containerlab exec -t vxlan-static.clab.yml --name vxlan-static --label clab-node-name=leaf1 --cmd "ip route flush cache"
```

---

### E) VXLAN interface + bridge programming

**VXLAN interface counters:**

```bash
sudo docker exec -it clab-vxlan-static-leaf1 sh -c "ip -s link show vxlan50100 | sed -n '1,25p'"
```

**FDB entries (L3VNI correctness depends on these):**

```bash
sudo docker exec -it clab-vxlan-static-leaf1 bridge fdb show dev vxlan50100 | head -n 120
sudo docker exec -it clab-vxlan-static-leaf2 bridge fdb show dev vxlan50100 | head -n 120
```

**Neighbor resolution for L3VNI VTEP next-hop:**

```bash
sudo docker exec -it clab-vxlan-static-leaf1 ip neigh show dev br50100
sudo docker exec -it clab-vxlan-static-leaf2 ip neigh show dev br50100
```

---

## Failure Testing and Convergence Measurement

### Dual-uplink failure on leaf1 (guaranteed impact)

Traffic probe:

```bash
sudo docker exec -it clab-vxlan-static-h1 ping -i 0.2 -c 125 192.168.102.12
```

Failure injection:

```bash
date +"DOWN start  %H:%M:%S.%3N"
sudo docker exec -it clab-vxlan-static-leaf1 ip link set eth1 down
sudo docker exec -it clab-vxlan-static-leaf1 ip link set eth2 down
date +"DOWN done   %H:%M:%S.%3N"

sleep 2

date +"UP start    %H:%M:%S.%3N"
sudo docker exec -it clab-vxlan-static-leaf1 ip link set eth1 up
sudo docker exec -it clab-vxlan-static-leaf1 ip link set eth2 up
date +"UP done     %H:%M:%S.%3N"
```

Post-check:

```bash
sudo docker exec -it clab-vxlan-static-leaf1 vtysh -c "show bfd peers"
sudo docker exec -it clab-vxlan-static-leaf1 vtysh -c "show ip bgp summary"
sudo docker exec -it clab-vxlan-static-leaf1 ip neigh show dev br50100
```

Measurement approach:

* Loss window ≈ `lost_packets × probe_interval`
* With 0.2s interval, each lost ping ≈ 200ms.

---

## Challenges Encountered (and how they were resolved)

### 1) `containerlab exec` syntax differences

Observed:

* `containerlab exec` required `--cmd`, and the selector needed correct lab name + label filters.

* Use:

  ```bash
  sudo containerlab exec -t <topo.yml> --name <labname> --label clab-node-name=<node> --cmd "<command>"
  ```
* Verify usage with:

  ```bash
  containerlab exec --help
  ```

### 2) Ping from loopbacks failed unless source was specified

Observed:

* Loopback-to-loopback pings failed until source IP was forced.
  Resolution:
* Use `ping -I <loopback-ip> <remote-loopback>`.

### 3) VRF route lookups appearing to use Docker `eth0` (misleading)

Observed:

* `ip vrf exec ... ip route get ...` sometimes returned cached/incorrect decisions, and table 10 was missing remote prefixes at times.
  
* Confirm kernel VRF routing table:

  ```bash
  ip route show table 10
  ```
* Flush cache when validating:

  ```bash
  ip route flush cache
  ```
* Ensure VRF remote prefix is installed in table 10 and that `br50100` exists/attached to VRF.

---

## Command Reference 

### Containerlab lifecycle

```bash
sudo containerlab deploy -t hello.clab.yml
sudo containerlab destroy -t underlay.clab.yml
sudo containerlab deploy -t underlay.clab.yml
sudo containerlab destroy -t vxlan-static.clab.yml
sudo containerlab deploy  -t vxlan-static.clab.yml
sudo containerlab inspect -t vxlan-static.clab.yml --name vxlan-static
containerlab exec --help
```

### Containerlab exec patterns

```bash
sudo containerlab exec -t hello.clab.yml --name hello --label clab-node-name=n1 --cmd "ping -c 3 n2"
sudo containerlab exec -t underlay.clab.yml --name underlay --label clab-node-name=leaf1 --cmd 'vtysh -c "show ip bgp summary"'
sudo containerlab exec -t vxlan-static.clab.yml --name vxlan-static --label clab-node-name=h1 --cmd "ping -c 3 192.168.102.12"
sudo containerlab exec -t vxlan-static.clab.yml --name vxlan-static --label clab-node-name=leaf1 --cmd 'sh -c "ip link show br50100 || true"'
```

### Docker exec (interactive and non-TTY parsing)

```bash
sudo docker exec -it clab-vxlan-static-leaf1 vtysh -c "show ip bgp summary"
sudo docker exec -it clab-vxlan-static-leaf1 vtysh -c "show bgp l2vpn evpn summary"
sudo docker exec -it clab-vxlan-static-leaf1 vtysh -c "show bgp l2vpn evpn route type 2"
sudo docker exec -it clab-vxlan-static-leaf1 vtysh -c "show bgp l2vpn evpn route type 5"
sudo docker exec -it clab-vxlan-static-leaf1 vtysh -c "show vrf vni"
sudo docker exec -it clab-vxlan-static-leaf1 vtysh -c "show bfd peers"

# Robust parsing (no TTY):
sudo docker exec -i clab-vxlan-static-leaf1 vtysh -c "show bgp l2vpn evpn route type 5"
```

### Linux dataplane inspection

```bash
sudo docker exec -it clab-vxlan-static-leaf1 ip -br addr    # note: some BusyBox environments lack -br
sudo docker exec -it clab-vxlan-static-leaf1 ip addr show
sudo docker exec -it clab-vxlan-static-leaf1 ip link show
sudo docker exec -it clab-vxlan-static-leaf1 ip -s link show vxlan50100
sudo docker exec -it clab-vxlan-static-leaf1 ip neigh show dev br50100
sudo docker exec -it clab-vxlan-static-leaf1 bridge fdb show dev vxlan50100
sudo docker exec -it clab-vxlan-static-leaf1 bridge link show
sudo docker exec -it clab-vxlan-static-leaf1 ip rule show
sudo docker exec -it clab-vxlan-static-leaf1 ip route show table 10
sudo docker exec -it clab-vxlan-static-leaf1 ip route flush cache
sudo docker exec -it clab-vxlan-static-leaf1 ip vrf exec vrf-ten1 ping -c 3 -I 192.168.101.1 192.168.102.12
```

### Host/endpoint checks

```bash
sudo docker exec -it clab-vxlan-static-h1 ip addr show dev eth1
sudo docker exec -it clab-vxlan-static-h1 ip route show
sudo docker exec -it clab-vxlan-static-h1 ping -c 2 192.168.101.1
sudo docker exec -it clab-vxlan-static-h1 ping -c 3 192.168.102.12

sudo docker exec -it clab-vxlan-static-h2 ip addr show dev eth1
sudo docker exec -it clab-vxlan-static-h2 ip route show
sudo docker exec -it clab-vxlan-static-h2 ping -c 2 192.168.102.1
```

### Failure injection

```bash
sudo docker exec -it clab-vxlan-static-leaf1 ip link set eth1 down
sudo docker exec -it clab-vxlan-static-leaf1 ip link set eth1 up
sudo docker exec -it clab-vxlan-static-leaf1 ip link set eth2 down
sudo docker exec -it clab-vxlan-static-leaf1 ip link set eth2 up
date +"%H:%M:%S.%3N"
```

### Diagram generation

```bash
sudo containerlab graph -t vxlan-static.clab.yml | dot -Tsvg > vxlan-static.svg
explorer.exe vxlan-static.svg
```

---

## Performance and Convergence Analysis

Failure injection demonstrated:

- BFD detects link failure within configured multiplier × interval.
- BGP session transitions occur rapidly.
- EVPN updates withdraw and re-install routes.
- Host-level ping loss corresponds to convergence window.

This confirms control-plane stability and proper underlay/overlay integration.

---

## Broader Impact and Learning Outcomes

This project validates understanding of:

- Modern DC routing paradigms
- Overlay/underlay separation
- Control-plane driven MAC learning
- Scalable L3 fabric design
- Linux dataplane behavior in EVPN
- Operational troubleshooting methodology

It bridges theory and implementation.

---

## References 

* **EVPN/VXLAN Spine-Leaf Configuration**

  * [https://www.youtube.com/watch?v=cE4Q6MjNJnk](https://www.youtube.com/watch?v=cE4Q6MjNJnk) : Step-by-step EVPN/VXLAN config in a spine-leaf. 

* **Cisco VXLAN EVPN MP-BGP Config Walkthrough**

  * [https://www.youtube.com/watch?v=VKRVvfMJ4PY](https://www.youtube.com/watch?v=VKRVvfMJ4PY) : MP-BGP EVPN overview, L2/L3 VNI config examples.

---

### **L3VNI (Layer 3 VXLAN Network Identifier)**

* **MP-BGP EVPN L3VNI Lesson (Article)**

  * [https://networklessons.com/vxlan/vxlan-mp-bgp-evpn-l3-vni](https://networklessons.com/vxlan/vxlan-mp-bgp-evpn-l3-vni) : Deep dive into L3VNIs, inter-VNI routing, and EVPN behavior. 

*  **Jeremy’s IT Lab — Spine-Leaf & LAN architectures**

  * [https://www.youtube.com/watch?v=PvyEcLhmNBk](https://www.youtube.com/watch?v=PvyEcLhmNBk) : CCNA level LAN Architectures including spine-leaf. 

---

## Conclusion

This project successfully implements a production-aligned EVPN/VXLAN fabric using open-source tools. It demonstrates a deep understanding of:

- Distributed routing
- Overlay networking
- Failure convergence
- Linux-based control/data-plane interaction

The architecture and troubleshooting approach reflect real-world operational challenges in modern data center networks. The lab is portable, reproducible, and suitable for advanced network engineering portfolios.

It serves as both a technical validation and a practical learning platform for scalable network design.
