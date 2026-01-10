# TEMS Infrastructure Deployment Example

This is a real-world example of how TEMS uses the shared `azure-infra-deploy` workflow.

## Caller Workflow

**File**: `.github/workflows/tems-infra-deploy.yml`

```yaml
name: TEMS Infra Deploy

on:
  workflow_dispatch:
    inputs:
      environment:
        description: 'Environment to deploy'
        required: true
        default: dev
        type: choice
        options: [dev, uat, preprod, prod]
      manageExistingPostgres:
        description: 'Allow infrastructure to update existing Postgres server'
        required: false
        default: false
        type: boolean

concurrency:
  group: tems-infra-${{ inputs.environment }}-deploy
  cancel-in-progress: ${{ inputs.environment != 'prod' }}

jobs:
  deploy-infrastructure:
    uses: aexionsolutions/azure-devops-workflows/.github/workflows/azure-infra-deploy.yml@v1.0.0
    with:
      # Environment Configuration
      environment: ${{ inputs.environment }}
      azure_location: ${{ vars.AZURE_LOCATION || 'ukwest' }}
      resource_group: tems-${{ inputs.environment }}-rg
      name_prefix: tems-${{ inputs.environment }}
      
      # Bicep Configuration
      bicep_template_path: infra/tems-infra/azure/main.bicep
      deployment_name: main
      
      # PostgreSQL Configuration
      postgres_admin_user: temsadmin
      manage_existing_postgres: ${{ inputs.manageExistingPostgres }}
      
      # Azure AD B2C
      aad_b2c_authority: ${{ secrets.AAD_B2C_AUTHORITY }}
      aad_b2c_client_id: ${{ secrets.AAD_B2C_CLIENT_ID }}
      aad_b2c_api_scope: ${{ secrets.AAD_B2C_API_SCOPE }}
      
      # Feature Flags
      enable_kv_rbac: true
      validate_secrets: true
    secrets:
      AZURE_CLIENT_ID: ${{ secrets.AZURE_CLIENT_ID }}
      AZURE_TENANT_ID: ${{ secrets.AZURE_TENANT_ID }}
      AZURE_SUBSCRIPTION_ID: ${{ secrets.AZURE_SUBSCRIPTION_ID }}
      POSTGRES_ADMIN_PASSWORD: ${{ secrets.POSTGRES_ADMIN_PASSWORD }}
```

## Required Secrets

### Repository Secrets

```
AZURE_CLIENT_ID=456eced5-12cd-45fc-b943-91fe1e0c92a1
AZURE_TENANT_ID=<your-tenant-id>
AZURE_SUBSCRIPTION_ID=0411cfe0-0738-4dbd-b3c3-39b7b2ab5359
```

### Environment Secrets (per environment)

**dev environment**:
```
POSTGRES_ADMIN_PASSWORD=<secure-password>
AAD_B2C_AUTHORITY=https://temsdev.b2clogin.com/...
AAD_B2C_CLIENT_ID=<b2c-client-id>
AAD_B2C_API_SCOPE=api://tems-dev/...
```

**uat environment**:
```
POSTGRES_ADMIN_PASSWORD=<secure-password>
AAD_B2C_AUTHORITY=https://temsuat.b2clogin.com/...
AAD_B2C_CLIENT_ID=<b2c-client-id>
AAD_B2C_API_SCOPE=api://tems-uat/...
```

(Similar for preprod and prod)

### Repository Variables

```
AZURE_LOCATION=ukwest
```

## Usage

### Deploy to Dev

1. Go to Actions → TEMS Infra Deploy
2. Click "Run workflow"
3. Select environment: `dev`
4. Click "Run workflow"

### Deploy with PostgreSQL Management

If you need to update an existing PostgreSQL server:

1. Go to Actions → TEMS Infra Deploy
2. Click "Run workflow"
3. Select environment: `dev`
4. Check "Allow infrastructure to update existing Postgres server"
5. Click "Run workflow"

## Bicep Template Structure

**File**: `infra/tems-infra/azure/main.bicep`

```bicep
@description('Name prefix for all resources')
param namePrefix string

@description('PostgreSQL admin username')
param pgAdminUser string

@description('PostgreSQL admin password')
@secure()
param pgAdminPassword string

@description('PostgreSQL server already exists')
param pgExisting bool = false

@description('Ensure database exists on existing server')
param ensureDbOnExisting bool = false

@description('Azure AD B2C authority URL')
param aadAuthority string = ''

@description('Azure AD B2C client ID')
param aadClientId string = ''

@description('Azure AD B2C API scope')
param aadApiScope string = ''

// Resources
module postgres 'modules/postgresql.bicep' = if (!pgExisting) {
  name: 'postgres-deployment'
  params: {
    serverName: '${namePrefix}-pg'
    adminUser: pgAdminUser
    adminPassword: pgAdminPassword
  }
}

module keyVault 'modules/keyvault.bicep' = {
  name: 'keyvault-deployment'
  params: {
    vaultName: '${namePrefix}-kv'
    enableRbac: true
  }
}

// Outputs
output keyVaultName string = keyVault.outputs.vaultName
output postgresServerName string = pgExisting ? '${namePrefix}-pg' : postgres.outputs.serverName
```

## Expected Behavior

### First Deployment (New Environment)

1. ✅ Creates resource group if not exists
2. ✅ Registers Azure resource providers
3. ✅ Deploys all Bicep resources:
   - PostgreSQL Flexible Server
   - Key Vault with RBAC
   - App Service Plan
   - App Services (API, Web)
   - Managed Identities
   - Application Insights
4. ✅ Configures Key Vault RBAC for workflow and managed identities
5. ✅ Stores connection strings in Key Vault

**Duration**: ~5-7 minutes

### Subsequent Deployments

1. ✅ Validates secrets
2. ✅ Checks PostgreSQL server state
3. ✅ Updates changed resources only
4. ✅ Skips PostgreSQL server (unless `manageExistingPostgres: true`)
5. ✅ Updates Key Vault secrets

**Duration**: ~2-3 minutes

## Troubleshooting

### "PostgreSQL server did not reach Ready state"

**Cause**: Server was stopped and didn't start in time.

**Solution**: Run again with `manageExistingPostgres: true` to ensure proper startup.

### "Key Vault RBAC assignment failed"

**Cause**: Service principal lacks User Access Administrator role.

**Solution**: See [Azure Setup Guide](../../docs/deployment/azure-setup.md) to grant required role.

### "Secret POSTGRES_ADMIN_PASSWORD not found"

**Cause**: Secret not configured for the target environment.

**Solution**: 
1. Go to GitHub repository Settings
2. Navigate to Secrets and variables → Actions
3. Select the environment (e.g., "dev")
4. Add secret `POSTGRES_ADMIN_PASSWORD`

## Integration with Other Workflows

After infrastructure deployment, you can deploy applications:

```yaml
jobs:
  # 1. Deploy infrastructure
  infrastructure:
    uses: aexionsolutions/azure-devops-workflows/.github/workflows/azure-infra-deploy.yml@v1.0.0
    # ... parameters ...
  
  # 2. Deploy API (depends on infrastructure)
  api:
    needs: infrastructure
    uses: aexionsolutions/azure-devops-workflows/.github/workflows/azure-api-deploy.yml@v1.0.0
    # ... parameters ...
  
  # 3. Deploy Web (depends on infrastructure)
  web:
    needs: infrastructure
    uses: aexionsolutions/azure-devops-workflows/.github/workflows/azure-web-deploy.yml@v1.0.0
    # ... parameters ...
```

## Monitoring

View deployment progress:
- GitHub Actions: Real-time logs and status
- Azure Portal: Resource deployment status
- Application Insights: Post-deployment health

## References

- [TEMS Documentation](https://github.com/aexionsolutions/tems/tree/main/docs)
- [Bicep Template](https://github.com/aexionsolutions/tems/tree/main/infra/tems-infra/azure)
- [Azure Setup Guide](https://github.com/aexionsolutions/tems/blob/main/docs/deployment/azure-setup.md)
