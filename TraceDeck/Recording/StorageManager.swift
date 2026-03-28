//
//  StorageManager.swift
//  TraceDeck
//

import Foundation
import GRDB

// MARK: - Trigger Reason

enum TriggerReason: String, Sendable {
    case timer = "timer"
    case appSwitch = "app_switch"
    case tabChange = "tab_change"
    case manual = "manual"
}

// MARK: - Audio Transcription Status

enum AudioTranscriptionStatus: String, Sendable {
    case pending = "pending"
    case ready = "ready"
    case failed = "failed"
    case noModel = "no_model"
}

// MARK: - Workflow Session Model

struct WorkflowSession: Sendable, Identifiable, FetchableRecord, PersistableRecord {
    var id: Int64?
    var startedAt: Int
    var endedAt: Int?
    var note: String?
    var summary: String?
    var liveTranscript: String?
    var transcriptUpdatedAt: Int?

    static let databaseTableName = "workflow_sessions"

    enum Columns: String, ColumnExpression {
        case id
        case startedAt = "started_at"
        case endedAt = "ended_at"
        case note
        case summary
        case liveTranscript = "live_transcript"
        case transcriptUpdatedAt = "transcript_updated_at"
    }

    func encode(to container: inout PersistenceContainer) {
        container["id"] = id
        container["started_at"] = startedAt
        container["ended_at"] = endedAt
        container["note"] = note
        container["summary"] = summary
        container["live_transcript"] = liveTranscript
        container["transcript_updated_at"] = transcriptUpdatedAt
    }

    init(row: Row) {
        id = row["id"]
        startedAt = row["started_at"]
        endedAt = row["ended_at"]
        note = row["note"]
        summary = row["summary"]
        liveTranscript = row["live_transcript"]
        transcriptUpdatedAt = row["transcript_updated_at"]
    }

    init(
        id: Int64? = nil,
        startedAt: Date,
        endedAt: Date? = nil,
        note: String? = nil,
        summary: String? = nil,
        liveTranscript: String? = nil,
        transcriptUpdatedAt: Date? = nil
    ) {
        self.id = id
        self.startedAt = Int(startedAt.timeIntervalSince1970)
        self.endedAt = endedAt.map { Int($0.timeIntervalSince1970) }
        self.note = note
        self.summary = summary
        self.liveTranscript = liveTranscript
        self.transcriptUpdatedAt = transcriptUpdatedAt.map { Int($0.timeIntervalSince1970) }
    }

    var startedDate: Date {
        Date(timeIntervalSince1970: TimeInterval(startedAt))
    }

    var endedDate: Date? {
        endedAt.map { Date(timeIntervalSince1970: TimeInterval($0)) }
    }

    var isActive: Bool {
        endedAt == nil
    }
}

// MARK: - Screenshot Model

struct Screenshot: Sendable, Identifiable, FetchableRecord, PersistableRecord {
    var id: Int64?
    var capturedAt: Int
    var filePath: String
    var fileSize: Int?
    var isProcessed: Bool
    var triggerReason: String
    var sessionId: Int64?

    static let databaseTableName = "screenshots"

    enum Columns: String, ColumnExpression {
        case id
        case capturedAt = "captured_at"
        case filePath = "file_path"
        case fileSize = "file_size"
        case isProcessed = "is_processed"
        case triggerReason = "trigger_reason"
        case sessionId = "session_id"
    }

    func encode(to container: inout PersistenceContainer) {
        container["id"] = id
        container["captured_at"] = capturedAt
        container["file_path"] = filePath
        container["file_size"] = fileSize
        container["is_processed"] = isProcessed ? 1 : 0
        container["trigger_reason"] = triggerReason
        container["session_id"] = sessionId
    }

    init(row: Row) {
        id = row["id"]
        capturedAt = row["captured_at"]
        filePath = row["file_path"]
        fileSize = row["file_size"]
        isProcessed = (row["is_processed"] as Int?) == 1
        triggerReason = row["trigger_reason"] ?? TriggerReason.timer.rawValue
        sessionId = row["session_id"]
    }

    init(
        id: Int64? = nil,
        capturedAt: Date,
        filePath: String,
        fileSize: Int? = nil,
        isProcessed: Bool = false,
        triggerReason: TriggerReason = .timer,
        sessionId: Int64? = nil
    ) {
        self.id = id
        self.capturedAt = Int(capturedAt.timeIntervalSince1970)
        self.filePath = filePath
        self.fileSize = fileSize
        self.isProcessed = isProcessed
        self.triggerReason = triggerReason.rawValue
        self.sessionId = sessionId
    }

    var capturedDate: Date {
        Date(timeIntervalSince1970: TimeInterval(capturedAt))
    }

    var trigger: TriggerReason {
        TriggerReason(rawValue: triggerReason) ?? .timer
    }
}

// MARK: - Audio Recording Model

struct AudioRecording: Sendable, Identifiable, FetchableRecord, PersistableRecord {
    var id: Int64?
    var startedAt: Int
    var endedAt: Int
    var filePath: String
    var fileSize: Int?
    var transcription: String?
    var transcriptionStatus: String
    var sessionId: Int64?

    static let databaseTableName = "audio_recordings"

    enum Columns: String, ColumnExpression {
        case id
        case startedAt = "started_at"
        case endedAt = "ended_at"
        case filePath = "file_path"
        case fileSize = "file_size"
        case transcription
        case transcriptionStatus = "transcription_status"
        case sessionId = "session_id"
    }

    func encode(to container: inout PersistenceContainer) {
        container["id"] = id
        container["started_at"] = startedAt
        container["ended_at"] = endedAt
        container["file_path"] = filePath
        container["file_size"] = fileSize
        container["transcription"] = transcription
        container["transcription_status"] = transcriptionStatus
        container["session_id"] = sessionId
    }

    init(row: Row) {
        id = row["id"]
        startedAt = row["started_at"]
        endedAt = row["ended_at"]
        filePath = row["file_path"]
        fileSize = row["file_size"]
        transcription = row["transcription"]
        transcriptionStatus = row["transcription_status"] ?? AudioTranscriptionStatus.pending.rawValue
        sessionId = row["session_id"]
    }

    init(
        id: Int64? = nil,
        startedAt: Date,
        endedAt: Date,
        filePath: String,
        fileSize: Int? = nil,
        transcription: String? = nil,
        transcriptionStatus: AudioTranscriptionStatus = .pending,
        sessionId: Int64? = nil
    ) {
        self.id = id
        self.startedAt = Int(startedAt.timeIntervalSince1970)
        self.endedAt = Int(endedAt.timeIntervalSince1970)
        self.filePath = filePath
        self.fileSize = fileSize
        self.transcription = transcription
        self.transcriptionStatus = transcriptionStatus.rawValue
        self.sessionId = sessionId
    }

    var startedDate: Date {
        Date(timeIntervalSince1970: TimeInterval(startedAt))
    }

    var endedDate: Date {
        Date(timeIntervalSince1970: TimeInterval(endedAt))
    }

    var status: AudioTranscriptionStatus {
        AudioTranscriptionStatus(rawValue: transcriptionStatus) ?? .pending
    }
}

// MARK: - Storage Manager

final class StorageManager: @unchecked Sendable {
    static let shared = StorageManager()

    private enum PurgeItemKind: String {
        case screenshot
        case audio
    }

    private struct PurgeItem {
        let kind: PurgeItemKind
        let id: Int64
        let timestamp: Int
        let filePath: String
        let fileSize: Int64
    }

    private var db: DatabasePool!
    private let fileManager = FileManager.default
    private let root: URL
    private let audioRoot: URL

    var recordingsRoot: URL { root }
    var audioRecordingsRoot: URL { audioRoot }

    var storageLimitBytes: Int64 {
        get { Int64(UserDefaults.standard.integer(forKey: "storageLimitGB")) * 1_073_741_824 }
        set { UserDefaults.standard.set(Int(newValue / 1_073_741_824), forKey: "storageLimitGB") }
    }

    private init() {
        if UserDefaults.standard.integer(forKey: "storageLimitGB") == 0 {
            UserDefaults.standard.set(5, forKey: "storageLimitGB")
        }

        let baseDir = AppIdentity.appSupportBaseURL(fileManager: fileManager)
        let recordingsDir = baseDir.appendingPathComponent("recordings", isDirectory: true)
        let audioDir = recordingsDir.appendingPathComponent("audio", isDirectory: true)

        try? fileManager.createDirectory(at: baseDir, withIntermediateDirectories: true)
        try? fileManager.createDirectory(at: recordingsDir, withIntermediateDirectories: true)
        try? fileManager.createDirectory(at: audioDir, withIntermediateDirectories: true)

        root = recordingsDir
        audioRoot = audioDir

        let dbURL = baseDir.appendingPathComponent("tracedeck.sqlite")
        let legacyDbURL = baseDir.appendingPathComponent("monitome.sqlite")
        if !fileManager.fileExists(atPath: dbURL.path),
           fileManager.fileExists(atPath: legacyDbURL.path) {
            try? fileManager.moveItem(at: legacyDbURL, to: dbURL)
        }

        var config = Configuration()
        config.prepareDatabase { db in
            try db.execute(sql: "PRAGMA journal_mode = WAL")
            try db.execute(sql: "PRAGMA synchronous = NORMAL")
            try db.execute(sql: "PRAGMA busy_timeout = 5000")
            try db.execute(sql: "PRAGMA foreign_keys = ON")
        }

        do {
            db = try DatabasePool(path: dbURL.path, configuration: config)
            migrate()
            startPurgeScheduler()
        } catch {
            fatalError("Failed to initialize database: \(error)")
        }
    }

    // MARK: - Migration

    private func migrate() {
        // Each migration step runs independently so one failure doesn't block others.

        // 1. Create workflow_sessions table
        try? db.write { db in
            try db.execute(sql: """
                CREATE TABLE IF NOT EXISTS workflow_sessions (
                    id INTEGER PRIMARY KEY AUTOINCREMENT,
                    started_at INTEGER NOT NULL,
                    ended_at INTEGER,
                    note TEXT,
                    summary TEXT,
                    live_transcript TEXT,
                    transcript_updated_at INTEGER
                )
            """)
            try db.execute(sql: "CREATE INDEX IF NOT EXISTS idx_workflow_started_at ON workflow_sessions(started_at)")
            try db.execute(sql: "CREATE INDEX IF NOT EXISTS idx_workflow_ended_at ON workflow_sessions(ended_at)")
        }

        // 2. Create screenshots table
        try? db.write { db in
            try db.execute(sql: """
                CREATE TABLE IF NOT EXISTS screenshots (
                    id INTEGER PRIMARY KEY AUTOINCREMENT,
                    captured_at INTEGER NOT NULL,
                    file_path TEXT NOT NULL,
                    file_size INTEGER,
                    is_processed INTEGER DEFAULT 0,
                    trigger_reason TEXT DEFAULT 'timer',
                    session_id INTEGER
                )
            """)
            try db.execute(sql: "CREATE INDEX IF NOT EXISTS idx_screenshots_captured_at ON screenshots(captured_at)")
            try db.execute(sql: "CREATE INDEX IF NOT EXISTS idx_screenshots_processed ON screenshots(is_processed)")
            try db.execute(sql: "CREATE INDEX IF NOT EXISTS idx_screenshots_trigger ON screenshots(trigger_reason)")
            try db.execute(sql: "CREATE INDEX IF NOT EXISTS idx_screenshots_session ON screenshots(session_id)")
        }

        // 3. Migrate screenshots columns
        try? db.write { db in
            let cols = try db.columns(in: "screenshots").map { $0.name }
            if !cols.contains("trigger_reason") {
                try db.execute(sql: "ALTER TABLE screenshots ADD COLUMN trigger_reason TEXT DEFAULT 'timer'")
            }
            if !cols.contains("session_id") {
                try db.execute(sql: "ALTER TABLE screenshots ADD COLUMN session_id INTEGER")
                try db.execute(sql: "CREATE INDEX IF NOT EXISTS idx_screenshots_session ON screenshots(session_id)")
            }
        }

        // 4. Create audio_recordings table
        try? db.write { db in
            try db.execute(sql: """
                CREATE TABLE IF NOT EXISTS audio_recordings (
                    id INTEGER PRIMARY KEY AUTOINCREMENT,
                    started_at INTEGER NOT NULL,
                    ended_at INTEGER NOT NULL,
                    file_path TEXT NOT NULL,
                    file_size INTEGER,
                    transcription TEXT,
                    transcription_status TEXT DEFAULT 'pending',
                    session_id INTEGER
                )
            """)
            try db.execute(sql: "CREATE INDEX IF NOT EXISTS idx_audio_started_at ON audio_recordings(started_at)")
            try db.execute(sql: "CREATE INDEX IF NOT EXISTS idx_audio_ended_at ON audio_recordings(ended_at)")
            try db.execute(sql: "CREATE INDEX IF NOT EXISTS idx_audio_status ON audio_recordings(transcription_status)")
            try db.execute(sql: "CREATE INDEX IF NOT EXISTS idx_audio_session ON audio_recordings(session_id)")
        }

        // 5. Migrate audio_recordings columns
        try? db.write { db in
            let cols = try db.columns(in: "audio_recordings").map { $0.name }
            if !cols.contains("transcription_status") {
                try db.execute(sql: "ALTER TABLE audio_recordings ADD COLUMN transcription_status TEXT DEFAULT 'pending'")
            }
            if !cols.contains("session_id") {
                try db.execute(sql: "ALTER TABLE audio_recordings ADD COLUMN session_id INTEGER")
                try db.execute(sql: "CREATE INDEX IF NOT EXISTS idx_audio_session ON audio_recordings(session_id)")
            }
        }
    }

    // MARK: - URL Helpers

    private func timestampFilename(_ date: Date, ext: String) -> String {
        let df = DateFormatter()
        df.dateFormat = "yyyyMMdd_HHmmssSSS"
        return "\(df.string(from: date)).\(ext)"
    }

    func nextScreenshotURL(at date: Date = Date()) -> URL {
        root.appendingPathComponent(timestampFilename(date, ext: "jpg"))
    }

    func nextAudioURL(startedAt: Date = Date()) -> URL {
        audioRoot.appendingPathComponent(timestampFilename(startedAt, ext: "wav"))
    }

    // MARK: - Workflow Sessions

    @discardableResult
    func startWorkflowSession(startedAt: Date = Date(), note: String? = nil) -> Int64? {
        let normalizedNote = note?.trimmingCharacters(in: .whitespacesAndNewlines)
        var session = WorkflowSession(
            startedAt: startedAt,
            endedAt: nil,
            note: normalizedNote?.isEmpty == false ? normalizedNote : nil
        )
        do {
            try db.write { db in
                try session.insert(db)
            }
            return session.id
        } catch {
            print("Failed to create workflow session: \(error)")
            return nil
        }
    }

    func endWorkflowSession(
        id: Int64,
        endedAt: Date = Date(),
        summary: String? = nil,
        liveTranscript: String? = nil
    ) {
        let normalizedSummary = summary?.trimmingCharacters(in: .whitespacesAndNewlines)
        let normalizedTranscript = liveTranscript?.trimmingCharacters(in: .whitespacesAndNewlines)
        try? db.write { db in
            try db.execute(
                sql: """
                    UPDATE workflow_sessions
                    SET ended_at = ?,
                        summary = COALESCE(?, summary),
                        live_transcript = COALESCE(?, live_transcript),
                        transcript_updated_at = CASE
                            WHEN ? IS NOT NULL THEN ?
                            ELSE transcript_updated_at
                        END
                    WHERE id = ?
                """,
                arguments: [
                    Int(endedAt.timeIntervalSince1970),
                    normalizedSummary?.isEmpty == false ? normalizedSummary : nil,
                    normalizedTranscript?.isEmpty == false ? normalizedTranscript : nil,
                    normalizedTranscript?.isEmpty == false ? 1 : nil,
                    Int(endedAt.timeIntervalSince1970),
                    id
                ]
            )
        }
    }

    func updateWorkflowSessionNote(id: Int64, note: String?) {
        let normalized = note?.trimmingCharacters(in: .whitespacesAndNewlines)
        try? db.write { db in
            try db.execute(
                sql: "UPDATE workflow_sessions SET note = ? WHERE id = ?",
                arguments: [normalized?.isEmpty == false ? normalized : nil, id]
            )
        }
    }

    func updateWorkflowSessionSummary(id: Int64, summary: String?) {
        let normalized = summary?.trimmingCharacters(in: .whitespacesAndNewlines)
        try? db.write { db in
            try db.execute(
                sql: "UPDATE workflow_sessions SET summary = ? WHERE id = ?",
                arguments: [normalized?.isEmpty == false ? normalized : nil, id]
            )
        }
    }

    func upsertWorkflowSessionTranscript(
        id: Int64,
        transcript: String?,
        updatedAt: Date = Date()
    ) {
        let normalized = transcript?.trimmingCharacters(in: .whitespacesAndNewlines)
        try? db.write { db in
            try db.execute(
                sql: """
                    UPDATE workflow_sessions
                    SET live_transcript = ?, transcript_updated_at = ?
                    WHERE id = ?
                """,
                arguments: [
                    normalized?.isEmpty == false ? normalized : nil,
                    Int(updatedAt.timeIntervalSince1970),
                    id
                ]
            )
        }
    }

    func activeWorkflowSession() -> WorkflowSession? {
        try? db.read { db in
            try WorkflowSession
                .filter(WorkflowSession.Columns.endedAt == nil)
                .order(WorkflowSession.Columns.startedAt.desc)
                .fetchOne(db)
        }
    }

    func fetchWorkflowSessionsForDateRange(from: Date, to: Date) -> [WorkflowSession] {
        let fromTs = Int(from.timeIntervalSince1970)
        let toTs = Int(to.timeIntervalSince1970)

        return (try? db.read { db in
            try WorkflowSession
                .filter(
                    WorkflowSession.Columns.startedAt <= toTs &&
                    (WorkflowSession.Columns.endedAt == nil || WorkflowSession.Columns.endedAt >= fromTs)
                )
                .order(WorkflowSession.Columns.startedAt.desc)
                .fetchAll(db)
        }) ?? []
    }

    func fetchWorkflowSessionsForDay(_ date: Date, activeSessionID: Int64? = nil) -> [WorkflowSession] {
        let calendar = Calendar.current
        let startOfDay = calendar.startOfDay(for: date)
        let endOfDay = calendar.date(byAdding: .day, value: 1, to: startOfDay)!
        let sessions = fetchWorkflowSessionsForDateRange(from: startOfDay, to: endOfDay)

        // Filter out empty sessions (no screenshots, no audio) unless currently active
        return sessions.filter { session in
            // Always keep the active session
            if let activeSessionID, session.id == activeSessionID { return true }
            // Keep sessions that have content
            guard let id = session.id else { return false }
            let hasScreenshots = !fetchScreenshots(forSessionID: id, limit: 1).isEmpty
            if hasScreenshots { return true }
            let hasAudio = !fetchAudioRecordings(forSessionID: id).isEmpty
            return hasAudio
        }
    }

    // MARK: - Save Screenshot

    @discardableResult
    func saveScreenshot(
        url: URL,
        capturedAt: Date,
        reason: TriggerReason = .timer,
        sessionID: Int64? = nil
    ) -> Int64? {
        let fileSize = (try? fileManager.attributesOfItem(atPath: url.path)[.size] as? Int) ?? 0

        var screenshot = Screenshot(
            capturedAt: capturedAt,
            filePath: url.path,
            fileSize: fileSize,
            isProcessed: false,
            triggerReason: reason,
            sessionId: sessionID
        )

        do {
            try db.write { db in
                try screenshot.insert(db)
            }
            return screenshot.id
        } catch {
            print("Failed to save screenshot: \(error)")
            return nil
        }
    }

    // MARK: - Save Audio

    @discardableResult
    func saveAudioRecording(
        url: URL,
        startedAt: Date,
        endedAt: Date,
        transcription: String? = nil,
        status: AudioTranscriptionStatus = .pending,
        sessionID: Int64? = nil
    ) -> Int64? {
        let fileSize = (try? fileManager.attributesOfItem(atPath: url.path)[.size] as? Int) ?? 0
        var recording = AudioRecording(
            startedAt: startedAt,
            endedAt: endedAt,
            filePath: url.path,
            fileSize: fileSize,
            transcription: transcription,
            transcriptionStatus: status,
            sessionId: sessionID
        )

        do {
            try db.write { db in
                try recording.insert(db)
            }
            return recording.id
        } catch {
            print("Failed to save audio recording: \(error)")
            return nil
        }
    }

    func updateAudioTranscription(
        recordingID: Int64,
        transcription: String?,
        status: AudioTranscriptionStatus
    ) {
        try? db.write { db in
            try db.execute(
                sql: """
                    UPDATE audio_recordings
                    SET transcription = ?, transcription_status = ?
                    WHERE id = ?
                """,
                arguments: [transcription, status.rawValue, recordingID]
            )
        }

        NotificationCenter.default.post(
            name: .audioTranscriptionUpdated,
            object: nil,
            userInfo: [
                "recordingId": recordingID,
                "status": status.rawValue,
                "transcription": transcription as Any
            ]
        )
    }

    // MARK: - Fetch Screenshots

    func fetchUnprocessed() -> [Screenshot] {
        (try? db.read { db in
            try Screenshot
                .filter(Screenshot.Columns.isProcessed == false)
                .order(Screenshot.Columns.capturedAt.asc)
                .fetchAll(db)
        }) ?? []
    }

    func fetchByDateRange(from: Date, to: Date) -> [Screenshot] {
        let fromTs = Int(from.timeIntervalSince1970)
        let toTs = Int(to.timeIntervalSince1970)

        return (try? db.read { db in
            try Screenshot
                .filter(Screenshot.Columns.capturedAt >= fromTs && Screenshot.Columns.capturedAt <= toTs)
                .order(Screenshot.Columns.capturedAt.desc)
                .fetchAll(db)
        }) ?? []
    }

    func fetchRecent(limit: Int = 100) -> [Screenshot] {
        (try? db.read { db in
            try Screenshot
                .order(Screenshot.Columns.capturedAt.desc)
                .limit(limit)
                .fetchAll(db)
        }) ?? []
    }

    func fetchForDay(_ date: Date) -> [Screenshot] {
        let calendar = Calendar.current
        let startOfDay = calendar.startOfDay(for: date)
        let endOfDay = calendar.date(byAdding: .day, value: 1, to: startOfDay)!
        return fetchByDateRange(from: startOfDay, to: endOfDay)
    }

    func fetchScreenshots(forSessionID sessionID: Int64, limit: Int? = nil) -> [Screenshot] {
        (try? db.read { db in
            if let limit {
                let recent = try Screenshot
                    .filter(Screenshot.Columns.sessionId == sessionID)
                    .order(Screenshot.Columns.capturedAt.desc)
                    .limit(limit)
                    .fetchAll(db)
                return recent.reversed()
            }
            return try Screenshot
                .filter(Screenshot.Columns.sessionId == sessionID)
                .order(Screenshot.Columns.capturedAt.asc)
                .fetchAll(db)
        }) ?? []
    }

    // MARK: - Fetch Audio

    func fetchAudioForDateRange(from: Date, to: Date) -> [AudioRecording] {
        let fromTs = Int(from.timeIntervalSince1970)
        let toTs = Int(to.timeIntervalSince1970)

        return (try? db.read { db in
            try AudioRecording
                .filter(AudioRecording.Columns.startedAt <= toTs && AudioRecording.Columns.endedAt >= fromTs)
                .order(AudioRecording.Columns.startedAt.desc)
                .fetchAll(db)
        }) ?? []
    }

    func fetchAudioRecordings(forSessionID sessionID: Int64) -> [AudioRecording] {
        (try? db.read { db in
            try AudioRecording
                .filter(AudioRecording.Columns.sessionId == sessionID)
                .order(AudioRecording.Columns.startedAt.asc)
                .fetchAll(db)
        }) ?? []
    }

    func latestTranscription(around timestamp: Date, within seconds: TimeInterval = 180) -> AudioRecording? {
        let ts = Int(timestamp.timeIntervalSince1970)
        let window = Int(seconds)
        return try? db.read { db in
            try AudioRecording.fetchOne(
                db,
                sql: """
                    SELECT *
                    FROM audio_recordings
                    WHERE transcription_status = 'ready'
                      AND transcription IS NOT NULL
                      AND started_at <= ?
                      AND ended_at >= ?
                    ORDER BY ABS(((started_at + ended_at) / 2) - ?) ASC
                    LIMIT 1
                """,
                arguments: [ts + window, ts - window, ts]
            )
        }
    }

    // MARK: - Mark as Processed

    func markProcessed(ids: [Int64]) {
        guard !ids.isEmpty else { return }
        try? db.write { db in
            let placeholders = ids.map { _ in "?" }.joined(separator: ",")
            try db.execute(
                sql: "UPDATE screenshots SET is_processed = 1 WHERE id IN (\(placeholders))",
                arguments: StatementArguments(ids)
            )
        }
    }

    // MARK: - Storage Stats

    func totalStorageUsed() -> Int64 {
        (try? db.read { db in
            let screenshotBytes = try Int64.fetchOne(db, sql: "SELECT COALESCE(SUM(file_size), 0) FROM screenshots") ?? 0
            let audioBytes = try Int64.fetchOne(db, sql: "SELECT COALESCE(SUM(file_size), 0) FROM audio_recordings") ?? 0
            return screenshotBytes + audioBytes
        }) ?? 0
    }

    func screenshotCount() -> Int {
        (try? db.read { db in
            try Int.fetchOne(db, sql: "SELECT COUNT(*) FROM screenshots")
        }) ?? 0
    }

    func audioRecordingCount() -> Int {
        (try? db.read { db in
            try Int.fetchOne(db, sql: "SELECT COUNT(*) FROM audio_recordings")
        }) ?? 0
    }

    func todayCount() -> Int {
        let startOfDay = Calendar.current.startOfDay(for: Date())
        let ts = Int(startOfDay.timeIntervalSince1970)
        return (try? db.read { db in
            try Int.fetchOne(db, sql: "SELECT COUNT(*) FROM screenshots WHERE captured_at >= ?", arguments: [ts])
        }) ?? 0
    }

    // MARK: - Purge Old Files

    private func startPurgeScheduler() {
        purgeIfNeeded()
        Timer.scheduledTimer(withTimeInterval: 3600, repeats: true) { [weak self] _ in
            self?.purgeIfNeeded()
        }
    }

    private func oldestItems(limit: Int) -> [PurgeItem] {
        (try? db.read { db in
            let rows = try Row.fetchAll(
                db,
                sql: """
                    SELECT 'screenshot' AS kind, id, captured_at AS ts, file_path, COALESCE(file_size, 0) AS size
                    FROM screenshots
                    UNION ALL
                    SELECT 'audio' AS kind, id, started_at AS ts, file_path, COALESCE(file_size, 0) AS size
                    FROM audio_recordings
                    ORDER BY ts ASC
                    LIMIT ?
                """,
                arguments: [limit]
            )
            return rows.compactMap { row in
                guard
                    let kindString: String = row["kind"],
                    let kind = PurgeItemKind(rawValue: kindString),
                    let id: Int64 = row["id"],
                    let ts: Int = row["ts"],
                    let path: String = row["file_path"]
                else {
                    return nil
                }
                let size = Int64(row["size"] ?? 0)
                return PurgeItem(kind: kind, id: id, timestamp: ts, filePath: path, fileSize: size)
            }
        }) ?? []
    }

    func purgeIfNeeded() {
        let limit = storageLimitBytes
        guard limit > 0 else { return }

        var currentSize = totalStorageUsed()
        guard currentSize > limit else { return }

        let targetSize = Int64(Double(limit) * 0.9)

        while currentSize > targetSize {
            let batch = oldestItems(limit: 200)
            guard !batch.isEmpty else { break }

            for item in batch {
                try? fileManager.removeItem(atPath: item.filePath)

                _ = try? db.write { db in
                    switch item.kind {
                    case .screenshot:
                        try Screenshot.deleteOne(db, id: item.id)
                    case .audio:
                        try AudioRecording.deleteOne(db, id: item.id)
                    }
                }

                currentSize -= item.fileSize
                if currentSize <= targetSize {
                    break
                }
            }
        }

        print("Purged recordings. Storage now: \(currentSize / 1_048_576)MB")
    }

    // MARK: - Delete

    func delete(id: Int64) {
        guard let screenshot = try? db.read({ db in
            try Screenshot.fetchOne(db, id: id)
        }) else { return }

        try? fileManager.removeItem(atPath: screenshot.filePath)
        _ = try? db.write { db in
            try Screenshot.deleteOne(db, id: id)
        }
    }
}
