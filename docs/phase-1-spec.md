# Phase 1 Spec - Completed

Last updated: 2026-07-03

Status: completed and accepted as the Phase 1 baseline.

This document now serves two purposes:

- record the Phase 1 product contract that was implemented
- define the regression surface that later phases must not break

## 1. Objective

Phase 1 delivered the first usable native macOS version of llmTools.

The app lets a user:

- register existing local Qwen models
- select or paste text
- run translation, polishing, summarization, explanation, or TODO extraction
- copy the result
- use a small floating desktop widget

The most important Phase 1 loop remains:

1. select text in any macOS app
2. press a global shortcut
3. choose a task
4. run the task with a local model
5. copy the generated result

## 2. Phase 1 Scope

Phase 1 scope is closed. New work should not be added here unless it is a regression fix or documentation correction.

### In Scope

- native macOS app
- menu-bar app lifecycle
- global shortcut
- selected-text capture where macOS permissions allow it
- manual text input fallback
- quick action panel
- floating desktop widget MVP
- model registry
- multiple model entries
- one active model per task
- GGUF model detection and inference support
- MLX-4bit model-folder detection and inference support
- local prompt templates
- result copy
- optional original-text replacement setting, disabled by default
- recent history capped at 20 entries, with one-click clear

### Out of Scope

- cloud model APIs
- automatic model download
- full chat product
- multi-document knowledge base
- vector indexing
- complex agent workflows
- OCR
- DOCX support
- deep PDF support
- model marketplace
- multi-model parallel inference
- always-loaded multiple models

## 3. Target Platform

The app is a native macOS application.

Minimum target:

- macOS 14 or newer
- development and verification on the current newer macOS environment

Early distribution strategy:

- build and test as a local `.app` during Phase 1
- use real app packaging to validate Accessibility permission, global shortcuts, launch behavior, and floating-window behavior
- defer notarization and external distribution until the app is ready for use outside the development machine

Recommended implementation:

- SwiftUI for settings and standard app surfaces
- AppKit where needed for menu-bar behavior, floating panel behavior, global shortcuts, window levels, and accessibility integration
- an isolated local model runner layer for inference backends

The UI must remain responsive while a model is loading or generating.

## 4. Initial Model Reality

The user's current model folder contains LM Studio-style downloaded models. The important formats for Phase 1 are:

- GGUF models, such as Qwen 0.8B GGUF
- MLX-4bit model folders, such as Qwen 4B MLX-4bit and Qwen 9B MLX-4bit

The app should not depend on LM Studio being open. LM Studio is only relevant because the user has already downloaded models into local folders.

Phase 1 is not considered complete unless both GGUF and MLX models can run real inference through the app.

## 5. Model Registry

The app provides a model settings page where the user can add models by selecting either:

- a `.gguf` file
- a folder that contains one or more `.gguf` files
- an MLX model folder

Each registered model has:

- id
- display name
- local path
- detected format
- size class
- default role
- context length
- enabled state
- last validation status
- last error message

Example config:

```json
{
  "models": [
    {
      "id": "qwen-0_8b-gguf",
      "name": "Qwen 0.8B GGUF",
      "path": "/Users/po/.lmstudio/models/lmstudio-community/Qwen3.5-0.8B-GGUF",
      "format": "gguf",
      "sizeClass": "0.8b",
      "role": "fast",
      "contextLength": 4096,
      "enabled": true
    },
    {
      "id": "qwen-4b-mlx",
      "name": "Qwen 4B MLX 4bit",
      "path": "/Users/po/.lmstudio/models/lmstudio-community/Qwen3.5-4B-MLX-4bit",
      "format": "mlx",
      "sizeClass": "4b",
      "role": "default",
      "contextLength": 8192,
      "enabled": true
    },
    {
      "id": "qwen-9b-mlx",
      "name": "Qwen 9B MLX 4bit",
      "path": "/Users/po/.lmstudio/models/lmstudio-community/Qwen3.5-9B-MLX-4bit",
      "format": "mlx",
      "sizeClass": "9b",
      "role": "quality",
      "contextLength": 8192,
      "enabled": true
    }
  ]
}
```

## 6. Model Detection

When the user selects a path, the app attempts to detect the model format.

Detection rules:

- If the path is a `.gguf` file, treat it as a GGUF model.
- If the path is a folder containing exactly one `.gguf` file, use that file.
- If the path is a folder containing multiple `.gguf` files, ask the user to choose one.
- If the path is a folder containing MLX-style files, treat it as an MLX model folder.
- If the app cannot detect the format, show a clear unsupported-model message.

MLX-style detection should look for files commonly present in MLX model folders, such as:

- `config.json`
- tokenizer files
- safetensors weight files
- MLX-specific metadata, if present

Detection should be conservative. Wrongly loading a model as the wrong backend is worse than asking the user to clarify.

## 7. Model Runtime Architecture

The native app owns:

- model registry
- UI state
- task selection
- prompt template selection
- runner lifecycle
- progress and error display

Inference should run outside the main UI thread.

Recommended Phase 1 architecture:

```text
Native macOS App
  MenuBarController
  QuickActionPanel
  FloatingWidget
  Settings
  ModelRegistry
  TaskEngine
  RuntimeManager

Local Runners
  GGUFRunner
  MLXRunner
```

The runner layer should be isolated enough that:

- a model crash does not terminate the app
- a model can be unloaded to free memory
- GGUF and MLX support can evolve independently
- future backends can be added without rewriting the UI

Both `GGUFRunner` and `MLXRunner` are required for Phase 1. They may be implemented with different underlying technologies, but both must share the same app-facing task contract.

## 8. Runtime Strategy

Phase 1 supports multiple configured models but only one active model per task.

Recommended default roles:

- Qwen 0.8B: fast
- Qwen 4B: default
- Qwen 9B: quality

These roles are confirmed Phase 1 defaults.

Task defaults:

- short translation: default model, with optional fast mode
- polishing: default model
- summarization: default or quality, depending on text length
- explanation: default model
- TODO extraction: default model

The app should not preload all models on launch.

Recommended loading behavior:

1. App launch reads model registry only.
2. First task loads the selected/default model.
3. The active model remains warm while the app is running.
4. Switching models unloads or detaches the previous model if needed.
5. Settings page can provide a manual "load model" action.

## 9. Model Status

Model status values:

- `not_configured`
- `configured`
- `validating`
- `ready_to_load`
- `loading`
- `ready`
- `running`
- `unloading`
- `failed`

User-facing status labels should be plain:

- No model configured
- Model configured
- Checking model
- Ready to load
- Loading
- Ready
- Running
- Unloading
- Failed

## 10. Menu-Bar App

The app runs as a menu-bar utility.

Menu items:

- Open Quick Action
- Open Floating Widget
- Models
- Settings
- Quit

The menu-bar UI should expose current model status:

- no model configured
- selected model name
- loading state
- ready state
- failure state

## 11. Global Shortcut

Default shortcuts:

- `Option + Space`: open quick action panel with selected text
- `Option + Shift + Space`: open quick action panel with empty input

Shortcut behavior:

1. Try to read selected text.
2. If selected text is available, open the quick action panel with that text.
3. If selected text is unavailable, open the panel with an empty input area and a message explaining that the user can paste text.

Selected-text capture may require macOS Accessibility permission.

The app should guide the user to grant permission only when needed.

## 12. Quick Action Panel

The quick action panel is optimized for processing text quickly.

Required UI:

- source text area
- task selector
- model indicator
- run button
- result area
- copy button
- regenerate button
- error message area

Task selector:

- Translate
- Polish
- Summarize
- Explain
- Extract TODOs

Optional controls:

- target language for translation
- tone for polishing
- quality mode
- model override

The panel should open quickly. It should not block on model loading before showing the input.

## 13. Tasks

### Translate

Purpose:

- translate selected or pasted text

Default behavior:

- Chinese input translates to English
- non-Chinese input translates to Chinese

This auto-detection behavior is the confirmed Phase 1 default.

Options:

- auto
- Chinese
- English
- Japanese
- Korean

### Polish

Purpose:

- rewrite text to be clearer, more natural, or more professional

Style options:

- natural
- formal
- concise
- conversational
- technical

### Summarize

Purpose:

- turn longer text into a compact summary

Default output:

- short summary
- key points

Optional output:

- action items

### Explain

Purpose:

- explain terms, sentences, code snippets, errors, or dense paragraphs

Default output:

- simple explanation
- context
- likely meaning

### Extract TODOs

Purpose:

- extract actionable items from notes, chats, or meeting text

Default output fields:

- task
- owner, if detected
- due date, if detected
- priority, if detected

The output format should be stable enough to copy into notes or task tools.

## 14. Floating Widget MVP

The floating widget is required in Phase 1, but file workflows remain minimal.

Default state:

- compact desktop widget
- draggable
- visible above normal windows
- visible on all Spaces/desktops by default
- can dock to screen edge
- auto-collapses when docked

Expanded state:

- text input
- task selector
- run button
- result preview
- copy button

Phase 1 drag support:

- plain text snippets
- `.txt`
- `.md`

Phase 1 should not attempt complex PDF or DOCX parsing.

Docking behavior:

- When dragged near the left or right screen edge, the widget snaps to the edge.
- After a short delay, it collapses to a narrow tab.
- Hover or click expands it.
- The user can disable auto-collapse in settings.
- The user can disable all-Spaces visibility in settings if it becomes distracting.

## 15. Copy and Replacement

Required:

- copy result to clipboard

Optional:

- replace original selected text

Default:

- original-text replacement is disabled

Replacement is controlled by a setting because it may require Accessibility permission and may behave differently across apps.

## 16. Settings

Phase 1 settings:

- model registry
- default model
- default fast/default/quality roles
- shortcut customization
- default translation target
- default polish style
- floating widget visibility
- floating widget auto-collapse
- launch at login
- result history retention
- clear recent history
- original-text replacement setting

## 17. Local Storage

The app stores:

- model registry
- user preferences
- shortcut settings
- recent history, capped at 20 entries
- last model validation errors

Privacy defaults:

- no cloud upload
- no automatic external API calls
- history is local only
- history retention is limited to the latest 20 entries
- history can be cleared with one action

## 18. Error Handling

Important errors:

- model path missing
- unsupported model format
- multiple GGUF files found and no selected file
- MLX folder missing required files
- model load failed
- runner crashed
- out of memory
- selected text unavailable
- Accessibility permission missing
- task timed out

Errors should explain what the user can do next.

Examples:

- "The model file no longer exists. Choose a new path."
- "This folder contains multiple GGUF files. Pick the file to use."
- "Selected text could not be read. Paste text manually or enable Accessibility permission."

## 19. Acceptance Criteria

Phase 1 is complete and accepted because the product surface covers:

- The app launches as a native macOS menu-bar utility.
- The user can register multiple local model paths.
- The user can register Qwen 0.8B, Qwen 4B, and Qwen 9B entries.
- The app can identify GGUF and MLX model entries.
- The app can load and run a GGUF model.
- The app can load and run an MLX model.
- The app can execute the same task contract through both GGUF and MLX runners.
- The user can open a quick action panel with a global shortcut.
- The user can paste or capture text.
- The user can run translate, polish, summarize, explain, and extract TODO tasks.
- The user can copy the result.
- The app keeps the latest 20 local results.
- The user can clear all recent results with one action.
- The floating widget can be shown, dragged, docked to the edge, collapsed, expanded, and used for pasted text.
- The floating widget appears on all Spaces/desktops by default.
- The app can be packaged and launched as a local `.app` for real macOS permission and window-behavior testing.
- Failures produce visible, understandable messages.

## 20. Completion Record

Accepted date: 2026-07-03.

Completed capability groups:

- Native macOS menu-bar app lifecycle.
- Global shortcut and quick action flow for selected or pasted text.
- Manual input fallback when selected-text capture is unavailable.
- Model registry with local GGUF and MLX model support.
- Shared task engine for translation, polishing, summarization, explanation, and TODO extraction.
- Real local runner support for GGUF and MLX model formats.
- Copyable results and recent history capped by local preferences.
- Floating widget MVP with drag/dock/collapse behavior.
- Local app packaging through `./scripts/package-app.sh`.
- Packaged app output at `dist/llmTools.app`.

Regression baseline:

- `swift build` should compile.
- `swift run LLMToolsChecks` should pass.
- Real-model smoke checks should continue to work for representative GGUF and MLX paths when models are present.
- The packaged app should launch from `dist/llmTools.app`.
- Settings, model registration, quick action, selected-text fallback, floating widget, and history clearing should remain usable after Phase 2 changes.

Maintenance boundary:

- Bugs found in Phase 1 flows should be fixed against this document.
- New product scope should be tracked in Phase 2 or later documents instead of reopening Phase 1.

## 21. Completed Implementation Milestones

### Milestone 1: Native Shell

- app target
- menu-bar lifecycle
- settings window
- floating widget window shell
- shortcut registration skeleton

### Milestone 2: Model Registry

- add model path
- detect GGUF and MLX candidates
- persist registry
- show validation status
- choose default model

### Milestone 3: Runtime Proof

- run a minimal prompt against one registered GGUF model
- run a minimal prompt against one registered MLX model
- normalize output and errors behind a shared runner protocol
- stream or return output to the app
- surface loading and failure states
- ensure UI stays responsive

### Milestone 4: Quick Action Panel

- selected-text capture attempt
- manual input fallback
- task selector
- result view
- copy action

### Milestone 5: Floating Widget MVP

- draggable widget
- edge snap
- auto-collapse
- expanded input
- task execution

### Milestone 6: Task Templates and Polish

- translate prompt
- polish prompt
- summarize prompt
- explain prompt
- TODO prompt
- settings refinements
- error copy improvements
- local `.app` packaging check
- recent history clear action

## 22. Confirmed Phase 1 Decisions

The following product decisions are confirmed:

1. Minimum target is macOS 14 or newer.
2. Phase 1 should be tested as a local `.app`.
3. Recent history keeps the latest 20 entries and supports one-click clear.
4. The floating widget appears on all Spaces/desktops by default.
5. Qwen 0.8B is fast mode, Qwen 4B is default mode, and Qwen 9B is quality mode.
6. Translation defaults to Chinese/English auto-detection.
7. GGUF and MLX inference must both work before Phase 1 is complete.

New uncertainties found during implementation should be raised for confirmation before expanding scope or making irreversible architecture decisions.
