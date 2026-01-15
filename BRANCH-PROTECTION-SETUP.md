# Branch Protection Setup Guide

## 🔐 Setting Up Branch Protection for Main

### Go to GitHub Repository Settings

1. Navigate to: `https://github.com/aexionsolutions/azure-devops-workflows/settings`
2. Click **Branches** in the left sidebar
3. Click **Add branch protection rule**

---

## ✅ Required Settings for `main` Branch

### Branch name pattern:
```
main
```

### Protection Rules:

#### ✅ Require a pull request before merging
- [x] **Require a pull request before merging**
  - [x] Require approvals: **1**
  - [x] Dismiss stale pull request approvals when new commits are pushed
  - [x] Require review from Code Owners (if CODEOWNERS file exists)

#### ✅ Require status checks to pass before merging
- [x] **Require status checks to pass before merging**
  - [x] Require branches to be up to date before merging
  - Add status checks (once workflows run):
    - `prerelease-tag` (from version-tag.yml)
    - `release-tag` (from version-tag.yml)

#### ✅ Require conversation resolution before merging
- [x] **Require conversation resolution before merging**

#### ✅ Require linear history (optional but recommended)
- [x] **Require linear history**
  - Prevents merge commits, enforces rebase or squash

#### ✅ Require deployments to succeed before merging
- [ ] Skip this (not needed for workflow repo)

#### ❌ Do not allow bypassing the above settings
- [x] **Do not allow bypassing the above settings**
  - Even admins must follow these rules

#### ✅ Restrict who can push to matching branches (optional)
- [ ] Skip this unless you want to limit who can create PRs

---

## 🎯 Recommended Additional Settings

### ✅ Rules applied to everyone including administrators
**Why:** Ensures consistent quality, even for urgent fixes

### ✅ Allow force pushes: NO
**Why:** Protects history integrity

### ✅ Allow deletions: NO
**Why:** Prevents accidental branch deletion

---

## 📝 CODEOWNERS File (Optional)

Create `.github/CODEOWNERS` for automatic review assignments:

```
# Global owners - review all changes
* @tahir @your-team

# Workflow-specific owners
/.github/workflows/ @workflow-team @devops-team

# Documentation owners
*.md @docs-team
```

---

## 🧪 Testing Branch Protection

After setup:

1. **Try to push directly to main:**
   ```bash
   git checkout main
   echo "test" >> README.md
   git commit -am "test"
   git push origin main
   ```
   **Expected:** ❌ Push rejected

2. **Create PR and try to merge without approval:**
   **Expected:** ❌ Merge button disabled

3. **Get approval and merge:**
   **Expected:** ✅ Merge allowed

---

## 🔄 Workflow

### Correct Workflow (after protection):
```bash
# 1. Create feature branch
git checkout main
git pull
git checkout -b feature/my-changes

# 2. Make changes and commit
git add .
git commit -m "feat: add new feature"

# 3. Push branch
git push origin feature/my-changes

# 4. Create PR on GitHub
# 5. Wait for approval
# 6. Merge PR
# 7. Stable tag auto-created
```

### What Gets Blocked:
```bash
# ❌ Direct push to main
git checkout main
git push origin main  # REJECTED

# ❌ Merge without approval
# Merge button disabled in GitHub

# ❌ Force push to main
git push -f origin main  # REJECTED
```

---

## 📊 Current State vs Target

### Before Branch Protection:
- ❌ Anyone can push to main directly
- ❌ No review required
- ❌ Can accidentally break main
- ❌ No audit trail

### After Branch Protection:
- ✅ All changes via PR
- ✅ At least 1 approval required
- ✅ Status checks must pass
- ✅ Full audit trail in PR history
- ✅ Automatic versioning on merge
- ✅ Pre-release testing available

---

## 🆘 Emergency Bypass (if needed)

If you need to bypass protection temporarily:

1. Go to Branch Protection settings
2. Temporarily **uncheck** "Do not allow bypassing"
3. Make your change
4. **Re-enable immediately**

**Note:** Better to create a hotfix PR and get fast approval!

---

## ✅ Setup Checklist

- [ ] Go to Repository Settings → Branches
- [ ] Add branch protection rule for `main`
- [ ] Enable "Require pull request before merging"
- [ ] Set "Require approvals" to 1
- [ ] Enable "Require status checks to pass"
- [ ] Enable "Require conversation resolution"
- [ ] Enable "Do not allow bypassing"
- [ ] Save changes
- [ ] Test by trying to push to main directly (should fail)
- [ ] Create test PR to verify workflow

---

## 📝 Next Steps After Setup

1. ✅ Branch protection enabled
2. ✅ Commit current changes to feature branch
3. ✅ Push feature branch
4. ✅ Create PR
5. ✅ Verify pre-release tag created
6. ✅ Get approval
7. ✅ Merge PR
8. ✅ Verify stable tag created
