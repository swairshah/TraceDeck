//
//  AudioRecorder.swift
//  TraceDeck
//

import Foundation
import AVFoundation
import Accelerate

final class AudioRecorder {
    enum State {
        case idle
        case recording
        case error(String)
    }

    private enum Config {
        static let sampleRate: Double = 16000
        static let levelUpdateInterval: TimeInterval = 0.05
    }

    var onAudioLevel: ((Float) -> Void)?
    var onError: ((String) -> Void)?

    private(set) var state: State = .idle

    private var audioEngine: AVAudioEngine?
    private var audioFile: AVAudioFile?
    private var levelTimer: Timer?
    private var currentLevel: Float = 0

    func start() {
        guard case .idle = state else { return }

        do {
            try setupAudioEngine()
            try audioEngine?.start()
            startLevelMonitoring()
            state = .recording
        } catch {
            let message = "Failed to start audio recording: \(error.localizedDescription)"
            state = .error(message)
            onError?(message)
        }
    }

    func stop() -> URL? {
        guard case .recording = state else { return nil }

        levelTimer?.invalidate()
        levelTimer = nil

        audioEngine?.stop()
        audioEngine?.inputNode.removeTap(onBus: 0)
        audioEngine = nil

        let url = audioFile?.url
        audioFile = nil
        state = .idle
        return url
    }

    private func setupAudioEngine() throws {
        let engine = AVAudioEngine()
        let inputNode = engine.inputNode
        let inputFormat = inputNode.outputFormat(forBus: 0)

        guard let targetFormat = AVAudioFormat(
            commonFormat: .pcmFormatFloat32,
            sampleRate: Config.sampleRate,
            channels: 1,
            interleaved: false
        ) else {
            throw NSError(
                domain: "AudioRecorder",
                code: 1,
                userInfo: [NSLocalizedDescriptionKey: "Failed to create target audio format"]
            )
        }

        let converter = AVAudioConverter(from: inputFormat, to: targetFormat)

        let outputURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("tracedeck_recording_\(UUID().uuidString).wav")

        let file = try AVAudioFile(
            forWriting: outputURL,
            settings: [
                AVFormatIDKey: kAudioFormatLinearPCM,
                AVSampleRateKey: Config.sampleRate,
                AVNumberOfChannelsKey: 1,
                AVLinearPCMBitDepthKey: 16,
                AVLinearPCMIsFloatKey: false,
                AVLinearPCMIsBigEndianKey: false,
            ]
        )
        audioFile = file

        let bufferSize: AVAudioFrameCount = 4096
        inputNode.installTap(onBus: 0, bufferSize: bufferSize, format: inputFormat) { [weak self] buffer, _ in
            guard let self else { return }
            if let converter {
                let frameCount = AVAudioFrameCount(
                    Double(buffer.frameLength) * Config.sampleRate / inputFormat.sampleRate
                )
                guard let converted = AVAudioPCMBuffer(pcmFormat: targetFormat, frameCapacity: frameCount) else {
                    return
                }

                var conversionError: NSError?
                let status = converter.convert(to: converted, error: &conversionError) { _, outStatus in
                    outStatus.pointee = .haveData
                    return buffer
                }

                if status == .haveData {
                    self.updateLevel(from: converted)
                    try? file.write(from: converted)
                }
            } else {
                self.updateLevel(from: buffer)
                try? file.write(from: buffer)
            }
        }

        audioEngine = engine
    }

    private func updateLevel(from buffer: AVAudioPCMBuffer) {
        guard let channelData = buffer.floatChannelData?[0] else { return }
        let frameLength = Int(buffer.frameLength)
        guard frameLength > 0 else { return }

        var rms: Float = 0
        vDSP_rmsqv(channelData, 1, &rms, vDSP_Length(frameLength))

        let minDb: Float = -60
        let maxDb: Float = 0
        let db = 20 * log10(max(rms, 0.000001))
        currentLevel = max(0, min(1, (db - minDb) / (maxDb - minDb)))
    }

    private func startLevelMonitoring() {
        levelTimer = Timer.scheduledTimer(withTimeInterval: Config.levelUpdateInterval, repeats: true) { [weak self] _ in
            guard let self else { return }
            DispatchQueue.main.async {
                self.onAudioLevel?(self.currentLevel)
            }
        }
    }

    static func checkMicrophonePermission() async -> Bool {
        switch AVCaptureDevice.authorizationStatus(for: .audio) {
        case .authorized:
            return true
        case .notDetermined:
            return await AVCaptureDevice.requestAccess(for: .audio)
        default:
            return false
        }
    }
}
