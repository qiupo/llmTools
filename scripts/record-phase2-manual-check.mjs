#!/usr/bin/env node

import { spawn } from "node:child_process";
import { promises as fs } from "node:fs";
import path from "node:path";
import { fileURLToPath } from "node:url";

const repoRoot = path.resolve(path.dirname(fileURLToPath(import.meta.url)), "..");
const defaultReportPath = path.join(repoRoot, "dist", "phase2-closure-report.md");
const extensionInstallCheckPath = path.join(repoRoot, "scripts", "check-browser-extension-install.mjs");
const acceptanceStatusCheckPath = path.join(repoRoot, "scripts", "check-phase2-acceptance-status.mjs");
const markerPattern = /<!--\s*phase2-manual:([a-z0-9-]+)\s*-->/;

function usage() {
  console.log(`Usage:
  node scripts/record-phase2-manual-check.mjs --list [--report path]
  node scripts/record-phase2-manual-check.mjs --assert-complete [--report path]
  node scripts/record-phase2-manual-check.mjs --pass <key> <note...> [--report path]
  node scripts/record-phase2-manual-check.mjs --skip <key> <note...> [--report path]
  node scripts/record-phase2-manual-check.mjs --reset <key> [note...] [--report path]

Default report: dist/phase2-closure-report.md
`);
}

function parseArgs(argv) {
  const args = [...argv];
  let reportPath = defaultReportPath;
  let explicitReport = false;
  const reportIndex = args.indexOf("--report");
  if (reportIndex !== -1) {
    const value = args[reportIndex + 1];
    if (!value) {
      throw new Error("--report requires a path");
    }
    reportPath = path.resolve(value);
    explicitReport = true;
    args.splice(reportIndex, 2);
  }
  const command = args.shift();
  const key = args.shift();
  const note = args.join(" ").trim();
  if (!command || command === "--help" || command === "-h") {
    return { help: true, reportPath, explicitReport };
  }
  if (!["--list", "--assert-complete", "--pass", "--skip", "--reset"].includes(command)) {
    throw new Error(`Unsupported command: ${command}`);
  }
  if (!["--list", "--assert-complete"].includes(command) && !key) {
    throw new Error(`${command} requires a checklist key`);
  }
  if (["--pass", "--skip"].includes(command) && !note) {
    throw new Error(`${command} requires a note describing the acceptance evidence or skip reason`);
  }
  return { command, key, note, reportPath, explicitReport };
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

function extractLinkedReportPaths(text) {
  const paths = new Set();
  for (const match of text.matchAll(/^(?:Report|Latest report): `([^`]+)`$/gm)) {
    paths.add(path.resolve(match[1]));
  }
  return paths;
}

function updateChecklist(text, key, command, note) {
  let found = false;
  const checked = command === "--reset" ? " " : "x";
  const action = command.replace(/^--/, "").toUpperCase();
  const updated = text.split(/\r?\n/).map((line) => {
    const marker = line.match(markerPattern);
    if (!marker || marker[1] !== key) return line;
    found = true;
    return line.replace(/^- \[[ xX]\]/, `- [${checked}]`);
  }).join("\n");
  if (!found) {
    throw new Error(`Manual acceptance key not found: ${key}`);
  }
  const timestamp = new Date().toISOString().replace(/\.\d{3}Z$/, "Z");
  const noteLine = `- ${timestamp} \`${key}\` ${action}${note ? `: ${note}` : ""}`;
  if (updated.includes("## Manual Acceptance Notes")) {
    return `${updated}\n${noteLine}\n`;
  }
  return `${updated}\n\n## Manual Acceptance Notes\n\n${noteLine}\n`;
}

function assertComplete(items, reportPath) {
  if (!items.length) {
    console.error(`No manual acceptance checklist items found in ${reportPath}`);
    process.exitCode = 1;
    return;
  }
  const pending = items.filter((item) => !item.checked);
  if (pending.length) {
    console.error(`Manual acceptance is incomplete: ${pending.length} pending item(s).`);
    for (const item of pending) {
      console.error(`[ ] ${item.key} - ${item.text}`);
    }
    process.exitCode = 1;
    return;
  }
  console.log(`Manual acceptance checklist complete: ${items.length} item(s).`);
}

function runCommand(command, args, failureMessage) {
  return new Promise((resolve, reject) => {
    const child = spawn(command, args, {
      cwd: repoRoot,
      stdio: "inherit"
    });
    child.on("error", reject);
    child.on("exit", (code, signal) => {
      if (code === 0) {
        resolve();
        return;
      }
      reject(new Error(signal ? `${failureMessage} (${signal})` : failureMessage));
    });
  });
}

async function runPreflight(parsed) {
  if (parsed.command === "--pass" && parsed.key === "reload-extension") {
    await runCommand(
      process.execPath,
      [extensionInstallCheckPath, "--browser", "chrome", "--require-ready"],
      [
        "Cannot mark reload-extension as passed until the Chrome unpacked extension is loaded from this repo and the native messaging manifest is ready.",
        `Load or reload the unpacked extension folder: ${path.join(repoRoot, "browser-extension", "chromium")}`,
        "Then verify with: node scripts/check-browser-extension-install.mjs --browser chrome --require-ready"
      ].join("\n")
    );
  }
}

async function updateAcceptanceStatusSnapshot(reportPath) {
  await runCommand(
    process.execPath,
    [acceptanceStatusCheckPath, "--report", reportPath, "--update-report"],
    `Failed to update Phase 2 acceptance status snapshot for ${reportPath}`
  );
}

async function readText(filePath) {
  return fs.readFile(filePath, "utf8");
}

async function main() {
  const parsed = parseArgs(process.argv.slice(2));
  if (parsed.help) {
    usage();
    return;
  }

  const initialText = await readText(parsed.reportPath);
  if (["--list", "--assert-complete"].includes(parsed.command)) {
    const items = parseManualItems(initialText);
    if (parsed.command === "--assert-complete") {
      assertComplete(items, parsed.reportPath);
      return;
    }
    if (!items.length) {
      console.log(`No manual acceptance checklist items found in ${parsed.reportPath}`);
      return;
    }
    for (const item of items) {
      console.log(`${item.checked ? "[x]" : "[ ]"} ${item.key} - ${item.text}`);
    }
    return;
  }

  await runPreflight(parsed);

  const reportTargets = parsed.explicitReport
    ? new Set([path.resolve(parsed.reportPath)])
    : new Set([path.resolve(parsed.reportPath), ...extractLinkedReportPaths(initialText)]);
  for (const target of reportTargets) {
    const text = await readText(target);
    const updated = updateChecklist(text, parsed.key, parsed.command, parsed.note);
    await fs.writeFile(target, updated);
  }
  for (const target of reportTargets) {
    await updateAcceptanceStatusSnapshot(target);
  }

  console.log(`Updated ${reportTargets.size} report file(s) for ${parsed.key}.`);
}

main().catch((error) => {
  console.error(error.message || String(error));
  process.exit(1);
});
