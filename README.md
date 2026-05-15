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
