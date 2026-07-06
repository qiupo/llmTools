#!/usr/bin/env node

import { execFile } from "node:child_process";
import { promises as fs } from "node:fs";
import path from "node:path";
import { promisify } from "node:util";
import { fileURLToPath } from "node:url";

const execFileAsync = promisify(execFile);
const repoRoot = path.resolve(path.dirname(fileURLToPath(import.meta.url)), "..");

function usage() {
  console.log(`Usage:
  node scripts/check-phase3-goal-audit.mjs [--run-checks] [--run-live-ocr] [--json] [--assert-complete]

Audits the end-to-end Phase 3 goal against current machine state:
- Phase 2 acceptance report and browser readiness
- packaged dist/llmTools.app process and code signature
- Swift/extension regression gates when --run-checks is set
- configured vision OCR model and live OCR/image explanation when --run-live-ocr is set

The script is intentionally strict: browser/manual acceptance remains incomplete until Chrome
has loaded the unpacked extension from this repo and the manual checklist is recorded.
`);
}

function parseArgs(argv) {
  const options = {
    runChecks: false,
    runLiveOCR: false,
    json: false,
    assertComplete: false
  };
  const args = [...argv];
  while (args.length) {
    const arg = args.shift();
    if (arg === "--help" || arg === "-h") {
      return { help: true };
    }
    if (arg === "--run-checks") {
      options.runChecks = true;
      continue;
    }
    if (arg === "--run-live-ocr") {
      options.runLiveOCR = true;
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
    throw new Error(`Unsupported argument: ${arg}`);
  }
  return options;
}

async function runCommand(command, args, options = {}) {
  try {
    const { stdout, stderr } = await execFileAsync(command, args, {
      cwd: repoRoot,
      maxBuffer: 1024 * 1024 * 30,
      ...options
    });
    return {
      ok: true,
      command: [command, ...args].join(" "),
      stdout,
      stderr
    };
  } catch (error) {
    return {
      ok: false,
      command: [command, ...args].join(" "),
      stdout: error.stdout || "",
      stderr: error.stderr || "",
      message: error.message || String(error),
      exitCode: error.code ?? null
    };
  }
}

async function readJSON(filePath) {
  return JSON.parse(await fs.readFile(filePath, "utf8"));
}

function oneLine(text, limit = 220) {
  const collapsed = String(text || "")
    .replace(/\s+/g, " ")
    .trim();
  if (collapsed.length <= limit) return collapsed;
  return `${collapsed.slice(0, limit)}...`;
}

function requirement(id, title, status, evidence = "", blockers = []) {
  return { id, title, status, evidence, blockers };
}

function isPassed(item) {
  return item.status === "pass" || item.status === "deferred";
}

async function auditPhase2() {
  const result = await runCommand(process.execPath, [
    path.join(repoRoot, "scripts", "check-phase2-acceptance-status.mjs"),
    "--json"
  ]);
  if (!result.ok) {
    return {
      command: result,
      status: null,
      requirement: requirement(
        "phase2-acceptance",
        "Phase 2 browser translation acceptance",
        "fail",
        oneLine(result.stderr || result.stdout || result.message),
        ["phase2_acceptance_status_failed"]
      )
    };
  }
  const status = JSON.parse(result.stdout);
  const blockers = status.blockers.map((blocker) => blocker.code + (blocker.key ? `:${blocker.key}` : ""));
  return {
    command: result,
    status,
    requirement: requirement(
      "phase2-acceptance",
      "Phase 2 browser translation acceptance",
      status.complete ? "pass" : "blocked",
      `manual=${status.manual.completed}/${status.manual.total}, chromeReady=${Boolean(status.browsers.find((browser) => browser.id === "chrome")?.ready)}, report=${status.reportPath}`,
      blockers
    )
  };
}

async function auditPackagedApp() {
  const binaryPath = path.join(repoRoot, "dist", "llmTools.app", "Contents", "MacOS", "llmTools");
  const pgrepResult = await runCommand("pgrep", ["-f", binaryPath]);
  let processResult = pgrepResult;
  if (pgrepResult.ok) {
    const pids = pgrepResult.stdout
      .split(/\s+/)
      .map((value) => value.trim())
      .filter(Boolean);
    if (pids.length) {
      processResult = await runCommand("ps", ["-p", pids.join(","), "-o", "pid=", "-o", "command="]);
    }
  }
  const codesignResult = await runCommand("codesign", [
    "--verify",
    "--deep",
    "--strict",
    "--verbose=2",
    path.join(repoRoot, "dist", "llmTools.app")
  ]);
  const running = processResult.ok && processResult.stdout.includes(binaryPath);
  const signed = codesignResult.ok;
  const blockers = [];
  if (!running) blockers.push("packaged_app_not_running");
  if (!signed) blockers.push("codesign_verify_failed");
  return {
    process: processResult,
    codesign: codesignResult,
    requirement: requirement(
      "packaged-app",
      "Packaged dist/llmTools.app is signed and running",
      running && signed ? "pass" : "fail",
      `running=${running}, codesign=${signed}, process=${oneLine(processResult.stdout)}`,
      blockers
    )
  };
}

async function auditRegistryOCR() {
  const registryPath = path.join(process.env.HOME, "Library", "Application Support", "llmTools", "model-registry.json");
  try {
    const registry = await readJSON(registryPath);
    const ocr = registry.preferences?.ocr || null;
    const models = registry.models || [];
    const ocrModel = models.find((model) => model.id === ocr?.modelID) || null;
    const supportsImage = Boolean(ocrModel?.capabilities?.inputs?.includes("image"));
    const probePassed = ocrModel?.capabilities?.source === "probePassed";
    const blockers = [];
    if (!ocr?.enabled) blockers.push("ocr_disabled");
    if (!ocr?.modelID) blockers.push("ocr_model_missing");
    if (!ocrModel) blockers.push("ocr_model_not_found");
    if (ocrModel && !supportsImage) blockers.push("ocr_model_not_vision_capable");
    if (ocrModel && !probePassed) blockers.push("ocr_model_not_probe_passed");
    return {
      registryPath,
      ocr,
      model: ocrModel,
      requirement: requirement(
        "ocr-configuration",
        "OCR has a configured probe-passed vision model",
        blockers.length ? "fail" : "pass",
        ocrModel ? `${ocrModel.name} (${ocrModel.providerConfiguration?.modelID || ocrModel.id}) source=${ocrModel.capabilities?.source}` : "No OCR model",
        blockers
      )
    };
  } catch (error) {
    return {
      registryPath,
      ocr: null,
      model: null,
      requirement: requirement(
        "ocr-configuration",
        "OCR has a configured probe-passed vision model",
        "fail",
        error.message || String(error),
        ["registry_read_failed"]
      )
    };
  }
}

async function auditChecks(options) {
  if (!options.runChecks) {
    return {
      results: [],
      requirement: requirement(
        "automated-regression",
        "Swift/native and browser fixture regression checks",
        "unknown",
        "Skipped; rerun with --run-checks.",
        ["checks_not_run"]
      )
    };
  }
  const checks = [
    await runCommand("git", ["diff", "--check"]),
    await runCommand("swift", ["run", "LLMToolsChecks"], { timeout: 120_000 }),
    await runCommand(process.execPath, [path.join(repoRoot, "scripts", "check-browser-extension-dom.mjs")], { timeout: 120_000 })
  ];
  const blockers = checks
    .filter((check) => !check.ok)
    .map((check) => `failed:${check.command}`);
  return {
    results: checks,
    requirement: requirement(
      "automated-regression",
      "Swift/native and browser fixture regression checks",
      blockers.length ? "fail" : "pass",
      checks.map((check) => `${check.command}=${check.ok ? "pass" : "fail"}`).join("; "),
      blockers
    )
  };
}

async function auditLiveOCR(options) {
  if (!options.runLiveOCR) {
    return {
      command: null,
      requirement: requirement(
        "live-ocr",
        "Live provider OCR and image explanation",
        "unknown",
        "Skipped; rerun with --run-live-ocr.",
        ["live_ocr_not_run"]
      )
    };
  }
  const result = await runCommand("swift", ["run", "-c", "release", "LLMToolsLiveOCRCheck"], { timeout: 180_000 });
  return {
    command: result,
    requirement: requirement(
      "live-ocr",
      "Live provider OCR and image explanation",
      result.ok ? "pass" : "fail",
      oneLine(result.stdout || result.stderr || result.message, 420),
      result.ok ? [] : ["live_ocr_failed"]
    )
  };
}

function formatText(audit) {
  const lines = [];
  lines.push(`Phase 3 goal audit: ${audit.complete ? "complete" : "incomplete"}`);
  lines.push(`Generated: ${audit.generatedAt}`);
  lines.push("");
  for (const item of audit.requirements) {
    lines.push(`- ${item.status.toUpperCase()} ${item.id}: ${item.title}`);
    if (item.evidence) lines.push(`  evidence: ${item.evidence}`);
    if (item.blockers.length) lines.push(`  blockers: ${item.blockers.join(", ")}`);
  }
  if (audit.nextSteps.length) {
    lines.push("");
    lines.push("Next steps:");
    for (const step of audit.nextSteps) {
      lines.push(`- ${step}`);
    }
  }
  return lines.join("\n");
}

function buildNextSteps(audit) {
  const steps = [];
  const phase2 = audit.phase2?.status;
  const chrome = phase2?.browsers?.find((browser) => browser.id === "chrome");
  if (chrome && !chrome.ready) {
    steps.push(`Load or reload the unpacked Chrome extension from ${path.join(repoRoot, "browser-extension", "chromium")}.`);
    steps.push("Verify with: node scripts/check-browser-extension-install.mjs --browser chrome --require-ready");
  }
  if (phase2?.manual?.pendingKeys?.length) {
    steps.push(`Record pending manual acceptance keys: ${phase2.manual.pendingKeys.join(", ")}.`);
  }
  if (audit.requirements.some((item) => item.status === "unknown")) {
    steps.push("Rerun with --run-checks --run-live-ocr for the strongest local Phase 3 evidence.");
  }
  return steps;
}

async function main() {
  const options = parseArgs(process.argv.slice(2));
  if (options.help) {
    usage();
    return;
  }

  const phase2 = await auditPhase2();
  const packagedApp = await auditPackagedApp();
  const ocrConfiguration = await auditRegistryOCR();
  const checks = await auditChecks(options);
  const liveOCR = await auditLiveOCR(options);
  const requirements = [
    phase2.requirement,
    packagedApp.requirement,
    ocrConfiguration.requirement,
    checks.requirement,
    liveOCR.requirement
  ];
  const complete = requirements.every(isPassed);
  const audit = {
    complete,
    generatedAt: new Date().toISOString().replace(/\.\d{3}Z$/, "Z"),
    requirements,
    phase2,
    packagedApp,
    ocrConfiguration,
    checks,
    liveOCR
  };
  audit.nextSteps = buildNextSteps(audit);

  if (options.json) {
    console.log(JSON.stringify(audit, null, 2));
  } else {
    console.log(formatText(audit));
  }

  if (options.assertComplete && !audit.complete) {
    process.exitCode = 1;
  }
}

main().catch((error) => {
  console.error(error.message || String(error));
  process.exit(1);
});
