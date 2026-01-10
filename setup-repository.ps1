#Requires -Version 7.0

<#
.SYNOPSIS
    Initialize and publish the azure-devops-workflows repository to GitHub.

.DESCRIPTION
    This script automates the complete setup process:
    1. Initializes git repository
    2. Creates GitHub repository (via GitHub CLI)
    3. Configures branch protection
    4. Commits and pushes all files
    5. Creates initial v1.0.0 release

.PARAMETER SkipGitHubCreation
    Skip GitHub repository creation (assumes repo already exists)

.PARAMETER SkipBranchProtection
    Skip branch protection rules setup

.EXAMPLE
    .\setup-repository.ps1
    
.EXAMPLE
    .\setup-repository.ps1 -SkipGitHubCreation

.NOTES
    Requires: GitHub CLI (gh) authenticated
    Requires: Git installed
#>

[CmdletBinding()]
param(
    [Parameter(Mandatory=$false)]
    [switch]$SkipGitHubCreation,
    
    [Parameter(Mandatory=$false)]
    [switch]$SkipBranchProtection
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

# Configuration
$REPO_NAME = "azure-devops-workflows"
$ORG_NAME = "aexionsolutions"
$REPO_DESCRIPTION = "Reusable GitHub Actions workflows for Azure-based .NET + React applications"
$REPO_PATH = $PSScriptRoot

# ANSI color codes
$ColorReset = "`e[0m"
$ColorGreen = "`e[32m"
$ColorYellow = "`e[33m"
$ColorRed = "`e[31m"
$ColorBlue = "`e[34m"
$ColorCyan = "`e[36m"

function Write-Success {
    param([string]$Message)
    Write-Host "${ColorGreen}✅ $Message${ColorReset}"
}

function Write-Warning {
    param([string]$Message)
    Write-Host "${ColorYellow}⚠️  $Message${ColorReset}"
}

function Write-Error {
    param([string]$Message)
    Write-Host "${ColorRed}❌ $Message${ColorReset}"
}

function Write-Info {
    param([string]$Message)
    Write-Host "${ColorBlue}ℹ️  $Message${ColorReset}"
}

function Write-Step {
    param([string]$Message)
    Write-Host "${ColorCyan}▶ $Message${ColorReset}"
}

function Test-Command {
    param([string]$Command)
    
    try {
        $null = Get-Command $Command -ErrorAction Stop
        return $true
    }
    catch {
        return $false
    }
}

try {
    Write-Host ""
    Write-Host "═══════════════════════════════════════════════════════════════" -ForegroundColor Cyan
    Write-Host "  Azure DevOps Workflows - Repository Setup" -ForegroundColor Cyan
    Write-Host "═══════════════════════════════════════════════════════════════" -ForegroundColor Cyan
    Write-Host ""
    
    # Validate prerequisites
    Write-Step "Validating prerequisites..."
    
    if (-not (Test-Command "git")) {
        Write-Error "Git is not installed. Please install Git first."
        exit 1
    }
    Write-Success "Git installed"
    
    if (-not (Test-Command "gh")) {
        Write-Error "GitHub CLI (gh) is not installed. Please install it first."
        Write-Info "Install from: https://cli.github.com/"
        exit 1
    }
    Write-Success "GitHub CLI installed"
    
    # Check GitHub CLI authentication
    Write-Step "Checking GitHub CLI authentication..."
    $ghAuthStatus = gh auth status 2>&1
    if ($LASTEXITCODE -ne 0) {
        Write-Error "GitHub CLI is not authenticated"
        Write-Info "Run: gh auth login"
        exit 1
    }
    Write-Success "GitHub CLI authenticated"
    
    Write-Host ""
    
    # Initialize git repository
    Write-Step "Initializing git repository..."
    Push-Location $REPO_PATH
    
    if (Test-Path ".git") {
        Write-Warning "Git repository already initialized"
    }
    else {
        git init
        Write-Success "Git repository initialized"
    }
    
    # Create GitHub repository (if needed)
    if (-not $SkipGitHubCreation) {
        Write-Step "Creating GitHub repository..."
        
        $repoExists = gh repo view "$ORG_NAME/$REPO_NAME" 2>&1
        if ($LASTEXITCODE -eq 0) {
            Write-Warning "Repository $ORG_NAME/$REPO_NAME already exists"
        }
        else {
            Write-Info "Creating repository: $ORG_NAME/$REPO_NAME"
            gh repo create "$ORG_NAME/$REPO_NAME" `
                --description "$REPO_DESCRIPTION" `
                --private `
                --source=. `
                --remote=origin
            
            Write-Success "Repository created"
        }
    }
    
    # Configure git remote (if not already set)
    Write-Step "Configuring git remote..."
    $remoteUrl = git remote get-url origin 2>&1
    if ($LASTEXITCODE -ne 0) {
        git remote add origin "https://github.com/$ORG_NAME/$REPO_NAME.git"
        Write-Success "Git remote configured"
    }
    else {
        Write-Info "Git remote already configured: $remoteUrl"
    }
    
    # Create .gitignore
    Write-Step "Creating .gitignore..."
    $gitignoreContent = @"
# OS
.DS_Store
Thumbs.db

# IDE
.vscode/
.idea/
*.swp
*.swo

# Logs
*.log
npm-debug.log*
yarn-debug.log*
yarn-error.log*

# Temporary files
*.tmp
*.temp
.temp/
"@
    $gitignoreContent | Out-File -FilePath ".gitignore" -Encoding utf8 -Force
    Write-Success ".gitignore created"
    
    # Commit all files
    Write-Step "Committing files..."
    git add .
    git commit -m "Initial commit: Reusable Azure DevOps workflows

- Azure infrastructure deployment (Bicep)
- .NET CI with coverage and SonarCloud
- Web CI for React/Next.js projects
- Complete documentation and examples
- Setup scripts for Azure OIDC"
    
    Write-Success "Files committed"
    
    # Set default branch to main
    Write-Step "Setting default branch to main..."
    $currentBranch = git branch --show-current
    if ($currentBranch -ne "main") {
        git branch -M main
        Write-Success "Renamed branch to main"
    }
    
    # Push to GitHub
    Write-Step "Pushing to GitHub..."
    git push -u origin main
    Write-Success "Pushed to GitHub"
    
    # Configure branch protection (if requested)
    if (-not $SkipBranchProtection) {
        Write-Step "Configuring branch protection for main..."
        
        try {
            gh api repos/$ORG_NAME/$REPO_NAME/branches/main/protection `
                -X PUT `
                -H "Accept: application/vnd.github+json" `
                -f required_status_checks='{"strict":true,"contexts":[]}' `
                -f enforce_admins=false `
                -f required_pull_request_reviews='{"required_approving_review_count":1}' `
                -f restrictions=null `
                2>&1 | Out-Null
            
            Write-Success "Branch protection configured"
        }
        catch {
            Write-Warning "Could not configure branch protection (may require admin permissions)"
        }
    }
    
    # Create initial release
    Write-Step "Creating initial release v1.0.0..."
    
    $releaseNotes = @"
## 🎉 Initial Release

First stable release of shared Azure DevOps workflows.

### ✨ Features

- **azure-infra-deploy.yml**: Deploy Bicep infrastructure with OIDC authentication
  - Automatic PostgreSQL server management
  - Key Vault RBAC configuration
  - Provider registration
  - Comprehensive error handling

- **dotnet-ci.yml**: .NET CI with coverage and quality gates
  - Unit and integration test support
  - Code coverage reporting
  - SonarCloud integration
  - Playwright E2E test support

- **web-ci.yml**: Web CI for React/Next.js projects
  - Lint, test, and build
  - Playwright browser automation
  - npm and pnpm support

### 📚 Documentation

- Complete usage guide
- Parameters reference
- Migration guide from inline workflows
- Azure OIDC setup instructions
- Real-world examples from TEMS and RavenXpress

### 🚀 Getting Started

See the [README](https://github.com/$ORG_NAME/$REPO_NAME#readme) for quick start guide.
"@
    
    git tag -a v1.0.0 -m "Release v1.0.0"
    git push origin v1.0.0
    
    gh release create v1.0.0 `
        --title "v1.0.0 - Initial Release" `
        --notes "$releaseNotes" `
        --verify-tag
    
    Write-Success "Release v1.0.0 created"
    
    Pop-Location
    
    # Summary
    Write-Host ""
    Write-Host "═══════════════════════════════════════════════════════════════" -ForegroundColor Cyan
    Write-Host "  Setup Complete!" -ForegroundColor Cyan
    Write-Host "═══════════════════════════════════════════════════════════════" -ForegroundColor Cyan
    Write-Host ""
    Write-Success "Repository: https://github.com/$ORG_NAME/$REPO_NAME"
    Write-Success "Version: v1.0.0"
    Write-Host ""
    Write-Info "Next Steps:"
    Write-Host "  1. Review workflows: https://github.com/$ORG_NAME/$REPO_NAME/tree/main/.github/workflows"
    Write-Host "  2. Update TEMS to use shared workflows"
    Write-Host "  3. Update RavenXpress to use shared workflows"
    Write-Host "  4. Test workflows in dev environment"
    Write-Host ""
    Write-Success "Setup completed successfully!"
    
    exit 0
}
catch {
    Write-Error "Setup failed: $_"
    Write-Host $_.ScriptStackTrace
    Pop-Location
    exit 1
}
