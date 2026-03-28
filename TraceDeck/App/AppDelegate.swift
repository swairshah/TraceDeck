//
//  AppDelegate.swift
//  TraceDeck
//

import AppKit
import Combine
import KeyboardShortcuts

// KVO-compatible accessor for bezel setting
extension UserDefaults {
    @objc dynamic var bezelEnabled: Bool {
        get { bool(forKey: "bezelEnabled") }
        set { set(newValue, forKey: "bezelEnabled") }
    }
}

@MainActor
class AppDelegate: NSObject, NSApplicationDelegate {
    private var statusBar: StatusBarController!
    private var recorder: ScreenRecorder!
    private var eventMonitor: EventTriggerMonitor!
    private var notchOverlay: NotchOverlayController?
    private var bezelEnabledObserver: NSKeyValueObservation?
    private var audioCapture: AudioCaptureManager?
    private var cancellables = Set<AnyCancellable>()

    func applicationDidFinishLaunching(_ notification: Notification) {
        let shouldRestoreRecording = UserDefaults.standard.bool(forKey: "isRecording")

        // Create status bar controller
        statusBar = StatusBarController()
        statusBar.onRightClick = { [weak self] in
            self?.recorder.captureNow(reason: .manual)
        }

        // Create notch bezel only if enabled (default: on)
        if UserDefaults.standard.object(forKey: "bezelEnabled") == nil {
            UserDefaults.standard.set(true, forKey: "bezelEnabled")
        }
        if UserDefaults.standard.bool(forKey: "bezelEnabled") {
            notchOverlay = NotchOverlayController()
        }

        // Watch for bezel setting changes
        bezelEnabledObserver = UserDefaults.standard.observe(\.bezelEnabled, options: [.new]) { [weak self] _, change in
            Task { @MainActor in
                guard let self else { return }
                if change.newValue == true {
                    if self.notchOverlay == nil {
                        self.notchOverlay = NotchOverlayController()
                    }
                } else {
                    self.notchOverlay?.tearDown()
                    self.notchOverlay = nil
                }
            }
        }

        // Initialize recorder (waits for permission)
        AppState.shared.isRecording = false
        UserDefaults.standard.set(shouldRestoreRecording, forKey: "isRecording")
        recorder = ScreenRecorder(autoStart: false)
        audioCapture = AudioCaptureManager.shared

        // Initialize event trigger monitor
        eventMonitor = EventTriggerMonitor()
        eventMonitor.onTrigger = { [weak self] reason in
            self?.recorder.captureNow(reason: reason)
        }

        // Observe both isRecording and eventTriggersEnabled
        // Event monitor should only run when BOTH are true
        Publishers.CombineLatest(
            AppState.shared.$isRecording,
            AppState.shared.$eventTriggersEnabled
        )
        .sink { [weak self] isRecording, eventTriggersEnabled in
            if isRecording && eventTriggersEnabled {
                self?.eventMonitor.start()
            } else {
                self?.eventMonitor.stop()
            }
        }
        .store(in: &cancellables)

        // Register keyboard shortcuts
        setupKeyboardShortcuts()
        
        // Start activity agent indexing
        ActivityAgentManager.shared.startPeriodicIndexing()

        // Restore recording state only if required permission is already granted
        if PermissionsManager.isScreenRecordingGranted {
            if shouldRestoreRecording, !AppState.shared.isRecording {
                AppState.shared.isRecording = true
            }
        } else {
            print("Screen recording permission not granted")
            AppState.shared.isRecording = false
            NotificationCenter.default.post(name: .showPermissionsOnboarding, object: nil)
        }
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        // Keep running in menu bar when window is closed
        return false
    }

    /// Called when the user clicks the dock icon (or re-activates the app)
    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        if !flag {
            // No visible windows - open the main window
            NSApp.setActivationPolicy(.regular)
            NSApp.activate(ignoringOtherApps: true)

            // Find and show the main window
            for window in NSApp.windows {
                if window.title == AppIdentity.displayName || window.styleMask.contains(.titled) {
                    window.makeKeyAndOrderFront(nil)
                    window.orderFrontRegardless()
                    break
                }
            }

            NotificationCenter.default.post(name: .openMainWindow, object: nil)
        }
        return true
    }

    func applicationWillTerminate(_ notification: Notification) {
        // Stop recording gracefully
        AppState.shared.isRecording = false
        eventMonitor.stop()
        notchOverlay?.tearDown()
        notchOverlay = nil
    }

    // MARK: - Keyboard Shortcuts

    private func setupKeyboardShortcuts() {
        KeyboardShortcuts.onKeyUp(for: .captureNow) { [weak self] in
            self?.recorder.captureNow(reason: .manual)
        }

        KeyboardShortcuts.onKeyUp(for: .toggleRecording) {
            AppState.shared.isRecording.toggle()
        }
    }
}
