# Releasing MenuStat

MenuStat releases are built by GitHub Actions when a `vX.Y.Z` tag is pushed, or
manually from the **Release** workflow in GitHub Actions.

The workflow builds, signs, notarizes, staples, verifies, and uploads:

- `MenuStat-X.Y.Z.dmg`
- `MenuStat-X.Y.Z.zip`
- `MenuStat-X.Y.Z-checksums.txt`

## Required GitHub Secrets

Set these in **GitHub → Settings → Secrets and variables → Actions**:

| Secret | Purpose |
|---|---|
| `APPLE_ID` | Apple ID email used for notarization. |
| `APPLE_APP_SPECIFIC_PASSWORD` | App-specific password for the Apple ID. |
| `DEVELOPER_ID_CERTIFICATE_BASE64` | Base64-encoded `.p12` Developer ID Application certificate. |
| `DEVELOPER_ID_CERTIFICATE_PASSWORD` | Password used when exporting the `.p12`. |
| `KEYCHAIN_PASSWORD` | Any strong password used for the temporary CI keychain. |

The app uses:

| Setting | Value |
|---|---|
| Bundle ID | `com.adhishthite.MenuStat` |
| Team ID | `ATQ45ZSG3M` |
| Signing identity | `Developer ID Application: Adhish Thite (ATQ45ZSG3M)` |
| Notary profile name | `MenuStatNotary` |

## Export the Certificate

On the Mac that has the Developer ID certificate:

1. Open **Keychain Access**.
2. Find `Developer ID Application: Adhish Thite (ATQ45ZSG3M)`.
3. Expand it and select both the certificate and private key.
4. Export as `developer-id.p12`.
5. Choose a strong export password.

Encode it for GitHub:

```bash
base64 -i developer-id.p12 | pbcopy
```

Paste that value into `DEVELOPER_ID_CERTIFICATE_BASE64`.

## Cut a Release

Use a tag:

```bash
git checkout main
git pull --ff-only
git tag v0.1.3
git push origin v0.1.3
```

Or run the **Release** workflow manually with:

```text
version: 0.1.3
build_number: optional
```

## Verify a Release

After the workflow completes:

```bash
gh release view v0.1.3 --json assets,url,isDraft,isPrerelease
gh release download v0.1.3 --pattern 'MenuStat-0.1.3.*' --dir /tmp/menustat-release-check
shasum -a 256 /tmp/menustat-release-check/MenuStat-0.1.3.*
```

The DMG should be Gatekeeper accepted:

```bash
spctl --assess --type open --context context:primary-signature --verbose MenuStat-0.1.3.dmg
```
