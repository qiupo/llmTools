#!/usr/bin/env node

import { createHash, createPublicKey } from "node:crypto";
import { promises as fs } from "node:fs";
import os from "node:os";
import path from "node:path";
import { fileURLToPath } from "node:url";

const repoRoot = path.resolve(path.dirname(fileURLToPath(import.meta.url)), "..");
const extensionRoot = path.join(repoRoot, "browser-extension", "chromium");
const extensionManifestPath = path.join(extensionRoot, "manifest.json");
const nativeHostName = "com.llmtools.native_host";
const packagedNativeHostPath = path.join(repoRoot, "dist", "llmTools.app", "Contents", "MacOS", "LLMToolsNativeHost");

function usage() {
  console.log(`Usage:
  node scripts/check-browser-extension-install.mjs [--browser chrome|edge|all] [--require-loaded] [--require-native] [--require-ready] [--json]

Checks whether the development Chromium extension is loaded from this repo in local browser profiles and whether the native messaging manifest points at the packaged app host.

Default browser: chrome
`);
}

function parseArgs(argv) {
  const args = [...argv];
  const options = {
    browser: "chrome",
    requireLoaded: false,
    requireNative: false,
    json: false
  };
  while (args.length) {
    const arg = args.shift();
    if (arg === "--help" || arg === "-h") {
      return { help: true };
    }
    if (arg === "--browser") {
      const value = args.shift();
      if (!["chrome", "edge", "all"].includes(value)) {
        throw new Error("--browser must be chrome, edge, or all");
      }
      options.browser = value;
      continue;
    }
    if (arg === "--require-loaded") {
      options.requireLoaded = true;
      continue;
    }
    if (arg === "--require-native") {
      options.requireNative = true;
      continue;
    }
    if (arg === "--require-ready") {
      options.requireLoaded = true;
      options.requireNative = true;
      continue;
    }
    if (arg === "--json") {
      options.json = true;
      continue;
    }
    throw new Error(`Unsupported argument: ${arg}`);
  }
  return options;
}

function expandHome(filePath) {
  if (filePath === "~") return os.homedir();
  if (filePath.startsWith("~/")) return path.join(os.homedir(), filePath.slice(2));
  return filePath;
}

async function readJSON(filePath) {
  return JSON.parse(await fs.readFile(filePath, "utf8"));
}

async function pathExists(filePath) {
  try {
    await fs.access(filePath);
    return true;
  } catch {
    return false;
  }
}

async function realPathOrNull(filePath) {
  try {
    return await fs.realpath(filePath);
  } catch {
    return null;
  }
}

function deriveChromeExtensionID(publicKeyBase64) {
  if (!publicKeyBase64) {
    throw new Error("browser-extension/chromium/manifest.json is missing manifest.key");
  }
  const der = createPublicKey({
    key: Buffer.from(publicKeyBase64, "base64"),
    format: "der",
    type: "spki"
  }).export({
    format: "der",
    type: "spki"
  });
  const hash = createHash("sha256").update(der).digest();
  return [...hash.subarray(0, 16)]
    .map((byte) => String.fromCharCode(97 + (byte >> 4)) + String.fromCharCode(97 + (byte & 15)))
    .join("");
}

function browserConfigs(extensionID) {
  const expectedOrigin = `chrome-extension://${extensionID}/`;
  return {
    chrome: {
      id: "chrome",
      name: "Google Chrome",
      appPath: "/Applications/Google Chrome.app",
      userDataDir: "~/Library/Application Support/Google/Chrome",
      nativeManifestPath: `~/Library/Application Support/Google/Chrome/NativeMessagingHosts/${nativeHostName}.json`,
      expectedOrigin
    },
    edge: {
      id: "edge",
      name: "Microsoft Edge",
      appPath: "/Applications/Microsoft Edge.app",
      userDataDir: "~/Library/Application Support/Microsoft Edge",
      nativeManifestPath: `~/Library/Application Support/Microsoft Edge/NativeMessagingHosts/${nativeHostName}.json`,
      expectedOrigin
    }
  };
}

function addIssue(issues, code, message) {
  issues.push({ code, message });
}

async function profilePreferencePaths(userDataDir) {
  const root = expandHome(userDataDir);
  const paths = [];
  const rootPreferences = path.join(root, "Preferences");
  if (await pathExists(rootPreferences)) {
    paths.push({ profile: ".", path: rootPreferences });
  }
  let entries = [];
  try {
    entries = await fs.readdir(root, { withFileTypes: true });
  } catch {
    return paths;
  }
  for (const entry of entries) {
    if (!entry.isDirectory()) continue;
    const prefPath = path.join(root, entry.name, "Preferences");
    if (await pathExists(prefPath)) {
      paths.push({ profile: entry.name, path: prefPath });
    }
  }
  return paths;
}

async function inspectProfilePreference(profileInfo, extensionID, expectedExtensionRoot) {
  const prefs = await readJSON(profileInfo.path);
  const setting = prefs.extensions?.settings?.[extensionID];
  if (!setting) {
    return {
      profile: profileInfo.profile,
      preferencesPath: profileInfo.path,
      installed: false,
      enabled: false,
      pathMatches: false
    };
  }
  const configuredPath = setting.path ? path.resolve(setting.path) : null;
  const configuredRealPath = configuredPath ? await realPathOrNull(configuredPath) : null;
  const expectedRealPath = await realPathOrNull(expectedExtensionRoot);
  return {
    profile: profileInfo.profile,
    preferencesPath: profileInfo.path,
    installed: true,
    enabled: setting.state === 1,
    state: setting.state ?? null,
    location: setting.location ?? null,
    configuredPath,
    configuredRealPath,
    expectedPath: expectedExtensionRoot,
    expectedRealPath,
    pathMatches: Boolean(configuredRealPath && expectedRealPath && configuredRealPath === expectedRealPath),
    manifestName: setting.manifest?.name ?? null,
    manifestVersion: setting.manifest?.version ?? null
  };
}

async function inspectNativeManifest(config) {
  const manifestPath = expandHome(config.nativeManifestPath);
  if (!(await pathExists(manifestPath))) {
    return {
      present: false,
      path: manifestPath,
      executableExists: false,
      allowedOriginPresent: false,
      pointsAtPackagedHost: false
    };
  }
  const manifest = await readJSON(manifestPath);
  const manifestHostPath = manifest.path ? path.resolve(manifest.path) : null;
  const manifestHostRealPath = manifestHostPath ? await realPathOrNull(manifestHostPath) : null;
  const expectedHostRealPath = await realPathOrNull(packagedNativeHostPath);
  return {
    present: true,
    path: manifestPath,
    name: manifest.name ?? null,
    hostPath: manifestHostPath,
    hostRealPath: manifestHostRealPath,
    expectedHostPath: packagedNativeHostPath,
    expectedHostRealPath,
    executableExists: Boolean(manifestHostPath && await pathExists(manifestHostPath)),
    allowedOrigins: Array.isArray(manifest.allowed_origins) ? manifest.allowed_origins : [],
    allowedOriginPresent: Array.isArray(manifest.allowed_origins) && manifest.allowed_origins.includes(config.expectedOrigin),
    pointsAtPackagedHost: Boolean(manifestHostRealPath && expectedHostRealPath && manifestHostRealPath === expectedHostRealPath)
  };
}

async function inspectBrowser(config, extensionID) {
  const preferencePaths = await profilePreferencePaths(config.userDataDir);
  const profiles = [];
  for (const profileInfo of preferencePaths) {
    profiles.push(await inspectProfilePreference(profileInfo, extensionID, extensionRoot));
  }
  const nativeManifest = await inspectNativeManifest(config);
  const loadedProfiles = profiles.filter((profile) => profile.installed && profile.enabled && profile.pathMatches);
  const appInstalled = await pathExists(config.appPath);
  const extensionLoaded = loadedProfiles.length > 0;
  const nativeManifestReady = nativeManifest.present && nativeManifest.executableExists && nativeManifest.allowedOriginPresent && nativeManifest.pointsAtPackagedHost;
  const issues = [];
  if (!appInstalled) {
    addIssue(issues, "browser_app_missing", `Browser app is missing at ${config.appPath}`);
  }
  if (!profiles.length) {
    addIssue(issues, "browser_profiles_missing", `No browser profiles were found under ${expandHome(config.userDataDir)}`);
  }
  if (!extensionLoaded) {
    addIssue(issues, "extension_not_loaded_from_repo", `Extension ${extensionID} is not enabled from ${extensionRoot} in any detected profile`);
  }
  if (!nativeManifest.present) {
    addIssue(issues, "native_manifest_missing", `Native messaging manifest is missing at ${nativeManifest.path}`);
  } else {
    if (!nativeManifest.executableExists) {
      addIssue(issues, "native_host_executable_missing", `Native host executable is missing at ${nativeManifest.hostPath || packagedNativeHostPath}`);
    }
    if (!nativeManifest.allowedOriginPresent) {
      addIssue(issues, "native_manifest_allowed_origin_missing", `Native manifest is missing allowed origin ${config.expectedOrigin}`);
    }
    if (!nativeManifest.pointsAtPackagedHost) {
      addIssue(issues, "native_manifest_wrong_host_path", `Native manifest does not point at packaged host ${packagedNativeHostPath}`);
    }
  }
  return {
    id: config.id,
    name: config.name,
    appPath: config.appPath,
    appInstalled,
    userDataDir: expandHome(config.userDataDir),
    extensionID,
    extensionRoot,
    ready: appInstalled && extensionLoaded && nativeManifestReady,
    issueCodes: issues.map((issue) => issue.code),
    issues,
    extensionLoaded,
    loadedProfiles: loadedProfiles.map((profile) => profile.profile),
    nativeManifestReady,
    profiles,
    nativeManifest
  };
}

function printTextReport(results) {
  for (const result of results) {
    console.log(`${result.name}`);
    console.log(`  app: ${result.appInstalled ? "present" : "missing"} (${result.appPath})`);
    console.log(`  extension id: ${result.extensionID}`);
    console.log(`  extension root: ${result.extensionRoot}`);
    console.log(`  ready: ${result.ready ? "yes" : "no"}`);
    console.log(`  extension loaded from repo: ${result.extensionLoaded ? `yes (${result.loadedProfiles.join(", ")})` : "no"}`);
    console.log(`  native manifest ready: ${result.nativeManifestReady ? "yes" : "no"}`);
    console.log(`  native manifest: ${result.nativeManifest.path}`);
    if (result.issues.length) {
      console.log("  issues:");
      for (const issue of result.issues) {
        console.log(`    - ${issue.code}: ${issue.message}`);
      }
    }
    if (!result.profiles.length) {
      console.log("  profiles: none found");
    } else {
      console.log("  profiles:");
      for (const profile of result.profiles) {
        const state = profile.installed
          ? `${profile.enabled ? "enabled" : "not enabled"}, ${profile.pathMatches ? "path ok" : "path mismatch"}`
          : "not installed";
        console.log(`    - ${profile.profile}: ${state}`);
        if (profile.installed && profile.configuredPath) {
          console.log(`      path: ${profile.configuredPath}`);
        }
      }
    }
    console.log("");
  }
}

async function main() {
  const options = parseArgs(process.argv.slice(2));
  if (options.help) {
    usage();
    return;
  }
  const extensionManifest = await readJSON(extensionManifestPath);
  const extensionID = deriveChromeExtensionID(extensionManifest.key);
  const configs = browserConfigs(extensionID);
  const selectedConfigs = options.browser === "all"
    ? [configs.chrome, configs.edge]
    : [configs[options.browser]];
  const results = [];
  for (const config of selectedConfigs) {
    results.push(await inspectBrowser(config, extensionID));
  }

  if (options.json) {
    console.log(JSON.stringify({ results }, null, 2));
  } else {
    printTextReport(results);
  }

  const loadedFailures = results.filter((result) => !result.extensionLoaded);
  const nativeFailures = results.filter((result) => !result.nativeManifestReady);
  if (options.requireLoaded && loadedFailures.length) {
    console.error(`Extension is not loaded from this repo in: ${loadedFailures.map((result) => result.name).join(", ")}`);
    process.exitCode = 1;
  }
  if (options.requireNative && nativeFailures.length) {
    console.error(`Native messaging manifest is not ready in: ${nativeFailures.map((result) => result.name).join(", ")}`);
    process.exitCode = 1;
  }
}

main().catch((error) => {
  console.error(error.message || String(error));
  process.exit(1);
});
