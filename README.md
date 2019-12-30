# Etcd by runC

## Overview

This project builds a bash script to containerize etcd by systemd-controlled runc. It provides only the basic initiation, join and removal operations of etcd cluster, and is NOT meant to perform all the functions of etcdctl. 

## Structure

systemd service => runc binary => etcd in container

## Compatibility
* CentOS 7+
* Ubuntu 16+

## Requirements 
* Docker 
* Systemd

## Options
```
NAME:
  runc-etcd/runc-etcd.sh - A script to maintain etcd cluster

WARNING:
  1. Only use this script after consulting Piraeus team
  2. Production requires a 3 or 5 nodes etcd cluster

LICENSE:
    Apache 2.0

USAGE:
  bash runc-etcd/runc-etcd.sh [flags] [ACTION]
  bash runc-etcd/runc-etcd.sh [ACTION] [flags]

ACTION:
   create   -[rtiecp]   Create a single-node etcd cluster from the local node
   join     -[rtiecp]   Join the local node to an existing etcd cluster
   remove   -[yf]       Remove the local node from the etcd cluster DANGEROUS!
   status               Check cluster health
   getconf              Display configuration
   upgrade  -[rt]       Upgrade the local node
   del_keys -[ak]       Delete keys under a key prefix in API 3 DANGEROUS!
   hide_init_cluster    Hide "initial-cluster" from config

flags:
  -r,--registry:  Docker registry address (default: 'quay.io/coreos')
  -t,--tag:  Image tag (default: 'latest')
  -i,--ip:  IP (default: '')
  -e,--peer_port:  Peer point (default: '13378')
  -c,--client_port:  Client point (default: '13379')
  -k,--key:  Key (default: '')
  -a,--all:  All (default: false)
  -p,--pull:  Enforce pull image (default: false)
  -y,--yes:  Answer yes to confirm (default: false)
  -f,--force:  Force (default: false)
  -d,--hide_init_cluster:  Hide INIT_CLUSTER= from env (default: false)
  -x,--debug:  Enable debug output (default: false)
  -h,--help:  show this help (default: false)
```

## Guide
### Download script
```
$ docker run --rm -v $(pwd):/drop piraeusdatastore/runc-etcd

$ ls -1 runc-etcd
Dockerfile
entry.sh
etcd-backup.sh
lib
LICENSE
oci-config.json
README.md
runc
runc-etcd.service
runc-etcd.sh
```
### Initiate cluster by creating first node
```
$ runc-etcd/runc-etcd.sh create -i 192.168.176.151

Create etcd cluster
New node: http://192.168.176.151:13379
Extract OCI rootfs
quay.io/coreos/etcd:latest  mkdir: created directory ‘/opt/runc-etcd’
mkdir: created directory ‘/opt/runc-etcd/oci’
mkdir: created directory ‘/opt/runc-etcd/oci/rootfs’                                                                                             ===================> /opt/runc-etcd/oci/rootfs/
Copy control files
mkdir: created directory ‘/opt/runc-etcd/bin’
mkdir: created directory ‘/var/local/runc-etcd’
mkdir: created directory ‘/var/local/runc-etcd/data’
‘/root/etcd-mac/runc’ -> ‘/opt/runc-etcd/bin/runc’
‘/root/etcd-mac/oci-config.json’ -> ‘/opt/runc-etcd/oci/config.json’
‘/root/etcd-mac/runc-etcd.service’ -> ‘/etc/systemd/system/runc-etcd.service’
Set etcd config file
name:                        k8s-master-1
max-txn-ops:                 1024
data-dir:                    /.etcd/data
advertise-client-urls:       http://192.168.176.151:13379
listen-peer-urls:            http://192.168.176.151:13378
listen-client-urls:          http://192.168.176.151:13379
initial-advertise-peer-urls: http://192.168.176.151:13378
initial-cluster:             k8s-master-1=http://192.168.176.151:13378
initial-cluster-state:       new
initial-cluster-token:       runc-etcd
auto-compaction-rate:        3
quota-backend-bytes:         8589934592
snapshot-count:              5000
enable-v2:                   true
Set OCI args
        "args": [
            "etcd",
            "--config-file", "/etcd.conf.yml"
        ],
Set OCI datadir binding
        {
            "destination": "/.etcd/data",
            "options": [
                    "rbind",
                    "rprivate"
            ],
            "source": "/var/local/runc-etcd/data",
                   "type": "bind"
        }
Set OCI env
        "env": [
            "PATH=/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin",
            "TERM=xterm",
            "GOMAXPROCS=8",
            "ETCDCTL_API=2",
            "ETCDCTL_ENDPOINTS=http://192.168.176.151:13379"
        ],
Start runc-etcd.service
   Loaded: loaded (/etc/systemd/system/runc-etcd.service; enabled; vendor preset: disabled)
   Active: active (running) since Mon 2019-12-30 22:01:29 CST; 5s ago
Check cluster health
etcdctl version: 3.3.8
API version: 2
member 806c9900ca835e67 is healthy: got healthy result from http://192.168.176.151:13379
cluster is healthy
806c9900ca835e67: name=k8s-master-1 peerURLs=http://192.168.176.151:13378 clientURLs=http://192.168.176.151:13379 isLeader=true
For copy & paste:
etcd:http://192.168.176.151:13379
etcd://192.168.176.151:13379
Command reference
Watch log:        journalctl -fu runc-etcd
Watch container:  /opt/runc-etcd/bin/runc list
Check health:     /opt/runc-etcd/bin/runc exec runc-etcd etcdctl cluster-health
Expand cluster:   /root/etcd-mac/runc-etcd.sh join -i 192.168.176.151
```
### Expand cluster by joining other nodes 
```
$ runc-etcd/runc-etcd.sh join -i 192.168.176.151

Extract OCI rootfs
quay.io/coreos/etcd:latest  mkdir: created directory ‘/opt/runc-etcd’
mkdir: created directory ‘/opt/runc-etcd/oci’
mkdir: created directory ‘/opt/runc-etcd/oci/rootfs’                                                                                             ===================> /opt/runc-etcd/oci/rootfs/
Check http://192.168.176.151:13379/health
member 806c9900ca835e67 is healthy: got healthy result from http://192.168.176.151:13379
cluster is healthy
Check member list
Join etcd cluster
New node: http://192.168.176.152:13379
Register node 192.168.176.152 to etcd cluster
Added member named k8s-master-2 with ID 27af6ee79d1416a6 to cluster

ETCD_NAME="k8s-master-2"
ETCD_INITIAL_CLUSTER="k8s-master-2=http://192.168.176.152:13378,k8s-master-1=http://192.168.176.151:13378"
ETCD_INITIAL_CLUSTER_STATE="existing"

Copy control files
mkdir: created directory ‘/opt/runc-etcd/bin’
mkdir: created directory ‘/var/local/runc-etcd’
mkdir: created directory ‘/var/local/runc-etcd/data’
‘/root/etcd-mac/runc’ -> ‘/opt/runc-etcd/bin/runc’
‘/root/etcd-mac/oci-config.json’ -> ‘/opt/runc-etcd/oci/config.json’
‘/root/etcd-mac/runc-etcd.service’ -> ‘/etc/systemd/system/runc-etcd.service’
Set etcd config file
name:                        k8s-master-2
max-txn-ops:                 1024
data-dir:                    /.etcd/data
advertise-client-urls:       http://192.168.176.152:13379
listen-peer-urls:            http://192.168.176.152:13378
listen-client-urls:          http://192.168.176.152:13379
initial-advertise-peer-urls: http://192.168.176.152:13378
initial-cluster:             k8s-master-1=http://192.168.176.151:13378,k8s-master-2=http://192.168.176.152:13378
initial-cluster-state:       existing
initial-cluster-token:       runc-etcd
auto-compaction-rate:        3
quota-backend-bytes:         8589934592
snapshot-count:              5000
enable-v2:                   true
Set OCI args
        "args": [
            "etcd",
            "--config-file", "/etcd.conf.yml"
        ],
Set OCI datadir binding
        {
            "destination": "/.etcd/data",
            "options": [
                    "rbind",
                    "rprivate"
            ],
            "source": "/var/local/runc-etcd/data",
                   "type": "bind"
        }
Set OCI env
        "env": [
            "PATH=/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin",
            "TERM=xterm",
            "GOMAXPROCS=8",
            "ETCDCTL_API=2",
            "ETCDCTL_ENDPOINTS=http://192.168.176.152:13379"
        ],
Start runc-etcd.service
   Loaded: loaded (/etc/systemd/system/runc-etcd.service; enabled; vendor preset: disabled)
   Active: active (running) since Mon 2019-12-30 22:03:19 CST; 5s ago
Check cluster health
etcdctl version: 3.3.8
API version: 2
member 27af6ee79d1416a6 is healthy: got healthy result from http://192.168.176.152:13379
member 806c9900ca835e67 is healthy: got healthy result from http://192.168.176.151:13379
cluster is healthy
27af6ee79d1416a6: name=k8s-master-2 peerURLs=http://192.168.176.152:13378 clientURLs=http://192.168.176.152:13379 isLeader=false
806c9900ca835e67: name=k8s-master-1 peerURLs=http://192.168.176.151:13378 clientURLs=http://192.168.176.151:13379 isLeader=true
For copy & paste:
etcd:http://192.168.176.152:13379,etcd:http://192.168.176.151:13379
etcd://192.168.176.152:13379,192.168.176.151:13379
```  
### Remove a node from cluster
```
$ runc-etcd/runc-etcd.sh remove

ATTENTION: Will irreversibly delete all etcd data on this node!
Continue (yes/no)? yes
Yes, continue
Check local member status
27af6ee79d1416a6: name=k8s-master-2 peerURLs=http://192.168.176.152:13378 clientURLs=http://192.168.176.152:13379 isLeader=false 79967816173ba114: name=k8s-master-3 peerURLs=http://192.168.176.153:13378 clientURLs=http://192.168.176.153:13379 isLeader=false 806c9900ca835e67: name=k8s-master-1 peerURLs=http://192.168.176.151:13378 clientURLs=http://192.168.176.151:13379 isLeader=true
Deregister local member from etcd cluster
Removed member 27af6ee79d1416a6 from cluster
WARN: Stop and remove runc-etcd.service
removed ‘/etc/systemd/system/runc-etcd.service’
WARN: Backup config and data to /var/runc-etcd-backup
mkdir: created directory ‘/var/local/runc-etcd-backup/2019-12-30_22-05-57’
‘/opt/runc-etcd/oci/rootfs/etcd.conf.yml’ -> ‘/var/local/runc-etcd-backup/2019-12-30_22-05-57/etcd.conf.yml’
‘/opt/runc-etcd/oci/config.json’ -> ‘/var/local/runc-etcd-backup/2019-12-30_22-05-57/config.json’
‘/var/local/runc-etcd/data’ -> ‘/var/local/runc-etcd-backup/2019-12-30_22-05-57/data’
WARN: Remove files
removed directory: ‘/opt/runc-etcd/’
removed directory: ‘/var/local/runc-etcd’

```

### Check configuration
```
$ runc-etcd/runc-etcd.sh getconf

Env:
PATH=/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin
TERM=xterm
GOMAXPROCS=8
ETCDCTL_API=2
ETCDCTL_ENDPOINTS=http://192.168.176.151:13379
HOME=/root
Config file:
name:                        k8s-master-1
max-txn-ops:                 1024
data-dir:                    /.etcd/data
advertise-client-urls:       http://192.168.176.151:13379
listen-peer-urls:            http://192.168.176.151:13378
listen-client-urls:          http://192.168.176.151:13379
initial-advertise-peer-urls: http://192.168.176.151:13378
initial-cluster:             k8s-master-1=http://192.168.176.151:13378
initial-cluster-state:       new
initial-cluster-token:       runc-etcd
auto-compaction-rate:        3
quota-backend-bytes:         8589934592
snapshot-count:              5000
enable-v2:                   true
Data dir:
        {
            "destination": "/.etcd/data",
            "options": [
                    "rbind",
                    "rprivate"
            ],
            "source": "/var/local/runc-etcd/data",
                   "type": "bind"
        }
```

### Check cluster status
```
$ runc-etcd/runc-etcd.sh status

Check cluster health
etcdctl version: 3.3.8
API version: 2
member 27af6ee79d1416a6 is healthy: got healthy result from http://192.168.176.152:13379
member 79967816173ba114 is healthy: got healthy result from http://192.168.176.153:13379
member 806c9900ca835e67 is healthy: got healthy result from http://192.168.176.151:13379
cluster is healthy
27af6ee79d1416a6: name=k8s-master-2 peerURLs=http://192.168.176.152:13378 clientURLs=http://192.168.176.152:13379 isLeader=false
79967816173ba114: name=k8s-master-3 peerURLs=http://192.168.176.153:13378 clientURLs=http://192.168.176.153:13379 isLeader=false
806c9900ca835e67: name=k8s-master-1 peerURLs=http://192.168.176.151:13378 clientURLs=http://192.168.176.151:13379 isLeader=true
For copy & paste:
etcd:http://192.168.176.152:13379,etcd:http://192.168.176.153:13379,etcd:http://192.168.176.151:13379
etcd://192.168.176.152:13379,192.168.176.153:13379,192.168.176.151:13379
```

### Upgrade node
```
$  runc-etcd/runc-etcd.sh upgrade -t v3.4.1
Upgrade etcd version to
quay.io/coreos/etcd:v3.4.1
Stop runc-etcd.service
Backup oci files
‘/opt/runc-etcd/oci/rootfs’ -> ‘/opt/runc-etcd/oci/rootfs_2019-12-30_22-06-43’
mkdir: created directory ‘/opt/runc-etcd/oci/rootfs’
Extract OCI rootfs
v3.4.1: Pulling from coreos/etcd
39fafc05754f: Already exists
518e528b37dd: Already exists
31f6c178d88f: Already exists
c3c3852c8923: Already exists
e730b3acbb4e: Already exists
18e1dd020b92: Already exists
Digest: sha256:49d3d4a81e0d030d3f689e7167f23e120abf955f7d08dbedf3ea246485acee9f
Status: Downloaded newer image for quay.io/coreos/etcd:v3.4.1
quay.io/coreos/etcd:v3.4.1 =========================================> /opt/runc-etcd/oci/rootfs/
Copy etcd.conf.yml
‘/opt/runc-etcd/oci/rootfs_2019-12-30_22-06-43/etcd.conf.yml’ -> ‘/opt/runc-etcd/oci/rootfs/etcd.conf.yml’
Start runc-etcd.service
   Loaded: loaded (/etc/systemd/system/runc-etcd.service; enabled; vendor preset: disabled)
   Active: active (running) since Mon 2019-12-30 22:06:51 CST; 5s ago
Check cluster health
etcdctl version: 3.4.1
API version: 2
member 79967816173ba114 is healthy: got healthy result from http://192.168.176.153:13379
member 806c9900ca835e67 is healthy: got healthy result from http://192.168.176.151:13379
cluster is healthy
79967816173ba114: name=k8s-master-3 peerURLs=http://192.168.176.153:13378 clientURLs=http://192.168.176.153:13379 isLeader=true
806c9900ca835e67: name=k8s-master-1 peerURLs=http://192.168.176.151:13378 clientURLs=http://192.168.176.151:13379 isLeader=false
For copy & paste:
etcd:http://192.168.176.153:13379,etcd:http://192.168.176.151:13379
etcd://192.168.176.153:13379,192.168.176.151:13379
```
