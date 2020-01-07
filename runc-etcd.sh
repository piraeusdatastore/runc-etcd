#!/bin/bash
#######################################################
## Author: alex.zheng@daocloud.io                    ##
## Disclaimer: Only Use under DaoCloud's supervision ##
#######################################################

# Must run in the script directoy 
WORK_DIR="$( pwd )"
SCRIPT_DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" >/dev/null && pwd )"
TIMESTAMP=$( date +%Y-%m-%d_%H-%M-%S )

source ${SCRIPT_DIR}/lib/bash_colors.sh
source ${SCRIPT_DIR}/lib/confirm.sh
source ${SCRIPT_DIR}/lib/shflags.sh 

DEFINE_string 'prefix' 'runc' 'Service name prefix: xxxx-etcd' 'p'
DEFINE_string 'registry' 'quay.io/coreos' 'Docker registry address' 'r'
DEFINE_string 'tag' 'latest' 'Image tag' 't'
DEFINE_string 'ip' '' 'IP' 'i'
DEFINE_string 'peer_port' '13378' 'Peer point' 'e'
DEFINE_string 'client_port' '13379' 'Client point' 'c'
DEFINE_string 'snapshot' '' 'Snapshot dir' 's'
DEFINE_string 'key' '' 'Key' 'k'
DEFINE_boolean 'all' false 'All' 'a'
DEFINE_boolean 'pull' false 'Enforce pull image' 'l'
DEFINE_boolean 'yes' false 'Answer "yes" to confirm' 'y'
DEFINE_boolean 'force' false 'Force' 'f'
DEFINE_boolean 'hide_init' false 'Hide "INIT_CLUSTER" from config' 'd'
DEFINE_boolean 'debug' false 'Enable debug output' 'x'

FLAGS_HELP=$( cat <<EOF
NAME:
  runc-etcd.sh - A script to maintain etcd cluster

$( clr_brown WARNING ):
  1. Only use this script after consulting Piraeus team
  2. Production requires a 3 or 5 nodes etcd cluster
  3. Backup/restore only works for v3 keys

LICENSE:
    Apache 2.0

USAGE:
  runc-etcd.sh [flags] [ACTION]
  runc-etcd.sh [ACTION] [flags]

ACTION:
   create    -[prtiecl] Create a single-node cluster from the local node
   join      -[prtiecl] Join the local node to an existing cluster
   remove    -[pyf]     Remove the local node from the cluster $( clr_red DANGEROUS! )
   status    -[p]       Check cluster health
   getconf   -[p]       Display configuration
   upgrade   -[prt]     Upgrade the local node
   backup    -[pf]      Backup conf and keys (v3 only!)
   restore   -[psyf]    Restore node with v3 snapshot
   del_keys  -[pak]     Delete keys under a key prefix in API 3 $( clr_red DANGEROUS! )
   hide_init -[p]       Hide "initial-cluster" from config       
EOF
)  

# Default parameters
: ${IMAGE:=etcd}
: ${NODE_NAME:=${HOSTNAME}}

# Parse cmdline arguments
_main() {
    # Parse args
    if [ $# -eq 0 ]; then
        clr_red "ERROR: Missing action."
        flags_help
        exit 1
    elif [ $# -gt 1 ]; then
        clr_red "ERROR: Only one action is allowed."
        flags_help
        exit 1
    fi
    ACTION=$1 
    UPGRADE=false

    # Parse flags
    [ ${FLAGS_debug} -eq ${FLAGS_TRUE} ] && set -x

    if [ -z "${FLAGS_registry}" ]; then
        IMAGE_ADDR=${IMAGE}:${FLAGS_tag}
    else
        IMAGE_ADDR=${FLAGS_registry}/${IMAGE}:${FLAGS_tag}
    fi     
    PEER_PORT=${FLAGS_peer_port}
    CLIENT_PORT=${FLAGS_client_port}

    BASE_NAME=${FLAGS_prefix}-etcd
    OPT_DIR=/opt/${BASE_NAME}
    OCI_DIR=${OPT_DIR}/oci
    BIN_DIR=${OPT_DIR}/bin
    ROOTFS_DIR=${OCI_DIR}/rootfs
    YML_FILE=${ROOTFS_DIR}/${BASE_NAME}.yml
    VAR_DIR=/var/local/${BASE_NAME}
    BACKUP_ROOT_DIR=/var/local/${BASE_NAME}_backup
    BACKUP_DIR=${BACKUP_ROOT_DIR}/${TIMESTAMP}

    # Parse actions 
    case ${ACTION} in
        create     )        _create     ;;
        join       )        _join       ;;
        remove     )        _remove     ;;
        status     )        _status     ;;
        upgrade    )        _upgrade    ;;
        getconf    )        _getconf    ;;
        backup     )        _backup     ;;
        restore    )        _restore    ;;
        del_keys   )        _del_keys   ;;
        hide_init  )        _hide_init  ;;   
        help       )        flags_help  ;;
        *          )
            clr_red "ERROR: Invalid action" >&2
            flags_help
            exit 1
    esac
}

_etcdctl2() {
    # etcdctl v2 outside container
    ETCDCTL_API=2 ${ROOTFS_DIR}/usr/local/bin/etcdctl $@
}

__etcdctl2() {
    # etcdctl v2 inside container
    ${BIN_DIR}/runc exec -e ETCDCTL_API=2 ${BASE_NAME} etcdctl $@
}

__etcdctl3() {
    # etcdctl v3 inside container
    ${BIN_DIR}/runc exec -e ETCDCTL_API=3 ${BASE_NAME} etcdctl $@
}

_create() { 
    [ -z ${FLAGS_ip} ] && clr_red "ERROR: Must provide an IP or Hostname by --ip" && exit 1

    # Check if IP is present on the local node 
    if ip a | grep -q "inet ${FLAGS_ip}\/"; then
        HOST_IP=${FLAGS_ip}
    else
        clr_red "ERROR: ${FLAGS_ip} is not present on this host"
        exit 1
    fi
    
    # Create cluster
    clr_green "Create etcd cluster"
    echo New node: http://${HOST_IP}:${CLIENT_PORT}
    EXISTING_CLUSTER=""
    CLUSTER_STATE=new

    _extract_rootfs

    _install
}

_join() {
    [ -z ${FLAGS_ip} ] && clr_red "ERROR: Must provide an IP or Hostname --ip" && exit 1

    REMOTE_IP=${FLAGS_ip}
    REMOTE_PORT=${CLIENT_PORT}

    REMOTE_API=http://${REMOTE_IP}:${REMOTE_PORT}
    export ETCDCTL_ENDPOINTS=${REMOTE_API}

    _extract_rootfs

    clr_green "Check ${REMOTE_API}/health"
    # Check remote IP and find local IP
    if _etcdctl2 cluster-health; then 
        clr_green "Check member list"
        HOST_IP=$( ip route get ${REMOTE_IP} | sed 's# #\n#g' | awk '/src/ {getline; print}' )  
        if [[ "${HOST_IP}" == "${REMOTE_IP}" ]]; then
            clr_red "ERROR: ${REMOTE_IP} should not be local"
            exit 1
        fi
    else
        clr_red "ERROR: etcd:${REMOTE_API} is either unreachable or in degraded state."  
        exit 1  
    fi     

    # Check the local IP is already registered   
    if _etcdctl2 member list | grep "clientURLs=.*${HOST_IP}"; then
        clr_red "ERROR: This host is already registered to the cluster"
        exit 1
    elif _etcdctl2 member list | grep -w "name=${HOSTNAME}"; then
        NODE_NAME="${HOSTNAME}@${HOST_IP}"
        clr_brown "WARN: Duplicated hostname: ${HOSTNAME}? Use ${NODE_NAME}"
    fi

    # Add cluster member
    clr_green "Join etcd cluster"
    echo New node: http://${HOST_IP}:${CLIENT_PORT}
    EXISTING_CLUSTER=$( _etcdctl2 member list | awk '/name=/ {print $2"="$3}' | sed 's/name=//; s/peerURLs=//' | tr '\n' ',' )
    CLUSTER_STATE=existing

    # Register new member 
    clr_green "Register node ${HOST_IP} to etcd cluster"
    if _etcdctl2 member add ${NODE_NAME} http://${HOST_IP}:${PEER_PORT}; then
        echo
    else
        clr_red "ERROR: Failed to register ${HOST_IP} to the cluster" 
        exit 1
    fi

    _install
}

_remove() {
    clr_red "ATTENTION: Will irreversibly delete all etcd data on this node!"
    
    confirm ${FLAGS_yes} || exit 1

    # Gracefully check and deregister
    if [ ${FLAGS_force} -eq ${FLAGS_FALSE} ]; then
        if ${BIN_DIR}/runc list | grep -qw "${BASE_NAME} .* running"; then 
            clr_green "Check local member status"
            LOCAL_MEMBER_SPEC=$( __etcdctl2 member list | grep "clientURLs=${ETCDCTL_ENDPOINTS}" )
            echo ${LOCAL_MEMBER_SPEC}
            LOCAL_MEMBER_ID=$( echo ${LOCAL_MEMBER_SPEC} | awk 'BEGIN {FS =":"}{print $1}' )
            #_etcdctl2 cluster-health | grep ${LOCAL_MEMBER_ID}

            clr_green "Deregister local member from etcd cluster"
            MEMBER_COUNT=$( __etcdctl2 member list | wc -l )
            if [[ "${MEMBER_COUNT}" == "1" ]]; then
                clr_brown "WARN: this is the last member, please use --force"
                exit 1
            else
                _backup
                __etcdctl2 member remove ${LOCAL_MEMBER_ID}
            fi
        else 
            clr_brown "WARN: ${BASE_NAME} seems not running on this host, use --force"
            exit 1
        fi
    else 
        clr_brown "WARN: Force remove an etcd member. Skip backup and deregistration"
    fi

    # Stop service
    clr_brown "WARN: Stop and remove ${BASE_NAME}.service"
    if [ -f /etc/systemd/system/${BASE_NAME}.service ]; then
        systemctl disable --now ${BASE_NAME} || true
        rm -vf /etc/systemd/system/${BASE_NAME}.service
        systemctl daemon-reload
    fi
    
    # Remove files
    clr_brown "WARN: Remove files"
    rm -vfr ${OPT_DIR}/ | tail -1
    rm -vfr ${VAR_DIR} | tail -1   
}

_upgrade() {
    UPGRADE=true
    clr_green "Upgrade etcd version to"
    echo ${IMAGE_ADDR}

    clr_green "Stop ${BASE_NAME}.service"
    systemctl disable --now ${BASE_NAME}

    clr_green "Backup oci files" 
    mv -vf ${ROOTFS_DIR} ${ROOTFS_DIR}_${TIMESTAMP}
    mkdir -vp ${ROOTFS_DIR}
    
    _extract_rootfs

    clr_green "Copy etcd.conf.yml"
    cp -vf ${ROOTFS_DIR}_${TIMESTAMP}/etcd.conf.yml ${ROOTFS_DIR}/

    _start_service
    
    _status

}

_status() { 
    clr_green "Check cluster health"
    __etcdctl2 -v

    __etcdctl2 cluster-health | sed -r "s/( healthy)/$(clr_cyan \\1)/g; s/(degraded|unreachable)/$(clr_red \\1)/g" || true      

    __etcdctl2 member list | sed -r "s/(isLeader=true)/$(clr_cyan \\1)/g"  || true

    clr_green "For copy & paste: "
    __etcdctl2 member list | awk '/name=/ {print "etcd:"$(NF-1)}' | sed 's/clientURLs=//g' | paste -sd "," -
    __etcdctl2 member list | awk '/name=/ {print $(NF-1)}' | sed 's#clientURLs=.*//##g' | paste -sd "," - | awk '{print "etcd://"$1}'

    clr_green "Command reference"
    echo "$( clr_brown 'Watch log:' )        journalctl -fu ${BASE_NAME}"
    echo "$( clr_brown 'Watch container:' )  ${BIN_DIR}/runc list"
    echo "$( clr_brown 'Check health:' )     ${BIN_DIR}/runc exec ${BASE_NAME} etcdctl cluster-health"
    HOST_IP=$( awk -F: '/listen-client-urls/{print $3}' ${YML_FILE} | sed 's#/##g' )
    echo "$( clr_brown 'Expand cluster:' )   ${SCRIPT_DIR}/./${BASE_NAME}.sh join -i ${HOST_IP}"
}

_backup() {
    clr_green "Copy config and data"
    mkdir -vp ${BACKUP_DIR}
    cp -vf ${YML_FILE} ${BACKUP_DIR}/ || true
    cp -vf ${OCI_DIR}/config.json ${BACKUP_DIR}/ || true
    cp -vfr ${VAR_DIR}/data ${BACKUP_DIR}/ || true  
    
    if [ ${FLAGS_force} -eq ${FLAGS_FALSE} ]; then
        clr_green "Take a v3 snapshot"
        __etcdctl3 snapshot save /.etcd/snapshot.db || true
        mv -vf ${VAR_DIR}/snapshot.db ${BACKUP_DIR}/ || true

        # clr_green "Backup v2 (experimental)"
        # __etcdctl2 backup \
        # --data-dir /.etcd/data \
        # --backup-dir /.etcd/v2_backup \
        # --with-v3 || true
        # mv -vf ${VAR_DIR}/v2_backup ${BACKUP_DIR}/ || true
    fi


    clr_green "Backed up at ${BACKUP_DIR}:"
    ls -lh ${BACKUP_DIR}
}

_restore() {
    if [ -z ${FLAGS_snapshot} ]; then
        clr_red "ERROR: Must provide a snapshot dir" 
        exit 1
    elif [[ "${FLAGS_snapshot}" =~ ^/ ]] ; then
        SNAPSHOT_FILE=${FLAGS_snapshot}
    else
        SNAPSHOT_FILE="${BACKUP_ROOT_DIR}/${FLAGS_snapshot}/snapshot.db"
    fi

    if [ ! -f ${SNAPSHOT_FILE} ]; then 
        clr_red "ERROR: Cannot find snapshot: ${SNAPSHOT_FILE}" 
        exit 1
    fi

    clr_red "ATTENSION: Restore will overwrite existing keys, and restart service!"
    confirm ${FLAGS_yes} || exit 1

    MEMBER_COUNT=$( __etcdctl2 member list | wc -l )
    if [[ "${MEMBER_COUNT}" != "1" ]]; then
        clr_red "ATTENSION: Restore requires a single node cluster"
        exit 1
    fi

    _backup

    clr_green "Restore from snapshot: ${SNAPSHOT_FILE}"
    cp -vf ${SNAPSHOT_FILE} ${VAR_DIR}/
    rm -vfr ${VAR_DIR}/data.restored
    __etcdctl3 snapshot restore /.etcd/snapshot.db \
    --data-dir /.etcd/data.restored \
    --name $( awk '/name:/ {print $2}' ${YML_FILE} ) \
    --initial-cluster $( awk '/initial-cluster:/ {print $2}' ${YML_FILE} ) \
    --initial-cluster-token $( awk '/initial-cluster-token:/ {print $2}' ${YML_FILE} ) \
    --initial-advertise-peer-urls $( awk '/initial-advertise-peer-urls:/ {print $2}' ${YML_FILE} ) \

    systemctl stop ${BASE_NAME}
    rm -fr ${VAR_DIR}/data 
    mv -vf ${VAR_DIR}/data.restored ${VAR_DIR}/data

    _start_service

    _status
}

_getconf() {
    clr_green "ENV:"
    ${BIN_DIR}/runc exec -e ETCDCTL_API=2 ${BASE_NAME} printenv

    clr_green "Config file:"
    cat ${YML_FILE}

    clr_green "Data dir:"
    grep -A7 -B1 '"destination": "/.etcd",' ${OCI_DIR}/config.json
}

_install() {
    # Copy files
    clr_green "Copy control files"
    mkdir -vp ${BIN_DIR} 
    mkdir -vp ${VAR_DIR}
    cp -vf ${SCRIPT_DIR}/runc ${BIN_DIR}/
    chmod +x -R ${BIN_DIR}/
    cp -vf ${SCRIPT_DIR}/oci-config.json ${OCI_DIR}/config.json
    cp -vf ${SCRIPT_DIR}/runc-etcd.service /etc/systemd/system/${BASE_NAME}.service
    sed -i "s/runc-etcd/${BASE_NAME}/g" ${OCI_DIR}/config.json /etc/systemd/system/${BASE_NAME}.service

    # Generate etcd config-file
    clr_green "Set etcd config file"
    cat > ${YML_FILE} <<EOF
name:                        ${NODE_NAME}
max-txn-ops:                 1024
data-dir:                    /.etcd/data
advertise-client-urls:       http://${HOST_IP}:${CLIENT_PORT}
listen-peer-urls:            http://${HOST_IP}:${PEER_PORT}
listen-client-urls:          http://${HOST_IP}:${CLIENT_PORT}
initial-advertise-peer-urls: http://${HOST_IP}:${PEER_PORT}
initial-cluster:             ${EXISTING_CLUSTER}${NODE_NAME}=http://${HOST_IP}:${PEER_PORT}
initial-cluster-state:       ${CLUSTER_STATE}
initial-cluster-token:       ${BASE_NAME}
auto-compaction-rate:        3
quota-backend-bytes:         $(( 8 * 1024 ** 3))
snapshot-count:              5000
enable-v2:                   true
EOF
    cat ${YML_FILE}

    # Verify config.json
    clr_green "Set OCI args"
    grep -A3 '\"args\"\: \[' ${OCI_DIR}/config.json

    clr_green "Set OCI datadir binding"
    sed -i "s#_ETCD_DATA_DIR_#${VAR_DIR}#" ${OCI_DIR}/config.json
    grep -A7 -B1 '"destination": "/.etcd",' ${OCI_DIR}/config.json

    clr_green "Set OCI env"
    sed -i "s#ETCDCTL_API=#&2#" ${OCI_DIR}/config.json
    sed -i "s#ETCDCTL_ENDPOINTS=#&http://${HOST_IP}:${CLIENT_PORT}#" ${OCI_DIR}/config.json
    grep -A6 '\"env\"\: \[' ${OCI_DIR}/config.json 

    # Start ${BASE_NAME}.service
    _start_service    

    # Check cluster health 
    _status

    # Hide init_cluster
    [ ${FLAGS_hide_init} -eq ${FLAGS_TRUE} ] && FLAGS_yes=true && _hide_init
}

_extract_rootfs() {
    clr_green "Extract OCI rootfs" 
    [ ${FLAGS_pull} -eq ${FLAGS_TRUE} ] || ${UPGRADE} && docker pull ${IMAGE_ADDR}
    printf "${IMAGE_ADDR}  "
    mkdir -vp ${ROOTFS_DIR}
    docker export $( docker create --rm ${IMAGE_ADDR} ) | \
    tar -C ${ROOTFS_DIR} --checkpoint=200 --checkpoint-action=exec='printf "\b=>"' -xf -
    echo " ${ROOTFS_DIR}/"
}

_start_service() {
    clr_green "Start ${BASE_NAME}.service"
    systemctl daemon-reload
    systemctl enable --now ${BASE_NAME}
    sleep 5
    systemctl status ${BASE_NAME} | grep -w "Loaded\|Active"
}

_hide_init() {
    clr_brown "WARN: Remove initial_cluster environmental variables" 
    sed -i '/initial-cluster:/d' ${YML_FILE}
    sed -i 's/initial-cluster-state:       new/initial-cluster-state:       existing/' ${YML_FILE}

    _getconf

    clr_brown "WARN: Restart ${BASE_NAME}.service"    
    confirm ${FLAGS_yes} || exit 1

    systemctl restart ${BASE_NAME}
    sleep 3

    _status 
}

_del_keys() {
    clr_red "ATTENTION: Will ireversibly delete user data!"

    if [ ${FLAGS_all} -eq ${FLAGS_TRUE} ]; then
        KEYS=""
        clr_brown "WARN: Delete all / entries!"
    elif [ ! -z ${FLAGS_key} ]; then
        KEYS=${FLAGS_key}
        clr_brown "WARN: Delete ${KEYS} entries!"
    else
        clr_red "ERROR: Need to provide prefix or use --all"
        exit 1
    fi

    confirm ${FLAGS_yes} || exit 1

    clr_brown "Delete entries for prefix: ${KEYS}"
    ${BIN_DIR}/runc exec -e ETCDCTL_API=3 \
    ${BASE_NAME} etcdctl del --prefix "${KEYS}" 

    clr_brown "Check number of entries for prefix: ${KEYS}"
    ${BIN_DIR}/runc exec -e ETCDCTL_API=3 \
    ${BASE_NAME} etcdctl get --prefix "${KEYS}" | wc -l
}

FLAGS "$@" || exit $?
eval set -- "${FLAGS_ARGV}"

set -e -o pipefail
_main "$@"

cd "${WORK_DIR}"

