apiVersion: apps/v1
kind: Deployment
metadata:
  name: {{ include "git-gateway.safeName" .Values.ingress.host }}
spec:
  replicas: {{ .Values.replicaCount }}
  selector:
    matchLabels:
      app: git-gateway
  template:
    metadata:
      labels:
        app: git-gateway
    spec:
      securityContext:
        fsGroup: 1000                # keeps /srv/git writeable by non-root
      volumes:
        - name: git-data
          persistentVolumeClaim:
            claimName: git-data-pvc
        - name: nginx-conf
          configMap:
            name: {{ include "git-gateway.safeName" .Values.ingress.host }}-nginx
      containers:
        - name: gateway
          image: nginx:1.27-alpine     # only one image now
          command:
            - /bin/sh
            - -c
            - |
                set -e
                # install git and fcgiwrap
                apk add --no-cache fcgiwrap git git-daemon

                # run fcgiwrap on TCP :9000, four workers
                fcgiwrap -f -c 4 -s tcp:127.0.0.1:9000 &

                # start nginx in foreground
                nginx -g 'daemon off;'
          volumeMounts:
            - name: git-data
              mountPath: /srv/git
            - name: nginx-conf
              mountPath: /etc/nginx/nginx.conf
              subPath: nginx.conf
          ports:
            - name: http
              containerPort: 80
          resources: {{- toYaml .Values.resources | nindent 12 }}
