#!/bin/sh -x
if [ -d /drop ]; then
    rm -fr /drop/runc-etcd && \
    cp -fr /runc-etcd /drop/
else
    echo /drop is not mounted
fi 