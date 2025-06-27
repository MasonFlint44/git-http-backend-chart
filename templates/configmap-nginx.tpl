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

      # derive $repo_owner from the first path component
      map $uri $repo_owner {
        "~^/([A-Za-z0-9._-]{1,128})/"   $1;
        default                         "";
      }

      # owner-mismatch detector (handshake-aware)
      map "$token_user:$repo_owner" $owner_mismatch {
        "~^:[^:]+$"       0;   # first unauthenticated probe
        "~^([^:]+):\1$"   0;   # token user matches repo owner
        default           1;   # mismatch
      }

      {{- if and .Values.tokenkeeper.enabled }}
      upstream tokenkeeper_backend {
        server tokenkeeper:{{ .Values.tokenkeeper.port }};
      }
      {{- end }}

      server {
        listen 80;
        server_name {{ .Values.ingress.host }};

        client_max_body_size 1g;

        # ─────────────── Git Smart-HTTP bloc ───────────────
        location ~ (/.*\.git)(/.*)?$ {
          {{- if .Values.tokenkeeper.enabled }}
          auth_request /auth;
          {{- else }}
          auth_request off;
          {{- end }}

          {{- if .Values.tokenkeeper.enabled }}
          auth_request_set $token_user $upstream_http_x_token_user;
          {{- else }}
          set $token_user "";
          {{- end }}

          auth_request_set $auth_status $upstream_status;

          error_page 401 403 = @basic401;
          error_page 500     = @auth_missing;

          # block when repo owner ≠ token user (after handshake)
          if ($owner_mismatch) { return 403 "owner–token mismatch\n"; }

          # ───── git-http-backend wiring ─────
          include fastcgi_params;
          fastcgi_param SCRIPT_FILENAME  /usr/libexec/git-core/git-http-backend;

          fastcgi_param HTTP_X_TOKEN_USER "";
          fastcgi_param GIT_PROJECT_ROOT /srv/git;

          fastcgi_param GIT_HTTP_EXPORT_ALL "";

          fastcgi_param PATH_INFO $uri;

          fastcgi_pass 127.0.0.1:9000;
          fastcgi_read_timeout 3600;
        }

        location @basic401 {
          add_header WWW-Authenticate 'Basic realm="Git repository"' always;
          return 401;
        }

        location @auth_missing {
          if ($auth_status = 422) {
            add_header WWW-Authenticate 'Basic realm="Git repository"' always;
            return 401;
          }
          return 500;
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
          proxy_set_header X-Token-User "";
        }
        {{- else }}
        location = /auth { return 204; }
        {{- end }}
      }
    }
