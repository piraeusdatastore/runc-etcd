#!/bin/bash -e

file="$1"
[ ! -f "$1" ] && echo 'File does not exist!' && exit 1
length="$( jq -r '.kvs | length' "$file" )"
for i in $( seq 0 "$(( length - 1))" ); do
    key="$( jq -r ".kvs[$i].key" "$file" | base64 --decode )"
    value="$( jq -r ".kvs[$i].value" "$file" | base64 --decode )"
    echo "$key"
    echo "$value"
    /opt/runc-etcd/bin/runc exec -e ETCDCTL_API=3 runc-etcd etcdctl put -- "$key" "$value"
    echo
done 