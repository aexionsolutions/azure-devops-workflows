# azure-devops-workflows

**Reusable GitHub Actions workflows for Azure-based .NET + React/Next.js applications**

[![License](https://img.shields.io/badge/license-Internal-blue.svg)](LICENSE)
[![Status](https://img.shields.io/badge/status-Active-success.svg)]()

## 🎯 Purpose

This repository provides battle-tested, reusable CI/CD workflows for Azure deployments, eliminating duplication across projects and ensuring consistency.

**Currently used by**:
- [TEMS](https://github.com/aexionsolutions/tems)
- [RavenXpress](https://github.com/aexionsolutions/ravenxpress)

## 🚀 Quick Start

### 1. Prerequisites

- Azure subscription with OIDC configured ([Setup Guide](docs/azure-oidc-setup.md))
- GitHub repository secrets configured
- Bicep templates for infrastructure (if using infra workflows)

### 2. Use in Your Workflow

Create a caller workflow in your repository (e.g., `.github/workflows/deploy-infra.yml`):

```yaml
name: Deploy Infrastructure

on:
  workflow_dispatch:
    inputs:
      environment:
        required: true
        type: choice
        options: [dev, uat, preprod, prod]

jobs:
  deploy:
    uses: aexionsolutions/azure-devops-workflows/.github/workflows/azure-infra-deploy.yml@v1.0.0
    with:
      environment: ${{ inputs.environment }}
      azure_location: ukwest
      resource_group: myapp-${{ inputs.environment }}-rg
      name_prefix: myapp-${{ inputs.environment }}
      bicep_template_path: infra/main.bicep
    secrets:
      AZURE_CLIENT_ID: ${{ secrets.AZURE_CLIENT_ID }}
      AZURE_TENANT_ID: ${{ secrets.AZURE_TENANT_ID }}
      AZURE_SUBSCRIPTION_ID: ${{ secrets.AZURE_SUBSCRIPTION_ID }}
      POSTGRES_ADMIN_PASSWORD: ${{ secrets.POSTGRES_ADMIN_PASSWORD }}
```

## 📚 Available Workflows

| Workflow | Purpose | Documentation | Status |
|----------|---------|---------------|--------|
| [azure-infra-deploy.yml](.github/workflows/azure-infra-deploy.yml) | Deploy Bicep infrastructure to Azure | [📖 Docs](docs/workflows/azure-infra-deploy.md) | ✅ Ready |
| [dotnet-ci.yml](.github/workflows/dotnet-ci.yml) | .NET build, test, coverage, SonarCloud | [📖 Docs](docs/workflows/dotnet-ci.md) | ✅ Ready |
| [web-ci.yml](.github/workflows/web-ci.yml) | React/Next.js lint, test, build | [📖 Docs](docs/workflows/web-ci.md) | ✅ Ready |
| azure-api-deploy.yml | Deploy .NET API to App Service | 📖 Docs | 🚧 Planned |
| azure-web-deploy.yml | Deploy static web app | 📖 Docs | 🚧 Planned |

## 📖 Documentation

- **[Usage Guide](docs/usage-guide.md)** - How to consume these workflows
- **[Parameters Reference](docs/parameters-reference.md)** - Complete input/secret documentation
- **[Migration Guide](docs/migration-guide.md)** - Migrate from inline workflows
- **[Examples](docs/examples/)** - Real-world usage examples
- **[Azure OIDC Setup](docs/azure-oidc-setup.md)** - Configure Azure authentication

## 🔐 Required Setup

### Azure Configuration

1. **Service Principal**: Create with Contributor + User Access Administrator roles
2. **Federated Credentials**: One per environment (dev, uat, preprod, prod)
3. **Resource Providers**: Ensure `Microsoft.DBforPostgreSQL` and `microsoft.operationalinsights` registered

See [Azure OIDC Setup Guide](docs/azure-oidc-setup.md) for detailed instructions.

### GitHub Secrets

**Repository Secrets** (one-time setup):
```
AZURE_CLIENT_ID          # Service principal application ID
AZURE_TENANT_ID          # Azure AD tenant ID  
AZURE_SUBSCRIPTION_ID    # Azure subscription ID
```

**Environment Secrets** (per environment: dev, uat, preprod, prod):
```
POSTGRES_ADMIN_PASSWORD  # PostgreSQL admin password
AZURE_LOCATION          # Azure region (e.g., ukwest)
```

## 🔄 Versioning

This repository follows [Semantic Versioning](https://semver.org/):

- **v1.0.0 → v2.0.0**: Breaking changes (update caller workflows required)
- **v1.0.0 → v1.1.0**: New features (backward compatible)
- **v1.0.0 → v1.0.1**: Bug fixes (backward compatible)

### Version Pinning Strategies

```yaml
# ✅ Recommended: Pin to specific version
uses: aexionsolutions/azure-devops-workflows/.github/workflows/azure-infra-deploy.yml@v1.2.0

# ✅ Safe: Latest patch version
uses: aexionsolutions/azure-devops-workflows/.github/workflows/azure-infra-deploy.yml@v1.2

# ✅ Moderate risk: Latest minor version
uses: aexionsolutions/azure-devops-workflows/.github/workflows/azure-infra-deploy.yml@v1

# ⚠️ Not recommended for production: Always latest (may break)
uses: aexionsolutions/azure-devops-workflows/.github/workflows/azure-infra-deploy.yml@main
```

## 🛠️ Development

### Testing Changes

1. Create feature branch: `git checkout -b feature/my-change`
2. Make workflow changes
3. Test from consumer repo using branch reference:
   ```yaml
   uses: aexionsolutions/azure-devops-workflows/.github/workflows/azure-infra-deploy.yml@feature/my-change
   ```
4. Create PR for review
5. After merge, tag release: `git tag v1.1.0 && git push --tags`

### Contributing

1. Follow existing workflow patterns and naming conventions
2. Document all inputs, secrets, and outputs
3. Add usage examples to [docs/examples/](docs/examples/)
4. Test with both TEMS and RavenXpress before releasing
5. Update [CHANGELOG.md](CHANGELOG.md) with changes

## 📊 Adoption Status

| Project | Status | Version | Migration Date |
|---------|--------|---------|----------------|
| TEMS | 🚧 In Progress | - | January 2026 |
| RavenXpress | 📋 Planned | - | TBD |

## 🎯 Benefits

### Before (Inline Workflows)
- 🔄 Duplicate workflow code across projects
- ⚠️ Manual synchronization required
- 🐛 Bugs fixed in one place, forgotten in another
- ⏰ Time-consuming updates across multiple repos

### After (Shared Workflows)
- ✅ Single source of truth
- ✅ Update once, benefit everywhere
- ✅ No drift between projects
- ✅ Faster onboarding for new projects

## 🆘 Support

**Having issues?**
1. Check [documentation](docs/)
2. Review [examples](docs/examples/)
3. Search [existing issues](https://github.com/aexionsolutions/azure-devops-workflows/issues)
4. Open a [new issue](https://github.com/aexionsolutions/azure-devops-workflows/issues/new)

## 📝 License

Internal use only - AexionSolutions Ltd © 2026

## 🔗 Related Resources

- [GitHub Reusable Workflows](https://docs.github.com/en/actions/using-workflows/reusing-workflows)
- [Azure OIDC with GitHub Actions](https://learn.microsoft.com/azure/developer/github/connect-from-azure)
- [Bicep Documentation](https://learn.microsoft.com/azure/azure-resource-manager/bicep/)
- [GitHub Actions Security](https://docs.github.com/en/actions/security-guides/security-hardening-for-github-actions)
