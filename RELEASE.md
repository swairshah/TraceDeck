# Release Guide (TraceDeck)

## Quick Release

```bash
# 1. Build, sign, and create notarized DMG (if credentials are set)
APPLE_ID="swairshah@gmail.com" APP_PASSWORD="$(grep '^APPLE_APP_PASSWORD=' ~/.env | cut -d= -f2-)" ./scripts/build-release.sh 1.0.1

# 2. Create GitHub release and upload DMG
gh release create v1.0.1 dist/TraceDeck-1.0.1.dmg --title "TraceDeck v1.0.1" --notes "Bugfix release"

# 3. Update Homebrew tap cask (tracedeck.rb) with new version + SHA256
```

## Manual Steps

### 1) Build release artifact

```bash
./scripts/build-release.sh 1.0.1
```

This script:
- Builds `activity-agent` (universal binary)
- Builds bundled extension (`extension-bundle.js`)
- Builds bundled `pi` (universal binary)
- Builds the Swift app (`TraceDeck`, Release)
- Bundles binaries/extensions into `TraceDeck.app`
- Signs app + embedded binaries
- Creates DMG in `dist/`
- Notarizes + staples DMG when `APPLE_ID` + `APP_PASSWORD` are provided
- Prints SHA256 for Homebrew cask update

### 2) Publish GitHub release

```bash
gh release create v1.0.1 dist/TraceDeck-1.0.1.dmg \
  --repo swairshah/TraceDeck \
  --title "TraceDeck v1.0.1" \
  --notes "Release notes"
```

### 3) Update Homebrew tap

Tap repo: `~/work/projects/homebrew-tap`
Cask: `Casks/tracedeck.rb`

```bash
cd ~/work/projects/homebrew-tap
# Edit Casks/tracedeck.rb: bump version + sha256
git add Casks/tracedeck.rb
git commit -m "Update tracedeck to v1.0.1"
git push
```

### 4) Verify install

```bash
brew tap swairshah/tap
brew install --cask tracedeck
```

## Optional: Manual notarization commands

If you need to notarize manually:

```bash
xcrun notarytool submit dist/TraceDeck-1.0.1.dmg \
  --apple-id "swairshah@gmail.com" \
  --team-id "8B9YURJS4G" \
  --password "$(grep '^APPLE_APP_PASSWORD=' ~/.env | cut -d= -f2-)" \
  --wait

xcrun stapler staple dist/TraceDeck-1.0.1.dmg
```

## Version bump checklist

- `TraceDeck.xcodeproj` (`MARKETING_VERSION`)
- Any user-facing version strings (if applicable)
- `~/work/projects/homebrew-tap/Casks/tracedeck.rb`
