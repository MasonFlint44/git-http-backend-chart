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
      sendfile on;

      # auth endpoint for tokenkeeper
      {{- if and .Values.tokenkeeper.enabled }}
      upstream tokenkeeper_backend {
        server tokenkeeper:{{ .Values.tokenkeeper.port }};
      }
      {{- end }}

      server {
        listen 80;
        server_name {{ .Values.ingress.host }};

        client_max_body_size 1g;

        # ────────────────────────────────────────────────────────────
        # Git Smart-HTTP traffic
        # ────────────────────────────────────────────────────────────
        location ~ (/.*\.git)(/.*)?$ {
          {{- if .Values.tokenkeeper.enabled }}
          auth_request /auth;
          {{- else }}
          auth_request off;
          {{- end }}

          # expose the sub-request’s status for later inspection
          auth_request_set $auth_status $upstream_status;

          # any 401/403 from /auth → add Basic challenge
          error_page 401 403 = @basic401;

          # any other error (incl. 422 → 500) → check & maybe convert
          error_page 500 = @auth_missing;

          include fastcgi_params;
          fastcgi_param SCRIPT_FILENAME   /usr/libexec/git-core/git-http-backend;
          fastcgi_param GIT_PROJECT_ROOT  /srv/git;
          fastcgi_param GIT_HTTP_EXPORT_ALL "";
          fastcgi_param PATH_INFO         $1$2;

          fastcgi_pass 127.0.0.1:9000;     # matches the fcgiwrap line
          fastcgi_read_timeout 3600;
        }

        # add Basic challenge for “bad / expired” credentials
        location @basic401 {
          add_header WWW-Authenticate 'Basic realm="Git repository"' always;
          return 401;
        }

        # convert “missing credentials” (auth returned 422) into a challenge
        location @auth_missing {
          if ($auth_status = 422) {
            add_header WWW-Authenticate 'Basic realm="Git repository"' always;
            return 401;
          }
          return 500;   # real 500 for anything else
        }

        {{- if .Values.tokenkeeper.enabled }}
        location = /auth {
          internal;
          proxy_http_version 1.1;
          proxy_method POST;
          proxy_pass http://tokenkeeper_backend/token/verify;
          proxy_pass_request_body off;
          proxy_set_header Content-Length "";
          proxy_set_header Authorization $http_authorization;
          # proxy_set_header X-Audience {{ .Values.tokenkeeper.audience }};
        }
        {{- else }}
        location = /auth {
          return 204;
        }
        {{- end }}
      }
    }
