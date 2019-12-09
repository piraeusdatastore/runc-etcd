```
/runc-etcd.sh -h
NAME:
  ./runc-etcd.sh - A script to maintain etcd cluster for PX

WARNING:
  1. Only use this script after consulting DaoCloud
  2. PX production requires a 3 or 5 nodes etcd cluster

USAGE:
  bash ./runc-etcd.sh [flags] [ACTION]
  bash ./runc-etcd.sh [ACTION] [flags]

ACTION:
   create   -[rtiecp]   Create a single-node etcd cluster from the local node
   join     -[rtiecp]   Join the local node to an existing etcd cluster
   remove   -[yf]       Remove the local node from the etcd cluster DANGEROUS!
   status               Check cluster health
   printenv -[k]        Display environment variables
   upgrade  -[rt]       Upgrade the local node
   del_pwx  -[ak]       Delete PX keys DANGEROUS!
   hide_init_cluster    Hide "INITIAL_CLUSTER=" from env

flags:
  -r  Docker registry address (default: 'daocloud.io/portworx')
  -t  Image tag (default: 'latest')
  -i  IP (default: '')
  -e  Peer point (default: '19018')
  -c  Client point (default: '19019')
  -k  Key (default: '')
  -a  All (default: false)
  -p  Enforce pull image (default: false)
  -y  Answer yes to confirm (default: false)
  -f  Force (default: false)
  -d  Hide INIT_CLUSTER= from env (default: false)
  -h  show this help (default: false)
```
