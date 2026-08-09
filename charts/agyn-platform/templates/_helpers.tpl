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

{{/*
Every database this release expects to exist, as secret key -> database name.

The platform services are listed in postgres.databases. A bundled app's database
is declared on the app instead, and only counted while the app is enabled: the
provisioning job fails the release over a database it cannot create, so listing
one for an app nobody deployed turns a disabled app into a failed upgrade.

An entry in postgres.databases still wins, so an installation that names an app
database itself keeps whatever it named.
*/}}
{{- define "agyn-platform.databases" -}}
{{- $databases := dict -}}
{{- range $name, $app := .Values.bundledApps }}
{{- if and $app.enabled $app.database }}
{{- $_ := set $databases (required (printf "bundledApps.%s.database.key is required" $name) $app.database.key) (required (printf "bundledApps.%s.database.name is required" $name) $app.database.name) }}
{{- end }}
{{- end }}
{{- range $key, $name := (.Values.postgres.databases | default dict) }}
{{- $_ := set $databases $key $name }}
{{- end }}
{{- toYaml $databases -}}
{{- end -}}
