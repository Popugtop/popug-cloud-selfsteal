FROM debian:12
RUN apt-get update && apt-get install -y --no-install-recommends ca-certificates curl python3 iproute2 procps ufw iptables \
    && rm -rf /var/lib/apt/lists/*
# no systemd in the test container: a shim that starts dockerd the way "systemctl enable --now docker" would
RUN printf '%s\n' '#!/bin/sh' \
  'case "$*" in *"enable --now docker"*) nohup dockerd >/var/log/dockerd.log 2>&1 & exit 0 ;; esac' \
  'exit 0' > /usr/local/bin/systemctl && chmod +x /usr/local/bin/systemctl
