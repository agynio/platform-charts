{{/*
Render a ConfigMap documenting umbrella-level configuration. Subcharts consume
values directly; this manifest gives operators a discoverable contract in the
cluster without materializing secret values.
*/}}
{{- define "agyn-platform.name" -}}
{{- default .Chart.Name .Values.nameOverride | trunc 63 | trimSuffix "-" -}}
{{- end -}}

{{- define "agyn-platform.fullname" -}}
{{- if .Values.fullnameOverride -}}
{{- .Values.fullnameOverride | trunc 63 | trimSuffix "-" -}}
{{- else -}}
{{- include "agyn-platform.name" . -}}
{{- end -}}
{{- end -}}
