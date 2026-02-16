# Electron Migration Plan

Migrate Monitome from a native Swift/macOS app to an Electron app targeting macOS + Windows.

## Why Electron

- The activity-agent and pi integration are already TypeScript — Electron unifies the stack
- Eliminates the subprocess-spawning bridge (`ActivityAgentManager.swift` parsing stdout)
- Activity-agent becomes a direct library import, not a compiled binary
- Every native macOS capability has a working Electron/JS equivalent
- Windows support with a single codebase

## Architecture Overview

```
monitome-electron/
├── package.json
├── electron-builder.yml          # Build/packaging config
├── tsconfig.json
├── src/
│   ├── main/                     # Electron main process
│   │   ├── index.ts              # Entry point, app lifecycle
│   │   ├── tray.ts               # System tray + popover window
│   │   ├── capture/
│   │   │   ├── screen-capture.ts # desktopCapturer periodic screenshots
│   │   │   ├── duplicate-detect.ts # Perceptual hash (port of ImageDiff.swift)
│   │   │   └── active-display.ts # Mouse → display tracking
│   │   ├── triggers/
│   │   │   ├── event-monitor.ts  # App switch + tab change detection
│   │   │   └── power-monitor.ts  # Sleep/wake/lock/unlock
│   │   ├── storage/
│   │   │   ├── database.ts       # better-sqlite3, migrations, models
│   │   │   ├── storage-manager.ts# File I/O, auto-purge
│   │   │   └── migrations/       # SQL migration files
│   │   ├── analysis/
│   │   │   ├── indexer.ts        # Direct import from activity-agent
│   │   │   ├── search.ts         # FTS, date queries — direct function calls
│   │   │   └── chat.ts           # Pi SDK integration — no subprocess
│   │   ├── platform/             # Platform abstraction layer
│   │   │   ├── index.ts          # Re-exports per platform
│   │   │   ├── active-window.ts  # active-win wrapper
│   │   │   ├── autolaunch.ts     # Login item settings
│   │   │   └── paths.ts          # App data directories
│   │   └── ipc.ts                # IPC handlers (main ↔ renderer)
│   ├── renderer/                 # UI (React + Vite)
│   │   ├── index.html
│   │   ├── App.tsx
│   │   ├── components/
│   │   │   ├── Tray/PopoverMenu.tsx
│   │   │   ├── Main/MainView.tsx
│   │   │   ├── Main/SearchTab.tsx
│   │   │   ├── Main/ChatTab.tsx
│   │   │   ├── Main/DayActivityView.tsx
│   │   │   ├── Main/ScreenshotCard.tsx
│   │   │   ├── Main/ActivityCard.tsx
│   │   │   ├── Settings/SettingsView.tsx
│   │   │   └── Shared/              # Reusable components
│   │   ├── hooks/
│   │   │   ├── useAppState.ts
│   │   │   ├── useScreenshots.ts
│   │   │   └── useSearch.ts
│   │   └── stores/
│   │       └── app-state.ts      # Zustand or similar (replaces AppState.swift)
│   ├── shared/                   # Types shared between main + renderer
│   │   ├── types.ts              # Screenshot, ActivitySearchResult, etc.
│   │   └── ipc-channels.ts       # Type-safe IPC channel definitions
│   └── activity-agent/           # Imported directly (not a subprocess)
│       └── (symlink or copy from existing activity-agent/src)
├── resources/
│   ├── icon.icns                 # macOS
│   ├── icon.ico                  # Windows
│   └── tray-icon.png             # Menu bar / system tray
└── scripts/
    ├── dev.ts                    # Dev server script
    └── build.ts                  # Production build
```

## Migration Phases

### Phase 0: Project Scaffold
**Goal**: Electron app that launches, shows a tray icon, and opens a window.

- [ ] Init project with `electron-forge` or `electron-vite` (recommended: `electron-vite` for Vite + React)
- [ ] Set up TypeScript config (main + renderer)
- [ ] System tray with icon, click opens a BrowserWindow
- [ ] Basic React shell in renderer (empty MainView, SettingsView routes)
- [ ] IPC scaffolding with typed channels
- [ ] electron-builder config for macOS (.dmg) + Windows (.exe) targets
- [ ] GitHub Actions CI: build on `macos-latest` + `windows-latest`

**Test**: App launches on macOS, shows tray icon, opens empty window.

### Phase 1: Screen Capture
**Goal**: Periodic screenshot capture, matching current Swift behavior.

**Port from**: `ScreenRecorder.swift`, `ImageDiff.swift`, `ActiveDisplayTracker.swift`

- [ ] `screen-capture.ts` — use `desktopCapturer.getSources({ types: ['screen'] })` to capture
  - Timer-based capture at configurable interval (default 10s)
  - Scale to ~1080p height, save as JPEG
  - Map `SCDisplay` → `electron.screen.getAllDisplays()`
- [ ] `duplicate-detect.ts` — port perceptual hash
  - Use `sharp` to resize to 8×8 grayscale
  - Compute average hash, Hamming distance (pure JS math)
  - Per-display hash tracking
- [ ] `active-display.ts` — port display tracking
  - `screen.getCursorScreenPoint()` + `screen.getDisplayNearestPoint()`
  - Debounce logic (same as Swift version)
- [ ] `power-monitor.ts` — pause/resume on sleep/lock
  - `powerMonitor.on('suspend' | 'resume' | 'lock-screen' | 'unlock-screen')`

**Platform notes**:
- macOS: Screen Recording permission prompt will appear (same as Swift version)
- Windows: No permission needed (pre-Win11) or simple consent (Win11+)
- The `desktopCapturer` API returns `NativeImage` — call `.toJPEG(quality)` directly

**Test**: Screenshots captured every 10s, duplicates skipped, pauses on sleep/lock.

### Phase 2: Storage Layer
**Goal**: SQLite database + file management, matching current schema.

**Port from**: `StorageManager.swift`

- [ ] `database.ts` — `better-sqlite3` with WAL mode
  - Same schema: `screenshots` table with `id, captured_at, file_path, file_size, is_processed, trigger_reason`
  - Same indexes
  - Migration system (can be simple: version number in a `meta` table)
- [ ] `storage-manager.ts`
  - `app.getPath('userData')` → `~/Library/Application Support/Monitome` (macOS) / `%APPDATA%/Monitome` (Windows)
  - JPEG file writing to `recordings/` subdirectory
  - Auto-purge when storage limit exceeded (same 90% target logic)
  - `nextScreenshotURL()`, `saveScreenshot()`, `fetchForDay()`, `fetchRecent()`, etc.

**Decision**: Use the *same* SQLite database file as the current Swift app? This would allow a seamless transition for existing users on macOS. The schema is identical. Path would be the same `~/Library/Application Support/Monitome/monitome.sqlite`.

**Test**: Screenshots saved to disk, tracked in DB, auto-purge works.

### Phase 3: Event Triggers
**Goal**: Capture on app switch and browser tab change.

**Port from**: `EventTriggerMonitor.swift`

- [ ] Install `active-win` (or `@aspect-build/active-win` — the maintained fork)
- [ ] `event-monitor.ts`
  - Poll active window every 500ms–1s
  - Detect app switch: `owner.name` changed → trigger capture
  - Detect tab change: same browser app but `title` changed → trigger capture
  - Same debounce logic (2s minimum between captures)
  - Browser detection: check `owner.name` against known browsers

**Platform notes**:
- macOS: `active-win` uses Accessibility API — needs permission (same as Swift)
- Windows: Uses Win32 `GetForegroundWindow()` / `GetWindowText()` — **no permission needed**
- This is actually *simpler* than the Swift version because `active-win` gives you app name + window title in one call (no separate AX element traversal)

**Test**: Screenshot fires on app switch and browser tab change, with debounce.

### Phase 4: Activity Agent Integration (The Big Win)
**Goal**: Import activity-agent as a library instead of spawning subprocesses.

**Replaces**: `ActivityAgentManager.swift` (~500 lines of subprocess management + stdout parsing)

- [ ] Refactor `activity-agent/src/` to export clean module interfaces:
  ```typescript
  // activity-agent/src/index.ts
  export { Indexer } from './indexer'
  export { SearchEngine } from './search'
  export { ActivityDB } from './db'
  ```
- [ ] `indexer.ts` — call indexer functions directly
  ```typescript
  import { Indexer } from '../activity-agent'
  const indexer = new Indexer(dataDir)
  await indexer.processNewScreenshots(batchSize: 10)  // no subprocess!
  ```
- [ ] `search.ts` — FTS and date queries as function calls
  ```typescript
  import { SearchEngine } from '../activity-agent'
  const results = await search.fts('github typescript')  // returns typed objects
  ```
- [ ] `chat.ts` — Pi SDK integration
  - Import pi extension directly (no `--extension` flag, no process spawn)
  - Session management in-process
  - Streaming responses to renderer via IPC

**What gets deleted**: The entire stdout text parser, the `runAgent()` / `runAgentWithStreaming()` process spawning, the `BUN_JSC_useJIT=0` hack, the binary-finding logic.

**Test**: Indexing, search, and chat work without any subprocess spawning.

### Phase 5: UI (Renderer)
**Goal**: Rebuild the SwiftUI views as React components.

**Port from**: `MainView.swift`, `SettingsView.swift`, `StatusMenuView.swift`

- [ ] App state management (Zustand store)
  - `isRecording`, `eventTriggersEnabled`, `todayScreenshotCount`
  - Persisted to electron-store (replaces UserDefaults)
  - IPC bridge: renderer reads state, main process updates it
- [ ] Tray popover (`PopoverMenu.tsx`)
  - Recording toggle, today's count, storage used
  - "Open Window" / "Quit" buttons
- [ ] Main window
  - [ ] Sidebar: recording status, date picker, stats, indexing controls
  - [ ] Search tab: search bar, grid of `ActivityCard` results
  - [ ] Chat tab: message list, input field, tool-call pills, screenshot thumbnails
  - [ ] Day activity tab: activities for selected date, screenshot detail modal
- [ ] Settings window
  - [ ] Permissions status (screen recording, accessibility)
  - [ ] Event triggers toggle
  - [ ] Screenshot interval picker
  - [ ] Storage limit picker
  - [ ] API key input
  - [ ] Keyboard shortcuts config
  - [ ] Storage info + "Open in Finder/Explorer"
- [ ] Global keyboard shortcuts
  - `globalShortcut.register()` for capture-now and toggle-recording
  - Settings UI for rebinding (use `electron-shortcuts` or custom recorder)

**UI library options**: 
- Tailwind + shadcn/ui (recommended — fast to build, looks native-ish)
- Or Radix UI + custom styling
- Date picker: `react-day-picker` or similar

**Test**: Full UI parity with the Swift app.

### Phase 6: Platform Polish
**Goal**: Platform-specific refinements.

- [ ] **macOS**
  - Permission prompts: screen recording, accessibility
  - Menu bar icon behavior (template image for dark/light mode)
  - `app.dock.hide()` for menu-bar-only mode
  - DMG packaging with background image
  - Code signing + notarization (via electron-builder + `afterSign` hook)
- [ ] **Windows**
  - System tray icon + balloon notifications
  - Auto-launch on startup (`app.setLoginItemSettings()`)
  - NSIS or MSI installer
  - Code signing (if you get a Windows cert)
  - Windows Defender SmartScreen (signing helps, otherwise users get a warning)
- [ ] **Auto-update**
  - `electron-updater` with GitHub Releases as the update source
  - Differential updates (saves bandwidth)
- [ ] **Platform paths abstraction**
  - Config: `electron-store` (cross-platform UserDefaults equivalent)
  - Data: `app.getPath('userData')`
  - Recordings: `path.join(app.getPath('userData'), 'recordings')`

## Dependency Map

| Swift Dependency | Electron Equivalent | Notes |
|---|---|---|
| ScreenCaptureKit | `desktopCapturer` (built-in) | Cross-platform |
| CoreGraphics / CoreImage | `sharp` | Image resize, JPEG encode |
| GRDB | `better-sqlite3` | Sync API, WAL, FTS5 |
| KeyboardShortcuts | `globalShortcut` (built-in) | Cross-platform |
| Accessibility API (AX*) | `active-win` | Easier on Windows |
| NSWorkspace notifications | `powerMonitor` (built-in) | Cross-platform |
| NSStatusItem | `Tray` (built-in) | Cross-platform |
| UserDefaults | `electron-store` | Cross-platform |
| SwiftUI | React + Tailwind | Full rewrite |
| Combine (reactive) | Zustand + IPC | Simpler model |

## IPC Design

Main ↔ Renderer communication via typed channels:

```typescript
// shared/ipc-channels.ts
export const IPC = {
  // State
  'state:get':          () => AppState,
  'state:subscribe':    () => void,           // main pushes updates
  'state:toggle-recording': () => void,

  // Screenshots
  'screenshots:for-day':    (date: string) => Screenshot[],
  'screenshots:recent':     (limit: number) => Screenshot[],

  // Search
  'search:fts':         (query: string) => ActivitySearchResult[],
  'search:by-date':     (date: string) => ActivitySearchResult[],

  // Chat
  'chat:send':          (message: string) => string,
  'chat:clear':         () => void,

  // Indexing
  'indexing:start':     () => void,
  'indexing:status':    () => IndexingStatus,

  // Settings
  'settings:get':       () => Settings,
  'settings:set':       (key: string, value: any) => void,
  'settings:open-data-dir': () => void,
} as const
```

## Data Migration (macOS existing users)

For users upgrading from the Swift app:
- SQLite DB is at the same path (`~/Library/Application Support/Monitome/monitome.sqlite`)
- Same schema — Electron version reads it directly
- Screenshots in same `recordings/` directory — no migration needed
- Activity index DB (`activity-index.db`) — same, no migration
- UserDefaults → electron-store: one-time migration on first launch
  - Read `defaults read swair.Monitome` and write to electron-store

## Build & Release

### Dev
```bash
npm run dev          # Vite dev server + Electron with hot reload
```

### Build
```bash
npm run build:mac    # .dmg
npm run build:win    # .exe (NSIS installer)
npm run build:all    # Both (on CI)
```

### CI (GitHub Actions)
```yaml
strategy:
  matrix:
    include:
      - os: macos-latest
        targets: dmg
      - os: windows-latest
        targets: nsis
```

### Signing & Notarization
- **macOS**: Same Apple ID + Team ID + app-specific password, via electron-builder's `afterSign` hook
- **Windows**: Optional code signing cert (reduces SmartScreen warnings)

### Distribution
- GitHub Releases (same as now)
- Homebrew cask (macOS, update tap as before)
- Winget / Chocolatey / Scoop (Windows — pick one to start)
- Auto-update via `electron-updater` pointing at GitHub Releases

## Timeline Estimate

| Phase | Effort | Notes |
|---|---|---|
| Phase 0: Scaffold | 1–2 days | Boilerplate, tray, empty window |
| Phase 1: Screen Capture | 2–3 days | Core capture loop + dedup |
| Phase 2: Storage | 1–2 days | DB + file management |
| Phase 3: Event Triggers | 1–2 days | active-win integration |
| Phase 4: Agent Integration | 3–4 days | Refactor activity-agent into importable lib |
| Phase 5: UI | 5–7 days | Biggest chunk — full React rebuild |
| Phase 6: Platform Polish | 3–4 days | Signing, installers, auto-update |
| **Total** | **~3–4 weeks** | Solo developer estimate |

## Open Questions

1. **Keep the Python analysis service?** The BAML/Gemini service (`service/`) is separate from the activity-agent. Could keep it as-is (HTTP calls from Electron) or fold it into the TS stack.
2. **Electron Forge vs electron-vite vs electron-builder?** Recommend `electron-vite` for dev + `electron-builder` for packaging — most flexible combo.
3. **Keep supporting the Swift app?** After migration, maintain both or deprecate Swift version?
4. **Linux support?** Electron makes it almost free. `desktopCapturer` and `active-win` work on Linux too. Worth adding from day one?
5. **Migrate existing Homebrew users?** The cask would need to point to the new Electron-based DMG. Same tap, new binary.
