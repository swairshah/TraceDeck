//
//  AudioCaptureManager.swift
//  TraceDeck
//

import Foundation
import Combine

@MainActor
final class AudioCaptureManager {
    static let shared = AudioCaptureManager()

    private let recorder = AudioRecorder()
    private var transcriber: Transcriber?
    private var recordingSub: AnyCancellable?

    private var currentSessionStartedAt: Date?
    private var currentSessionAudioURL: URL?
    private var isSessionRecording = false

    private init() {
        refreshTranscriber()

        recordingSub = AppState.shared.$isRecording
            .removeDuplicates()
            .sink { [weak self] isRecording in
                guard let self else { return }
                if isRecording {
                    self.startSession()
                } else {
                    self.stopSession()
                }
            }
    }

    func refreshTranscriber() {
        let userConfiguredPath = UserDefaults.standard.string(forKey: Transcriber.modelPathUserDefaultsKey)
        let candidatePath = (userConfiguredPath?.isEmpty == false) ? userConfiguredPath! : Transcriber.defaultModelPath

        if FileManager.default.fileExists(atPath: candidatePath) {
            transcriber = Transcriber(modelPath: candidatePath)
        } else {
            transcriber = nil
        }
    }

    private func startSession() {
        guard !isSessionRecording else { return }

        Task {
            let hasMicrophonePermission = await AudioRecorder.checkMicrophonePermission()
            guard hasMicrophonePermission else {
                print("AudioCaptureManager: microphone permission denied")
                return
            }

            currentSessionStartedAt = Date()
            recorder.start()
            isSessionRecording = true
        }
    }

    private func stopSession() {
        guard isSessionRecording else { return }
        defer {
            isSessionRecording = false
            currentSessionStartedAt = nil
            currentSessionAudioURL = nil
        }

        let sessionEndedAt = Date()
        guard let startedAt = currentSessionStartedAt else { return }
        guard let tempURL = recorder.stop() else { return }

        let storedURL = StorageManager.shared.nextAudioURL(startedAt: startedAt)
        do {
            try FileManager.default.moveItem(at: tempURL, to: storedURL)
        } catch {
            print("AudioCaptureManager: failed to store recording: \(error)")
            try? FileManager.default.removeItem(at: tempURL)
            return
        }

        currentSessionAudioURL = storedURL
        let status: AudioTranscriptionStatus = transcriber == nil ? .noModel : .pending
        guard let recordingID = StorageManager.shared.saveAudioRecording(
            url: storedURL,
            startedAt: startedAt,
            endedAt: sessionEndedAt,
            status: status
        ) else {
            return
        }

        guard let transcriber else { return }
        Task { [weak self] in
            await self?.transcribeAndPersist(recordingID: recordingID, audioURL: storedURL, transcriber: transcriber)
        }
    }

    private func transcribeAndPersist(recordingID: Int64, audioURL: URL, transcriber: Transcriber) async {
        do {
            let text = try await transcriber.transcribe(audioURL: audioURL)
            StorageManager.shared.updateAudioTranscription(
                recordingID: recordingID,
                transcription: text,
                status: .ready
            )
            print("AudioCaptureManager: transcription saved for recording \(recordingID)")
        } catch {
            StorageManager.shared.updateAudioTranscription(
                recordingID: recordingID,
                transcription: nil,
                status: .failed
            )
            print("AudioCaptureManager: transcription failed for recording \(recordingID): \(error)")
        }
    }
}
