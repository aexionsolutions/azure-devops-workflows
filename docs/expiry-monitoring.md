# Certificate and credential expiry monitoring

The public monitor checks actual TLS certificates daily at 11:15 UTC across RavenXpress, TEMS and Aexion Solutions. The Azure reusable monitor runs under each caller's environment-bound OIDC identity. It lists expiry metadata for explicitly inventoried Entra apps, subscription App Service certificates, and enabled Key Vault secrets, keys and certificates. It never reads secret values, private keys, app settings or GitHub secret contents.

Warnings start at 60 days, with 30/14/7-day bands. Expired, unknown and unavailable targets fail the run. Failed checks preserve metadata reports for 30 days and maintain one open GitHub issue per scope; a complete successful run closes it. Job summaries contain the full result. Repository owners should watch these alert issues and enable Actions failure notifications. Updating an existing issue does not guarantee a new notification; the open issue and failing daily run remain the durable signals. No external email service is configured.

## Activation

Merge the shared workflow change to activate its scheduled public TLS scan. Merge each app's caller to activate Azure monitoring. Callers pin the shared implementation to an immutable commit, including its checkout ref. Dispatch the workflows once after merge and inspect the report: unreadable metadata must be resolved or explicitly documented before claiming coverage. No new Azure permissions are automatically granted.

Use Azure Reader at the required subscription scope, metadata-only Key Vault Reader where RBAC vaults permit it, and appropriate Entra application metadata read permissions for the explicit app list. Azure RBAC does not grant Microsoft Graph access. Access-policy vaults may require separate list permission. Do not grant secret-value retrieval solely for monitoring. Customer identity directories need their own identity/trust and metadata permissions; the workforce login does not cover them.

Production public hosts are monitored now, independently of app environments. Add Azure prod callers only after configuring their environment OIDC identity and target subscription; do not invent a production subscription or use dev credentials for it. Hosts that are not serving trusted HTTPS remain unavailable alerts until corrected or deliberately removed from the inventory with an explanation.

## Renewal and rotation

RavenXpress already has an hourly `Dev Wildcard TLS` workflow. It requests renewal within 30 days, uploads the replacement and verifies the SNI binding. Keep that renewal job; this monitor independently checks the certificates served by representative tenant hosts. Add representative hosts for each new certificate boundary, including custom customer domains.

Azure-managed App Service and Static Web Apps certificates should renew through their platform provider. Monitoring is still required because DNS or validation changes can prevent renewal. Verify the live served certificate after provider renewal; an uploaded certificate alone does not prove the correct binding.

Do not generically auto-rotate Entra client secrets, signing keys, database passwords or third-party credentials. Rotation needs a consumer-specific process: create replacement, install in every consumer, validate authentication, then retire the old credential. Prefer OIDC/managed identities to remove client secrets. The existing TEMS fallback must not be removed until its remaining callers support OIDC and are verified.

## Coverage and known limits

Initial public inventory: root/www RavenXpress, TEMS and Aexion Solutions, both dev front doors, and two RavenXpress tenant hosts. Initial Azure callers cover each dev subscription and known workforce deployment/workload applications. The Aexion website uses Azure Static Web Apps; its public TLS is covered, but its deployment token has no observable expiry through GitHub secrets. Additional identity-directory app credentials, third-party tokens, DNS/domain registrations, private endpoints, GitHub Apps/PATs and non-Azure certificates are not automatically discovered. GitHub's secret update timestamp is not an expiry date, and a valid Entra credential does not prove the stored GitHub value matches it.

When adding an app, domain, vault, subscription or identity directory, update the inventory/caller and prove a manual run. Review inventory quarterly. Unknown expiry requires provider documentation or a documented rotation owner, not a fabricated date. Disabled Key Vault items are excluded; enabled historical Azure certificates may still alert even if no longer bound. Confirm non-use before deleting retired resources.
