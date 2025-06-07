{{/*
Expand host name to a valid DNS-1123 label for resource names
*/}}
{{- define "git-gateway.safeName" -}}
{{- . | replace "." "-" | trunc 63 | trimSuffix "-" -}}
{{- end -}}
