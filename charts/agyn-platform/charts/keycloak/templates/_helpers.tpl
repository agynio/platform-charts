{{- define "keycloak.name" -}}
{{- default .Chart.Name .Values.nameOverride | trunc 63 | trimSuffix "-" -}}
{{- end -}}

{{- define "keycloak.fullname" -}}
{{- if .Values.fullnameOverride -}}
{{- .Values.fullnameOverride | trunc 63 | trimSuffix "-" -}}
{{- else -}}
{{- $name := include "keycloak.name" . -}}
{{- printf "%s-%s" .Release.Name $name | trunc 63 | trimSuffix "-" -}}
{{- end -}}
{{- end -}}

{{- define "keycloak.realmConfigMapName" -}}
{{- printf "%s-realm" (include "service-base.fullname" .) -}}
{{- end -}}

{{- define "keycloak.secretName" -}}
{{- if .Values.auth.existingSecret -}}
{{- .Values.auth.existingSecret -}}
{{- else -}}
{{- printf "%s-auth" (include "service-base.fullname" .) -}}
{{- end -}}
{{- end -}}

{{- define "keycloak.databaseSecretName" -}}
{{- if .Values.database.existingSecret -}}
{{- .Values.database.existingSecret -}}
{{- else -}}
{{- include "keycloak.secretName" . -}}
{{- end -}}
{{- end -}}

{{- define "keycloak.databasePasswordKey" -}}
{{- if .Values.database.existingSecret -}}
{{- .Values.database.passwordKey -}}
{{- else -}}
database-password
{{- end -}}
{{- end -}}

{{- define "keycloak.envValue" -}}
{{- tpl (toString .value) .context -}}
{{- end -}}

{{- /* configMounts[].sourceName is not templated by service-base, so the realm
       mount is injected here where the rendered ConfigMap name is known. */ -}}
{{- define "keycloak.render" -}}
{{- $template := .template -}}
{{- $root := .context -}}
{{- $values := deepCopy $root.Values -}}
{{- $env := list -}}
{{- range $envVar := $values.env | default (list) -}}
  {{- $renderedEnvVar := deepCopy $envVar -}}
  {{- if hasKey $renderedEnvVar "value" -}}
    {{- $_ := set $renderedEnvVar "value" (include "keycloak.envValue" (dict "value" (get $renderedEnvVar "value") "context" $root)) -}}
  {{- end -}}
  {{- $env = append $env $renderedEnvVar -}}
{{- end -}}
{{- $secretEnv := list -}}
{{- $secretEnv = append $secretEnv (dict "name" "KC_DB_PASSWORD" "valueFrom" (dict "secretKeyRef" (dict "name" (include "keycloak.databaseSecretName" $root) "key" (include "keycloak.databasePasswordKey" $root)))) -}}
{{- $secretEnv = append $secretEnv (dict "name" "KC_BOOTSTRAP_ADMIN_USERNAME" "value" $root.Values.adminUser.username) -}}
{{- $secretEnv = append $secretEnv (dict "name" "KC_BOOTSTRAP_ADMIN_PASSWORD" "valueFrom" (dict "secretKeyRef" (dict "name" (include "keycloak.secretName" $root) "key" $root.Values.auth.bootstrapPasswordKey))) -}}
{{- /* Substituted into the realm JSON by Keycloak's ${VAR} expansion, which is
       why the password never appears in the ConfigMap. */ -}}
{{- $secretEnv = append $secretEnv (dict "name" "AGYN_ADMIN_PASSWORD" "valueFrom" (dict "secretKeyRef" (dict "name" (include "keycloak.secretName" $root) "key" $root.Values.auth.adminPasswordKey))) -}}
{{- $values = set $values "env" (concat $env $secretEnv) -}}
{{- $mount := dict "name" "realm-import" "sourceName" (include "keycloak.realmConfigMapName" $root) "type" "configMap" "mountPath" "/opt/keycloak/data/import" "readOnly" true -}}
{{- $mounts := $values.configMounts | default (list) -}}
{{- $mounts = append $mounts $mount -}}
{{- $values = set $values "configMounts" $mounts -}}
{{- $ctx := dict "Values" $values "Chart" $root.Chart "Capabilities" $root.Capabilities "Release" $root.Release "Files" $root.Files "Template" $root.Template -}}
{{- include $template $ctx -}}
{{- end -}}
