ARG VERSION=rootless-latest
FROM netbirdio/netbird:$VERSION

# Railway volumes are mounted owned by root, so the rootless image's
# unprivileged user can't write its state. Netstack mode still means no
# capabilities or TUN device are needed.
USER root
RUN apk add --no-cache jq

ENV NB_LOG_FORMAT="json" \
    NB_LOG_FILE="console"

COPY entrypoint.sh /entrypoint.sh
ENTRYPOINT ["/entrypoint.sh"]
