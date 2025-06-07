{{- if .Values.ingress.enabled }}
apiVersion: networking.k8s.io/v1
kind: Ingress
metadata:
  name: git-gateway
  annotations:
    kubernetes.io/ingress.class: {{ .Values.ingress.className }}
    {{- if .Values.ingress.tls.enabled }}
    cert-manager.io/cluster-issuer: letsencrypt-prod
    {{- end }}
spec:
  rules:
    - host: {{ .Values.ingress.host }}
      http:
        paths:
          - path: /
            pathType: Prefix
            backend:
              service:
                name: {{ include "git-gateway.safeName" .Values.ingress.host }}
                port:
                  number: {{ .Values.service.port }}
  {{- if .Values.ingress.tls.enabled }}
  tls:
    - hosts:
        - {{ .Values.ingress.host }}
      secretName: {{ .Values.ingress.tls.secretName }}
  {{- end }}
{{- end }}
