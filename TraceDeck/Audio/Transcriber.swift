//
//  Transcriber.swift
//  TraceDeck
//

import Foundation

final class Transcriber {
    enum TranscriptionError: Error, LocalizedError {
        case binaryNotFound
        case modelNotFound(String)
        case transcriptionFailed(String)
        case noOutput

        var errorDescription: String? {
            switch self {
            case .binaryNotFound:
                return "qwen_asr binary not found"
            case .modelNotFound(let path):
                return "Transcription model not found at \(path)"
            case .transcriptionFailed(let message):
                return "Transcription failed: \(message)"
            case .noOutput:
                return "Transcription returned no text"
            }
        }
    }

    static let defaultModelPath = NSHomeDirectory() + "/Library/Application Support/Hearsay/Models/qwen3-asr-0.6b"
    static let modelPathUserDefaultsKey = "transcriptionModelPath"

    private let modelPath: String

    init(modelPath: String) {
        self.modelPath = modelPath
    }

    func transcribe(audioURL: URL) async throws -> String {
        let binaryURL = try findBinary()
        guard FileManager.default.fileExists(atPath: modelPath) else {
            throw TranscriptionError.modelNotFound(modelPath)
        }

        let process = Process()
        process.executableURL = binaryURL
        process.arguments = [
            "-d", modelPath,
            "-i", audioURL.path,
            "--silent",
        ]

        let outputPipe = Pipe()
        let errorPipe = Pipe()
        process.standardOutput = outputPipe
        process.standardError = errorPipe

        return try await withCheckedThrowingContinuation { continuation in
            do {
                try process.run()
                process.terminationHandler = { _ in
                    let outputData = outputPipe.fileHandleForReading.readDataToEndOfFile()
                    let errorData = errorPipe.fileHandleForReading.readDataToEndOfFile()
                    let output = String(data: outputData, encoding: .utf8)?
                        .trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
                    let stderr = String(data: errorData, encoding: .utf8) ?? ""

                    if process.terminationStatus != 0 {
                        continuation.resume(throwing: TranscriptionError.transcriptionFailed(stderr))
                        return
                    }
                    if output.isEmpty {
                        continuation.resume(throwing: TranscriptionError.noOutput)
                        return
                    }
                    continuation.resume(returning: output)
                }
            } catch {
                continuation.resume(throwing: TranscriptionError.transcriptionFailed(error.localizedDescription))
            }
        }
    }

    private func findBinary() throws -> URL {
        if let bundleBinary = Bundle.main.executableURL?.deletingLastPathComponent().appendingPathComponent("qwen_asr"),
           FileManager.default.isExecutableFile(atPath: bundleBinary.path) {
            return bundleBinary
        }

        if let resourcesBinary = Bundle.main.url(forResource: "qwen_asr", withExtension: nil),
           FileManager.default.isExecutableFile(atPath: resourcesBinary.path) {
            return resourcesBinary
        }

        let devPath = URL(fileURLWithPath: "/Users/swair/work/misc/qwen-asr/qwen_asr")
        if FileManager.default.isExecutableFile(atPath: devPath.path) {
            return devPath
        }

        throw TranscriptionError.binaryNotFound
    }
}
