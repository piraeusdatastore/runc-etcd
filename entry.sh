#!/bin/sh -x
if [ -d /drop ]; then
    rm -fr /drop/runc-etcd && \
    cp -fr cmd /drop/runc-etcd
else
    echo /drop is not mounted
fi 