# Deploying mac-duo.com

The site is static (`site/`) and deploys to GitHub Pages from the `Site` workflow on every push to `main` that touches `site/`.

## One-time setup

1. Create the repository `ninobc/mac-duo` on GitHub and push `main`.
2. In the repository, open **Settings › Pages** and set **Source** to *GitHub Actions*.
3. Under **Custom domain**, enter `mac-duo.com` and tick *Enforce HTTPS* once the certificate is issued (a few minutes after DNS resolves). `site/CNAME` already contains the domain.
4. At GoDaddy (the current DNS host), set:

   | Type | Name | Value |
   |---|---|---|
   | A | @ | 185.199.108.153 |
   | A | @ | 185.199.109.153 |
   | A | @ | 185.199.110.153 |
   | A | @ | 185.199.111.153 |
   | CNAME | www | ninobc.github.io |

   Remove the GoDaddy parking A records first.

## Releases

Tag a version to build, package and publish it:

```sh
git tag v1.0.0 && git push origin v1.0.0
```

The `Release` workflow builds a universal binary, signs and notarizes it when the `APPLE_*` secrets exist (see `.github/workflows/release.yml`), and attaches the DMG, ZIP and checksums to a GitHub release. The download button on the site points at the latest release. After publishing, update `site/updates.json` (the `Scripts/release.sh` script writes it) so installed copies learn about the new version.

## Signing

Distribution needs a **Developer ID Application** certificate from the Apple Developer Program. Until one exists, builds are signed with the local development identity and macOS shows the "can't verify the developer" prompt on first open; the site's install step explains the right-click › Open path. With the certificate:

- Locally: `SIGN_IDENTITY="Developer ID Application: Name (TEAMID)" NOTARY_PROFILE=macduo Scripts/release.sh 1.0.0` after `xcrun notarytool store-credentials macduo`.
- In CI: add the secrets `APPLE_CERTIFICATE_P12_BASE64`, `APPLE_CERTIFICATE_PASSWORD`, `APPLE_NOTARY_KEY_P8_BASE64`, `APPLE_NOTARY_KEY_ID`, `APPLE_NOTARY_ISSUER_ID`.
