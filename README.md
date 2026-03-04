<h1>  <img src="assets/icon_128.png" alt="TraceDeck icon" width="30"/> TraceDeck</h1>

**Personal context capture for macOS.** All data stays local. TraceDeck quietly indexes your screen activity, analyzes it with the LLM of your choice, and builds a searchable knowledge base of everything you've seen and done.

Use it as a personal bookmark engine, a knowledge database, or a context cartridge you can plug into any LLM or chatbot — bootstrapping it with *your* knowledge.

- Continuous screen capture via ScreenCaptureKit (macOS 13+)
- Event-triggered capture on app switch and browser tab change
- Contextual indexing of all activity with a local search API
- All data stays on your machine — you choose which LLM analyzes it
- Multi-display support, GRDB/SQLite storage with automatic cleanup

## Install

```bash
brew tap swairshah/tap
brew install --cask tracedeck
```

Or download from [Releases](https://github.com/swairshah/TraceDeck/releases).

## Configuration

- **Screenshot interval**: Default 10 seconds (configurable in Settings)
- **Storage limit**: Default 5 GB, auto-purges oldest screenshots
- **Storage location**: `~/Library/Application Support/TraceDeck/recordings/`

## Dev

### Build

1. Open `TraceDeck.xcodeproj` in Xcode
2. Add GRDB if missing: File → Add Package Dependencies → `https://github.com/groue/GRDB.swift.git`
3. Cmd+R to build and run

### Archive & Release

```bash
# In Xcode: Product → Archive → Distribute App → Direct Distribution → Export

# Create DMG
mkdir -p dist && cp -r /path/to/TraceDeck.app dist/
hdiutil create -volname "TraceDeck" -srcfolder dist -ov -format UDZO TraceDeck-1.0.0.dmg

# Release
gh release create v1.0.0 TraceDeck-1.0.0.dmg
```

### Project Structure

```
TraceDeck/
├── App/                  # Entry point, app delegate, state
├── Recording/            # ScreenCaptureKit, storage, display tracking
├── Views/                # SwiftUI views
├── System/               # Menu bar controller
├── Analysis/             # Analysis service client
└── service/              # Python BAML analysis service
```
