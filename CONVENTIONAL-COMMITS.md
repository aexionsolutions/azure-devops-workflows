# Conventional Commits Guide

This repository uses [Conventional Commits](https://www.conventionalcommits.org/) for automatic version tagging.

## 📝 Commit Message Format

```
<type>[optional scope][!]: <description>

[optional body]

[optional footer(s)]
```

## 🏷️ Types

### Breaking Changes (Major version bump: v1.0.0 → v2.0.0)
```bash
feat!: add required inputs for all workflows
# or
feat: add new parameter

BREAKING CHANGE: All callers must now provide explicit paths
```

### Features (Minor version bump: v1.0.0 → v1.1.0)
```bash
feat: add pre-release tagging workflow
feat(dotnet-ci): add sonar_exclusions input parameter
```

### Fixes & Improvements (Patch version bump: v1.0.0 → v1.0.1)
```bash
fix: correct SonarCloud lcov path detection
fix(web-deploy): remove hardcoded TEMS paths
chore: update documentation
refactor: simplify exclusion building logic
perf: optimize coverage reporting
```

### Non-versioned Changes (No version bump)
```bash
docs: update README
test: add unit tests
ci: update GitHub Actions
style: fix formatting
```

## 🚀 Automated Workflow

### When PR is Created/Updated:
1. Workflow analyzes commit messages
2. Determines version bump type (major/minor/patch)
3. Creates pre-release tag: `v3.2.0-pr.123.abc1234`
4. Comments on PR with tag info
5. Calling repos can test with: `@v3.2.0-pr.123.abc1234`

### When PR is Merged to Main:
1. Workflow analyzes all commits since last release
2. Creates stable tag: `v3.2.0`
3. Creates GitHub Release with CHANGELOG
4. Calling repos update to: `@v3.2.0`

## 💡 Examples

### This PR (Breaking Changes)
```bash
git add .
git commit -m "feat!: remove hardcoded repo-specific paths

BREAKING CHANGE: All workflows now require explicit path inputs.
- js_lcov_path is now required (no auto-construction)
- sonar_exclusions and sonar_coverage_exclusions are required
- concurrency_group is required in web-deploy and api-deploy
- Removes all TEMS-specific defaults for multi-repo compatibility

Migration guide provided in TEMS-MIGRATION-GUIDE.md"
```

Expected result: `v1.0.0` → `v2.0.0` (major bump)

### Feature Addition
```bash
git commit -m "feat(azure-infra): add container registry support

Adds new input parameters for ACR deployment"
```

Expected result: `v2.0.0` → `v2.1.0` (minor bump)

### Bug Fix
```bash
git commit -m "fix(sonar): correct coverage exclusion patterns

Fixes issue where .d.ts files were incorrectly included in coverage"
```

Expected result: `v2.1.0` → `v2.1.1` (patch bump)

## 🔍 Viewing Generated Tags

### Pre-release Tags (on PR)
- Visit PR page
- Bot will comment with tag: `v3.2.0-pr.123.abc1234`
- Also visible in GitHub Tags page

### Release Tags (on merge)
- Visit Releases page: `https://github.com/aexionsolutions/azure-devops-workflows/releases`
- View tag history: `https://github.com/aexionsolutions/azure-devops-workflows/tags`

## 🛠️ Manual Override (if needed)

If automatic detection fails:

```bash
# Create tag manually
git tag -a v3.2.0 -m "Release v3.2.0"
git push origin v3.2.0

# Create GitHub Release
gh release create v3.2.0 --title "Release v3.2.0" --notes "See CHANGELOG.md"
```

## 📋 Checklist for This PR

- ✅ Created feature branch (not on main)
- ✅ Made changes
- ✅ Updated CHANGELOG.md with breaking changes
- ✅ Commit with conventional commit message
- ✅ Push and create PR
- ✅ Verify pre-release tag created
- ✅ Test pre-release in TEMS repo
- ✅ Merge PR after approval
- ✅ Verify stable tag `v3.2.0` created
- ✅ Update TEMS to stable tag

## 🔐 Branch Protection Required

Set these rules on main branch:
1. ✅ Require pull request before merging
2. ✅ Require approvals (at least 1)
3. ✅ Require status checks to pass
4. ✅ Require conversation resolution
5. ✅ Do not allow bypassing the above settings
