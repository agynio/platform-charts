# Upgrading

## To 0.49.0, from any release before it

**Reinstall any app installed before 0.48.0**, or it still cannot use agents.

0.49.0 takes apps 0.4.8, where installing an app makes it a member of the
organization it is installed into. Membership is what `can_initiate` resolves
through for an `internal` agent, so before this an installed app could create a
thread and then fail to add any agent to it — the bundled connectors reported
`identity cannot initiate this agent` on their first mention.

Existing installations were created without the membership tuple and are not
backfilled, so uninstall and reinstall each one. Installation configuration is
not preserved by that round trip — copy it first.

**Skip 0.48.0.** It shipped membership on apps 0.4.7, where install and
uninstall sent a fixed tuple batch. An OpenFGA write batch is atomic and is
rejected whole for deleting a tuple that does not exist, so uninstalling an
installation predating membership removed nothing while still reporting success
— and the reinstall then failed with `AlreadyExists` on the permissions left
behind. 0.4.8 reads what is written and sends only the difference, which also
clears an organization already holding orphans.

## To 0.31.0, from any release before it

0.31.0 ships the [Slack Connector](https://github.com/agynio/slack-connector) as
a third bundled app, enabled by default, and moves the bundled apps' databases
into the chart.

**On a bundled Postgres, nothing is required.** A bundled app declares its
database on itself, under `bundledApps.<app>.database`, and the chart counts it
only while that app is enabled. The provisioning job creates any database that
does not exist yet, so an existing volume is brought up to date without manual
SQL. An installation naming an app database in its own `postgres.databases`
keeps whatever it named — an explicit entry still wins, and is then expected
whether or not the app is on.

**On a managed instance**, the platform database Secret belongs to the operator
and the chart does not touch it. Create a database for the connector and add its
URL under the key `slack-connector`, the same way the other two were added.

**Upgrade past 0.30.0 rather than onto it.** 0.30.0 listed the three app
databases in `postgres.databases` directly, where they were expected
unconditionally. An installation with a bundled app turned off then had the
provisioning job demand a database nothing uses, and that job fails the release
when it cannot create one. 0.31.0 is the same feature without that edge.

The connector needs `bot_token`, `app_token` and `agent_id` in its installation
configuration before it does anything; without them it reports `Misconfigured`
and idles. To leave it out entirely, set
`bundledApps.slackConnector.enabled=false` — no database is expected for a
disabled app.

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
