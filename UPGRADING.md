# Upgrading

## To 0.57.0

**Nothing is required for an install whose apps sit at `<product>.<domain>`.**
The frontends used to find each other by replacing the first label of their own
hostname, which is right only under that layout. They are now told the addresses
instead, through a ConfigMap derived from `platform.ingress.routes` — the same
routes that build the VirtualServices — so a custom subdomain is declared once
and the switcher follows it. Where an address is absent the old derivation still
runs, so an install that changes nothing behaves as it did.

**An install that owns its ingress has to name them.** With
`platform.ingress.enabled: false` there are no routes to derive from, and the
frontends fall back to guessing. Set the ones you serve:

```yaml
platform:
  externalUrls:
    chat: https://chat.example.com
    tracing: https://tracing.example.com
    console: https://console.example.com
    sandboxes: https://sandboxes.example.com
    mediaProxy: https://media.example.com
```

These also take a port, which no derivation from a hostname would have produced.

**`chat-app.mediaProxyUrl` is gone.** It was an entry in the chart's `env:`
block, and an explicit environment variable — empty included — shadows the
ConfigMap the umbrella feeds these through. Leaving it would have kept the media
proxy guessing while the other four were told. Set
`platform.externalUrls.mediaProxy` instead, or `chat-app.extraEnvVars` for a
standalone install.

0.56.0 shipped the umbrella half of this against the previous app charts, which
ignore it. 0.57.0 is the first version where the setting reaches the browser.

## To 0.55.0

**Dex is the bundled provider now, and it serves `auth.`.** An install that sets
nothing gets Dex; one that sets `keycloak.enabled: true` must now also set
`dex.enabled: false`, or the render fails naming the hostname they collide on.
That refusal is deliberate: two VirtualServices for one host merge into a route
set whose order across resources is not defined, so a `/` prefix on either
swallows the other and which one wins changes between applies.

The hostname moved from `dex.` to `auth.` because the name belongs to the role
rather than to whatever fills it. A consumer's issuer then survives a change of
provider, and moving between them is one value instead of six.

**Switching provider on an install that has users is not a flag.** An account is
keyed on the subject its issuer asserts, so the same person signing in through a
new issuer arrives as a new account while the old one keeps the address and
whatever roles were granted to it. Installs with real users should stay on
Keycloak (`keycloak.enabled: true`, `dex.enabled: false`) until that migration is
worth doing deliberately.

The issuer itself changes shape: Keycloak serves it at
`https://auth.<domain>/realms/<realm>`, Dex at `https://auth.<domain>` with no
path. Everything configured with the issuer moves together —
`platform.oidc.issuerUrl`, `gateway.gateway.oidcIssuerUrl`, `media-proxy`'s
`oidcIssuerUrl`, and the four apps' `oidcAuthority`.

One difference remains against Keycloak: Dex holds no SSO cookie, so each app
asks for the password separately, and again in each new tab. Tracked upstream in
dexidp/dex#4560. Sign-out no longer differs — the apps drop their tokens when a
provider publishes no `end_session_endpoint`.

## To 0.54.0

**Nothing is required.** 0.53.0 adds `dex` as a second bundled OIDC provider,
disabled, and changes nothing for an install that does not enable it. Keycloak
stays exactly as it was and remains the provider the bundle ships with.

Dex is there for installs that cannot carry Keycloak: on the same cluster it
holds 7Mi resident against Keycloak's 596Mi, from a 42MiB image against 237MiB,
and starts in under a second instead of running a schema migration.

It serves the same clients (`agyn-<app>`, public, PKCE), the same claims
(`email`, `email_verified`, `name`, `preferred_username`) and the same password
grant the e2e suites use, so switching is a change of issuer and nothing else.

It ships **two** accounts, `admin/admin` and `user/user`. `admin@agyn.dev` is the
address `provisioning.clusterAdmins` declares, so the controller grants it
cluster admin once that account exists; `user@agyn.dev` arrives with no role and
no organization, which is what the platform does with a subject it has not seen.
Add or replace them under `dex.users`.

Three differences to know first:

- **The first sign-in for each account must use the email address.** Dex looks a
  static user up by email and has no separate username field, so `dex.users[]`
  carries a `loginAliases` list whose entries are extra static passwords sharing
  one `userID` — the same identity, since `sub` is built from `userID`. The login
  form still reads "Email Address" (a literal in Dex, with no config path), but
  `admin` and `user` are accepted. The catch is that an alias *is* its entry's
  email field, so provisioning through one stores `admin` as the user's email and
  the `ClusterAdmin` declaration for the real address has nothing to resolve to.
  Once a user exists, either identifier works: the Gateway resolves a known
  subject without re-reading the claims.
- **No `end_session_endpoint`.** oidc-client-ts `signoutRedirect()` throws on a
  discovery document without one, so the apps' Sign out button does nothing
  until they fall back to dropping the local tokens. Dex holds no browser
  session, so that fallback is a complete sign-out.
- **No SSO cookie.** Each app asks for the password separately, and again in
  each new tab, because the apps keep tokens in `sessionStorage`.

Both gaps are one upstream change ([dexidp/dex#4560]).

To enable it: set `dex.enabled=true`, give it a hostname of its own
(`dex.externalUrl`), and point `platform.oidc.issuerUrl`, the Gateway's
`oidcIssuerUrl` and each app's `oidcAuthority` at it. Its database is created by
the provisioning job, counted only while it is enabled. Both providers may run
at once — that is how an install moves from one to the other — but not on one
hostname; the chart fails the render if they collide.

[dexidp/dex#4560]: https://github.com/dexidp/dex/issues/4560

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
