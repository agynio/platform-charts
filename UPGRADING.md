# Upgrading

## To 0.29.0, from any release before it

**Recreate the `agents-orchestrator` Deployment after the upgrade**, or it will
lose `WORKLOAD_DNS_UPSTREAM` and `IMAGE_PROXY_HOST`:

```bash
kubectl -n <namespace> delete deploy agents-orchestrator
helm upgrade <release> oci://ghcr.io/agynio/charts/agyn-platform --version 0.29.0 --reuse-values
```

Before 0.29.0, `extraEnvVars` appended to `env` rather than overriding it, so an
installation that set a name the chart already set ended up with two entries for
it. Kubernetes keeps both and uses the last, so the override worked.

0.29.0 takes service-base 0.1.6, which collapses those to one. Migrating onto it
is what bites: a strategic merge patch over a list that already holds duplicate
keys deletes **both** copies rather than collapsing them, and Helm reports the
upgrade as successful. Empty `IMAGE_PROXY_HOST` then disables every catalog image
reference, which fails on the next workload rather than during the upgrade.

An installation that never set `extraEnvVars` for a name the chart sets is not
affected.
