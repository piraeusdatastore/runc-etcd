# install etcdctl to local
docker run --rm \
-v $(pwd):/drop daocloud.io/portworx/etcd:v3.4.2 \
cp -vf /usr/local/bin/etcdctl /drop

# backup px-etcd
ETCDCTL_API=3 ./etcdctl \
--endpoints 10.10.176.151:19019 \
snapshot save \
px-etcd-snap1.db

# restore px-etcd
# make sure etcd cluster is single node 
systemctl stop portworx-etcd

NAME=$( cat /opt/pwx-etcd/oci/config.json \
| awk '/"--name",/ {print $1 $2}' \
| sed 's/"//g; s/,/ /' )

echo $NAME

CLUSTER=$( cat /opt/pwx-etcd/oci/config.json \
| grep -wE ETCD_INITIAL_ADVERTISE_PEER_URLS\|ETCD_INITIAL_CLUSTER_TOKEN\|ETCD_INITIAL_CLUSTER \
| sed 's/=/ /; s/,$//; s/"//g; s/^\s*ETCD_/--/; s/_/-/g; ' | tr '[A-Z]' '[a-z]' )

echo $CLUSTER

mv -vf /var/local/pwx-etcd/data /var/local/pwx-etcd/data.old

ETCDCTL_API=3 ./etcdctl \
snapshot restore ${NAME} ${CLUSTER} \
--data-dir /var/local/pwx-etcd/data px-etcd-snap1.db 

 # restart etcd
 systemctl start portworx-etcd; journalctl -fu $_
