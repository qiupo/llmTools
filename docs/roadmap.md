# llmTranslate Roadmap

Last updated: 2026-06-26

## Product Direction

llmTranslate is a native macOS local-model assistant. It is not primarily a chat app. Its core value is to connect small local models to high-frequency desktop workflows:

- selected-text translation, polishing, summarization, explanation, and TODO extraction
- a floating desktop widget that accepts pasted text and dragged files
- local model reuse through user-selected model files or model folders
- task-first interaction, with model selection hidden behind sensible defaults

The app should default to local processing. Cloud APIs are not part of the initial product scope.

## Confirmed Decisions

- Platform: native macOS app using SwiftUI/AppKit.
- Minimum platform target: macOS 14 or newer, with development and verification on the current newer macOS environment.
- Model source: users can reuse already downloaded local models by selecting model files or model folders.
- Model management: the app manages model registration, status, routing, and runner lifecycle.
- Text replacement: copying results is required; replacing original selected text is optional and controlled by a setting.
- Floating window: a desktop widget is required; it appears on all Spaces by default and can auto-collapse at the screen edge.
- Phase 1 model support: multiple model registrations are supported from the beginning.
- Phase 1 runtime support: GGUF and MLX inference must both fully work before Phase 1 is complete.
- Initial user model set: Qwen 0.8B, Qwen 4B, and Qwen 9B.
- Default model roles: Qwen 0.8B is fast mode, Qwen 4B is default mode, and Qwen 9B is quality mode.
- Observed model formats: GGUF models and MLX-4bit model folders.
- Early distribution: Phase 1 should be packaged as a local `.app` for realistic permission, shortcut, and floating-window testing.
- Recent history: keep the latest 20 local results and provide a one-click clear action.
- Translation default: Chinese input translates to English, and non-Chinese input translates to Chinese.

## Phase 1: Native MVP

Goal: ship a usable menu-bar macOS app that can process selected or pasted text with local models.

Core capabilities:

- menu-bar app
- global shortcut for selected-text processing
- quick action panel
- local model registry
- multiple configured models
- one active model at a time
- working GGUF and MLX model inference
- translation, polishing, summarization, explanation, and TODO extraction
- result copy
- optional original-text replacement setting, disabled by default
- floating desktop widget MVP with edge auto-collapse
- recent history capped at 20 entries with one-click clear
- local `.app` packaging for Phase 1 testing

Primary acceptance:

- A user can register Qwen 0.8B, Qwen 4B, and Qwen 9B from existing local folders.
- A user can run real inference with both a GGUF model and an MLX model.
- A user can select text in another app, press a shortcut, process it, and copy the result.
- A user can paste text into the floating widget and process it.
- A user can clear recent results with one action.

See `docs/phase-1-spec.md` for the detailed spec.

## Phase 2: Floating File Drop Workflow

Goal: make the floating widget a natural file-processing entry point.

Core capabilities:

- always-available floating widget
- drag-to-process interaction
- screen-edge docking and auto-collapse
- TXT and Markdown file ingestion
- PDF ingestion after text extraction is stable
- automatic task suggestion based on file content
- file summary
- key point extraction
- action item extraction
- recent result history
- clear running/error states

Suggested scope:

- Start with TXT/Markdown because they are predictable and allow the model pipeline to be hardened first.
- Add PDF only after text chunking, page extraction, and progress reporting are reliable.
- Treat DOCX as a later extension unless it becomes an explicit priority.

Primary acceptance:

- A user can drag a supported file onto the floating widget and receive a structured result.
- The widget remains unobtrusive when docked to the side of the screen.
- Large-file failures produce understandable messages instead of silent hangs.

## Phase 3: Local Document Assistant

Goal: move from single-shot processing to reusable local document understanding.

Core capabilities:

- import files and folders
- local document index
- searchable processing history
- document-level question answering
- multi-document summary
- project or folder digest
- local metadata storage
- tags and lightweight organization

Suggested scope:

- Keep all data local by default.
- Add indexing only for user-selected folders.
- Make index status visible, including "not indexed", "indexing", "ready", and "failed".

Primary acceptance:

- A user can add a folder and ask questions against its indexed documents.
- A user can summarize a set of files without manually opening each file.
- The app clearly separates raw files, extracted text, generated summaries, and vector/index data.

## Phase 4: Model Routing and Automation

Goal: make multiple small models cooperate behind simple task workflows.

Core capabilities:

- task classification
- automatic model routing
- speed/quality mode
- 0.8B model for lightweight classification and short tasks
- 4B model for default everyday tasks
- 9B model for higher-quality or longer-context tasks
- prompt template management
- custom workflows
- developer utilities: log explanation, error analysis, diff summary, commit message drafting

Suggested scope:

- Keep routing observable. The user should be able to see which model was used and why.
- Allow users to override model choice per task.
- Store prompt templates locally.

Primary acceptance:

- The app can choose a reasonable model based on task type, text length, and user quality preference.
- The user can define custom actions without editing code.
- Developer workflows are useful but do not dominate the general product experience.

## Cross-Phase Principles

- Local-first by default.
- Explicit model paths, no hidden model downloads in early phases.
- Native macOS interactions should feel first-class.
- Failures must be visible and actionable.
- Long-running model work should never freeze the UI.
- Model runners should be isolated enough that a backend crash does not crash the whole app.
- Privacy-sensitive data should not be retained unless the user opts in.
