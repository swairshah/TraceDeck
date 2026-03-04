//
//  AppState.swift
//  TraceDeck
//

import SwiftUI
import Combine

@MainActor
final class AppState: ObservableObject {
    static let shared = AppState()

    private let recordingKey = "isRecording"
    private let eventTriggersKey = "eventTriggersEnabled"
    private let sessionNoteKey = "workflowSessionNoteDraft"

    @Published var isRecording: Bool {
        didSet {
            guard isRecording != oldValue else { return }
            UserDefaults.standard.set(isRecording, forKey: recordingKey)
            isRecording ? beginWorkflowSessionIfNeeded() : endWorkflowSessionIfNeeded()
            NotificationCenter.default.post(name: .recordingStateChanged, object: nil)
        }
    }

    @Published var eventTriggersEnabled: Bool {
        didSet {
            UserDefaults.standard.set(eventTriggersEnabled, forKey: eventTriggersKey)
            NotificationCenter.default.post(name: .eventTriggersStateChanged, object: nil)
        }
    }

    @Published var sessionNoteDraft: String {
        didSet {
            UserDefaults.standard.set(sessionNoteDraft, forKey: sessionNoteKey)
            if let currentSessionID {
                StorageManager.shared.updateWorkflowSessionNote(
                    id: currentSessionID,
                    note: sessionNoteDraft
                )
            }
        }
    }

    @Published private(set) var currentSessionID: Int64?
    @Published private(set) var currentSessionStartedAt: Date?
    @Published var currentLiveTranscript: String = ""
    @Published var currentSessionSummary: String = ""

    /// Today's screenshot count - updates reactively when screenshots are captured
    @Published var todayScreenshotCount: Int = 0

    private init() {
        // Restore saved preferences
        self.isRecording = UserDefaults.standard.bool(forKey: recordingKey)

        // Default event triggers to ON if not set
        if UserDefaults.standard.object(forKey: eventTriggersKey) == nil {
            UserDefaults.standard.set(true, forKey: eventTriggersKey)
        }
        self.eventTriggersEnabled = UserDefaults.standard.bool(forKey: eventTriggersKey)
        self.sessionNoteDraft = UserDefaults.standard.string(forKey: sessionNoteKey) ?? ""
        self.currentSessionID = nil
        self.currentSessionStartedAt = nil

        // Initialize today's count
        self.todayScreenshotCount = StorageManager.shared.todayCount()

        // Listen for new screenshots to update count
        NotificationCenter.default.addObserver(
            forName: .screenshotCaptured,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            Task { @MainActor in
                self?.todayScreenshotCount = StorageManager.shared.todayCount()
            }
        }
    }

    private func beginWorkflowSessionIfNeeded() {
        guard currentSessionID == nil else { return }

        let trimmedNote = sessionNoteDraft.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let sessionID = StorageManager.shared.startWorkflowSession(
            startedAt: Date(),
            note: trimmedNote.isEmpty ? nil : trimmedNote
        ) else {
            return
        }

        currentSessionID = sessionID
        currentSessionStartedAt = Date()
        currentLiveTranscript = ""
        currentSessionSummary = ""

        NotificationCenter.default.post(
            name: .workflowSessionUpdated,
            object: nil,
            userInfo: ["sessionId": sessionID]
        )
    }

    private func endWorkflowSessionIfNeeded() {
        guard let currentSessionID else { return }

        let transcript = currentLiveTranscript.trimmingCharacters(in: .whitespacesAndNewlines)
        let summary = currentSessionSummary.trimmingCharacters(in: .whitespacesAndNewlines)

        StorageManager.shared.endWorkflowSession(
            id: currentSessionID,
            endedAt: Date(),
            summary: summary.isEmpty ? nil : summary,
            liveTranscript: transcript.isEmpty ? nil : transcript
        )

        NotificationCenter.default.post(
            name: .workflowSessionUpdated,
            object: nil,
            userInfo: ["sessionId": currentSessionID]
        )

        self.currentSessionID = nil
        self.currentSessionStartedAt = nil
        self.currentLiveTranscript = ""
        self.currentSessionSummary = ""
    }

    func attachWorkflowSession(id: Int64, startedAt: Date = Date()) {
        currentSessionID = id
        currentSessionStartedAt = startedAt
        NotificationCenter.default.post(
            name: .workflowSessionUpdated,
            object: nil,
            userInfo: ["sessionId": id]
        )
    }

    func updateCurrentLiveTranscript(_ transcript: String) {
        currentLiveTranscript = transcript
    }

    func updateCurrentSessionSummary(_ summary: String) {
        currentSessionSummary = summary
    }
}

// MARK: - Notification Names

extension Notification.Name {
    /// Posted when a screenshot is captured and saved
    static let screenshotCaptured = Notification.Name("screenshotCaptured")

    /// Posted when recording state changes
    static let recordingStateChanged = Notification.Name("recordingStateChanged")

    /// Posted when event triggers setting changes
    static let eventTriggersStateChanged = Notification.Name("eventTriggersStateChanged")

    /// Posted to request opening the main window
    static let openMainWindow = Notification.Name("openMainWindow")

    /// Posted to switch MainView to the Settings tab
    static let openSettingsTab = Notification.Name("openSettingsTab")

    /// Posted to present permissions onboarding UI
    static let showPermissionsOnboarding = Notification.Name("showPermissionsOnboarding")

    /// Posted when an audio transcription is saved or updated
    static let audioTranscriptionUpdated = Notification.Name("audioTranscriptionUpdated")

    /// Posted when a workflow session is created, updated, or ended
    static let workflowSessionUpdated = Notification.Name("workflowSessionUpdated")
}
