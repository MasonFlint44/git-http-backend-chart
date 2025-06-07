apiVersion: v1
kind: ConfigMap
metadata:
  name: {{ include "git-gateway.safeName" .Values.ingress.host }}-nginx
data:
  nginx.conf: |
    user  nginx;
    worker_processes  auto;
    error_log  /var/log/nginx/error.log warn;
    pid        /var/run/nginx.pid;

    events { worker_connections  1024; }

    http {
      include       /etc/nginx/mime.types;
      default_type  application/octet-stream;
      sendfile        on;

      # auth endpoint
      upstream auth_backend {
        server 127.0.0.1:9000;  # fcgiwrap handles /auth internally
      }

      server {
        listen 80;
        server_name {{ .Values.ingress.host }};

        client_max_body_size 1g;

        # only smart HTTP Git traffic
        location ~ (/.*\.git)(/.*)?$ {
          auth_request off;                         # or /auth; if you enable auth

          include fastcgi_params;

          fastcgi_param  SCRIPT_FILENAME   /usr/libexec/git-core/git-http-backend;
          fastcgi_param  GIT_PROJECT_ROOT  /srv/git;
          fastcgi_param  GIT_HTTP_EXPORT_ALL "";
          fastcgi_param  PATH_INFO         $1$2;

          fastcgi_pass   127.0.0.1:9000;   # matches the fcgiwrap line
          fastcgi_read_timeout 3600;
        }

        location = /auth {
          internal;
          proxy_pass {{ .Values.auth.verifierUrl }};
          proxy_set_header Authorization $http_authorization;
          proxy_set_header X-Audience {{ .Values.auth.audience }};
        }
      }
    }
