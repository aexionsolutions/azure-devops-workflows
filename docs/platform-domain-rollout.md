# Platform custom-domain rollout

This runbook is the shared operational contract for assigning branded web
hostnames to RavenXpress, TEMS, and future App Service products.

## Approved hostname matrix

| Environment | RavenXpress | TEMS |
|---|---|---|
| Development | `dev.ravenxpress.com` | `dev.temstrade.com` |
| UAT | `uat.ravenxpress.com` | `uat.temstrade.com` |
| Pre-production | `preprod.ravenxpress.com` | `preprod.temstrade.com` |
| Production | `www.ravenxpress.com` | `www.temstrade.com` |

Production uses the public `www` hostname, not a `prod` hostname. Decide
separately whether the apex domain redirects to `www`; do not add an
unapproved production alias during an environment rollout.

RavenXpress tenant URLs remain `/t/{slug}` on the platform hostname unless a
tenant uses the existing managed custom-domain feature. A future
`{tenant}.ravenxpress.com` design would require separate wildcard DNS,
certificate, cookie, routing, and tenant-isolation review.

## What is and is not automatic

Ordinary application releases use the branded hostname after it has been
commissioned. Commissioning a hostname is intentionally a one-time,
fail-closed operation per environment and is not performed by a normal
release.

Each new environment requires:

1. its App Service infrastructure;
2. DNS verification and CNAME records;
3. an Azure hostname binding and managed TLS certificate;
4. the exact CIAM redirect URI;
5. an environment-specific GitHub base-URL variable;
6. infrastructure configuration refresh;
7. deployed authentication acceptance.

This ordering prevents the application from advertising a hostname before
DNS, TLS, and identity redirects are ready.

## Commissioning sequence

### 1. Deploy the environment infrastructure

Run the product's **Infra Deploy** workflow for the target environment. Record
the web App Service name and its custom-domain verification ID.

### 2. Publish DNS records

In the authoritative DNS provider, add:

- a CNAME from the approved hostname to the environment web App Service
  default hostname; and
- the Azure `asuid` TXT verification record using that App Service's
  verification ID.

Example targets:

- `uat.ravenxpress.com` → `rx-uat-web.azurewebsites.net`
- `preprod.ravenxpress.com` → `rx-preprod-web.azurewebsites.net`
- `uat.temstrade.com` → `tems-uat-web.azurewebsites.net`
- `preprod.temstrade.com` → `tems-preprod-web.azurewebsites.net`

Wait for public DNS propagation before continuing.

### 3. Bind the hostname and TLS certificate

Run the product repository's **Platform Domain Binding** workflow with the
exact environment and approved hostname. The workflow rejects any
environment/hostname pair outside the matrix above.

The workflow binds the hostname and provisions the free App Service managed
certificate. Do not rerun it after TLS is enabled: its guard deliberately
refuses to cycle a live hostname through an insecure intermediate binding.

### 4. Register the CIAM callback

Add the exact SPA callback:

`https://<approved-hostname>/auth/callback`

Use the browser client registration actually advertised by the deployed
`/api/config`. Product names are not proof of ownership: TEMS currently
advertises its TEMS API registration as the browser MSAL client, while
RavenXpress advertises RavenXpress Web (SPA).

Keep the previous callback during transition. Remove obsolete callbacks only
after deployed authentication has passed and no supported workflow or
environment uses them.

### 5. Set the GitHub environment variable

Set the Actions **variable** (not a secret) on the target GitHub environment:

- RavenXpress: `RAVENXPRESS_WEB_BASE_URL=https://<approved-hostname>`
- TEMS: `TEMS_WEB_BASE_URL=https://<approved-hostname>`

### 6. Refresh runtime configuration

Run **Infra Deploy** again so App Service runtime settings, activation links,
and authentication callbacks use the branded origin. A normal release alone
does not guarantee that infrastructure-owned app settings are refreshed.

### 7. Deploy and prove the environment

Promote the intended release, then run **Manual - Deployed Web Auth Smoke**
against the branded hostname. Acceptance requires:

- valid HTTPS with the managed certificate;
- the expected lower-environment `robots.txt` policy;
- public/browser smoke checks;
- real CIAM token acquisition;
- authenticated `/api/me` success for an invited identity;
- credential fields remaining masked in Actions logs.

Record the run URL as release evidence.

## Azure default hostnames

Do not delete or attempt to replace the App Service
`*.azurewebsites.net` hostname. It is an Azure-owned operational endpoint and
is intentionally retained for:

- package-deployment warm-up and health probes;
- build-version and slot verification;
- App Service diagnostics and recovery;
- staging-slot traffic;
- custom-domain CNAME targets;
- RavenXpress managed tenant-domain targets.

The default hostname is not the supported human-facing address. Remove it
from business bookmarks, test instructions, and customer communications.
Use the branded hostname for all manual testing.

An optional product-level canonical redirect may send ordinary browser
requests on the default hostname to the branded hostname. Such a redirect
must exempt health, metadata, deployment, and other machine-consumed paths.

## Lower-environment access

`robots.txt` prevents routine search indexing; it is not access control.
Custom domains and `noindex` do not make development, UAT, or pre-production
staff-only.

Choose and document a deliberate access perimeter before treating lower
environments as private. Options include an identity-aware edge gate or
carefully managed network restrictions. Do not add shared passwords or a
second ad-hoc authentication mechanism around the product.

## Completion criteria

The custom-domain work for an environment is complete only when:

- DNS and TLS are healthy;
- runtime configuration advertises the branded callback;
- the callback exists on the correct CIAM client;
- the deployed branded-domain authentication smoke passes;
- lower-environment indexing policy is verified;
- business test instructions use only the branded hostname;
- the operational evidence is recorded.

Lower-environment access control is a separate security deliverable and must
not be represented as complete merely because custom domains and
`robots.txt` are in place.
