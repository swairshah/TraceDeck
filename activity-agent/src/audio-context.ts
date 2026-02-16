import { existsSync } from "fs";
import { join } from "path";
import type { AudioContextSnippet } from "./types.js";

declare global {
  // eslint-disable-next-line no-var
  var Bun: any;
}

type SqliteStatement = {
  get: (...params: unknown[]) => Record<string, unknown> | undefined;
};

type SqliteDb = {
  prepare?: (sql: string) => SqliteStatement;
  query?: (sql: string) => SqliteStatement;
  close?: () => void;
};

async function getDatabaseClass(): Promise<any> {
  const isBun = typeof globalThis.Bun !== "undefined";
  if (isBun) {
    // @ts-ignore - Bun built-in
    const mod = await import("bun:sqlite");
    return mod.Database;
  }
  const mod = await import("better-sqlite3");
  return mod.default;
}

function getSingleRow(db: SqliteDb, sql: string, params: unknown[]): Record<string, unknown> | undefined {
  if (typeof db.prepare === "function") {
    return db.prepare(sql).get(...params);
  }
  if (typeof db.query === "function") {
    return db.query(sql).get(...params);
  }
  return undefined;
}

export async function loadAudioContextForTimestamp(
  dataDir: string,
  timestampMs: number,
  windowSeconds = 180
): Promise<AudioContextSnippet | undefined> {
  const dbPath = join(dataDir, "monitome.sqlite");
  if (!existsSync(dbPath)) {
    return undefined;
  }

  const Database = await getDatabaseClass();
  const db: SqliteDb = new Database(dbPath);
  const ts = Math.floor(timestampMs / 1000);
  const window = Math.max(0, Math.floor(windowSeconds));

  const sql = `
    SELECT id, started_at, ended_at, transcription
    FROM audio_recordings
    WHERE transcription_status = 'ready'
      AND transcription IS NOT NULL
      AND started_at <= ?
      AND ended_at >= ?
    ORDER BY ABS(((started_at + ended_at) / 2) - ?) ASC
    LIMIT 1
  `;

  try {
    const row = getSingleRow(db, sql, [ts + window, ts - window, ts]);
    if (!row) {
      return undefined;
    }

    const transcription = String(row.transcription ?? "").trim();
    if (!transcription) {
      return undefined;
    }

    return {
      recordingId: Number(row.id ?? 0),
      startedAt: Number(row.started_at ?? ts),
      endedAt: Number(row.ended_at ?? ts),
      transcription,
    };
  } finally {
    db.close?.();
  }
}
