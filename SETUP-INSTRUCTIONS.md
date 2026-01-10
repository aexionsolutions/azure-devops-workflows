# 🚀 Setup Instructions

## You're Almost There!

I've created the complete `azure-devops-workflows` repository structure at:
```
C:\Users\tahir\Source\azure-devops-workflows\
```

All files are ready. You just need to create the GitHub repository and push!

## ✅ What's Been Created

### Workflows (3 core workflows)
- ✅ `azure-infra-deploy.yml` - Infrastructure deployment with OIDC, PostgreSQL, Key Vault
- ✅ `dotnet-ci.yml` - .NET CI with coverage, SonarCloud, Playwright
- ✅ `web-ci.yml` - React/Next.js CI with lint, test, build

### Documentation
- ✅ `README.md` - Repository overview and quick start
- ✅ `docs/usage-guide.md` - Complete usage guide with examples
- ✅ `docs/examples/tems-infra-deploy.md` - Real-world TEMS example
- ✅ `CHANGELOG.md` - Version history
- ✅ `CONTRIBUTING.md` - Contribution guidelines
- ✅ `LICENSE` - Internal use license

### Scripts
- ✅ `setup-repository.ps1` - Automated setup script (creates repo, commits, tags v1.0.0)

## 🎯 Next Steps

### Option A: Automated Setup (Recommended)

Run the setup script to do everything automatically:

```powershell
cd C:\Users\tahir\Source\azure-devops-workflows
.\setup-repository.ps1
```

This will:
1. ✅ Initialize git repository
2. ✅ Create GitHub repository `aexionsolutions/azure-devops-workflows`
3. ✅ Configure branch protection on main
4. ✅ Commit all files
5. ✅ Push to GitHub
6. ✅ Create v1.0.0 release

**Prerequisites**: GitHub CLI (gh) must be authenticated
```powershell
gh auth login  # If not already authenticated
```

### Option B: Manual Setup

If you prefer to do it manually:

```powershell
cd C:\Users\tahir\Source\azure-devops-workflows

# Initialize git
git init
git add .
git commit -m "Initial commit: Reusable Azure DevOps workflows"

# Create GitHub repository (via web UI or CLI)
gh repo create aexionsolutions/azure-devops-workflows --private --source=. --remote=origin

# Push to GitHub
git branch -M main
git push -u origin main

# Create release
git tag v1.0.0
git push origin v1.0.0
gh release create v1.0.0 --title "v1.0.0 - Initial Release" --notes "First stable release"
```

## 📝 After Repository Creation

### 1. Update TEMS to Use Shared Workflows

I've created a migration plan in TEMS:
```
C:\Users\tahir\Source\tems\docs\architecture\workflow-consolidation-plan.md
```

Create a new workflow in TEMS (`.github/workflows/tems-infra-deploy.yml`):

```yaml
name: TEMS Infra Deploy

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
      resource_group: tems-${{ inputs.environment }}-rg
      name_prefix: tems-${{ inputs.environment }}
      bicep_template_path: infra/tems-infra/azure/main.bicep
      postgres_admin_user: temsadmin
    secrets:
      AZURE_CLIENT_ID: ${{ secrets.AZURE_CLIENT_ID }}
      AZURE_TENANT_ID: ${{ secrets.AZURE_TENANT_ID }}
      AZURE_SUBSCRIPTION_ID: ${{ secrets.AZURE_SUBSCRIPTION_ID }}
      POSTGRES_ADMIN_PASSWORD: ${{ secrets.POSTGRES_ADMIN_PASSWORD }}
```

### 2. Test the Shared Workflow

1. Push the new caller workflow to TEMS
2. Run it manually: Actions → TEMS Infra Deploy → Run workflow
3. Verify it works correctly
4. Once validated, you can delete the old inline `infra-deploy.yml`

### 3. Migrate Other Workflows

Follow the same pattern for:
- CI workflows (dotnet-ci, web-ci)
- Deployment workflows (when ready)

## 🎓 Learning & Support

### Documentation
- Review the [Usage Guide](C:\Users\tahir\Source\azure-devops-workflows\docs\usage-guide.md)
- Check [Examples](C:\Users\tahir\Source\azure-devops-workflows\docs\examples)
- Read [TEMS Example](C:\Users\tahir\Source\azure-devops-workflows\docs\examples\tems-infra-deploy.md)

### Repository Structure
```
azure-devops-workflows/
├── .github/workflows/        # Reusable workflows
│   ├── azure-infra-deploy.yml
│   ├── dotnet-ci.yml
│   └── web-ci.yml
├── docs/                     # Documentation
│   ├── usage-guide.md
│   └── examples/
│       └── tems-infra-deploy.md
├── setup-repository.ps1      # Setup automation
├── README.md
├── CHANGELOG.md
├── CONTRIBUTING.md
└── LICENSE
```

## ✨ Benefits You'll Get

### Before (Current State)
- 🔄 22+ workflow files in TEMS (many duplicated in RavenXpress)
- ⚠️ Manual sync between projects
- 🐛 Bug fixes need to be applied twice
- ⏰ Time-consuming maintenance

### After (With Shared Workflows)
- ✅ 3 shared workflows consumed by both projects
- ✅ Update once, benefit everywhere
- ✅ No drift between projects
- ✅ 5 minutes to add new project with same pattern

## 🚧 Future Work

After initial setup:
- [ ] Extract API deployment workflow
- [ ] Extract web deployment workflow
- [ ] Migrate RavenXpress to shared workflows
- [ ] Add workflow validation tests
- [ ] Create automated testing pipeline

## 📞 Need Help?

If you encounter issues:
1. Check the [Usage Guide](C:\Users\tahir\Source\azure-devops-workflows\docs\usage-guide.md)
2. Review existing documentation
3. Test from feature branch first
4. Ask for help if stuck

## 🎉 Ready to Go!

Everything is prepared. Just run:

```powershell
cd C:\Users\tahir\Source\azure-devops-workflows
.\setup-repository.ps1
```

Then start using it in TEMS! 🚀
