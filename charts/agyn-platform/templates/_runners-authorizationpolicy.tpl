{{- define "agyn-platform.principal" -}}
{{- printf "cluster.local/ns/%s/sa/%s" (.namespace | default $.Release.Namespace) .name -}}
{{- end -}}
{{- define "agyn-platform.pathList" -}}
{{- range . }}
              - {{ . | quote }}
{{- end -}}
{{- end -}}
