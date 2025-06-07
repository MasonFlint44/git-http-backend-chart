apiVersion: v1
kind: ConfigMap
metadata:
  name: {{ include "git-gateway.safeName" .Values.ingress.host }}-start
data:
  start-fcgiwrap.sh: |
    #!/bin/sh
    set -e

    # ➊ install git + fcgiwrap exactly once
    apk add --no-cache git fcgiwrap spawn-fcgi

    # ➋ make sure the socket directory exists and is writable
    mkdir -p /var/run
    chmod 777 /var/run

    # ➌ launch fcgiwrap safely via spawn-fcgi (keeps it alive)
    spawn-fcgi -s /var/run/fcgiwrap.sock -M 766 -F 4 -u nginx -g nginx /usr/sbin/fcgiwrap

    # ➍ start nginx in foreground
    exec nginx -g 'daemon off;'
