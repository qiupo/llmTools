#!/usr/bin/env node

import { execFile } from "node:child_process";
import { promises as fs } from "node:fs";
import path from "node:path";
import { promisify } from "node:util";
import { fileURLToPath } from "node:url";

const execFileAsync = promisify(execFile);
const repoRoot = path.resolve(path.dirname(fileURLToPath(import.meta.url)), "..");
const defaultReportPath = path.join(repoRoot, "dist", "phase2-closure-report.md");
const installCheckPath = path.join(repoRoot, "scripts", "check-browser-extension-install.mjs");
const markerPattern = /<!--\s*phase2-manual:([a-z0-9-]+)\s*-->/;
const notePattern = /^- (\d{4}-\d{2}-\d{2}T[^ ]+) `([^`]+)` ([A-Z]+)(?:: (.*))?$/;
const snapshotStartMarker = "<!-- phase2-acceptance-status:start -->";
const snapshotEndMarker = "<!-- phase2-acceptance-status:end -->";

function usage() {
  console.log(`Usage:
  node scripts/check-phase2-acceptance-status.mjs [--report path] [--json] [--assert-complete] [--update-report]

Summarizes Phase 2 closure report checklist state plus current Chrome/Edge extension readiness.

Default report: dist/phase2-closure-report.md
`);
}

function parseArgs(argv) {
  const args = [...argv];
  const options = {
    reportPath: defaultReportPath,
    json: false,
    assertComplete: false,
    updateReport: false
  };
  while (args.length) {
    const arg = args.shift();
    if (arg === "--help" || arg === "-h") {
      return { help: true };
    }
    if (arg === "--report") {
      const value = args.shift();
      if (!value) throw new Error("--report requires a path");
      options.reportPath = path.resolve(value);
      continue;
    }
    if (arg === "--json") {
      options.json = true;
      continue;
    }
    if (arg === "--assert-complete") {
      options.assertComplete = true;
      continue;
    }
    if (arg === "--update-report") {
      options.updateReport = true;
      continue;
    }
    throw new Error(`Unsupported argument: ${arg}`);
  }
  if (options.updateReport && options.json) {
    throw new Error("--update-report cannot be combined with --json");
  }
  return options;
}

function parseManualItems(text) {
  return text.split(/\r?\n/).flatMap((line) => {
    const marker = line.match(markerPattern);
    if (!marker) return [];
    const checkbox = line.match(/^- \[([ xX])\]\s*(.*?)(?:\s*<!--.*)?$/);
    return [{
      key: marker[1],
      checked: Boolean(checkbox && checkbox[1].toLowerCase() === "x"),
      text: checkbox ? checkbox[2].trim() : line.replace(markerPattern, "").trim()
    }];
  });
}

function parseManualNotes(text) {
  const notes = {};
  for (const line of text.split(/\r?\n/)) {
    const match = line.match(notePattern);
    if (!match) continue;
    const [, timestamp, key, action, note = ""] = match;
    notes[key] = { timestamp, action, note };
  }
  return notes;
}

function extractReportMetadata(text) {
  const metadata = {};
  for (const field of ["Started", "Completed", "Git branch", "Git HEAD", "Browser target", "Running PID(s)"]) {
    const escaped = field.replace(/[.*+?^${}()|[\]\\]/g, "\\$&");
    const match = text.match(new RegExp("^- " + escaped + ": `([^`]+)`$", "m"));
    if (match) {
      metadata[field.toLowerCase().replace(/[^a-z0-9]+/g, "_").replace(/^_|_$/g, "")] = match[1];
    }
  }
  const reportMatch = text.match(/^Report: `([^`]+)`$/m);
  const latestMatch = text.match(/^Latest report: `([^`]+)`$/m);
  if (reportMatch) metadata.report = reportMatch[1];
  if (latestMatch) metadata.latestReport = latestMatch[1];
  return metadata;
}

async function readExtensionReadiness() {
  const { stdout } = await execFileAsync(process.execPath, [installCheckPath, "--browser", "all", "--json"], {
    cwd: repoRoot,
    maxBuffer: 1024 * 1024 * 10
  });
  return JSON.parse(stdout).results;
}

function summarize(reportPath, reportText, browserReadiness) {
  const reportMetadata = extractReportMetadata(reportText);
  const notes = parseManualNotes(reportText);
  const items = parseManualItems(reportText).map((item) => ({
    ...item,
    latestNote: notes[item.key] || null
  }));
  const pending = items.filter((item) => !item.checked);
  const completed = items.filter((item) => item.checked);
  const chrome = browserReadiness.find((result) => result.id === "chrome") || null;
  const edge = browserReadiness.find((result) => result.id === "edge") || null;
  const blockers = [];
  if (!items.length) {
    blockers.push({ code: "manual_checklist_missing", message: `No manual acceptance checklist items found in ${reportPath}` });
  }
  for (const item of pending) {
    blockers.push({ code: "manual_item_pending", key: item.key, message: item.text });
  }
  if (!chrome?.ready) {
    blockers.push({
      code: "chrome_not_ready",
      issueCodes: chrome?.issueCodes || [],
      message: "Chrome extension readiness has not passed"
    });
  }
  const complete = blockers.length === 0;
  const status = {
    complete,
    reportPath: reportMetadata.report || reportPath,
    sourceReportPath: reportPath,
    report: reportMetadata,
    manual: {
      total: items.length,
      completed: completed.length,
      pending: pending.length,
      pendingKeys: pending.map((item) => item.key),
      items
    },
    browsers: browserReadiness,
    blockers
  };
  status.nextSteps = buildNextSteps(status);
  return status;
}

function buildNextSteps(status) {
  const steps = [];
  const chrome = status.browsers.find((result) => result.id === "chrome") || null;
  const pendingKeys = new Set(status.manual.pendingKeys);
  if (!chrome?.ready) {
    if (chrome?.issueCodes?.includes("extension_not_loaded_from_repo")) {
      steps.push({
        code: "load_chrome_extension",
        message: "Load or reload the unpacked Chrome extension from this repo.",
        path: path.join(repoRoot, "browser-extension", "chromium")
      });
    }
    steps.push({
      code: "verify_chrome_ready",
      message: "Verify Chrome extension readiness after loading or reloading the unpacked extension.",
      command: "node scripts/check-browser-extension-install.mjs --browser chrome --require-ready"
    });
  }
  if (pendingKeys.has("reload-extension")) {
    steps.push({
      code: "record_reload_extension",
      message: "Record the reload-extension checklist item after Chrome readiness passes.",
      command: "node scripts/record-phase2-manual-check.mjs --pass reload-extension \"Reloaded unpacked extension in Chrome and readiness check passed\""
    });
  }
  const nextManualItem = status.manual.items.find((item) => !item.checked && item.key !== "reload-extension");
  if (nextManualItem) {
    steps.push({
      code: "record_next_manual_item",
      key: nextManualItem.key,
      message: `After manually verifying ${nextManualItem.key}, record it with an evidence note.`,
      command: `node scripts/record-phase2-manual-check.mjs --pass ${nextManualItem.key} "<acceptance evidence>"`
    });
  }
  steps.push({
    code: "assert_phase2_acceptance",
    message: "Re-check the combined Phase 2 acceptance gate.",
    command: "node scripts/check-phase2-acceptance-status.mjs --assert-complete"
  });
  return steps;
}

function formatTextStatus(status) {
  const lines = [];
  lines.push(`Phase 2 acceptance: ${status.complete ? "complete" : "incomplete"}`);
  lines.push(`Report: ${status.reportPath}`);
  if (status.report.report) lines.push(`Archive: ${status.report.report}`);
  lines.push(`Manual checklist: ${status.manual.completed}/${status.manual.total} complete`);
  if (status.manual.pendingKeys.length) {
    lines.push(`Pending manual keys: ${status.manual.pendingKeys.join(", ")}`);
  }
  for (const browser of status.browsers) {
    const issues = browser.issueCodes?.length ? ` (${browser.issueCodes.join(", ")})` : "";
    lines.push(`${browser.name}: ready=${browser.ready ? "yes" : "no"}${issues}`);
  }
  if (status.blockers.length) {
    lines.push("Blockers:");
    for (const blocker of status.blockers) {
      const key = blocker.key ? ` ${blocker.key}` : "";
      const issueCodes = blocker.issueCodes?.length ? ` [${blocker.issueCodes.join(", ")}]` : "";
      lines.push(`  - ${blocker.code}${key}${issueCodes}: ${blocker.message}`);
    }
  }
  if (status.nextSteps.length) {
    lines.push("Next steps:");
    for (const step of status.nextSteps) {
      const key = step.key ? ` ${step.key}` : "";
      lines.push(`  - ${step.code}${key}: ${step.message}`);
      if (step.path) lines.push(`    path: ${step.path}`);
      if (step.command) lines.push(`    command: ${step.command}`);
    }
  }
  return lines.join("\n");
}

function printTextStatus(status) {
  console.log(formatTextStatus(status));
}

function renderSnapshot(status) {
  const timestamp = status.report.completed || new Date().toISOString().replace(/\.\d{3}Z$/, "Z");
  const timestampLabel = status.report.completed ? "Report completed" : "Generated";
  return [
    "## Phase 2 Acceptance Status Snapshot",
    "",
    snapshotStartMarker,
    "",
    `${timestampLabel}: \`${timestamp}\``,
    "",
    "```text",
    formatTextStatus(status),
    "```",
    "",
    snapshotEndMarker
  ].join("\n");
}

function updateReportSnapshot(reportText, status) {
  const snapshot = renderSnapshot(status);
  const start = reportText.indexOf(snapshotStartMarker);
  const end = reportText.indexOf(snapshotEndMarker);
  if (start !== -1 && end !== -1 && end > start) {
    const sectionStart = reportText.lastIndexOf("\n## Phase 2 Acceptance Status Snapshot", start);
    const replaceStart = sectionStart === -1 ? start : sectionStart + 1;
    const replaceEnd = end + snapshotEndMarker.length;
    return `${reportText.slice(0, replaceStart)}${snapshot}${reportText.slice(replaceEnd)}`;
  }
  return `${reportText.replace(/\s*$/, "")}\n\n${snapshot}\n`;
}

async function main() {
  const options = parseArgs(process.argv.slice(2));
  if (options.help) {
    usage();
    return;
  }
  const reportText = await fs.readFile(options.reportPath, "utf8");
  const browserReadiness = await readExtensionReadiness();
  const status = summarize(options.reportPath, reportText, browserReadiness);
  if (options.updateReport) {
    const updated = updateReportSnapshot(reportText, status);
    await fs.writeFile(options.reportPath, updated);
    console.log(`Updated Phase 2 acceptance status snapshot in ${options.reportPath}`);
  }
  if (options.json) {
    console.log(JSON.stringify(status, null, 2));
  } else if (!options.updateReport) {
    printTextStatus(status);
  }
  if (options.assertComplete && !status.complete) {
    process.exitCode = 1;
  }
}

main().catch((error) => {
  console.error(error.message || String(error));
  process.exit(1);
});
