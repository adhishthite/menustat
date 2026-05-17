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
- Team ID: `ATQ45ZSG3M`
- Signing identity: `Developer ID Application: Adhish Thite (ATQ45ZSG3M)`
- Notary profile: `MenuStatNotary`
- Current release artifact shape: notarized `.dmg` plus `.zip`
- CI/CD release workflow: `.github/workflows/release.yml`
- CI/CD setup docs: `docs/releasing.md`

## Release Checklist

1. Inspect state:
   ```bash
   git status --short
   gh release list --limit 10
   ```

2. Update source/docs as needed:
   - README install link should point to the version being released.
   - If packaging behavior changes, update `script/package_release.sh`.
   - Keep generated `dist/` files out of git.

3. Run validation:
   ```bash
   make check
   ```

4. Build, sign, notarize, staple, and package:
   ```bash
   MARKETING_VERSION=X.Y.Z BUILD_NUMBER=N NOTARY_PROFILE=MenuStatNotary make package-release
   ```

5. Verify artifacts:
   ```bash
   spctl --assess --type execute --verbose dist/work/MenuStat.app
   spctl --assess --type open --context context:primary-signature --verbose dist/MenuStat-X.Y.Z.dmg
   shasum -a 256 dist/MenuStat-X.Y.Z.dmg dist/MenuStat-X.Y.Z.zip
   ```

6. Commit and push code/docs changes:
   ```bash
   git add <changed files>
   git commit -m "<release-related message>"
   git push origin main
   ```

7. Create GitHub Release:
   ```bash
   gh release create vX.Y.Z \
     dist/MenuStat-X.Y.Z.dmg \
     dist/MenuStat-X.Y.Z.zip \
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

## Notes

- Do not ask for or print Apple passwords. The notary credential is already
  stored in Keychain as `MenuStatNotary`.
- Prefer `.dmg` as the primary README install artifact. Keep `.zip` attached as
  an alternate asset.
- The release script notarizes the app first, staples it, builds the DMG, signs
  the DMG, notarizes the DMG, staples the DMG, and verifies Gatekeeper.
- If `hdiutil verify` races the new DMG, `package_release.sh` includes retry
  logic.
- For screenshots, run the app with `make verify`, open the menu-bar panel, and
  capture the actual window into `docs/screenshots/`.
