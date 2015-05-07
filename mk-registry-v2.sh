#!/bin/bash
PRG="$0"
PRGDIR=`dirname "$PRG"`
PRGDIR=`cd "$PRGDIR/." && pwd -P`
CACHEDIR="$PRGDIR/.cache"
if [ ! -d "$CACHEDIR" ] ; then
    mkdir "$CACHEDIR"
fi
DISTFILE="$CACHEDIR/distribution-2.0.zip"
if [ ! -f "$DISTFILE" ] ; then
    curl -o "$DISTFILE" "https://codeload.github.com/docker/distribution/zip/release/2.0"
    if [ "0" -ne "$?" ] ; then
        echo "Fetch the docker distribution release v2.0 fail" >&2
        exit 1
    fi
fi
BUILDBASEDIR=`mktemp -d /tmp/cn_tsflink_reg_v2.XXXXX` || $(echo "Create build directory fail!" && exit 1)
cd "$BUILDBASEDIR"
unzip "$DISTFILE"
BUILDDIR="$BUILDBASEDIR/distribution-release-2.0"
cd "$BUILDDIR"

cat > cmd/registry/config.yml <<EOF
version: 0.1
log:
  level: debug
  fields:
    service: registry
    environment: production
storage:
    cache:
        layerinfo: inmemory
    filesystem:
        rootdirectory: /data/registry
http:
    addr: :5000
    secret: asecretforlocaldevelopment
    debug:
        addr: localhost:5001
redis:
  addr: localhost:6379
  pool:
    maxidle: 16
    maxactive: 64
    idletimeout: 300s
  dialtimeout: 10ms
  readtimeout: 10ms
  writetimeout: 10ms
notifications:
    endpoints:
        - name: local-8082
          url: http://localhost:5003/callback
          headers:
             Authorization: [Bearer <an example token>]
          timeout: 1s
          threshold: 10
          backoff: 1s
          disabled: true
        - name: local-8083
          url: http://localhost:8083/callback
          timeout: 1s
          threshold: 10
          backoff: 1s
          disabled: true
EOF

docker rmi udiabon/docker-registry-v2-tsflink:latest
docker build --rm -t udiabon/docker-registry-v2-tsflink .

rm -fr "$BUILDBASEDIR"

