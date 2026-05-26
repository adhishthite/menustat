# Releasing MenuStat

MenuStat releases are built by GitHub Actions when a `vX.Y.Z` tag is pushed, or
manually from the **Release** workflow in GitHub Actions.

The workflow builds, signs, notarizes, staples, verifies, and uploads:

- `MenuStat-X.Y.Z.dmg`
- `MenuStat-X.Y.Z.zip`
- `MenuStatCLI-X.Y.Z.zip`
- `MenuStat-X.Y.Z-checksums.txt`
- `MenuStat.dmg`
- `MenuStat.zip`
- `MenuStatCLI.zip`
- `MenuStat-checksums.txt`

The versioned artifacts provide immutable release history. The stable artifacts
are overwritten on each release so public links can always download the latest
build via `releases/latest/download/MenuStat.dmg` and
`releases/latest/download/MenuStatCLI.zip`.

MenuStat is supported only on Apple Silicon Macs running macOS 13 or later. The
release app includes an `x86_64` compatibility slice only so Intel Macs can show
an unsupported-hardware alert and quit.

## Required GitHub Configuration

Set these in **GitHub → Settings → Secrets and variables → Actions**:

Secrets:

| Secret | Purpose |
|---|---|
| `APPLE_ID` | Apple ID email used for notarization. |
| `APPLE_APP_SPECIFIC_PASSWORD` | App-specific password for the Apple ID. |
| `DEVELOPER_ID_CERTIFICATE_BASE64` | Base64-encoded `.p12` Developer ID Application certificate. |
| `DEVELOPER_ID_CERTIFICATE_PASSWORD` | Password used when exporting the `.p12`. |
| `KEYCHAIN_PASSWORD` | Any strong password used for the temporary CI keychain. |

Variables:

| Variable | Purpose |
|---|---|
| `APPLE_TEAM_ID` | Apple Developer Team ID used for notarization. |
| `DEVELOPER_ID_SIGNING_IDENTITY` | Full Developer ID Application signing identity. |
| `NOTARY_PROFILE` | Temporary keychain profile name used by the release workflow. |

The app uses:

| Setting | Value |
|---|---|
| Bundle ID | `com.adhishthite.MenuStat` |
| Team ID | GitHub Actions variable `APPLE_TEAM_ID` |
| Signing identity | GitHub Actions variable `DEVELOPER_ID_SIGNING_IDENTITY` |
| Notary profile name | GitHub Actions variable `NOTARY_PROFILE` |

## Export the Certificate

On the Mac that has the Developer ID certificate:

1. Open **Keychain Access**.
2. Find the Developer ID Application certificate for the configured Apple team.
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
gh release download v0.1.3 --pattern 'MenuStatCLI-0.1.3.zip' --dir /tmp/menustat-release-check
shasum -a 256 /tmp/menustat-release-check/MenuStat-0.1.3.*
shasum -a 256 /tmp/menustat-release-check/MenuStatCLI-0.1.3.zip
```

The DMG should be Gatekeeper accepted and the extracted CLI should retain a valid Developer ID signature:

```bash
spctl --assess --type open --context context:primary-signature --verbose MenuStat-0.1.3.dmg
unzip /tmp/menustat-release-check/MenuStatCLI-0.1.3.zip -d /tmp/menustat-cli-check
codesign --verify --strict --verbose=2 /tmp/menustat-cli-check/menustat
```
