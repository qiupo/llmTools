import { readFile } from "node:fs/promises";

const [appState, appDelegate, views, ttsAppState] = await Promise.all([
  readFile("Sources/LLMToolsApp/AppState.swift", "utf8"),
  readFile("Sources/LLMToolsApp/AppDelegate.swift", "utf8"),
  readFile("Sources/LLMToolsApp/Views.swift", "utf8"),
  readFile("Sources/LLMToolsApp/TTSAppState.swift", "utf8")
]);

function expect(value, message) {
  if (!value) {
    throw new Error(message);
  }
}

function functionSource(source, signature) {
  const start = source.indexOf(signature);
  expect(start >= 0, `Missing function: ${signature}`);
  const remainder = source.slice(start + signature.length);
  const nextFunction = remainder.search(/\n    (?:private )?func /);
  return nextFunction < 0
    ? source.slice(start)
    : source.slice(start, start + signature.length + nextFunction);
}

const inputSetter = functionSource(appState, "func setInputText(");
expect(inputSetter.includes("preserveOutput: Bool = false"), "Text input must distinguish editing from a new session");
expect(inputSetter.includes("if !preserveOutput"), "Editing must be able to preserve the current result");
expect(
  inputSetter.indexOf("beginQuickActionInputChange()") > inputSetter.indexOf("if !preserveOutput"),
  "Draft editing must not cancel the request that is already running"
);

for (const signature of [
  "func runCurrentTask(",
  "func runCurrentOCR()",
  "func runCurrentMediaSubtitles()",
  "func translateCurrentMediaSubtitles()"
]) {
  expect(
    functionSource(appState, signature).includes("clearCurrentQuickActionOutput()"),
    `${signature} must replace the old result only when execution starts`
  );
}

for (const signature of ["func loadMediaSubtitleFile(", "func clearOCRImage()", "func clearMediaSubtitleFile()", "private func setOCRImage("]) {
  expect(
    !functionSource(appState, signature).includes('outputText = ""'),
    `${signature} must preserve the current result while input changes`
  );
}

for (const signature of ["func updateQuickTTSInputText(", "func updateQuickTTSDeliveryStyle(", "func selectQuickTTSVoice("]) {
  expect(
    !functionSource(ttsAppState, signature).includes("invalidateQuickTTSOutput()"),
    `${signature} must preserve generated audio until the next generation`
  );
}

const reset = functionSource(appState, "func resetQuickActionSession()");
for (const required of [
  "inputText = \"\"",
  "ocrImageInput = nil",
  "mediaSubtitleFileURL = nil",
  "textOutputState = QuickActionOutputState()",
  "resetQuickActionSpeechSession()",
  "quickActionSessionRevision += 1"
]) {
  expect(reset.includes(required), `Session reset is missing: ${required}`);
}

expect(appDelegate.includes("quickActionWindow.onClose"), "Quick Action close callback is missing");
expect(appDelegate.includes("appState.resetQuickActionSession()"), "Window close must reset the Quick Action session");
expect(views.includes("preserveOutput: true"), "Quick Action editors must preserve results while editing");
expect(
  !views.includes("onSubmit: {\n                    guard !appState.isRunning"),
  "Submitting an edited draft with Return must be able to restart the current request"
);
expect(
  views.includes('Label(L10n.text("Regenerate", language: language), systemImage: "arrow.clockwise")'),
  "Text tasks must offer an explicit regenerate command while running"
);
expect(views.includes("onChange(of: appState.quickActionSessionRevision)"), "View-local drafts must reset after close");

// 这是 UI 状态契约检查；Swift 编译仍负责验证类型和并发隔离。
console.log("Quick Action session state checks passed");
