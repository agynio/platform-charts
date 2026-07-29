{{- define "terminal-proxy.configureEnv" -}}
{{- $env := list -}}

{{- $httpAddress := trimAll " \n\t" (default ":8080" .Values.terminalProxy.httpAddress) -}}
{{- if $httpAddress }}
{{- $env = append $env (dict "name" "HTTP_ADDRESS" "value" $httpAddress) -}}
{{- end }}

{{- $grpcAddress := trimAll " \n\t" (default ":50051" .Values.terminalProxy.grpcAddress) -}}
{{- if $grpcAddress }}
{{- $env = append $env (dict "name" "GRPC_ADDRESS" "value" $grpcAddress) -}}
{{- end }}

{{- $websocketURL := trimAll " \n\t" (default "" .Values.terminalProxy.websocketUrl) -}}
{{- if not $websocketURL }}
{{- fail "terminalProxy.websocketUrl is required: clients receive it from IssueTicket" -}}
{{- end }}
{{- $env = append $env (dict "name" "TERMINAL_PROXY_WEBSOCKET_URL" "value" $websocketURL) -}}

{{- $runnersAddress := trimAll " \n\t" (default "runners:50051" .Values.terminalProxy.runnersAddress) -}}
{{- if $runnersAddress }}
{{- $env = append $env (dict "name" "RUNNERS_ADDRESS" "value" $runnersAddress) -}}
{{- end }}

{{- $agentsAddress := trimAll " \n\t" (default "agents:50051" .Values.terminalProxy.agentsAddress) -}}
{{- if $agentsAddress }}
{{- $env = append $env (dict "name" "AGENTS_ADDRESS" "value" $agentsAddress) -}}
{{- end }}

{{- $authorizationAddress := trimAll " \n\t" (default "authorization:50051" .Values.terminalProxy.authorizationAddress) -}}
{{- if $authorizationAddress }}
{{- $env = append $env (dict "name" "AUTHORIZATION_ADDRESS" "value" $authorizationAddress) -}}
{{- end }}

{{- $ticketTTL := trimAll " \n\t" (default "30s" .Values.terminalProxy.ticketTTL) -}}
{{- if $ticketTTL }}
{{- $env = append $env (dict "name" "TERMINAL_PROXY_TICKET_TTL" "value" $ticketTTL) -}}
{{- end }}

{{- $touchInterval := trimAll " \n\t" (default "10s" .Values.terminalProxy.touchInterval) -}}
{{- if $touchInterval }}
{{- $env = append $env (dict "name" "TERMINAL_PROXY_TOUCH_INTERVAL" "value" $touchInterval) -}}
{{- end }}

{{- $pingInterval := trimAll " \n\t" (default "30s" .Values.terminalProxy.websocketPingInterval) -}}
{{- if $pingInterval }}
{{- $env = append $env (dict "name" "TERMINAL_PROXY_WEBSOCKET_PING_INTERVAL" "value" $pingInterval) -}}
{{- end }}

{{- $pingTimeout := trimAll " \n\t" (default "30s" .Values.terminalProxy.websocketPingTimeout) -}}
{{- if $pingTimeout }}
{{- $env = append $env (dict "name" "TERMINAL_PROXY_WEBSOCKET_PING_TIMEOUT" "value" $pingTimeout) -}}
{{- end }}

{{- /* The signing key is only ever read from a Secret: a shared HMAC key is
       what lets any replica validate a ticket issued by any other, and a
       literal in values would leak it into the release manifest. */ -}}
{{- $signingKey := default dict .Values.terminalProxy.ticketSigningKey -}}
{{- $signingSecretName := trimAll " \n\t" (default "" $signingKey.secretName) -}}
{{- $signingSecretKey := trimAll " \n\t" (default "signingKey" $signingKey.secretKey) -}}
{{- if not $signingSecretName }}
{{- fail "terminalProxy.ticketSigningKey.secretName is required: the ticket signing key must come from a Secret" -}}
{{- end }}
{{- $env = append $env (dict "name" "TERMINAL_PROXY_TICKET_SIGNING_KEY" "valueFrom" (dict "secretKeyRef" (dict "name" $signingSecretName "key" $signingSecretKey))) -}}

{{- $ziti := default dict .Values.terminalProxy.ziti -}}
{{- $zitiEnabled := default false $ziti.enabled -}}
{{- $env = append $env (dict "name" "ZITI_ENABLED" "value" (printf "%t" $zitiEnabled)) -}}
{{- if $zitiEnabled }}
{{- $managementAddress := trimAll " \n\t" (default "ziti-management:50051" $ziti.managementAddress) -}}
{{- $env = append $env (dict "name" "ZITI_MANAGEMENT_ADDRESS" "value" $managementAddress) -}}
{{- if $ziti.enrollmentTimeout }}
{{- $env = append $env (dict "name" "ZITI_ENROLLMENT_TIMEOUT" "value" (trimAll " \n\t" $ziti.enrollmentTimeout)) -}}
{{- end }}
{{- if $ziti.leaseRenewalInterval }}
{{- $env = append $env (dict "name" "ZITI_LEASE_RENEWAL_INTERVAL" "value" (trimAll " \n\t" $ziti.leaseRenewalInterval)) -}}
{{- end }}
{{- else }}
{{- $runnerAddress := trimAll " \n\t" (default "k8s-runner:50051" .Values.terminalProxy.runnerAddress) -}}
{{- if $runnerAddress }}
{{- $env = append $env (dict "name" "RUNNER_ADDRESS" "value" $runnerAddress) -}}
{{- end }}
{{- end }}

{{- $userEnv := .Values.env | default (list) -}}
{{- $_ := set .Values "env" (concat $env $userEnv) -}}
{{- end -}}

