#!/usr/bin/env bash
set -euo pipefail

repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$repo_root"

browser_target="${LLMTOOLS_E2E_BROWSER:-all}"
app_bundle="$repo_root/dist/llmTools.app"
app_binary="$app_bundle/Contents/MacOS/llmTools"
started_at="$(date -u +"%Y-%m-%dT%H:%M:%SZ")"
report_stamp="$(date -u +"%Y%m%dT%H%M%SZ")"
latest_report_path="$repo_root/dist/phase2-closure-report.md"
if [[ -n "${LLMTOOLS_CLOSURE_REPORT:-}" ]]; then
  report_path="$LLMTOOLS_CLOSURE_REPORT"
else
  report_path="$repo_root/dist/phase2-closure-reports/phase2-closure-${report_stamp}.md"
fi
git_head="$(git rev-parse --short HEAD 2>/dev/null || printf 'unknown')"
git_branch="$(git branch --show-current 2>/dev/null || printf 'unknown')"
git_status="$(git status --short 2>/dev/null || true)"
node_version="$(node --version 2>/dev/null || printf 'unknown')"
swift_version="$(swift --version 2>/dev/null | head -n 1 || printf 'unknown')"
chrome_path="${CHROME_PATH:-/Applications/Google Chrome.app/Contents/MacOS/Google Chrome}"
edge_path="${EDGE_PATH:-/Applications/Microsoft Edge.app/Contents/MacOS/Microsoft Edge}"

mkdir -p "$(dirname "$report_path")"
mkdir -p "$(dirname "$latest_report_path")"
: > "$report_path"

sync_latest_report() {
  if [[ "$report_path" != "$latest_report_path" ]]; then
    cp "$report_path" "$latest_report_path"
  fi
}

{
  printf '# Phase 2 Closure Report\n\n'
  printf -- '- Started: %s\n' "$started_at"
  printf -- '- Repo: `%s`\n' "$repo_root"
  printf -- '- Git branch: `%s`\n' "$git_branch"
  printf -- '- Git HEAD: `%s`\n' "$git_head"
  printf -- '- Browser target: `%s`\n' "$browser_target"
  printf -- '- App bundle: `%s`\n' "$app_bundle"
  printf -- '- Report: `%s`\n' "$report_path"
  printf -- '- Latest report: `%s`\n' "$latest_report_path"
  printf -- '- Node: `%s`\n' "$node_version"
  printf -- '- Swift: `%s`\n' "$swift_version"
  printf -- '- Chrome path: `%s`\n' "$chrome_path"
  printf -- '- Edge path: `%s`\n\n' "$edge_path"
  printf '## Worktree Snapshot\n\n'
  if [[ -n "$git_status" ]]; then
    printf '```text\n%s\n```\n' "$git_status"
  else
    printf '```text\nclean\n```\n'
  fi
} >> "$report_path"
sync_latest_report

run_step() {
  local label="$1"
  shift
  {
    printf '\n## %s\n\n' "$label"
    printf 'Command: `'
    printf '%q ' "$@"
    printf '`\n\n'
  } | tee -a "$report_path"
  if "$@" 2>&1 | tee -a "$report_path"; then
    printf '\nStatus: PASS\n' | tee -a "$report_path"
    sync_latest_report
  else
    local status=$?
    printf '\nStatus: FAIL (%s)\n' "$status" | tee -a "$report_path"
    sync_latest_report
    printf '\nPhase 2 closure checks failed. Report: %s\n' "$report_path" >&2
    exit "$status"
  fi
}

run_step "Node syntax: background.js" node --check browser-extension/chromium/background.js
run_step "Node syntax: contentScript.js" node --check browser-extension/chromium/contentScript.js
run_step "Node syntax: check-browser-extension-dom.mjs" node --check scripts/check-browser-extension-dom.mjs
run_step "Node syntax: check-browser-extension-install.mjs" node --check scripts/check-browser-extension-install.mjs
run_step "Node syntax: check-phase2-acceptance-status.mjs" node --check scripts/check-phase2-acceptance-status.mjs
run_step "Node syntax: record-phase2-manual-check.mjs" node --check scripts/record-phase2-manual-check.mjs
run_step "Whitespace diff check" git diff --check
run_step "Swift native regression checks" swift run LLMToolsChecks
run_step "Swift app build" swift build --product llmTools
run_step "Browser extension DOM and Chrome fixture checks" node scripts/check-browser-extension-dom.mjs
run_step "Browser extension fixture matrix: ${browser_target}" env "LLMTOOLS_E2E_BROWSER=${browser_target}" node scripts/check-browser-extension-dom.mjs
run_step "Package dist app" ./scripts/package-app.sh
run_step "Browser extension install readiness snapshot" node scripts/check-browser-extension-install.mjs --browser all

{
  printf '\n## Restart packaged app\n\n'
  printf 'App binary: `%s`\n\n' "$app_binary"
} | tee -a "$report_path"
sync_latest_report
existing_pids="$(pgrep -f "$app_binary" || true)"
if [[ -n "$existing_pids" ]]; then
  printf 'Stopping existing PID(s): %s\n' "$existing_pids" | tee -a "$report_path"
  # shellcheck disable=SC2086
  kill $existing_pids
  sleep 1
fi
open "$app_bundle"
sleep 2

running_pids="$(pgrep -f "$app_binary" || true)"
if [[ -z "$running_pids" ]]; then
  printf 'Packaged app did not start from %s\n' "$app_binary" | tee -a "$report_path" >&2
  exit 1
fi

{
  printf 'Packaged app running from `%s`\n' "$app_binary"
  printf 'PID(s): `%s`\n' "$running_pids"
  printf '\nStatus: PASS\n'
  printf '\n## Manual Acceptance Checklist\n\n'
  printf 'Automated closure checks are complete. Before declaring Phase 2 fully accepted, record these manual checks against the packaged app and browser extension:\n\n'
  printf -- '- [ ] Reload the unpacked Chromium extension in `chrome://extensions` if extension files changed, then verify with `node scripts/check-browser-extension-install.mjs --browser chrome --require-ready`. <!-- phase2-manual:reload-extension -->\n'
  printf -- '- [ ] Confirm Settings -> `网页翻译` shows the Chrome development channel, extension ID, native host path, manifest path, and latest status clearly. <!-- phase2-manual:settings-status -->\n'
  printf -- '- [ ] Translate a representative English article page from the Chrome development extension. <!-- phase2-manual:translate-article -->\n'
  printf -- '- [ ] Restore the translated article page to the original text without reload. <!-- phase2-manual:restore-article -->\n'
  printf -- '- [ ] Start a translation, cancel it, and confirm no late translations overwrite the cancelled state. <!-- phase2-manual:cancel-late -->\n'
  printf -- '- [ ] Switch replace, bilingual, and original reading modes, then switch Loading, flip-text, and no-style pending translation styles before starting a new translation. <!-- phase2-manual:reading-modes -->\n'
  printf -- '- [ ] Change natural, literal, and technical quality modes and run current-page retranslate. <!-- phase2-manual:quality-retranslate -->\n'
  printf -- '- [ ] Clear current-page, current-site, and all webpage translation cache from the popup. <!-- phase2-manual:cache-clear -->\n'
  printf -- '- [ ] Set a site to auto-translate and confirm browser permission gating is clear. <!-- phase2-manual:auto-permission -->\n'
  printf -- '- [ ] Set a site to never translate and confirm automatic/context-menu translation is blocked while manual popup translation remains explicit. <!-- phase2-manual:never-translate -->\n'
  printf -- '- [ ] Restart `dist/llmTools.app` and the browser, then confirm webpage translation reconnects. <!-- phase2-manual:restart-reconnect -->\n'
  printf -- '- [ ] Run the same acceptance in Microsoft Edge when Edge is available, or record Edge as unavailable in this environment. <!-- phase2-manual:edge-acceptance -->\n'
  printf '\n## Result\n\n'
  printf 'Phase 2 closure checks completed.\n\n'
  printf -- '- Started: `%s`\n' "$started_at"
  printf -- '- Completed: `%s`\n' "$(date -u +"%Y-%m-%dT%H:%M:%SZ")"
  printf -- '- Git branch: `%s`\n' "$git_branch"
  printf -- '- Git HEAD: `%s`\n' "$git_head"
  printf -- '- Browser target: `%s`\n' "$browser_target"
  printf -- '- Running PID(s): `%s`\n\n' "$running_pids"
  printf 'Report: `%s`\n' "$report_path"
  printf 'Latest report: `%s`\n\n' "$latest_report_path"
  printf 'If browser extension files changed, reload the unpacked extension in chrome://extensions.\n'
} | tee -a "$report_path"
sync_latest_report

node scripts/check-phase2-acceptance-status.mjs --report "$report_path" --update-report
sync_latest_report

if [[ ! -x "$edge_path" ]]; then
  node scripts/record-phase2-manual-check.mjs \
    --report "$report_path" \
    --skip edge-acceptance \
    "Microsoft Edge is not installed at ${edge_path} in this environment; closure report recorded edge issue codes browser_app_missing and native_manifest_missing."
  sync_latest_report
fi
