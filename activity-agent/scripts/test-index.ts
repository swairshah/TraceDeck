#!/usr/bin/env npx tsx
/**
 * Test the indexing prompt on any image.
 * 
 * Usage:
 *   npx tsx scripts/test-index.ts <image-path>
 *   npx tsx scripts/test-index.ts ~/Desktop/screenshot.png
 *   npx tsx scripts/test-index.ts ./data/20260103_094128820.jpg
 */

import { readFileSync } from "fs";
import { resolve } from "path";
import { ActivityAgent } from "../src/activity-agent.js";
import { join } from "path";
import { homedir } from "os";

const imagePath = process.argv[2];
if (!imagePath) {
  console.error("Usage: npx tsx scripts/test-index.ts <image-path>");
  process.exit(1);
}

const resolved = resolve(imagePath);
console.log(`\nIndexing: ${resolved}\n`);

// Use the real ActivityAgent so we get the full prompt + learned rules
const dataDir = process.argv.includes("--data") 
  ? process.argv[process.argv.indexOf("--data") + 1]
  : join(homedir(), "Library/Application Support/Monitome");

const agent = await ActivityAgent.create({ 
  dataDir,
  enableSearchIndex: false,  // don't touch the real index
});

const entry = await agent.analyzeScreenshot({
  filename: "test_manual.jpg",
  timestamp: Date.now(),
  date: new Date().toISOString().split("T")[0],
  time: new Date().toTimeString().split(" ")[0],
  path: resolved,
});

console.log(JSON.stringify(entry, null, 2));
