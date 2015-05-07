#!/bin/bash
BUILDDIR=`mktemp -d /tmp/cn_tsflink_reg_nginx.XXXXX` || $(echo "Create build directory fail!" && exit 1)
cd "$BUILDDIR"

cat > docker-registry-v2.conf <<"EOF"
proxy_pass                          http://docker-registry-v2;
proxy_set_header  Host              $http_host;   # required for docker client's sake
proxy_set_header  X-Real-IP         $remote_addr; # pass on real client's IP
proxy_set_header  X-Forwarded-For   $proxy_add_x_forwarded_for;
proxy_set_header  X-Forwarded-Proto $scheme;
proxy_read_timeout                  900;
EOF

cat > docker-registry.conf <<"EOF"
proxy_pass                          http://docker-registry;
proxy_set_header  Host              $http_host;   # required for docker client's sake
proxy_set_header  X-Real-IP         $remote_addr; # pass on real client's IP
proxy_set_header  X-Forwarded-For   $proxy_add_x_forwarded_for;
proxy_set_header  X-Forwarded-Proto $scheme;
proxy_set_header  Authorization     ""; # see https://github.com/docker/docker-registry/issues/170
proxy_read_timeout                  900;
EOF

cat > registry.conf <<"EOF"
# Docker registry proxy for api versions 1 and 2

upstream docker-registry {
  server registryv1:5000;
}

upstream docker-registry-v2 {
  server registryv2:5000;
}

# No client auth or TLS
server {
  listen 5000;
  server_name registry.docker.365link.cn;

  # disable any limits to avoid HTTP 413 for large image uploads
  client_max_body_size 0;

  # required to avoid HTTP 411: see Issue #1486 (https://github.com/docker/docker/issues/1486)
  chunked_transfer_encoding on;

  ssl on;
  ssl_certificate /etc/nginx/certs/registry_docker_365link_cn.crt;
  ssl_certificate_key /etc/nginx/certs/registry_docker_365link_cn.key;

  location /v2/ {
    # Do not allow connections from docker 1.5 and earlier
    # docker pre-1.6.0 did not properly set the user agent on ping, catch "Go *" user agents
    if ($http_user_agent ~ "^(docker\/1\.(3|4|5(?!\.[0-9]-dev))|Go ).*$" ) {
      return 404;
    }

    include               docker-registry-v2.conf;
  }

  location / {
    include               docker-registry.conf;
  }
}
EOF

cat > nginx.conf <<"EOF"
user  nginx;
worker_processes  1;

error_log /var/log/nginx/error.log warn;
pid        /var/run/nginx.pid;

events {
    worker_connections  1024;
}

http {
    include       /etc/nginx/mime.types;
    default_type  application/octet-stream;

    log_format  main  '$remote_addr - $remote_user [$time_local] "$request" '
                      '$status $body_bytes_sent "$http_referer" '
                      '"$http_user_agent" "$http_x_forwarded_for"';

    access_log  /var/log/nginx/access.log main;

    sendfile        on;

    keepalive_timeout  65;

    include /etc/nginx/conf.d/*.conf;
}
EOF

cat > Dockerfile <<"EOF"
# VERSION 0.1
# DOCKER-VERSION 1.5
# AUTHOR:        Nick Jiang <liangdongj@gmail.com>
# DESCRIPTION:   Image of the nginx to run the docker registry for production running in the 365LINK.
# TO_BUILD:      docker build -rm -t udiabon/docker-registry-nginx-tsflink .
# TO_RUN:        docker run -p 5000:5000 udiabon/docker-registry-nginx-tsflink
FROM nginx:1.7

COPY nginx.conf /etc/nginx/nginx.conf
COPY registry.conf /etc/nginx/conf.d/registry.conf
COPY docker-registry.conf /etc/nginx/docker-registry.conf
COPY docker-registry-v2.conf /etc/nginx/docker-registry-v2.conf

VOLUME /etc/nginx/certs
VOLUME /var/log/nginx

EOF

docker rmi udiabon/docker-registry-nginx-tsflink:latest
docker build --rm -t udiabon/docker-registry-nginx-tsflink .

rm -fr "$BUILDDIR"

