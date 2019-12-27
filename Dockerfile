FROM busybox

COPY cmd /cmd

COPY entry.sh /

ENTRYPOINT [ "/entry.sh" ]