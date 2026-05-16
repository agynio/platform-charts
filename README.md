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

Authenticate Helm to GHCR if the charts are private:

```sh
helm registry login ghcr.io
```

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

`agyn-platform` reads operator-provided source Secrets and renders internal
Secrets consumed by dependent service charts. This keeps service chart values
secret-ref based and avoids plaintext database URLs or S3 credentials in Helm
values.

Database URLs are read from `platform.database.existingSecret` using
`platform.database.existingSecretKeyPattern`. The pattern is evaluated with a
`service` variable for each database-backed service and defaults to the service
name:

```yaml
platform:
  database:
    mode: external
    existingSecret: agyn-platform-database-urls
    existingSecretKeyPattern: "{{ .service }}"
```

The chart renders `agyn-platform-generated-database-urls`, and every
DATABASE_URL consumer references that generated Secret with `valueFrom` or the
subchart's secret-ref fields. Set `validation.requireExistingSecrets=true` for
install/upgrade against a live cluster to fail rendering when the source DB/S3
Secrets or required keys are missing. This validation uses Helm `lookup`, so it
requires access to the target cluster and is disabled by default for offline
`helm lint` / `helm template` workflows. The source Secret should contain keys
for:

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

S3 credentials for the `files` service are read from `s3.existingSecret` and
rendered into `agyn-platform-generated-files-s3`, which is then wired into
`files.files.s3.accessKey.existingSecret` and
`files.files.s3.secretKey.existingSecret`. The existing `files` subchart remains
a chart dependency. The non-secret S3 settings are rendered into the
`agyn-platform-files-s3-config` ConfigMap and injected into the files subchart
through `files.env` so user overrides of the top-level S3 contract flow at
template time. `forcePathStyle` is exposed to the files container as
`S3_FORCE_PATH_STYLE`:

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

validation:
  requireExistingSecrets: true
```

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
