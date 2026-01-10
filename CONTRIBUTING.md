# Contributing to Azure DevOps Workflows

Thank you for contributing! This document provides guidelines for contributing to this repository.

## Development Workflow

### 1. Create Feature Branch

```bash
git checkout -b feature/my-improvement
```

### 2. Make Changes

- Update workflows in `.github/workflows/`
- Add/update documentation in `docs/`
- Update CHANGELOG.md with your changes

### 3. Test Changes

Test your changes from a consumer repository (TEMS or RavenXpress):

```yaml
uses: aexionsolutions/azure-devops-workflows/.github/workflows/azure-infra-deploy.yml@feature/my-improvement
```

### 4. Create Pull Request

- Provide clear description of changes
- Reference any related issues
- Ensure all documentation is updated
- Add examples if introducing new features

### 5. Code Review

- Address review comments
- Ensure CI passes
- Get approval from at least one maintainer

### 6. Merge and Release

After merge:
1. Create and push version tag: `git tag v1.1.0 && git push --tags`
2. Create GitHub release with changelog

## Guidelines

### Workflow Design

- **Keep workflows generic**: Avoid hardcoding project-specific values
- **Use inputs**: Make everything configurable via inputs
- **Provide defaults**: Sensible defaults for common scenarios
- **Document everything**: Every input, secret, and output

### Breaking Changes

- **Avoid when possible**: Try to maintain backward compatibility
- **Version bump**: Increment major version (v1.x.x → v2.0.0)
- **Migration guide**: Document upgrade path in CHANGELOG

### Documentation

- **Update usage guide**: For new parameters or workflows
- **Add examples**: Real-world usage examples
- **Update changelog**: Document all changes

### Testing

- **Test locally**: Use feature branch references from consumer repos
- **Test all scenarios**: Happy path and error cases
- **Test with both projects**: TEMS and RavenXpress

## Code Style

### Workflow Files

```yaml
# Use descriptive names
name: Azure Infrastructure Deploy

# Group related inputs
inputs:
  # Environment Configuration
  environment:
    description: 'Clear description'
    required: true
    type: string
  
  # Database Configuration
  postgres_admin_user:
    description: 'PostgreSQL admin username'
    required: false
    type: string
    default: 'pgadmin'

# Use clear step names
steps:
  - name: Checkout repository
    uses: actions/checkout@v4
  
  - name: Deploy Bicep template
    shell: bash
    run: |
      set -e  # Fail fast
      az deployment group create ...
```

### Shell Scripts

```bash
# Use strict mode
set -e

# Clear variable names
RESOURCE_GROUP="${{ inputs.resource_group }}"

# Informative output
echo "Deploying to resource group: $RESOURCE_GROUP"

# Error handling
if [ -z "$RESOURCE_GROUP" ]; then
  echo "❌ Resource group not specified"
  exit 1
fi
```

## Versioning

We follow [Semantic Versioning](https://semver.org/):

- **Major (v1.0.0 → v2.0.0)**: Breaking changes
- **Minor (v1.0.0 → v1.1.0)**: New features, backward compatible
- **Patch (v1.0.0 → v1.0.1)**: Bug fixes

## Questions?

- Open an issue for discussion
- Contact the DevOps team
- Check existing documentation

Thank you for contributing! 🎉
