# Agyn Platform Charts

This repository publishes production umbrella Helm charts for Agyn workloads.
The charts compose service charts published under `oci://ghcr.io/agynio/charts`.

## Charts

| Chart | Purpose |
| --- | --- |
| `charts/agyn-platform` | Deploys the core platform services as one umbrella chart. |
| `charts/agyn-apps` | Deploys optional apps plus the default Kubernetes runner. |

## Repository layout

```text
platform-charts/
├── README.md
├── charts/
│   ├── agyn-platform/
│   │   ├── Chart.yaml
│   │   ├── values.yaml
│   │   ├── values.schema.json
│   │   └── templates/
│   └── agyn-apps/
│       ├── Chart.yaml
│       ├── values.yaml
│       ├── values.schema.json
│       └── templates/
└── .github/workflows/
    └── chart-release.yaml
```

## Secret-first configuration

Production installs should provide database URLs, S3 credentials, app service
tokens, and runner service tokens through pre-created Kubernetes Secrets. The
charts intentionally do not require plaintext secrets in values files.

Example database secret:

```sh
kubectl create secret generic agyn-platform-database-urls \
  --from-literal=agents=postgresql://agents:REDACTED@postgres.example.com:5432/agents \
  --from-literal=threads=postgresql://threads:REDACTED@postgres.example.com:5432/threads
```

Example S3 secret for the `files` service:

```sh
kubectl create secret generic agyn-files-s3 \
  --from-literal=access-key=REDACTED \
  --from-literal=secret-key=REDACTED
```

## Install

Install the platform chart:

```sh
helm dependency update charts/agyn-platform
helm upgrade --install agyn-platform charts/agyn-platform \
  --namespace platform \
  --create-namespace \
  --values production-platform-values.yaml
```

Install apps and the default runner:

```sh
helm dependency update charts/agyn-apps
helm upgrade --install agyn-apps charts/agyn-apps \
  --namespace apps \
  --create-namespace \
  --values production-apps-values.yaml
```

Published OCI installs use:

```sh
helm upgrade --install agyn-platform oci://ghcr.io/agynio/charts/agyn-platform \
  --version 0.1.0 \
  --namespace platform \
  --create-namespace \
  --values production-platform-values.yaml

helm upgrade --install agyn-apps oci://ghcr.io/agynio/charts/agyn-apps \
  --version 0.1.0 \
  --namespace apps \
  --create-namespace \
  --values production-apps-values.yaml
```

## Local validation

```sh
helm dependency update charts/agyn-platform
helm dependency update charts/agyn-apps
helm lint charts/agyn-platform charts/agyn-apps
helm template agyn-platform charts/agyn-platform >/tmp/agyn-platform.yaml
helm template agyn-apps charts/agyn-apps >/tmp/agyn-apps.yaml
helm package charts/agyn-platform --destination .dist
helm package charts/agyn-apps --destination .dist
yamllint .
```

## Registration and tokens

`agynio/bootstrap` currently registers apps/runners and creates service tokens
through Terraform resources. These umbrella charts only deploy workloads and
wire configuration. Registration IDs and service tokens must be supplied as
pre-created Kubernetes Secrets or non-secret values where appropriate.


### Platform database and S3 source Secrets

`agyn-platform` wires workloads directly to operator-provided Secrets. It does
not render intermediate Secrets and does not require plaintext database URLs or
S3 credentials in Helm values.

Database URLs come from `platform.database.existingSecret`. The key for each
service is derived from `platform.database.existingSecretKeyPattern`; the
pattern is evaluated with a `service` variable and defaults to the service name:

```yaml
platform:
  database:
    mode: external
    existingSecret: agyn-platform-database-urls
    existingSecretKeyPattern: "{{ .service }}"
```

Each database-backed dependency must point at that same Secret/key contract.
The default values already do this. If you change the top-level database Secret
or key pattern, update the matching dependency override paths in the same values
file; the chart validates these refs during render and fails if they drift.
Important override paths are:

```text
agents.env[].valueFrom.secretKeyRef
agents-orchestrator.env[].valueFrom.secretKeyRef
apps.env[].valueFrom.secretKeyRef
chat.env[].valueFrom.secretKeyRef
expose.env[].valueFrom.secretKeyRef
identity.env[].valueFrom.secretKeyRef
organizations.env[].valueFrom.secretKeyRef
runners.env[].valueFrom.secretKeyRef
threads.env[].valueFrom.secretKeyRef
tracing.env[].valueFrom.secretKeyRef
users.env[].valueFrom.secretKeyRef
ziti-management.env[].valueFrom.secretKeyRef
secrets.database.existingSecret
llm.llm.databaseUrl
files.files.databaseUrl
```

Example custom database Secret and key pattern:

```yaml
platform:
  database:
    existingSecret: prod-db-urls
    existingSecretKeyPattern: "{{ .service }}-url"

agents:
  env:
    - name: GRPC_ADDRESS
      value: ":50051"
    - name: DATABASE_URL
      valueFrom:
        secretKeyRef:
          name: prod-db-urls
          key: agents-url

files:
  files:
    databaseUrl:
      existingSecret: prod-db-urls
      existingSecretKey: files-url
```

The database Secret should contain keys for:

```text
agents
agents-orchestrator
apps
chat
expose
files
identity
llm
organizations
runners
secrets
threads
tracing
users
ziti-management
```

S3 credentials for the `files` service are also wired directly to the
operator-provided Secret. `files.files.s3.accessKey.existingSecret` and
`files.files.s3.secretKey.existingSecret` must match `s3.existingSecret`, while
their key fields must match `s3.accessKeyKey` and `s3.secretKeyKey`:

```yaml
s3:
  existingSecret: agyn-files-s3
  accessKeyKey: access-key
  secretKeyKey: secret-key
  endpoint: s3.example.com
  bucket: agyn-files
  region: us-east-1
  useSSL: true
  forcePathStyle: false

files:
  files:
    s3:
      endpoint: s3.example.com
      bucket: agyn-files
      region: us-east-1
      useSSL: true
      accessKey:
        existingSecret: agyn-files-s3
        existingSecretKey: access-key
      secretKey:
        existingSecret: agyn-files-s3
        existingSecretKey: secret-key
```

The existing `files` subchart remains a chart dependency. The non-secret S3
settings are set on `files.files.s3.*`; `forcePathStyle` is additionally exposed
to the files container as `S3_FORCE_PATH_STYLE` through the
`agyn-platform-files-s3-config` ConfigMap because the files subchart does not
have a native value for it.

Set `validation.requireExistingSecrets=true` for install/upgrade against a live
cluster to fail rendering when the referenced DB/S3 Secrets or required keys are
missing. This validation uses Helm `lookup`, so it requires access to the target
cluster and is disabled by default for offline `helm lint` / `helm template`
workflows.

## Override points

The platform chart exposes a top-level non-sensitive OpenFGA contract at
`openfga.apiUrl`, `openfga.storeId`, and `openfga.modelId`. The chart renders
those values into the `agyn-platform-openfga` ConfigMap and wires the
`authorization` subchart through `authorization.extraEnvVarsCM`.

Sensitive cluster-admin token configuration is not exposed as plaintext. The
`gateway` subchart receives `CLUSTER_ADMIN_TOKEN` through `gateway.env` using a
Kubernetes Secret reference. Override `gateway.env` directly when your Secret
name or key differs:

```yaml
gateway:
  env:
    - name: CLUSTER_ADMIN_TOKEN
      valueFrom:
        secretKeyRef:
          name: agyn-cluster-admin
          key: token
```

The apps chart intentionally exposes only dependency toggles at `apps.*.enabled`
and `runners.k8s.enabled`. Runtime configuration maps directly to the dependent
subchart values:

- `reminders.env`
- `telegram-connector.env`
- `k8s-runner.env`

Use those paths to override database URL Secret refs, service token Secret refs,
app IDs, gateway addresses, runner namespace, runner PVC size, and other
workload environment values.

## Egress deployment contract

`agyn-platform` deploys the Egress control-plane service (`egress`) and the
Egress Gateway data-plane service (`egress-gateway`) by default. The platform
chart expects the platform database Secret to include an `egress` connection
string key, matching `platform.database.existingSecretKeyPattern`.

The Egress CA contract is fixed across deployment layers:

- Secret name: `egress-ca`
- Public certificate key: `tls.crt`
- Private key key: `tls.key`
- Egress Gateway mount path: `/var/run/agyn/egress-ca/`
- Egress Gateway env vars: `EGRESS_CA_CERT_PATH` and `EGRESS_CA_KEY_PATH`

The Egress Gateway Ziti identity is consumed from the
`egress-gateway-ziti-identity` Secret and mounted at `/var/lib/ziti`. In
bootstrap environments this Secret is created by the bootstrap platform stack;
in external environments operators must provide an enrolled identity Secret with
an `identity.json` key before enabling `egress-gateway`.

`gateway.gateway.egressRulesGrpcTarget` and `secrets.egressRules.grpcTarget`
are both wired to `egress:50051` so Gateway and Secrets call the renamed control
plane service instead of the legacy `egress-rules` name.
