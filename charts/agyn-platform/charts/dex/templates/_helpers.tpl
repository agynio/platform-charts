{{- define "dex.name" -}}
{{- default .Chart.Name .Values.nameOverride | trunc 63 | trimSuffix "-" -}}
{{- end -}}

{{- define "dex.fullname" -}}
{{- if .Values.fullnameOverride -}}
{{- .Values.fullnameOverride | trunc 63 | trimSuffix "-" -}}
{{- else -}}
{{- $name := include "dex.name" . -}}
{{- printf "%s-%s" .Release.Name $name | trunc 63 | trimSuffix "-" -}}
{{- end -}}
{{- end -}}

{{- define "dex.configMapName" -}}
{{- printf "%s-config" (include "service-base.fullname" .) -}}
{{- end -}}

{{- define "dex.secretName" -}}
{{- if .Values.auth.existingSecret -}}
{{- .Values.auth.existingSecret -}}
{{- else -}}
{{- printf "%s-auth" (include "service-base.fullname" .) -}}
{{- end -}}
{{- end -}}

{{- define "dex.databaseSecretName" -}}
{{- if .Values.database.existingSecret -}}
{{- .Values.database.existingSecret -}}
{{- else -}}
{{- include "dex.secretName" . -}}
{{- end -}}
{{- end -}}

{{- define "dex.databasePasswordKey" -}}
{{- if .Values.database.existingSecret -}}
{{- .Values.database.passwordKey -}}
{{- else -}}
database-password
{{- end -}}
{{- end -}}

{{- /* One Secret key and one env var per user, both derived from the username so
       neither depends on the order of the list. */ -}}
{{- define "dex.hashSecretKey" -}}
{{- printf "password-hash-%s" (.username | lower) -}}
{{- end -}}

{{- define "dex.hashEnvName" -}}
{{- $upper := .username | upper -}}
{{- printf "DEX_PASSWORD_HASH_%s" (regexReplaceAll "[^A-Z0-9]" $upper "_") -}}
{{- end -}}

{{- /* The hostname in externalUrl, which is what the VirtualService and the
       cluster wiring both name. */ -}}
{{- define "dex.host" -}}
{{- if .Values.routing.host -}}
{{- .Values.routing.host -}}
{{- else -}}
{{- $hostPort := regexReplaceAll "/.*$" (regexReplaceAll "^https?://" .Values.externalUrl "") "" -}}
{{- regexReplaceAll ":[0-9]+$" $hostPort "" -}}
{{- end -}}
{{- end -}}

{{- /* The Dex configuration file. Rendered here rather than in the ConfigMap so
       the Deployment can hash it and roll the pod: Dex reads this once, at
       start, and a change that does not restart it never takes effect. */ -}}
{{- define "dex.config" -}}
{{- $externalUrl := required "dex.externalUrl is required: it is the token issuer every OIDC consumer must be configured with" .Values.externalUrl -}}
{{- $dbHost := required "dex.database.host is required" .Values.database.host -}}
{{- $c := .Values.config -}}

{{- $clients := list -}}
{{- range $app, $origin := .Values.appOrigins }}
{{- if $origin }}
{{- $clients = append $clients (dict
      "id" (printf "agyn-%s" $app)
      "name" (printf "Agyn %s" (title $app))
      "public" true
      "redirectURIs" (list (printf "%s%s" $origin $.Values.callbackPath)))
-}}
{{- end }}
{{- end }}

{{- $origins := .Values.allowedOrigins -}}
{{- if not $origins -}}
{{- $origins = list -}}
{{- range $app, $origin := .Values.appOrigins }}
{{- if $origin }}
{{- $origins = append $origins $origin -}}
{{- end }}
{{- end }}
{{- end }}

{{- /* One entry per user, keyed on the address. Dex looks a static user up by
       the email field and nothing else, and returns that same field as the
       email claim -- so a second entry keyed on a username is not an alias, it
       is an account whose email is that username. The platform matches
       declarations on the address, so that costs more than it buys.

       emailVerified is left at Dex's default of true. */ -}}
{{- $passwords := list -}}
{{- range $user := .Values.users | default (list) }}
{{- $passwords = append $passwords (dict
      "email" (required "dex.users[].email is required" $user.email)
      "username" (required "dex.users[].username is required" $user.username)
      "name" ($user.name | default $user.username)
      "preferredUsername" $user.username
      "userID" (required "dex.users[].userID is required" $user.userID)
      "hashFromEnv" (include "dex.hashEnvName" $user))
-}}
{{- end }}
{{- if not $passwords -}}
{{- fail "dex.users must list at least one user, or nobody can sign in" -}}
{{- end -}}

{{- $refresh := dict -}}
{{- if $c.refreshTokenExpiry.absoluteLifetime -}}
{{- $_ := set $refresh "absoluteLifetime" $c.refreshTokenExpiry.absoluteLifetime -}}
{{- end -}}
{{- if $c.refreshTokenExpiry.validIfNotUsedFor -}}
{{- $_ := set $refresh "validIfNotUsedFor" $c.refreshTokenExpiry.validIfNotUsedFor -}}
{{- end -}}

{{- $oauth2 := dict
      "skipApprovalScreen" $c.skipApprovalScreen
      "alwaysShowLoginScreen" $c.alwaysShowLoginScreen
-}}
{{- if $c.passwordConnector -}}
{{- $_ := set $oauth2 "passwordConnector" $c.passwordConnector -}}
{{- end -}}

{{- /* $DEX_DB_PASSWORD is expanded by Dex itself: env expansion covers the
       storage config, so the password stays out of the ConfigMap. */ -}}
{{- $config := dict
      "issuer" $externalUrl
      "storage" (dict
        "type" "postgres"
        "config" (dict
          "host" $dbHost
          "port" (.Values.database.port | int)
          "database" .Values.database.name
          "user" .Values.database.username
          "password" "$DEX_DB_PASSWORD"
          "ssl" (dict "mode" .Values.database.sslMode)))
      "web" (dict
        "http" "0.0.0.0:5556"
        "allowedOrigins" $origins)
      "telemetry" (dict "http" "0.0.0.0:5558")
      "oauth2" $oauth2
      "expiry" (dict
        "idTokens" $c.idTokenExpiry
        "refreshTokens" $refresh)
      "enablePasswordDB" true
      "staticPasswords" $passwords
      "staticClients" $clients
-}}
{{- toYaml (mergeOverwrite $config (deepCopy (.Values.extraConfig | default dict))) -}}
{{- end -}}

{{- /* configMounts[].sourceName is not templated by service-base, so the config
       mount is injected here where the rendered ConfigMap name is known. */ -}}
{{- define "dex.render" -}}
{{- $template := .template -}}
{{- $root := .context -}}
{{- $values := deepCopy $root.Values -}}

{{- $secretEnv := list -}}
{{- $secretEnv = append $secretEnv (dict "name" "DEX_DB_PASSWORD" "valueFrom" (dict "secretKeyRef" (dict "name" (include "dex.databaseSecretName" $root) "key" (include "dex.databasePasswordKey" $root)))) -}}
{{- range $user := $root.Values.users | default (list) -}}
{{- $secretEnv = append $secretEnv (dict "name" (include "dex.hashEnvName" $user) "valueFrom" (dict "secretKeyRef" (dict "name" (include "dex.secretName" $root) "key" (include "dex.hashSecretKey" $user)))) -}}
{{- end -}}
{{- $values = set $values "env" (concat ($values.env | default (list)) $secretEnv) -}}

{{- $mount := dict "name" "config" "sourceName" (include "dex.configMapName" $root) "type" "configMap" "mountPath" "/etc/dex" "readOnly" true -}}
{{- $values = set $values "configMounts" (append ($values.configMounts | default (list)) $mount) -}}

{{- $annotations := $values.podAnnotations | default dict -}}
{{- $annotations = merge (dict "checksum/config" (include "dex.config" $root | sha256sum)) $annotations -}}
{{- $values = set $values "podAnnotations" $annotations -}}

{{- $ctx := dict "Values" $values "Chart" $root.Chart "Capabilities" $root.Capabilities "Release" $root.Release "Files" $root.Files "Template" $root.Template -}}
{{- include $template $ctx -}}
{{- end -}}
