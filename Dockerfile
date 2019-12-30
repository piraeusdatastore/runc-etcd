FROM busybox

COPY ./ /runc-etcd
    
ENTRYPOINT [ "/runc-etcd/entry.sh" ]