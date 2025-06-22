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

      # ────────────────────────────────────────────────────────────
      # 1. helper variable: repo owner (Unicode-aware, ≤128 chars)   ★
      #    \p{L} Letters   \p{M} Marks   \p{N} Numbers
      #    \p{S} Symbols   \p{P} Punctuation   (NO slashes)
      # ────────────────────────────────────────────────────────────
      map $uri $repo_owner {                                        # ★
          # PCRE in “UTF-8 + Unicode properties” mode: (?u)         # ★
          # anchor start, grab 1 – 128 allowed code points, stop at /
          ~(?u)^/([\p{L}\p{M}\p{N}\p{S}\p{P}]{1,128})/   $1;        # ★
          default                                   "";             # ★
      }

      # ────────────────────────────────────────────────────────────
      # 2. owner-mismatch detector                                  ★
      #    Sets $owner_mismatch to 1 whenever $token_user ≠ $repo_owner
      # ────────────────────────────────────────────────────────────
      map "$token_user:$repo_owner" $owner_mismatch {              # ★
        "~^([^:]+):\1$"  0;  # identical → OK                      # ★
        default          1;  # mismatch → flag                     # ★
      }

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

          # capture the username that Tokenkeeper echoes back
          {{- if .Values.tokenkeeper.enabled }}
          auth_request_set $token_user $upstream_http_x_token_user;
          {{- else }}
          set $token_user "";
          {{- end }}

          # expose the sub-request’s status for later inspection
          auth_request_set $auth_status $upstream_status;

          # any 401/403 from /auth → add Basic challenge
          error_page 401 403 = @basic401;

          # any other error (incl. 422 → 500) → check & maybe convert
          error_page 500   = @auth_missing;

          # ─── repo-owner → user match (map-based) ──────────────── ★
          if ($owner_mismatch) { return 403; }                      # ★

          include fastcgi_params;
          fastcgi_param SCRIPT_FILENAME  /usr/libexec/git-core/git-http-backend;

          # prevent client-supplied spoofed header reaching git-http-backend ★
          fastcgi_param HTTP_X_TOKEN_USER "";                       # ★

          # hand git-http-backend a per-user project root
          {{- if .Values.tokenkeeper.enabled }}
          fastcgi_param GIT_PROJECT_ROOT /srv/git/$token_user;
          {{- else }}
          fastcgi_param GIT_PROJECT_ROOT /srv/git;
          {{- end }}

          fastcgi_param GIT_HTTP_EXPORT_ALL "";
          fastcgi_param PATH_INFO        $1$2;

          fastcgi_pass 127.0.0.1:9000;
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
          proxy_set_header X-Token-User "";   # strip any spoofed client header ★
        }
        {{- else }}
        location = /auth {
          return 204;
        }
        {{- end }}
      }
    }
