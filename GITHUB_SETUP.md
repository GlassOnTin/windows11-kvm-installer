# GitHub Repository Setup

Follow these steps to push this repository to GitHub:

## 1. Create a new repository on GitHub

1. Go to https://github.com/new
2. Name it: `windows11-kvm-setup` (or your preferred name)
3. Description: "Automated setup scripts for Windows 11 VM using KVM/QEMU"
4. Keep it public or private as desired
5. **DO NOT** initialize with README, .gitignore, or license (we already have these)
6. Click "Create repository"

## 2. Add GitHub as remote and push

After creating the empty repository, run these commands:

```bash
cd /home/ian/scripts

# Add GitHub remote (replace YOUR_REPO_NAME with actual repo name)
git remote add origin git@github.com:GlassOnTin/YOUR_REPO_NAME.git

# Or if using HTTPS:
# git remote add origin https://github.com/GlassOnTin/YOUR_REPO_NAME.git

# Push to GitHub
git push -u origin main
```

## 3. Alternative: Using GitHub CLI

If you have GitHub CLI installed:

```bash
cd /home/ian/scripts

# Create repo and push in one command
gh repo create GlassOnTin/windows11-kvm-setup --public --source=. --remote=origin --push
```

## 4. Verify

After pushing, your repository will be available at:
https://github.com/GlassOnTin/windows11-kvm-setup

## Repository Contents

- `setup-windows11-vm.sh` - Main automation script
- `troubleshoot-vm.sh` - Diagnostic helper script
- `README.md` - Comprehensive documentation
- `.gitignore` - Excludes VM disk images and temp files

## Future Updates

To update the repository after making changes:

```bash
git add .
git commit -m "Your commit message"
git push
```