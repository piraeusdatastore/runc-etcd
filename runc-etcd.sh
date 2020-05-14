#!/bin/bash
#######################################################
## Author: alex.zheng@daocloud.io                    ##
## Disclaimer: Only Use under DaoCloud's supervision ##
#######################################################

# Must run in the script directoy 
work_dir="$( pwd )"
script_dir="$( cd "$( dirname "${BASH_SOURCE[0]}" )" >/dev/null && pwd )"
timestamp="$( date +%Y-%m-%d_%H-%M-%S )"

source "${script_dir}/lib/bash_colors.sh"
source "${script_dir}/lib/confirm.sh"
source "${script_dir}/lib/shflags.sh"

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
: "${image:=etcd}"
: "${node_name:="$HOSTNAME"}"

# Parse cmdline arguments
_main() {
    # Parse args
    if [ "$#" -eq 0 ]; then
        clr_red "ERROR: Missing action."
        flags_help
        exit 1
    elif [ "$#" -gt 1 ]; then
        clr_red "ERROR: Only one action is allowed."
        flags_help
        exit 1
    fi
    action="$1" 
    upgrade=false

    # Parse flags
    [ "$FLAGS_debug" -eq "$FLAGS_TRUE" ] && set -x

    if [ -z "$FLAGS_registry" ]; then
        image_addr="${image}:${FLAGS_tag}"
    else
        image_addr="${FLAGS_registry}/${image}:${FLAGS_tag}"
    fi     
    peer_port="$FLAGS_peer_port"
    client_port="$FLAGS_client_port"

    base_name="${FLAGS_prefix}-etcd"
    opt_dir="/opt/${base_name}"
    oci_dir="${opt_dir}/oci"
    bin_dir="${opt_dir}/bin"
    rootfs_dir="${oci_dir}/rootfs"
    yml_file="${rootfs_dir}/${base_name}.yml"
    var_dir="/var/local/${base_name}"
    backup_root_dir="/var/local/${base_name}_backup"
    backup_dir="${backup_root_dir}/${timestamp}"

    # Parse actions 
    case "$action" in
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
    ETCDCTL_API=2 "${rootfs_dir}/usr/local/bin/etcdctl" "$@"
}

__etcdctl2() {
    # etcdctl v2 inside container
    "${bin_dir}/runc" exec -e ETCDCTL_API=2 "$base_name" etcdctl "$@"
}

__etcdctl3() {
    # etcdctl v3 inside container
    "${bin_dir}/runc" exec -e ETCDCTL_API=3 "$base_name" etcdctl "$@"
}

_create() { 
    [ -z "${FLAGS_ip}" ] && clr_red "ERROR: Must provide an IP or Hostname by --ip" && exit 1

    # Check if IP is present on the local node 
    if ip a | grep -q "inet ${FLAGS_ip}\/"; then
        host_ip="$FLAGS_ip"
    else
        clr_red "ERROR: ${FLAGS_ip} is not present on this host"
        exit 1
    fi
    
    # Create cluster
    clr_green "Create etcd cluster"
    echo New node: "http://${host_ip}:${client_port}"
    existing_cluster=""
    cluster_state=new

    _extract_rootfs

    _install
}

_join() {
    [ -z "$FLAGS_ip" ] && clr_red "ERROR: Must provide an IP or Hostname --ip" && exit 1

    remote_ip="$FLAGS_ip"
    remote_port="$client_port"

    remote_api="http://${remote_ip}:${remote_port}"
    export ETCDCTL_ENDPOINTS="$remote_api"

    _extract_rootfs

    clr_green "Check ${remote_api}/health"
    # Check remote IP and find local IP
    if _etcdctl2 cluster-health; then 
        clr_green "Check member list"
        host_ip="$( ip route get "$remote_ip" | sed 's# #\n#g' | awk '/src/ {getline; print}' )"
        if [[ "$host_ip" == "$remote_ip" ]]; then
            clr_red "ERROR: $remote_ip should not be local"
            exit 1
        fi
    else
        clr_red "ERROR: etcd:${remote_api} is either unreachable or in degraded state."  
        exit 1  
    fi     

    # Check the local IP is already registered   
    if _etcdctl2 member list | grep "clientURLs=.*${host_ip}"; then
        clr_red "ERROR: This host is already registered to the cluster"
        exit 1
    elif _etcdctl2 member list | grep -w "name=${HOSTNAME}"; then
        node_name="${HOSTNAME}@${host_ip}"
        clr_brown "WARN: Duplicated hostname: ${HOSTNAME}? Use ${node_name}"
    fi

    # Add cluster member
    clr_green "Join etcd cluster"
    echo New node: "http://${host_ip}:${client_port}"
    existing_cluster=$( _etcdctl2 member list | awk '/name=/ {print $2"="$3}' | sed 's/name=//; s/peerURLs=//' | tr '\n' ',' )
    cluster_state=existing

    # Register new member 
    clr_green "Register node $host_ip to etcd cluster"
    if _etcdctl2 member add "$node_name" "http://${host_ip}:${peer_port}"; then
        echo
    else
        clr_red "ERROR: Failed to register ${host_ip} to the cluster" 
        exit 1
    fi

    _install
}

_remove() {
    clr_red "ATTENTION: Will irreversibly delete all etcd data on this node!"
    
    confirm "$FLAGS_yes" || exit 1

    # Gracefully check and deregister
    if [ "$FLAGS_force" -eq "$FLAGS_FALSE" ]; then
        if "$bin_dir/runc" list | grep -qw "$base_name .* running"; then 
            clr_green "Check local member status"
            local_member_spec="$( __etcdctl2 member list | grep "clientURLs=${ETCDCTL_ENDPOINTS}" )"
            echo "$local_member_spec"
            local_member_id="$( echo "$local_member_spec" | awk 'BEGIN {FS =":"}{print $1}' )"
            #_etcdctl2 cluster-health | grep ${local_member_id}

            clr_green "Deregister local member from etcd cluster"
            member_count="$( __etcdctl2 member list | wc -l )"
            if [[ "$member_count" == "1" ]]; then
                clr_brown "WARN: this is the last member, please use --force"
                exit 1
            else
                _backup
                __etcdctl2 member remove "$local_member_id"
            fi
        else 
            clr_brown "WARN: $base_name seems not running on this host, use --force"
            exit 1
        fi
    else 
        clr_brown "WARN: Force remove an etcd member. Skip backup and deregistration"
    fi

    # Stop service
    clr_brown "WARN: Stop and remove ${base_name}.service"
    if [ -f "/etc/systemd/system/${base_name}.service" ]; then
        systemctl disable --now "$base_name" || true
        rm -vf "/etc/systemd/system/${base_name}.service"
        systemctl daemon-reload
    fi
    
    # Remove files
    clr_brown "WARN: Remove files"
    rm -vfr "$opt_dir" | tail -1
    rm -vfr "$var_dir" | tail -1   
}

_upgrade() {
    upgrade=true
    clr_green "Upgrade etcd version to"
    echo "$image_addr"

    clr_green "Stop ${base_name}.service"
    systemctl disable --now "$base_name"

    clr_green "Backup oci files" 
    mv -vf "$rootfs_dir" "${rootfs_dir}_${timestamp}"
    mkdir -vp "$rootfs_dir"
    
    _extract_rootfs

    clr_green "Copy ${base_name}.yml"
    cp -vf "${rootfs_dir}_${timestamp}/${base_name}.yml" "${rootfs_dir}/"

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
    echo "$( clr_brown 'Watch log:' )        journalctl -fu ${base_name}"
    echo "$( clr_brown 'Watch container:' )  ${bin_dir}/runc list"
    echo "$( clr_brown 'Check health:' )     ${bin_dir}/runc exec ${base_name} etcdctl cluster-health"
    host_ip="$( awk -F: '/listen-client-urls/{print $3}' "$yml_file" | sed 's#/##g' )"
    echo "$( clr_brown 'Expand cluster:' )   ./${base_name}.sh join -i ${host_ip}"
}

_backup() {
    clr_green "Copy config and data"
    mkdir -vp "$backup_dir"
    cp -vf "$yml_file" "${backup_dir}/" || true
    cp -vf "${oci_dir}/config.json" "${backup_dir}/" || true
    cp -vfr "${var_dir}/data" "${backup_dir}/" || true  
    
    if [ "$FLAGS_force" -eq "$FLAGS_FALSE" ]; then
        clr_green "Take a v3 snapshot"
        __etcdctl3 snapshot save /.etcd/snapshot.db || true
        mv -vf "$var_dir/snapshot.db" "$backup_dir/" || true

        # clr_green "Backup v2 (experimental)"
        # __etcdctl2 backup \
        # --data-dir /.etcd/data \
        # --backup-dir /.etcd/v2_backup \
        # --with-v3 || true
        # mv -vf ${var_dir}/v2_backup ${backup_dir}/ || true
    fi


    clr_green "Backed up at ${backup_dir}:"
    ls -lh "$backup_dir"
}

_restore() {
    if [ -z "$FLAGS_snapshot" ]; then
        clr_red "ERROR: Must provide a snapshot dir" 
        exit 1
    elif [[ "$FLAGS_snapshot" =~ ^/ ]] ; then
        snapshot_file="$FLAGS_snapshot"
    else
        snapshot_file="${backup_root_dir}/${FLAGS_snapshot}/snapshot.db"
    fi

    if [ ! -f "$snapshot_file" ]; then 
        clr_red "ERROR: Cannot find snapshot: $snapshot_file" 
        exit 1
    fi

    clr_red "ATTENSION: Restore will overwrite existing keys, and restart service!"
    confirm "$FLAGS_yes" || exit 1

    member_count=$( __etcdctl2 member list | wc -l )
    if [[ "$member_count" != "1" ]]; then
        clr_red "ATTENSION: Restore requires a single node cluster"
        exit 1
    fi

    _backup

    clr_green "Restore from snapshot: $snapshot_file"
    cp -vf "$snapshot_file" "${var_dir}/"
    rm -vfr "${var_dir}/data.restored"
    __etcdctl3 snapshot restore /.etcd/snapshot.db \
    --data-dir /.etcd/data.restored \
    --name "$( awk '/name:/ {print $2}' "$yml_file" )" \
    --initial-cluster "$( awk '/initial-cluster:/ {print $2}' "$yml_file" )" \
    --initial-cluster-token "$( awk '/initial-cluster-token:/ {print $2}' "$yml_file" )" \
    --initial-advertise-peer-urls "$( awk '/initial-advertise-peer-urls:/ {print $2}' "$yml_file" )"

    systemctl stop "$base_name"
    rm -fr "${var_dir}/data"
    mv -vf "${var_dir}/data.restored" "${var_dir}/data"

    _start_service

    _status
}

_getconf() {
    clr_green "ENV:"
    "$bin_dir/runc" exec -e ETCDCTL_API=2 "$base_name" printenv

    clr_green "Config file:"
    cat "$yml_file"

    clr_green "Data dir:"
    grep -A7 -B1 '"destination": "/.etcd",' "$oci_dir/config.json"
}

_install() {
    # Copy files
    clr_green "Copy control files"
    mkdir -vp "$bin_dir"
    mkdir -vp "$var_dir"
    cp -vf "${script_dir}/runc" "${bin_dir}/"
    chmod +x -R "${bin_dir}/"
    cp -vf "${script_dir}/oci-config.json" "${oci_dir}/config.json"
    cp -vf "${script_dir}/runc-etcd.service" "/etc/systemd/system/${base_name}.service"
    sed -i "s/runc-etcd/${base_name}/g" "${oci_dir}/config.json" "/etc/systemd/system/${base_name}.service"

    # Generate etcd config-file
    clr_green "Set etcd config file"
    cat > "$yml_file" <<EOF
name:                        ${node_name}
max-txn-ops:                 1024
data-dir:                    /.etcd/data
advertise-client-urls:       http://${host_ip}:${client_port}
listen-peer-urls:            http://${host_ip}:${peer_port}
listen-client-urls:          http://${host_ip}:${client_port}
initial-advertise-peer-urls: http://${host_ip}:${peer_port}
initial-cluster:             ${existing_cluster}${node_name}=http://${host_ip}:${peer_port}
initial-cluster-state:       ${cluster_state}
initial-cluster-token:       ${base_name}
auto-compaction-rate:        3
quota-backend-bytes:         $(( 8 * 1024 ** 3))
snapshot-count:              5000
enable-v2:                   true
EOF
    cat "$yml_file"

    # Verify config.json
    clr_green "Set OCI args"
    grep -A3 '\"args\"\: \[' "$oci_dir/config.json"

    clr_green "Set OCI datadir binding"
    sed -i "s#_ETCD_DATA_DIR_#${var_dir}#" "${oci_dir}/config.json"
    grep -A7 -B1 '"destination": "/.etcd",' "${oci_dir}/config.json"

    clr_green "Set OCI env"
    sed -i "s#ETCDCTL_API=#&2#" "${oci_dir}/config.json"
    sed -i "s#ETCDCTL_ENDPOINTS=#&http://${host_ip}:${client_port}#" "${oci_dir}/config.json"
    grep -A6 '\"env\"\: \[' "${oci_dir}/config.json"

    # Start ${base_name}.service
    _start_service    

    # Check cluster health 
    _status

    # Hide init_cluster
    [ "$FLAGS_hide_init" -eq "$FLAGS_TRUE" ] && FLAGS_yes=true && _hide_init
}

_extract_rootfs() {
    clr_green "Extract OCI rootfs" 
    [ "$FLAGS_pull" -eq "$FLAGS_TRUE" ] || "$upgrade" && docker pull "$image_addr"
    printf "%s  " "$image_addr"
    mkdir -vp "$rootfs_dir"
    container_id="$( docker create --rm "$image_addr" )"
    docker export "$container_id" | \
    tar -C "$rootfs_dir" --checkpoint=200 --checkpoint-action=exec='printf "\b=>"' -xf -
    echo " ${rootfs_dir}/"
    docker rm -f "$container_id"
}

_start_service() {
    clr_green "Start ${base_name}.service"
    systemctl daemon-reload
    systemctl enable --now "$base_name"
    sleep 5
    systemctl status "$base_name" | grep -w "Loaded\|Active"
}

_hide_init() {
    clr_brown "WARN: Remove initial_cluster environmental variables" 
    sed -i '/initial-cluster:/d' "$yml_file"
    sed -i 's/initial-cluster-state:       new/initial-cluster-state:       existing/' "$yml_file"

    _getconf

    clr_brown "WARN: Restart ${base_name}.service"    
    confirm "$FLAGS_yes" || exit 1

    systemctl restart "$base_name"
    sleep 3

    _status 
}

_del_keys() {
    clr_red "ATTENTION: Will ireversibly delete user data!"

    if [ "$FLAGS_all" -eq "$FLAGS_TRUE" ]; then
        keys=""
        clr_brown "WARN: Delete all / entries!"
    elif [ "$FLAGS_key" ]; then
        keys="$FLAGS_key"
        clr_brown "WARN: Delete ${keys} entries!"
    else
        clr_red "ERROR: Need to provide prefix or use --all"
        exit 1
    fi

    confirm ${FLAGS_yes} || exit 1

    clr_brown "Delete entries for prefix: ${keys}"
    "${bin_dir}/runc" exec -e ETCDCTL_API=3 \
    "$base_name" etcdctl del --prefix "$keys" 

    clr_brown "Check number of entries for prefix: ${keys}"
    "${bin_dir}/runc" exec -e ETCDCTL_API=3 \
    "$base_name" etcdctl get --prefix "$keys" | wc -l
}

FLAGS "$@" || exit $?
eval set -- "$FLAGS_ARGV"

set -e -o pipefail
_main "$@"

cd "$work_dir"

