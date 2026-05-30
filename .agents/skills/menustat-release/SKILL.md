---
name: menustat-release
description: Cut MenuStat releases from the repository root, including docs, signed/notarized app packaging, DMG and zip assets, GitHub release upload, and verification.
---

# MenuStat Release Skill

Use this skill when working from the MenuStat repository root, especially for
release prep, install docs, notarization, GitHub Releases, screenshots, app
icon, or launch-at-login distribution work.

## Repo

- GitHub: `adhishthite/menustat`
- Bundle ID: `com.adhishthite.MenuStat`
- Apple ID: configured in GitHub Actions secret `APPLE_ID`
- Team ID: configured in GitHub Actions variable `APPLE_TEAM_ID`
- Signing identity: configured in GitHub Actions variable `DEVELOPER_ID_SIGNING_IDENTITY`
- Notary profile: configured in GitHub Actions variable `NOTARY_PROFILE`
- Current release artifact shape: notarized `.dmg`, app `.zip`, CLI `.zip`,
  checksums, and stable latest-download aliases.
- CI/CD release workflow: `.github/workflows/release.yml`
- CI/CD setup docs: `docs/releasing.md`
- Repository visibility: public.
- CODEOWNERS: `.github/CODEOWNERS` owns all paths with `@adhishthite`.
- `main` is protected: PR required, CODEOWNER review required, one approval
  required, `Format / Lint / Build / Test` required, branch must be up to date,
  stale reviews are dismissed, conversations must be resolved, linear history is
  required, force-pushes and branch deletion are blocked, admins are not
  enforced.

## Release Checklist

1. Inspect state:
   ```bash
   git status --short
   gh release list --limit 10
   ```

2. Update source/docs as needed:
   - README and website install links should use stable latest assets:
     `https://github.com/adhishthite/menustat/releases/latest/download/MenuStat.dmg`
     and `https://github.com/adhishthite/menustat/releases/latest/download/MenuStatCLI.zip`.
   - Always review `website/app/page.tsx` for copy changes whenever the release
     includes user-facing behavior, version changes, screenshots, install
     instructions, supported hardware or macOS requirements, or visible app UI.
     Update the website copy in the same release PR when it would otherwise
     describe stale product behavior. If no website copy needs to change, say so
     explicitly in the PR/release notes.
   - Website display text may still show the version being released.
   - If packaging behavior changes, update `script/package_release.sh`.
   - If GitHub Actions upload behavior changes, update `.github/workflows/release.yml`.
   - Keep generated `dist/` files out of git.

3. Run validation:
   ```bash
   make check
   ```

4. Build, sign, notarize, staple, and package:
   ```bash
   MARKETING_VERSION=X.Y.Z BUILD_NUMBER=N TEAM_ID=<team-id> NOTARY_PROFILE=<profile> make package-release
   ```

5. Verify artifacts:
   ```bash
   spctl --assess --type execute --verbose dist/work/MenuStat.app
   spctl --assess --type open --context context:primary-signature --verbose dist/MenuStat-X.Y.Z.dmg
   shasum -a 256 dist/MenuStat-X.Y.Z.dmg dist/MenuStat-X.Y.Z.zip
   ```

6. Commit and open a PR for code/docs changes:
   ```bash
   branch="codex/release-X.Y.Z"
   git checkout -b "$branch"
   git add <changed files>
   git commit -m "<release-related message>"
   git push -u origin "$branch"
   gh pr create --base main --head "$branch" \
     --title "<release-related title>" \
     --body "<release summary and validation>"
   ```

   Merge the PR after the required `Format / Lint / Build / Test` check and
   CODEOWNER review pass. Then sync local `main` before tagging:
   ```bash
   git checkout main
   git pull --ff-only origin main
   ```

7. Create GitHub Release:
   ```bash
   gh release create vX.Y.Z \
     dist/MenuStat-X.Y.Z.dmg \
     dist/MenuStat-X.Y.Z.zip \
     dist/MenuStatCLI-X.Y.Z.zip \
     dist/MenuStat-X.Y.Z-checksums.txt \
     dist/MenuStat.dmg \
     dist/MenuStat.zip \
     dist/MenuStatCLI.zip \
     dist/MenuStat-checksums.txt \
     --target main \
     --title "MenuStat X.Y.Z" \
     --notes-file /path/to/release-notes.md \
     --latest
   ```

   If GitHub Actions secrets are configured, prefer pushing a tag instead:
   ```bash
   git tag vX.Y.Z
   git push origin vX.Y.Z
   ```

8. Verify uploaded assets:
   ```bash
   gh release view vX.Y.Z --json tagName,name,url,isDraft,isPrerelease,assets,publishedAt,targetCommitish
   rm -rf /tmp/menustat-release-check-X.Y.Z
   mkdir -p /tmp/menustat-release-check-X.Y.Z
   gh release download vX.Y.Z --pattern 'MenuStat-X.Y.Z.*' --dir /tmp/menustat-release-check-X.Y.Z
   shasum -a 256 /tmp/menustat-release-check-X.Y.Z/MenuStat-X.Y.Z.*
   ```

9. Verify public latest-download URLs:
   ```bash
   gh repo view adhishthite/menustat --json visibility,isPrivate,url
   curl -I -L https://github.com/adhishthite/menustat/releases/latest/download/MenuStat.dmg
   curl -I -L https://github.com/adhishthite/menustat/releases/latest/download/MenuStatCLI.zip
   curl -L -s https://menustat.adhishthite.vercel.app |
     rg -o 'releases/latest/download/MenuStat[^\"]+|vX.Y.Z'
   ```

10. Clean up merged release branches when appropriate:
    ```bash
    git branch -d codex/release-X.Y.Z
    git push origin --delete codex/release-X.Y.Z
    ```

## Repository Governance

Do not assume direct pushes to `main` are acceptable. `main` is protected and
normal code/docs changes should land through a PR. A release tag may still be
pushed from the reviewed `main` commit to trigger `.github/workflows/release.yml`.

Before changing policies, inspect current state:

```bash
gh repo view adhishthite/menustat --json nameWithOwner,visibility,isPrivate,defaultBranchRef
cat .github/CODEOWNERS
gh api repos/adhishthite/menustat/branches/main/protection \
  --jq '{required_status_checks, required_pull_request_reviews, enforce_admins, required_linear_history, allow_force_pushes, allow_deletions, required_conversation_resolution}'
```

Current intended protection:

- Require pull requests before merging.
- Require `Format / Lint / Build / Test`.
- Require branch to be up to date before merge.
- Require one approval and CODEOWNER review.
- Dismiss stale reviews.
- Require conversation resolution.
- Require linear history.
- Disable force-pushes and branch deletion.
- Leave admin enforcement off for owner recovery.

## Stable Download URLs

MenuStat uses two artifact naming layers:

- Versioned assets preserve immutable release history:
  - `MenuStat-X.Y.Z.dmg`
  - `MenuStat-X.Y.Z.zip`
  - `MenuStatCLI-X.Y.Z.zip`
  - `MenuStat-X.Y.Z-checksums.txt`
- Stable assets are overwritten on every release and power website/docs links:
  - `MenuStat.dmg`
  - `MenuStat.zip`
  - `MenuStatCLI.zip`
  - `MenuStat-checksums.txt`

The website and README should not link to versioned download URLs. They should
use `releases/latest/download/MenuStat.dmg` and
`releases/latest/download/MenuStatCLI.zip` so new releases do not require link
maintenance.

For an existing release that predates stable aliases, backfill them with:

```bash
version=X.Y.Z
tmp="/tmp/menustat-stable-assets-$version"
rm -rf "$tmp"
mkdir -p "$tmp"
gh release download "v$version" \
  --pattern "MenuStat-$version.dmg" \
  --pattern "MenuStat-$version.zip" \
  --pattern "MenuStatCLI-$version.zip" \
  --dir "$tmp"
cp "$tmp/MenuStat-$version.dmg" "$tmp/MenuStat.dmg"
cp "$tmp/MenuStat-$version.zip" "$tmp/MenuStat.zip"
cp "$tmp/MenuStatCLI-$version.zip" "$tmp/MenuStatCLI.zip"
shasum -a 256 \
  "$tmp/MenuStat-$version.dmg" \
  "$tmp/MenuStat-$version.zip" \
  "$tmp/MenuStatCLI-$version.zip" \
  "$tmp/MenuStat.dmg" \
  "$tmp/MenuStat.zip" \
  "$tmp/MenuStatCLI.zip" > "$tmp/MenuStat-checksums.txt"
gh release upload "v$version" \
  "$tmp/MenuStat.dmg" \
  "$tmp/MenuStat.zip" \
  "$tmp/MenuStatCLI.zip" \
  "$tmp/MenuStat-checksums.txt" \
  --clobber
```

## Notes

- Do not ask for or print Apple passwords. In CI, the notary credential is
  created from GitHub Actions secrets and variables.
- Prefer `.dmg` as the primary README install artifact. Keep `.zip` attached as
  an alternate asset.
- The repo must be public for website, Slack, and X download links to work for
  unauthenticated users.
- The release script notarizes the app first, staples it, builds the DMG, signs
  the DMG, notarizes the DMG, staples the DMG, and verifies Gatekeeper.
- If `hdiutil verify` races the new DMG, `package_release.sh` includes retry
  logic.
- For screenshots, run the app with `make verify`, open the menu-bar panel, and
  capture the actual window into `docs/screenshots/`.
