apiVersion: v1
kind: Service
metadata:
  name: {{ include "git-gateway.safeName" .Values.ingress.host }}
spec:
  type: {{ .Values.service.type }}
  ports:
    - name: http
      port: {{ .Values.service.port }}
      targetPort: 80
      {{- if eq .Values.service.type "NodePort" }}
      nodePort: {{ .Values.service.nodePort }}
      {{- end }}
  selector:
    app: git-gateway
