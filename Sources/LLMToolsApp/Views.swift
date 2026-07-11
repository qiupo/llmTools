import AppKit
import Carbon.HIToolbox
import SwiftUI
import UniformTypeIdentifiers
import LLMToolsCore

struct SelectionActionView: View {
    @ObservedObject var appState: AppState
    @ObservedObject var pinState: WindowPinState
    var onSelect: (TaskKind) -> Void

    private let actionBarWidth: CGFloat = 244
    private let actionBarHeight: CGFloat = 48
    private let inlinePanelWidth: CGFloat = 218
    private let inlinePanelHeight: CGFloat = 112
    private let inlinePanelOverlap: CGFloat = 3

    private var language: AppLanguage {
        appState.preferences.appLanguage
    }

    private var translationOutputText: String {
        guard appState.selectedTask == .translate else {
            return ""
        }
        return appState.outputText
    }

    private var shouldShowInlineResult: Bool {
        appState.inputOrigin == .selection
            && appState.selectionInlineResultVisible
            && appState.selectedTask == .translate
    }

    private var contentHeight: CGFloat {
        shouldShowInlineResult
            ? actionBarHeight + inlinePanelHeight - inlinePanelOverlap
            : actionBarHeight
    }

    var body: some View {
        ZStack(alignment: .top) {
            if shouldShowInlineResult {
                inlineResultPanel
                    .offset(y: actionBarHeight - inlinePanelOverlap)
            }

            actionBar
        }
        .frame(width: 260, height: contentHeight, alignment: .top)
        .padding(.vertical, 5)
    }

    private func iconName(for task: TaskKind) -> String {
        switch task {
        case .translate: return "character.book.closed"
        case .webPageTranslate: return "safari"
        case .polish: return "wand.and.stars"
        case .summarize: return "doc.text"
        case .explain: return "questionmark.circle"
        case .extractTodos: return "list.bullet.clipboard"
        case .ocr: return "text.viewfinder"
        }
    }

    private var actionBar: some View {
        HStack(spacing: 6) {
            ForEach(TaskKind.interactiveCases) { task in
                Button {
                    onSelect(task)
                } label: {
                    Image(systemName: iconName(for: task))
                        .font(.system(size: 17, weight: .medium))
                        .symbolRenderingMode(.hierarchical)
                        .frame(width: 34, height: 32)
                        .background(actionBackground(for: task))
                        .contentShape(RoundedRectangle(cornerRadius: 9, style: .continuous))
                }
                .buttonStyle(.plain)
                .foregroundStyle(actionForeground(for: task))
                .help(task.title(language: language))
                .disabled(appState.isRunning)
            }

            WindowPinButton(
                pinState: pinState,
                language: language,
                appearance: .selectionAction
            )
        }
        .padding(.horizontal, 8)
        .frame(width: actionBarWidth, height: actionBarHeight)
        .background(Color(NSColor.controlBackgroundColor).opacity(0.98), in: RoundedRectangle(cornerRadius: 18, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .strokeBorder(Color.primary.opacity(0.16), lineWidth: 0.8)
        )
        .shadow(color: .black.opacity(0.13), radius: 8, y: 3)
        .compositingGroup()
    }

    @ViewBuilder
    private func actionBackground(for task: TaskKind) -> some View {
        if task == .translate && shouldShowInlineResult {
            RoundedRectangle(cornerRadius: 9, style: .continuous)
                .fill(Color.accentColor.opacity(0.14))
        } else {
            Color.clear
        }
    }

    private func actionForeground(for task: TaskKind) -> Color {
        task == .translate && shouldShowInlineResult ? .accentColor : .primary
    }

    private var inlineResultPanel: some View {
        ZStack(alignment: .topLeading) {
            if appState.isRunning {
                HStack(spacing: 8) {
                    ProgressView()
                        .controlSize(.small)
                    Text(appState.statusMessage)
                        .font(.system(size: 14))
                        .foregroundStyle(.secondary)
                }
                .padding(.horizontal, 10)
                .padding(.vertical, 9)
            } else if let error = appState.validationError,
                      translationOutputText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                Text(error)
                    .font(.system(size: 14))
                    .foregroundStyle(.red)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.horizontal, 10)
                    .padding(.vertical, 9)
            } else {
                ScrollView {
                    Text(translationOutputText)
                        .font(.system(size: 15, weight: .regular))
                        .lineSpacing(2)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(.horizontal, 12)
                        .padding(.top, 12)
                        .padding(.bottom, 10)
                }
            }
        }
        .frame(width: inlinePanelWidth, height: inlinePanelHeight, alignment: .topLeading)
        .background(
            Color(NSColor.textBackgroundColor).opacity(0.98),
            in: UnevenRoundedRectangle(
                topLeadingRadius: 0,
                bottomLeadingRadius: 8,
                bottomTrailingRadius: 8,
                topTrailingRadius: 0,
                style: .continuous
            )
        )
        .overlay(
            UnevenRoundedRectangle(
                topLeadingRadius: 0,
                bottomLeadingRadius: 8,
                bottomTrailingRadius: 8,
                topTrailingRadius: 0,
                style: .continuous
            )
            .strokeBorder(Color.primary.opacity(0.16), lineWidth: 0.8)
        )
        .clipShape(
            UnevenRoundedRectangle(
                topLeadingRadius: 0,
                bottomLeadingRadius: 8,
                bottomTrailingRadius: 8,
                topTrailingRadius: 0,
                style: .continuous
            )
        )
        .shadow(color: .black.opacity(0.08), radius: 5, y: 2)
    }
}

struct QuickActionView: View {
    @ObservedObject var appState: AppState
    @ObservedObject var pinState: WindowPinState
    var onClose: () -> Void = {}
    @State private var showFileImporter = false
    @State private var showImageImporter = false
    @State private var showMediaImporter = false
    @State private var showInput = true
    @State private var imageURLDraft = ""
    @State private var isImagePreviewPresented = false
    @State private var showsMarkdownSource = false

    private var language: AppLanguage {
        appState.preferences.appLanguage
    }

    private var displayedOutputText: String {
        appState.displayedOutputText
    }

    private var markdownPreviewAvailable: Bool {
        guard !appState.showsRawOutput,
              MarkdownResultPreview.looksLikeMarkdown(displayedOutputText) else {
            return false
        }
        switch appState.quickActionMode {
        case .text:
            return appState.selectedTask != .translate && appState.selectedTask != .webPageTranslate
        case .image:
            switch appState.ocrMode {
            case .structured, .explainImage:
                return true
            case .plainText, .extractThenTranslate:
                return false
            }
        case .media:
            return true
        }
    }

    private var shouldRenderMarkdownPreview: Bool {
        markdownPreviewAvailable && !showsMarkdownSource
    }

    private var shouldRenderMediaSubtitlePreview: Bool {
        appState.quickActionMode == .media
            && !appState.showsRawOutput
            && !showsMarkdownSource
            && !appState.mediaSubtitleSegments.isEmpty
    }

    private var imagePreviewPresentation: Binding<Bool> {
        Binding(
            get: { isImagePreviewPresented && appState.ocrImageInput != nil },
            set: { isImagePreviewPresented = $0 }
        )
    }

    var body: some View {
        VStack(spacing: 0) {
            controlsBar
                .layoutPriority(2)
            Divider()
            mainContent
                .layoutPriority(1)
            Divider()
            bottomBar
                .layoutPriority(2)
        }
        .frame(minWidth: 560)
        .background(Color(NSColor.windowBackgroundColor))
        .sheet(isPresented: imagePreviewPresentation) {
            if let image = appState.ocrImageInput {
                OCRImagePreviewSheet(input: image, language: language)
            }
        }
        .fileImporter(isPresented: $showFileImporter, allowedContentTypes: [.plainText, .text, .item], allowsMultipleSelection: false) { result in
            if case let .success(urls) = result, let url = urls.first {
                appState.loadInputFile(from: url)
            }
        }
        .fileImporter(isPresented: $showImageImporter, allowedContentTypes: [.image, .item], allowsMultipleSelection: false) { result in
            if case let .success(urls) = result, let url = urls.first {
                appState.loadOCRImageFile(from: url)
            }
        }
        .fileImporter(isPresented: $showMediaImporter, allowedContentTypes: [.audio, .movie, .video, .item], allowsMultipleSelection: false) { result in
            if case let .success(urls) = result, let url = urls.first {
                appState.loadMediaSubtitleFile(from: url)
            }
        }
        .onDrop(of: [.fileURL, .plainText, .text, .image], isTargeted: nil) { providers in
            handleDrop(providers)
        }
        .onChange(of: appState.outputText) { _, _ in
            showsMarkdownSource = false
        }
        .onChange(of: appState.selectedTask) { _, _ in
            showsMarkdownSource = false
        }
        .onChange(of: appState.quickActionMode) { _, _ in
            showsMarkdownSource = false
        }
        .onChange(of: appState.ocrMode) { _, _ in
            showsMarkdownSource = false
        }
    }

    private var controlsBar: some View {
        ZStack(alignment: .leading) {
            quickActionModePicker
                .offset(x: quickActionModePickerX)

            primaryModeControl
                .fixedSize(horizontal: true, vertical: false)
                .offset(x: primaryModeControlX)

            if appState.quickActionMode == .text {
                modeOptions
                    .frame(width: 175, alignment: .leading)
                    .offset(x: textModeOptionsX)
            }

            if appState.quickActionMode == .text {
                HStack {
                    Spacer(minLength: 0)
                    hideSourceButton
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.leading, controlsBarLeadingPadding)
        .padding(.trailing, 14)
        .padding(.vertical, 10)
    }

    private var controlsBarLeadingPadding: CGFloat {
        12
    }

    private var quickActionModePickerWidth: CGFloat {
        168
    }

    private var quickActionModePickerVisualWidth: CGFloat {
        140
    }

    private var controlsBarCompactGap: CGFloat {
        8
    }

    private var textTaskPickerWidth: CGFloat {
        108
    }

    private var targetLanguagePickerWidth: CGFloat {
        86
    }

    private var quickActionModePickerX: CGFloat {
        0
    }

    private var primaryModeControlX: CGFloat {
        quickActionModePickerVisualWidth + controlsBarCompactGap
    }

    private var textModeOptionsX: CGFloat {
        primaryModeControlX + textTaskPickerWidth + controlsBarCompactGap
    }

    private var quickActionModePicker: some View {
        Picker("", selection: $appState.quickActionMode) {
            Text(L10n.text("Text mode", language: language)).tag(AppState.QuickActionMode.text)
            Text(L10n.text("Image mode", language: language)).tag(AppState.QuickActionMode.image)
            Text(L10n.text("Media mode", language: language)).tag(AppState.QuickActionMode.media)
        }
        .labelsHidden()
        .pickerStyle(.segmented)
        .frame(width: quickActionModePickerWidth, alignment: .leading)
        .fixedSize(horizontal: true, vertical: false)
        .disabled(appState.isRunning || appState.isPreparingOCRImage)
    }

    private var hideSourceButton: some View {
        Button {
            showInput.toggle()
        } label: {
            HStack(spacing: 4) {
                Text(L10n.text(showInput ? "Hide source" : "Show source", language: language))
                    .lineLimit(1)
                Image(systemName: showInput ? "chevron.up" : "chevron.down")
                    .font(.caption2)
                    .frame(width: 10)
            }
            .frame(width: 76, alignment: .center)
        }
        .buttonStyle(.borderless)
        .disabled(appState.inputText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
    }

    @ViewBuilder
    private var primaryModeControl: some View {
        if appState.quickActionMode == .text {
            Picker("", selection: $appState.selectedTask) {
                ForEach(TaskKind.interactiveCases) { task in
                    Text(task.title(language: language)).tag(task)
                }
            }
            .labelsHidden()
            .frame(width: textTaskPickerWidth, alignment: .leading)
            .disabled(appState.isRunning)
        } else if appState.quickActionMode == .image {
            modeOptions
                .frame(width: 126, alignment: .leading)
        } else {
            mediaModePicker
                .frame(width: 126, alignment: .leading)
        }
    }

    @ViewBuilder
    private var modeOptions: some View {
        if appState.quickActionMode == .image {
            Picker("", selection: Binding(
                get: { appState.ocrMode },
                set: { appState.setOCRMode($0) }
            )) {
                ForEach(OCRMode.allCases) { mode in
                    Text(L10n.ocrModeName(mode, language: language)).tag(mode)
                }
            }
            .labelsHidden()
            .frame(width: 126)
            .disabled(appState.isRunning || appState.isPreparingOCRImage)
        } else {
            switch appState.selectedTask {
            case .translate:
                HStack(spacing: 4) {
                    Text(L10n.text("Auto detect", language: language))
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                        .fixedSize(horizontal: true, vertical: false)
                        .frame(width: 56)
                        .padding(.horizontal, 8)
                        .padding(.vertical, 5)
                        .background(.quaternary.opacity(0.45))
                        .clipShape(RoundedRectangle(cornerRadius: 6))
                    Image(systemName: "arrow.right")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    Picker("", selection: Binding(
                        get: { appState.preferences.defaultTranslationTarget },
                        set: { newValue in
                            appState.updatePreferences { $0.defaultTranslationTarget = newValue }
                        }
                    )) {
                        Text(L10n.targetLanguageName("Chinese", language: language)).tag("Chinese")
                        Text(L10n.targetLanguageName("English", language: language)).tag("English")
                        Text(L10n.targetLanguageName("Japanese", language: language)).tag("Japanese")
                        Text(L10n.targetLanguageName("Korean", language: language)).tag("Korean")
                        Text(L10n.targetLanguageName("auto", language: language)).tag("auto")
                    }
                    .labelsHidden()
                    .frame(width: targetLanguagePickerWidth)
                    .disabled(appState.isRunning)
                }
            case .polish:
                Picker("", selection: Binding(
                    get: { appState.preferences.defaultPolishStyle },
                    set: { newValue in
                        appState.updatePreferences { $0.defaultPolishStyle = newValue }
                    }
                )) {
                    Text(L10n.polishStyleName("natural", language: language)).tag("natural")
                    Text(L10n.polishStyleName("formal", language: language)).tag("formal")
                    Text(L10n.polishStyleName("concise", language: language)).tag("concise")
                    Text(L10n.polishStyleName("conversational", language: language)).tag("conversational")
                    Text(L10n.polishStyleName("technical", language: language)).tag("technical")
                }
                .labelsHidden()
                .frame(width: 118)
                .disabled(appState.isRunning)
            case .summarize:
                summaryModePicker
            case .explain:
                explanationModePicker
            case .extractTodos:
                todoExtractionModePicker
            case .webPageTranslate, .ocr:
                EmptyView()
            }
        }
    }

    private var mediaModePicker: some View {
        Picker("", selection: Binding(
            get: { appState.mediaSubtitleMode },
            set: { appState.setMediaSubtitleMode($0) }
        )) {
            ForEach(SubtitleDisplayMode.allCases) { mode in
                Text(subtitleModeName(mode)).tag(mode)
            }
        }
        .labelsHidden()
        .pickerStyle(.menu)
        .disabled(appState.isRunning)
    }

    private var summaryModePicker: some View {
        Picker("", selection: Binding(
            get: { appState.preferences.defaultSummaryMode },
            set: { newValue in
                appState.updatePreferences { $0.defaultSummaryMode = newValue }
            }
        )) {
            ForEach(SummaryMode.allCases) { mode in
                Text(L10n.summaryModeName(mode, language: language)).tag(mode)
            }
        }
        .labelsHidden()
        .pickerStyle(.menu)
        .frame(width: 142)
        .disabled(appState.isRunning)
        .help(L10n.text("Summary mode", language: language))
    }

    private var explanationModePicker: some View {
        Picker("", selection: Binding(
            get: { appState.preferences.defaultExplanationMode },
            set: { newValue in
                appState.updatePreferences { $0.defaultExplanationMode = newValue }
            }
        )) {
            ForEach(ExplanationMode.allCases) { mode in
                Text(L10n.explanationModeName(mode, language: language)).tag(mode)
            }
        }
        .labelsHidden()
        .pickerStyle(.menu)
        .frame(width: 142)
        .disabled(appState.isRunning)
        .help(L10n.text("Explanation mode", language: language))
    }

    private var todoExtractionModePicker: some View {
        Picker("", selection: Binding(
            get: { appState.preferences.defaultTodoExtractionMode },
            set: { newValue in
                appState.updatePreferences { $0.defaultTodoExtractionMode = newValue }
            }
        )) {
            ForEach(TodoExtractionMode.allCases) { mode in
                Text(L10n.todoExtractionModeName(mode, language: language)).tag(mode)
            }
        }
        .labelsHidden()
        .pickerStyle(.menu)
        .frame(width: 142)
        .disabled(appState.isRunning)
        .help(L10n.text("TODO mode", language: language))
    }

    private var mainContent: some View {
        Group {
            if appState.quickActionMode == .image {
                imageMainContent
            } else if appState.quickActionMode == .media {
                mediaMainContent
            } else {
                VStack(spacing: 10) {
                    if showInput || appState.outputText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                        inputPanel
                    }
                    resultPanel
                    if markdownPreviewAvailable || appState.hasDifferentRawOutput {
                        outputDisplayOptions
                    }
                }
            }
        }
        .padding(12)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private var imageMainContent: some View {
        HStack(spacing: 10) {
            imageInputPanel
                .frame(width: 220)
            VStack(spacing: 10) {
                resultPanel
                if markdownPreviewAvailable || appState.hasDifferentRawOutput {
                    outputDisplayOptions
                }
                ocrFollowUpBar
            }
        }
    }

    private var mediaMainContent: some View {
        HStack(spacing: 10) {
            mediaInputPanel
                .frame(width: 230)
            VStack(spacing: 10) {
                resultPanel
                if markdownPreviewAvailable || appState.hasDifferentRawOutput {
                    outputDisplayOptions
                }
                mediaExportBar
            }
        }
    }

    private var mediaInputPanel: some View {
        VStack(alignment: .leading, spacing: 10) {
            ZStack(alignment: .topTrailing) {
                RoundedRectangle(cornerRadius: 8)
                    .fill(Color(NSColor.textBackgroundColor))
                VStack(spacing: 9) {
                    Button {
                        showMediaImporter = true
                    } label: {
                        Image(systemName: "waveform.badge.mic")
                            .font(.system(size: 27, weight: .medium))
                            .foregroundStyle(.secondary)
                            .frame(width: 42, height: 42)
                    }
                    .buttonStyle(.plain)
                    .help(L10n.text("Choose Media", language: language))
                    .disabled(appState.isRunning)
                    Text(appState.mediaSubtitleDescriptor == nil
                        ? L10n.text("Drop audio or video.", language: language)
                        : L10n.text("Media loaded", language: language))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)

                if appState.mediaSubtitleDescriptor != nil {
                    clearMediaButton
                }
            }
            .frame(height: 132)
            .overlay(RoundedRectangle(cornerRadius: 8).stroke(Color.secondary.opacity(0.18)))

            if let descriptor = appState.mediaSubtitleDescriptor {
                VStack(alignment: .leading, spacing: 5) {
                    Text(descriptor.fileName)
                        .font(.caption.weight(.medium))
                        .lineLimit(1)
                        .truncationMode(.middle)
                    Text(mediaDescriptorLine(descriptor))
                        .font(.caption2.monospaced())
                        .foregroundStyle(.secondary)
                        .lineLimit(2)
                }
            }

            Divider()

            VStack(alignment: .leading, spacing: 7) {
                Text(L10n.text("File ASR", language: language))
                    .font(.caption)
                    .foregroundStyle(.secondary)
                mediaFileASRPicker
                Text(L10n.text("Realtime ASR", language: language))
                    .font(.caption)
                    .foregroundStyle(.secondary)
                mediaRealtimeASRPicker
            }

            if let report = appState.mediaSubtitleHealthReport {
                Text(report.message)
                    .font(.caption)
                    .foregroundStyle(report.status == .ready ? Color.secondary : Color.red)
                    .lineLimit(3)
            }

            mediaSpeakerStatusView
        }
        .padding(10)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .background(Color(NSColor.controlBackgroundColor).opacity(0.65))
        .overlay(RoundedRectangle(cornerRadius: 8).stroke(Color.secondary.opacity(0.14)))
        .clipShape(RoundedRectangle(cornerRadius: 8))
    }

    private var clearMediaButton: some View {
        Button(role: .destructive) {
            appState.clearMediaSubtitleFile()
        } label: {
            Image(systemName: "xmark")
                .font(.system(size: 10, weight: .semibold))
                .foregroundStyle(.secondary)
                .frame(width: 22, height: 22)
                .background(Color(NSColor.windowBackgroundColor).opacity(0.94), in: Circle())
                .overlay(Circle().stroke(Color.secondary.opacity(0.22)))
                .contentShape(Circle())
        }
        .buttonStyle(.plain)
        .help(L10n.text("Clear", language: language))
        .disabled(appState.isRunning)
        .padding(6)
    }

    private var mediaFileASRPicker: some View {
        Picker("", selection: Binding<UUID?>(
            get: { appState.preferences.mediaSubtitles.fileASRModelID },
            set: { newValue in
                appState.updatePreferences { $0.mediaSubtitles.fileASRModelID = newValue }
            }
        )) {
            Text(L10n.text("No model", language: language)).tag(UUID?.none)
            ForEach(appState.fileSpeechModels) { model in
                Text(speechModelPickerTitle(model)).tag(Optional(model.id))
            }
        }
        .labelsHidden()
        .pickerStyle(.menu)
        .disabled(appState.fileSpeechModels.isEmpty || appState.isRunning)
    }

    private var mediaRealtimeASRPicker: some View {
        Picker("", selection: Binding<UUID?>(
            get: { appState.preferences.mediaSubtitles.realtimeASRModelID },
            set: { newValue in
                appState.setRealtimeASRModel(id: newValue)
            }
        )) {
            Text(L10n.text("No model", language: language)).tag(UUID?.none)
            ForEach(appState.realtimeSpeechModels) { model in
                Text(speechModelPickerTitle(model)).tag(Optional(model.id))
            }
        }
        .labelsHidden()
        .pickerStyle(.menu)
        .disabled(appState.realtimeSpeechModels.isEmpty || appState.isRunning)
    }

    private var mediaExportBar: some View {
        HStack(spacing: 6) {
            Text(L10n.text("Export", language: language))
                .font(.caption)
                .foregroundStyle(.secondary)
            ForEach(SubtitleExportFormat.allCases) { format in
                Button {
                    appState.exportCurrentMediaSubtitles(format: format)
                } label: {
                    Text(format.rawValue.uppercased())
                        .font(.caption.bold())
                        .frame(width: 38, height: 22)
                }
                .controlSize(.small)
                .disabled(appState.mediaSubtitleSegments.isEmpty || appState.isRunning)
                .help("\(L10n.text("Export", language: language)) \(format.rawValue.uppercased())")
            }
            Button {
                appState.translateCurrentMediaSubtitles()
            } label: {
                Label(L10n.text("Retry translation", language: language), systemImage: "arrow.clockwise")
                    .labelStyle(.iconOnly)
                    .frame(width: 26, height: 22)
            }
            .controlSize(.small)
            .help(L10n.text("Retry translation", language: language))
            .disabled(appState.mediaSubtitleSegments.isEmpty || appState.isRunning)
            Spacer(minLength: 0)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    @ViewBuilder
    private var mediaSpeakerStatusView: some View {
        if let status = mediaSpeakerStatus {
            Label {
                Text(status.text)
                    .font(.caption)
                    .foregroundStyle(status.color)
                    .fixedSize(horizontal: false, vertical: true)
            } icon: {
                Image(systemName: status.icon)
                    .foregroundStyle(status.color)
            }
        }
    }

    private var mediaSpeakerStatus: (text: String, icon: String, color: Color)? {
        guard appState.preferences.speakerDiarization.enabledForFileSubtitles else {
            return nil
        }
        if appState.isRunning && appState.quickActionMode == .media {
            return (
                localizedMediaSpeakerStatus(
                    chinese: "说话人分离会在文件 ASR 后运行",
                    english: "Speaker diarization runs after file ASR"
                ),
                "person.wave.2",
                .secondary
            )
        }
        guard !appState.mediaSubtitleSegments.isEmpty else {
            return (
                localizedMediaSpeakerStatus(
                    chinese: "已启用；下次生成文件字幕时会运行说话人分离",
                    english: "Enabled for the next file subtitle generation"
                ),
                "checkmark.circle",
                .secondary
            )
        }
        if let errorCode = appState.mediaSubtitleDiagnostics?.diarizationErrorCode {
            let message = appState.mediaSubtitleDiagnostics?.diarizationErrorMessage ?? errorCode
            return (
                mediaSpeakerFailureStatusText(message: message),
                "exclamationmark.triangle.fill",
                .red
            )
        }
        let speakerCount = appState.mediaSubtitleDiagnostics?.speakerCount
            ?? SpeakerTurnMapper.speakerCount(in: appState.mediaSubtitleSegments)
        if speakerCount > 0 {
            return (
                localizedMediaSpeakerStatus(
                    chinese: "已标注 \(speakerCount) 个说话人",
                    english: "Labeled \(speakerCount) \(speakerCount == 1 ? "speaker" : "speakers")"
                ),
                "person.2.fill",
                .secondary
            )
        }
        return (
            localizedMediaSpeakerStatus(
                chinese: "当前结果没有说话人标签；请重新生成以应用说话人分离",
                english: "Current result has no speaker labels; regenerate to apply diarization"
            ),
            "arrow.clockwise",
            .orange
        )
    }

    private func localizedMediaSpeakerStatus(chinese: String, english: String) -> String {
        language == .chinese ? chinese : english
    }

    private func mediaSpeakerFailureStatusText(message: String) -> String {
        let lowercased = message.lowercased()
        let displayMessage: String
        let resolution: String
        if isPyannoteSetupFailure(lowercased) {
            displayMessage = localizedMediaSpeakerStatus(
                chinese: "pyannote 模型未就绪。请先到 设置 > 模型 > 模型设置 > 说话人分离 完成 pyannote 配置。",
                english: "pyannote model is not ready. Configure pyannote first in Settings > Models > Model Settings > Speaker Diarization."
            )
            resolution = localizedMediaSpeakerStatus(
                chinese: "解决路径：按模型设置里的步骤接受 speaker-diarization-3.1 和 segmentation-3.0 两个 pyannote 条款、保存 HF Token、运行健康检查/修复运行时；如果本机无法访问 huggingface.co，请先缓存 pyannote 模型后重新生成。",
                english: "Fix: accept both pyannote terms for speaker-diarization-3.1 and segmentation-3.0, save the HF token, run Health Check or Repair Runtime in Settings, and pre-cache the pyannote models if huggingface.co is unreachable."
            )
        } else if lowercased.contains("token") || lowercased.contains("auth") {
            displayMessage = message
            resolution = localizedMediaSpeakerStatus(
                chinese: "解决路径：保存本地 HF Token 后重新生成。",
                english: "Fix: save the local HF token, then regenerate."
            )
        } else if lowercased.contains("terms") || lowercased.contains("gated") || lowercased.contains("repository") {
            displayMessage = message
            resolution = localizedMediaSpeakerStatus(
                chinese: "解决路径：用同一个 Hugging Face 账号接受 speaker-diarization-3.1 和 segmentation-3.0 两个 pyannote 条款，再重新生成。",
                english: "Fix: accept both pyannote terms for speaker-diarization-3.1 and segmentation-3.0 with the same Hugging Face account, then regenerate."
            )
        } else if lowercased.contains("no route") || lowercased.contains("network") || lowercased.contains("connection") || lowercased.contains("timed out") {
            displayMessage = message
            resolution = localizedMediaSpeakerStatus(
                chinese: "解决路径：让本机可访问 huggingface.co，或预先缓存 pyannote 模型后重新生成。",
                english: "Fix: make huggingface.co reachable, or pre-cache the pyannote model, then regenerate."
            )
        } else if lowercased.contains("python") || lowercased.contains("runtime") || lowercased.contains("module") || lowercased.contains("import") {
            displayMessage = message
            resolution = localizedMediaSpeakerStatus(
                chinese: "解决路径：在设置里点击健康检查；如果提示运行时缺失，点击修复运行时。",
                english: "Fix: run Health Check in Settings; if runtime is missing, click Repair Runtime."
            )
        } else {
            displayMessage = message
            resolution = localizedMediaSpeakerStatus(
                chinese: "解决路径：在设置里运行健康检查，按提示修复后重新生成。",
                english: "Fix: run Health Check in Settings, follow the repair prompt, then regenerate."
            )
        }
        return localizedMediaSpeakerStatus(
            chinese: "说话人分离失败：\(displayMessage)\n\(resolution)",
            english: "Speaker diarization failed: \(displayMessage)\n\(resolution)"
        )
    }

    private func isPyannoteSetupFailure(_ lowercased: String) -> Bool {
        let mentionsPyannoteModel = lowercased.contains("pyannote")
            || lowercased.contains("speaker-diarization")
        let mentionsSettingsPath = lowercased.contains("settings > models > speaker diarization")
            || lowercased.contains("settings > models > model settings > speaker diarization")
        let mentionsHuggingFaceAccess = lowercased.contains("huggingface")
            || lowercased.contains("hf token")
            || lowercased.contains("hf_token")
            || lowercased.contains("pyannote_auth_token")
            || lowercased.contains("gated")
            || lowercased.contains("model terms")
            || lowercased.contains("repository")
            || lowercased.contains("resolve/main")
        let mentionsNetworkFailure = lowercased.contains("no route")
            || lowercased.contains("cannot send a request")
            || lowercased.contains("connection")
            || lowercased.contains("timed out")
            || lowercased.contains("network")
        return mentionsSettingsPath || (mentionsPyannoteModel && (mentionsHuggingFaceAccess || mentionsNetworkFailure))
    }

    private var imageInputPanel: some View {
        VStack(alignment: .leading, spacing: 10) {
            imagePreviewArea

            if let image = appState.ocrImageInput {
                VStack(alignment: .leading, spacing: 4) {
                    Text(image.fileName ?? image.sourceDescription)
                        .font(.caption.weight(.medium))
                        .lineLimit(1)
                        .truncationMode(.middle)
                    Text(image.redactedHistoryPreview)
                        .font(.caption2.monospaced())
                        .foregroundStyle(.secondary)
                        .lineLimit(2)
                        .truncationMode(.middle)
                }
            }

            HStack(spacing: 6) {
                CommandFriendlyTextField(
                    text: $imageURLDraft,
                    placeholder: L10n.text("Image URL", language: language)
                )
                Button {
                    appState.loadOCRImageFromRemoteURL(imageURLDraft)
                } label: {
                    Image(systemName: "arrow.down.doc")
                        .frame(width: 24, height: 24)
                }
                .buttonStyle(.borderless)
                .help(L10n.text("Load URL", language: language))
                .disabled(appState.isPreparingOCRImage || imageURLDraft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            }

            ocrModelPicker
        }
        .padding(10)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .background(Color(NSColor.controlBackgroundColor).opacity(0.65))
        .overlay(RoundedRectangle(cornerRadius: 8).stroke(Color.secondary.opacity(0.14)))
        .clipShape(RoundedRectangle(cornerRadius: 8))
    }

    private var imagePreviewHeight: CGFloat {
        appState.ocrImageInput == nil ? 148 : 126
    }

    private var imagePreviewArea: some View {
        ZStack(alignment: .topTrailing) {
            RoundedRectangle(cornerRadius: 8)
                .fill(Color(NSColor.textBackgroundColor))
            imagePreviewContent
            if appState.ocrImageInput != nil {
                clearImageButton
            }
        }
        .frame(height: imagePreviewHeight, alignment: .center)
        .frame(maxWidth: .infinity, alignment: .center)
        .overlay(RoundedRectangle(cornerRadius: 8).stroke(Color.secondary.opacity(0.18)))
    }

    @ViewBuilder
    private var imagePreviewContent: some View {
        if let preview = appState.ocrPreviewImage {
            Button {
                isImagePreviewPresented = true
            } label: {
                ZStack(alignment: .bottomTrailing) {
                    Image(nsImage: preview)
                        .resizable()
                        .scaledToFit()
                        .padding(8)
                        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .center)

                    Image(systemName: "magnifyingglass")
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundStyle(.secondary)
                        .frame(width: 22, height: 22)
                        .background(Color(NSColor.windowBackgroundColor).opacity(0.94), in: Circle())
                        .overlay(Circle().stroke(Color.secondary.opacity(0.22)))
                        .padding(6)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .center)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .help(L10n.text("Open Image Preview", language: language))
        } else {
            VStack(spacing: 8) {
                addImageButton
                Text(L10n.text("Drop or paste an image.", language: language))
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            .padding(12)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .center)
        }
    }

    private var addImageButton: some View {
        Button {
            showImageImporter = true
        } label: {
            Image(systemName: "plus")
                .font(.system(size: 24, weight: .medium))
                .foregroundStyle(.secondary)
                .frame(width: 38, height: 38)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .help(L10n.text("Choose Image", language: language))
        .disabled(appState.isRunning || appState.isPreparingOCRImage)
    }

    private var clearImageButton: some View {
        Button(role: .destructive) {
            isImagePreviewPresented = false
            appState.clearOCRImage()
        } label: {
            Image(systemName: "xmark")
                .font(.system(size: 10, weight: .semibold))
                .foregroundStyle(.secondary)
                .frame(width: 22, height: 22)
                .background(Color(NSColor.windowBackgroundColor).opacity(0.94), in: Circle())
                .overlay(Circle().stroke(Color.secondary.opacity(0.22)))
                .contentShape(Circle())
        }
        .buttonStyle(.plain)
        .help(L10n.text("Clear Image", language: language))
        .disabled(appState.isRunning)
        .padding(6)
    }

    private var ocrModelPicker: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(L10n.text("OCR model", language: language))
                .font(.caption)
                .foregroundStyle(.secondary)
            Picker("", selection: Binding<UUID?>(
                get: { appState.preferences.ocr.modelID },
                set: { newValue in
                    appState.updatePreferences { $0.ocr.modelID = newValue }
                }
            )) {
                Text(L10n.text("No model", language: language)).tag(UUID?.none)
                ForEach(appState.visionCapableModels) { model in
                    Text(modelPickerTitle(model)).tag(Optional(model.id))
                }
            }
            .labelsHidden()
            .pickerStyle(.menu)
            .disabled(appState.visionCapableModels.isEmpty || appState.isRunning)
        }
    }

    private var inputPanel: some View {
        ZStack(alignment: .topLeading) {
            if appState.inputText.isEmpty {
                Text(inputPlaceholder)
                    .foregroundStyle(.secondary)
                    .padding(.horizontal, 11)
                    .padding(.vertical, 10)
                    .allowsHitTesting(false)
            }
            EditableTextView(text: Binding(
                get: { appState.inputText },
                set: { newValue in
                    appState.setInputText(newValue, origin: .manual)
                }
            ), onSubmit: {
                guard !appState.isRunning else {
                    return
                }
                appState.runCurrentTask()
            })
            .frame(minHeight: appState.outputText.isEmpty ? 155 : 88)
        }
        .background(Color(NSColor.textBackgroundColor))
        .overlay(RoundedRectangle(cornerRadius: 8).stroke(Color.secondary.opacity(0.18)))
        .clipShape(RoundedRectangle(cornerRadius: 8))
    }

    private var resultPanel: some View {
        ZStack(alignment: .topLeading) {
            if appState.isRunning {
                HStack(spacing: 10) {
                    ProgressView()
                        .controlSize(.small)
                    Text(appState.statusMessage)
                        .foregroundStyle(.secondary)
                }
                .padding(12)
            } else if displayedOutputText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
                      let error = appState.validationError,
                      appState.quickActionMode == .image {
                VStack(alignment: .leading, spacing: 8) {
                    Label(L10n.text("Failed", language: language), systemImage: "exclamationmark.triangle.fill")
                        .font(.headline)
                        .foregroundStyle(.red)
                    Text(error)
                        .foregroundStyle(.secondary)
                        .textSelection(.enabled)
                }
                .padding(12)
            } else if displayedOutputText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                Text(resultPlaceholder)
                    .foregroundStyle(.secondary)
                    .padding(12)
            } else if shouldRenderMediaSubtitlePreview {
                MediaSubtitleResultPreview(
                    segments: appState.mediaSubtitleSegments,
                    mode: appState.mediaSubtitleMode,
                    language: language
                )
            } else if shouldRenderMarkdownPreview {
                MarkdownResultPreview(markdown: displayedOutputText)
            } else {
                ReadOnlyTextView(text: displayedOutputText)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color(NSColor.textBackgroundColor))
        .overlay(RoundedRectangle(cornerRadius: 8).stroke(Color.secondary.opacity(0.18)))
        .clipShape(RoundedRectangle(cornerRadius: 8))
    }

    private var bottomBar: some View {
        HStack(spacing: 8) {
            Button {
                onClose()
            } label: {
                Label(L10n.text("Close", language: language), systemImage: "xmark.circle")
            }

            Button {
                if appState.isRunning {
                    appState.cancelCurrentTask(unloadModel: true)
                } else if appState.quickActionMode == .image {
                    appState.runCurrentOCR()
                } else if appState.quickActionMode == .media {
                    appState.runCurrentMediaSubtitles()
                } else {
                    appState.runCurrentTask()
                }
            } label: {
                if appState.isRunning {
                    Label(L10n.text("Cancel", language: language), systemImage: "stop.fill")
                } else if appState.quickActionMode == .image {
                    Label(ocrRunButtonTitle, systemImage: ocrRunButtonIcon)
                } else if appState.quickActionMode == .media {
                    Label(mediaRunButtonTitle, systemImage: "waveform")
                } else {
                    Label(appState.outputText.isEmpty ? L10n.text("Run", language: language) : L10n.text("Regenerate", language: language), systemImage: appState.outputText.isEmpty ? "play.fill" : "arrow.clockwise")
                }
            }
            .disabled((appState.quickActionMode == .image && !appState.isRunning && !canRunOCR)
                || (appState.quickActionMode == .media && !appState.isRunning && !canRunMediaSubtitles))

            Button {
                NSPasteboard.general.clearContents()
                NSPasteboard.general.setString(displayedOutputText, forType: .string)
            } label: {
                Label(L10n.text("Copy", language: language), systemImage: "doc.on.doc")
            }
            .disabled(displayedOutputText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)

            Spacer()
            if let error = appState.validationError {
                Text(error)
                    .font(.caption)
                    .foregroundStyle(.red)
                    .lineLimit(1)
                    .help(error)
            } else {
                Text(appState.statusMessage)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
            WindowPinButton(pinState: pinState, language: language)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 9)
    }

    private var canRunOCR: Bool {
        appState.ocrImageInput != nil
            && appState.preferences.ocr.enabled
            && appState.selectedOCRModel != nil
            && !appState.isPreparingOCRImage
    }

    private var canRunMediaSubtitles: Bool {
        appState.mediaSubtitleFileURL != nil
            && appState.preferences.mediaSubtitles.isEnabled
            && appState.selectedFileASRModel != nil
    }

    private var ocrRunButtonTitle: String {
        if appState.outputText.isEmpty {
            return appState.ocrMode == .explainImage
                ? L10n.text("Explain Image", language: language)
                : L10n.text("Recognize", language: language)
        }
        return L10n.text("Regenerate", language: language)
    }

    private var ocrRunButtonIcon: String {
        if !appState.outputText.isEmpty {
            return "arrow.clockwise"
        }
        return appState.ocrMode == .explainImage ? "eye" : "text.viewfinder"
    }

    private var mediaRunButtonTitle: String {
        if appState.mediaSubtitleSegments.isEmpty {
            return L10n.text("Generate subtitles", language: language)
        }
        return L10n.text("Regenerate", language: language)
    }

    private var ocrFollowUpBar: some View {
        HStack(spacing: 6) {
            Text(L10n.text("Follow up", language: language))
                .font(.caption)
                .foregroundStyle(.secondary)
            ForEach(TaskKind.interactiveCases) { task in
                Button {
                    appState.sendOutputToTask(task)
                } label: {
                    Label(task.title(language: language), systemImage: followUpIcon(for: task))
                        .labelStyle(.iconOnly)
                        .frame(width: 26, height: 22)
                }
                .controlSize(.small)
                .help(task.title(language: language))
                .disabled(displayedOutputText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            }
            Spacer(minLength: 0)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func followUpIcon(for task: TaskKind) -> String {
        switch task {
        case .translate: return "character.book.closed"
        case .polish: return "wand.and.stars"
        case .summarize: return "doc.text"
        case .explain: return "questionmark.circle"
        case .extractTodos: return "list.bullet.clipboard"
        case .webPageTranslate, .ocr: return "arrow.right"
        }
    }

    private var outputDisplayOptions: some View {
        HStack(spacing: 10) {
            Spacer()
            if markdownPreviewAvailable {
                Button {
                    showsMarkdownSource.toggle()
                } label: {
                    Label(
                        L10n.text(showsMarkdownSource ? "Show Markdown preview" : "Show Markdown source", language: language),
                        systemImage: showsMarkdownSource ? "doc.richtext" : "curlybraces"
                    )
                }
                .buttonStyle(.borderless)
                .font(.caption)
                .foregroundStyle(.secondary)
            }

            if appState.hasDifferentRawOutput {
                Button {
                    appState.showsRawOutput.toggle()
                    showsMarkdownSource = false
                } label: {
                    Label(
                        L10n.text(appState.showsRawOutput ? "Show result" : "Show raw output", language: language),
                        systemImage: appState.showsRawOutput ? "text.badge.checkmark" : "curlybraces"
                    )
                }
                .buttonStyle(.borderless)
                .font(.caption)
                .foregroundStyle(.secondary)
            }
        }
    }

    private var inputPlaceholder: String {
        switch appState.selectedTask {
        case .translate:
            return L10n.text("Paste text to translate.", language: language)
        case .webPageTranslate:
            return L10n.text("Paste text to translate.", language: language)
        case .polish:
            return L10n.text("Paste text to polish.", language: language)
        case .summarize:
            return L10n.text("Paste text to summarize.", language: language)
        case .explain:
            return L10n.text("Paste text to explain.", language: language)
        case .extractTodos:
            return L10n.text("Paste text to extract TODOs.", language: language)
        case .ocr:
            return L10n.text("Drop or paste an image.", language: language)
        }
    }

    private var resultPlaceholder: String {
        if appState.quickActionMode == .image {
            return L10n.text("Image result will appear here.", language: language)
        }
        if appState.quickActionMode == .media {
            return L10n.text("Subtitle preview will appear here.", language: language)
        }
        switch appState.selectedTask {
        case .translate:
            return L10n.text("Translation will appear here.", language: language)
        case .webPageTranslate:
            return L10n.text("Translation will appear here.", language: language)
        case .polish:
            return L10n.text("Polished text will appear here.", language: language)
        case .summarize:
            return L10n.text("Summary will appear here.", language: language)
        case .explain:
            return L10n.text("Explanation will appear here.", language: language)
        case .extractTodos:
            return L10n.text("TODOs will appear here.", language: language)
        case .ocr:
            return L10n.text("Image result will appear here.", language: language)
        }
    }

    private func modelPickerTitle(_ model: ModelDescriptor) -> String {
        if model.isRemoteProvider {
            return "\(model.name) · \(model.providerDisplayName)"
        }
        return "\(model.name) · \(model.format.rawValue.uppercased()) · \(model.sizeClass)"
    }

    private func speechModelPickerTitle(_ model: ModelDescriptor) -> String {
        let modeLabel: String
        if model.capabilities.supportsRealtimeSpeech {
            modeLabel = L10n.text("Realtime", language: language)
        } else {
            modeLabel = L10n.text("File only", language: language)
        }
        let family = model.capabilities.speech?.family.rawValue ?? model.sizeClass
        return "\(model.name) · \(family) · \(modeLabel)"
    }

    private func subtitleModeName(_ mode: SubtitleDisplayMode) -> String {
        switch (language, mode) {
        case (.chinese, .original):
            return "原文"
        case (.chinese, .translated):
            return "译文"
        case (.chinese, .bilingual):
            return "双语"
        case (.english, .original):
            return "Original"
        case (.english, .translated):
            return "Translated"
        case (.english, .bilingual):
            return "Bilingual"
        }
    }

    private func mediaDescriptorLine(_ descriptor: MediaFileDescriptor) -> String {
        let sizeText: String
        if let size = descriptor.sizeBytes {
            sizeText = ByteCountFormatter.string(fromByteCount: size, countStyle: .file)
        } else {
            sizeText = "-"
        }
        let durationText: String
        if let duration = descriptor.duration {
            durationText = String(format: "%.1fs", duration)
        } else {
            durationText = "duration -"
        }
        return "\(descriptor.mediaKind) · \(descriptor.fileExtension) · \(sizeText) · \(durationText) · \(descriptor.redactedPathHash)"
    }

    private func handleDrop(_ providers: [NSItemProvider]) -> Bool {
        if appState.quickActionMode == .media {
            return handleFileDrop(providers) || handleTextDrop(providers) || handleImageDrop(providers)
        }
        if appState.quickActionMode == .image {
            return handleImageDrop(providers) || handleTextDrop(providers) || handleFileDrop(providers)
        }
        return handleTextDrop(providers) || handleImageDrop(providers) || handleFileDrop(providers)
    }

    private func handleTextDrop(_ providers: [NSItemProvider]) -> Bool {
        guard let provider = providers.first(where: { $0.canLoadObject(ofClass: NSString.self) }) else {
            return false
        }
        provider.loadObject(ofClass: NSString.self) { item, _ in
            guard let text = item as? String else {
                return
            }
            DispatchQueue.main.async {
                if appState.quickActionMode == .image,
                   text.trimmingCharacters(in: .whitespacesAndNewlines).hasPrefix("http") {
                    imageURLDraft = text.trimmingCharacters(in: .whitespacesAndNewlines)
                    appState.loadOCRImageFromRemoteURL(imageURLDraft)
                } else {
                    appState.setInputText(text, origin: .manual)
                    appState.statusMessage = L10n.text("Loaded dropped text", language: appState.preferences.appLanguage)
                }
            }
        }
        return true
    }

    private func handleImageDrop(_ providers: [NSItemProvider]) -> Bool {
        guard let provider = providers.first(where: { $0.canLoadObject(ofClass: NSImage.self) }) else {
            return false
        }
        provider.loadObject(ofClass: NSImage.self) { item, _ in
            guard let image = item as? NSImage,
                  let data = image.tiffRepresentation else {
                return
            }
            DispatchQueue.main.async {
                appState.loadOCRImageData(data, fileName: "dropped-image.tiff", sourceDescription: "Dropped image")
            }
        }
        return true
    }

    private func handleFileDrop(_ providers: [NSItemProvider]) -> Bool {
        guard let provider = providers.first(where: { $0.hasItemConformingToTypeIdentifier(UTType.fileURL.identifier) }) else {
            return false
        }
        provider.loadItem(forTypeIdentifier: UTType.fileURL.identifier, options: nil) { item, _ in
            let url: URL?
            if let data = item as? Data {
                url = URL(dataRepresentation: data, relativeTo: nil)
            } else {
                url = item as? URL
            }
            guard let url else {
                return
            }
            DispatchQueue.main.async {
                if isMediaFile(url) {
                    appState.loadMediaSubtitleFile(from: url)
                } else if isImageFile(url) {
                    appState.loadOCRImageFile(from: url)
                } else {
                    appState.loadInputFile(from: url)
                }
            }
        }
        return true
    }

    private func isImageFile(_ url: URL) -> Bool {
        guard let type = UTType(filenameExtension: url.pathExtension) else {
            return false
        }
        return type.conforms(to: .image)
    }

    private func isMediaFile(_ url: URL) -> Bool {
        MediaIntakeService.isSupportedMediaFile(url)
    }
}

private struct OCRImagePreviewSheet: View {
    let input: OCRImageInput
    let language: AppLanguage

    @Environment(\.dismiss) private var dismiss

    private var previewImage: NSImage? {
        NSImage(data: input.data)
    }

    private var title: String {
        input.fileName ?? input.sourceDescription
    }

    private var metadataText: String {
        var pieces: [String] = []
        if let pixelWidth = input.pixelWidth,
           let pixelHeight = input.pixelHeight {
            pieces.append("\(pixelWidth)x\(pixelHeight)")
        }
        pieces.append(input.mimeType)
        pieces.append(ByteCountFormatter.string(fromByteCount: Int64(input.byteCount), countStyle: .file))
        return pieces.joined(separator: " | ")
    }

    var body: some View {
        VStack(spacing: 0) {
            HStack(alignment: .center, spacing: 12) {
                VStack(alignment: .leading, spacing: 3) {
                    Text(title)
                        .font(.headline)
                        .lineLimit(1)
                        .truncationMode(.middle)
                    Text(metadataText)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }

                Spacer(minLength: 12)

                Button {
                    dismiss()
                } label: {
                    Image(systemName: "xmark")
                        .font(.system(size: 12, weight: .semibold))
                        .frame(width: 26, height: 26)
                        .contentShape(Circle())
                }
                .buttonStyle(.plain)
                .help(L10n.text("Close", language: language))
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 12)

            Divider()

            ZStack {
                Color(NSColor.textBackgroundColor)

                if let previewImage {
                    GeometryReader { proxy in
                        Image(nsImage: previewImage)
                            .resizable()
                            .scaledToFit()
                            .frame(width: proxy.size.width, height: proxy.size.height, alignment: .center)
                    }
                    .padding(14)
                } else {
                    Text(L10n.text("Image preview unavailable.", language: language))
                        .foregroundStyle(.secondary)
                        .padding(24)
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .frame(minWidth: 760, idealWidth: 900, minHeight: 540, idealHeight: 680)
        .background(Color(NSColor.windowBackgroundColor))
    }
}

struct EditableTextView: NSViewRepresentable {
    @Binding var text: String
    var onSubmit: (() -> Void)? = nil

    func makeCoordinator() -> Coordinator {
        Coordinator(text: $text, onSubmit: onSubmit)
    }

    func makeNSView(context: Context) -> NSScrollView {
        let scrollView = NSScrollView()
        scrollView.drawsBackground = false
        scrollView.hasVerticalScroller = true
        scrollView.borderType = .noBorder

        let textView = CommandFriendlyTextView()
        textView.delegate = context.coordinator
        textView.onSubmit = onSubmit
        textView.string = text
        textView.font = .systemFont(ofSize: NSFont.systemFontSize)
        textView.textColor = .labelColor
        textView.backgroundColor = .clear
        textView.drawsBackground = false
        textView.isEditable = true
        textView.isSelectable = true
        textView.allowsUndo = true
        textView.isRichText = false
        textView.importsGraphics = false
        textView.usesFindPanel = true
        textView.textContainerInset = NSSize(width: 10, height: 8)
        textView.textContainer?.lineFragmentPadding = 0
        textView.autoresizingMask = [.width]
        textView.minSize = NSSize(width: 0, height: 0)
        textView.maxSize = NSSize(width: CGFloat.greatestFiniteMagnitude, height: CGFloat.greatestFiniteMagnitude)
        textView.isVerticallyResizable = true
        textView.isHorizontallyResizable = false
        textView.textContainer?.widthTracksTextView = true

        scrollView.documentView = textView
        context.coordinator.textView = textView
        return scrollView
    }

    func updateNSView(_ scrollView: NSScrollView, context: Context) {
        guard let textView = scrollView.documentView as? NSTextView else {
            return
        }
        context.coordinator.onSubmit = onSubmit
        if let textView = textView as? CommandFriendlyTextView {
            textView.onSubmit = onSubmit
        }
        if textView.string != text {
            let selectedRanges = textView.selectedRanges
            textView.string = text
            textView.selectedRanges = selectedRanges
        }
    }

    final class Coordinator: NSObject, NSTextViewDelegate {
        @Binding var text: String
        weak var textView: NSTextView?
        var onSubmit: (() -> Void)?

        init(text: Binding<String>, onSubmit: (() -> Void)?) {
            _text = text
            self.onSubmit = onSubmit
        }

        func textDidChange(_ notification: Notification) {
            guard let textView = notification.object as? NSTextView else {
                return
            }
            text = textView.string
        }
    }
}

struct ReadOnlyTextView: NSViewRepresentable {
    var text: String

    func makeNSView(context: Context) -> NSScrollView {
        let scrollView = CommandFriendlyTextScrollView()
        scrollView.drawsBackground = false
        scrollView.hasVerticalScroller = true
        scrollView.borderType = .noBorder

        let textView = CommandFriendlyTextView()
        textView.copyFallbackText = text
        textView.string = text
        textView.font = .systemFont(ofSize: NSFont.systemFontSize)
        textView.textColor = .labelColor
        textView.backgroundColor = .clear
        textView.drawsBackground = false
        textView.isEditable = false
        textView.isSelectable = true
        textView.allowsUndo = false
        textView.isRichText = false
        textView.importsGraphics = false
        textView.usesFindPanel = true
        textView.textContainerInset = NSSize(width: 10, height: 8)
        textView.textContainer?.lineFragmentPadding = 0
        textView.autoresizingMask = [.width]
        textView.minSize = NSSize(width: 0, height: 0)
        textView.maxSize = NSSize(width: CGFloat.greatestFiniteMagnitude, height: CGFloat.greatestFiniteMagnitude)
        textView.isVerticallyResizable = true
        textView.isHorizontallyResizable = false
        textView.textContainer?.widthTracksTextView = true

        scrollView.documentView = textView
        return scrollView
    }

    func updateNSView(_ scrollView: NSScrollView, context: Context) {
        guard let textView = scrollView.documentView as? NSTextView else {
            return
        }

        if textView.string != text {
            let selectedRanges = textView.selectedRanges
            textView.string = text
            textView.selectedRanges = selectedRanges
        }
        if let textView = textView as? CommandFriendlyTextView {
            textView.copyFallbackText = text
        }
    }
}

private struct MediaSubtitleResultPreview: View {
    var segments: [SubtitleSegment]
    var mode: SubtitleDisplayMode
    var language: AppLanguage

    var body: some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: 8) {
                ForEach(Array(segments.enumerated()), id: \.element.id) { offset, segment in
                    segmentRow(segment, offset: offset)
                }
            }
            .padding(12)
            .frame(maxWidth: .infinity, alignment: .topLeading)
        }
        .textSelection(.enabled)
    }

    private func segmentRow(_ segment: SubtitleSegment, offset: Int) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(alignment: .center, spacing: 8) {
                Text(timeRange(segment))
                    .font(.caption.monospacedDigit())
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                if let speaker = normalized(segment.speakerLabel) ?? normalized(segment.speakerID) {
                    Text(speaker)
                        .font(.caption2.weight(.semibold))
                        .foregroundStyle(Color.accentColor)
                        .padding(.horizontal, 6)
                        .padding(.vertical, 2)
                        .background(Color.accentColor.opacity(0.10), in: RoundedRectangle(cornerRadius: 4))
                }
                Spacer(minLength: 0)
            }

            ForEach(Array(displayLines(for: segment).enumerated()), id: \.offset) { _, line in
                Text(line.text)
                    .font(.system(size: line.isSecondary ? 12 : 13, weight: line.isSecondary ? .regular : .medium))
                    .foregroundStyle(line.isSecondary ? Color.secondary : Color.primary)
                    .lineSpacing(3)
                    .fixedSize(horizontal: false, vertical: true)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 9)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(rowBackground(offset), in: RoundedRectangle(cornerRadius: 7))
        .overlay(RoundedRectangle(cornerRadius: 7).stroke(Color.secondary.opacity(0.12), lineWidth: 0.7))
    }

    private func rowBackground(_ offset: Int) -> Color {
        offset.isMultiple(of: 2)
            ? Color.secondary.opacity(0.055)
            : Color.secondary.opacity(0.025)
    }

    private struct DisplayLine {
        var text: String
        var isSecondary: Bool
    }

    private func displayLines(for segment: SubtitleSegment) -> [DisplayLine] {
        let original = normalized(segment.originalText) ?? ""
        let translated = normalized(segment.translatedText ?? "") ?? ""
        switch mode {
        case .original:
            return [DisplayLine(text: original.isEmpty ? " " : original, isSecondary: false)]
        case .translated:
            let text = translated.isEmpty ? original : translated
            return [DisplayLine(text: text.isEmpty ? " " : text, isSecondary: false)]
        case .bilingual:
            if translated.isEmpty || translated == original {
                return [DisplayLine(text: original.isEmpty ? " " : original, isSecondary: false)]
            }
            return [
                DisplayLine(text: original.isEmpty ? " " : original, isSecondary: false),
                DisplayLine(text: translated, isSecondary: true)
            ]
        }
    }

    private func timeRange(_ segment: SubtitleSegment) -> String {
        "\(timestamp(segment.startTime)) - \(timestamp(segment.endTime ?? (segment.startTime + 2)))"
    }

    private func timestamp(_ value: TimeInterval) -> String {
        let clamped = max(0, value)
        let hours = Int(clamped / 3600)
        let minutes = Int((clamped.truncatingRemainder(dividingBy: 3600)) / 60)
        let seconds = Int(clamped.truncatingRemainder(dividingBy: 60))
        let milliseconds = Int((clamped - floor(clamped)) * 1000)
        return String(format: "%02d:%02d:%02d.%03d", hours, minutes, seconds, milliseconds)
    }

    private func normalized(_ value: String?) -> String? {
        let trimmed = value?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        return trimmed.isEmpty ? nil : trimmed
    }
}

private struct MarkdownResultPreview: View {
    var markdown: String

    private enum Block {
        case heading(level: Int, text: String)
        case paragraph(String)
        case bullet(indent: Int, text: String)
        case numbered(indent: Int, marker: String, text: String)
        case quote(String)
        case code(language: String?, text: String)
        case table(rows: [[String]])
    }

    private var blocks: [Block] {
        Self.parse(markdown)
    }

    var body: some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: 8) {
                ForEach(Array(blocks.enumerated()), id: \.offset) { _, block in
                    blockView(block)
                }
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 10)
            .frame(maxWidth: .infinity, alignment: .topLeading)
        }
        .textSelection(.enabled)
    }

    @ViewBuilder
    private func blockView(_ block: Block) -> some View {
        switch block {
        case .heading(let level, let text):
            Self.inlineText(text)
                .font(headingFont(level: level))
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.top, level <= 2 ? 4 : 2)
        case .paragraph(let text):
            Self.inlineText(text)
                .font(.system(size: 13))
                .lineSpacing(3)
                .frame(maxWidth: .infinity, alignment: .leading)
        case .bullet(let indent, let text):
            HStack(alignment: .firstTextBaseline, spacing: 7) {
                Text("•")
                    .font(.system(size: 13, weight: .semibold))
                    .frame(width: 10, alignment: .trailing)
                Self.inlineText(text)
                    .font(.system(size: 13))
                    .lineSpacing(2)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
            .padding(.leading, CGFloat(indent) * 16)
        case .numbered(let indent, let marker, let text):
            HStack(alignment: .firstTextBaseline, spacing: 7) {
                Text(marker)
                    .font(.system(size: 13, weight: .medium))
                    .foregroundStyle(.secondary)
                    .frame(width: 28, alignment: .trailing)
                Self.inlineText(text)
                    .font(.system(size: 13))
                    .lineSpacing(2)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
            .padding(.leading, CGFloat(indent) * 16)
        case .quote(let text):
            HStack(alignment: .top, spacing: 8) {
                Rectangle()
                    .fill(Color.secondary.opacity(0.35))
                    .frame(width: 3)
                    .clipShape(Capsule())
                Self.inlineText(text)
                    .font(.system(size: 13))
                    .foregroundStyle(.secondary)
                    .lineSpacing(3)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
            .padding(.vertical, 2)
        case .code(let language, let text):
            VStack(alignment: .leading, spacing: 5) {
                if let language {
                    Text(language)
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }
                ScrollView(.horizontal) {
                    Text(text.isEmpty ? " " : text)
                        .font(.system(size: 12, design: .monospaced))
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(8)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Color.secondary.opacity(0.08), in: RoundedRectangle(cornerRadius: 6))
            .overlay(RoundedRectangle(cornerRadius: 6).stroke(Color.secondary.opacity(0.12)))
        case .table(let rows):
            MarkdownTablePreview(rows: rows)
        }
    }

    private func headingFont(level: Int) -> Font {
        switch level {
        case 1:
            return .system(size: 18, weight: .semibold)
        case 2:
            return .system(size: 16, weight: .semibold)
        case 3:
            return .system(size: 14, weight: .semibold)
        default:
            return .system(size: 13, weight: .semibold)
        }
    }

    static func looksLikeMarkdown(_ source: String) -> Bool {
        let lines = normalizedLines(source)
        for index in lines.indices {
            let trimmed = lines[index].trimmingCharacters(in: .whitespaces)
            if trimmed.isEmpty {
                continue
            }
            if parseHeadingLine(trimmed) != nil ||
                parseBulletLine(lines[index]) != nil ||
                parseNumberedLine(lines[index]) != nil ||
                trimmed.hasPrefix("> ") ||
                trimmed.hasPrefix("```") ||
                trimmed.contains("**") ||
                trimmed.contains("__") ||
                trimmed.contains("`") {
                return true
            }
            if index + 1 < lines.count,
               isTableCandidate(trimmed),
               isTableDivider(lines[index + 1]) {
                return true
            }
        }
        return false
    }

    private static func parse(_ source: String) -> [Block] {
        let lines = normalizedLines(source)
        var blocks: [Block] = []
        var paragraphLines: [String] = []
        var index = 0

        func flushParagraph() {
            let text = paragraphLines
                .joined(separator: "\n")
                .trimmingCharacters(in: .whitespacesAndNewlines)
            if !text.isEmpty {
                blocks.append(.paragraph(text))
            }
            paragraphLines.removeAll()
        }

        while index < lines.count {
            let line = lines[index]
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            if trimmed.isEmpty {
                flushParagraph()
                index += 1
                continue
            }

            if trimmed.hasPrefix("```") {
                flushParagraph()
                let fenceInfo = String(trimmed.dropFirst(3)).trimmingCharacters(in: .whitespaces)
                let language = fenceInfo.isEmpty ? nil : fenceInfo
                var codeLines: [String] = []
                index += 1
                while index < lines.count {
                    let codeLine = lines[index]
                    if codeLine.trimmingCharacters(in: .whitespaces).hasPrefix("```") {
                        index += 1
                        break
                    }
                    codeLines.append(codeLine)
                    index += 1
                }
                blocks.append(.code(language: language, text: codeLines.joined(separator: "\n")))
                continue
            }

            if let table = parseTable(at: index, in: lines) {
                flushParagraph()
                blocks.append(.table(rows: table.rows))
                index = table.nextIndex
                continue
            }

            if let heading = parseHeadingLine(trimmed) {
                flushParagraph()
                blocks.append(.heading(level: heading.level, text: heading.text))
                index += 1
                continue
            }

            if let bullet = parseBulletLine(line) {
                flushParagraph()
                blocks.append(.bullet(indent: bullet.indent, text: bullet.text))
                index += 1
                continue
            }

            if let numbered = parseNumberedLine(line) {
                flushParagraph()
                blocks.append(.numbered(indent: numbered.indent, marker: numbered.marker, text: numbered.text))
                index += 1
                continue
            }

            if trimmed.hasPrefix(">") {
                flushParagraph()
                var quoteLines: [String] = []
                while index < lines.count {
                    let quoteLine = lines[index].trimmingCharacters(in: .whitespaces)
                    guard quoteLine.hasPrefix(">") else {
                        break
                    }
                    quoteLines.append(String(quoteLine.dropFirst()).trimmingCharacters(in: .whitespaces))
                    index += 1
                }
                blocks.append(.quote(quoteLines.joined(separator: "\n")))
                continue
            }

            paragraphLines.append(line)
            index += 1
        }

        flushParagraph()
        return blocks
    }

    private static func normalizedLines(_ source: String) -> [String] {
        source
            .replacingOccurrences(of: "\r\n", with: "\n")
            .replacingOccurrences(of: "\r", with: "\n")
            .components(separatedBy: "\n")
    }

    private static func parseHeadingLine(_ line: String) -> (level: Int, text: String)? {
        var index = line.startIndex
        var level = 0
        while index < line.endIndex, line[index] == "#" {
            level += 1
            index = line.index(after: index)
        }
        guard level > 0,
              level <= 6,
              index < line.endIndex,
              line[index].isWhitespace else {
            return nil
        }
        let text = String(line[line.index(after: index)...])
            .trimmingCharacters(in: .whitespaces)
        return text.isEmpty ? nil : (level, text)
    }

    private static func parseBulletLine(_ line: String) -> (indent: Int, text: String)? {
        let leadingWhitespace = line.prefix { character in
            character == " " || character == "\t"
        }.count
        let trimmed = line.trimmingCharacters(in: .whitespaces)
        for marker in ["- ", "* ", "+ "] where trimmed.hasPrefix(marker) {
            let text = String(trimmed.dropFirst(marker.count))
                .trimmingCharacters(in: .whitespaces)
            return text.isEmpty ? nil : (leadingWhitespace / 2, text)
        }
        return nil
    }

    private static func parseNumberedLine(_ line: String) -> (indent: Int, marker: String, text: String)? {
        let leadingWhitespace = line.prefix { character in
            character == " " || character == "\t"
        }.count
        let trimmed = line.trimmingCharacters(in: .whitespaces)
        var index = trimmed.startIndex
        var digits = ""
        while index < trimmed.endIndex, trimmed[index].isNumber {
            digits.append(trimmed[index])
            index = trimmed.index(after: index)
        }
        guard !digits.isEmpty,
              index < trimmed.endIndex,
              trimmed[index] == "." || trimmed[index] == ")" else {
            return nil
        }
        let marker = "\(digits)\(trimmed[index])"
        let afterMarker = trimmed.index(after: index)
        guard afterMarker < trimmed.endIndex,
              trimmed[afterMarker].isWhitespace else {
            return nil
        }
        let textStart = trimmed.index(after: afterMarker)
        let text = String(trimmed[textStart...]).trimmingCharacters(in: .whitespaces)
        return text.isEmpty ? nil : (leadingWhitespace / 2, marker, text)
    }

    private static func parseTable(
        at index: Int,
        in lines: [String]
    ) -> (rows: [[String]], nextIndex: Int)? {
        guard index + 1 < lines.count else {
            return nil
        }
        let firstLine = lines[index].trimmingCharacters(in: .whitespaces)
        guard isTableCandidate(firstLine),
              isTableDivider(lines[index + 1]) else {
            return nil
        }

        var rows = [parseTableRow(firstLine)]
        var nextIndex = index + 2
        while nextIndex < lines.count {
            let line = lines[nextIndex].trimmingCharacters(in: .whitespaces)
            guard isTableCandidate(line), !isTableDivider(line) else {
                break
            }
            rows.append(parseTableRow(line))
            nextIndex += 1
        }

        guard let columnCount = rows.map(\.count).max(), columnCount >= 2 else {
            return nil
        }
        rows = rows.map { row in
            row + Array(repeating: "", count: max(0, columnCount - row.count))
        }
        return (rows, nextIndex)
    }

    private static func isTableCandidate(_ line: String) -> Bool {
        line.contains("|") && parseTableRow(line).count >= 2
    }

    private static func isTableDivider(_ line: String) -> Bool {
        let cells = parseTableRow(line)
        guard cells.count >= 2 else {
            return false
        }
        return cells.allSatisfy { cell in
            let compact = cell.replacingOccurrences(of: " ", with: "")
            return compact.count >= 3 && compact.allSatisfy { character in
                character == "-" || character == ":"
            }
        }
    }

    private static func parseTableRow(_ line: String) -> [String] {
        var value = line.trimmingCharacters(in: .whitespaces)
        if value.hasPrefix("|") {
            value.removeFirst()
        }
        if value.hasSuffix("|") {
            value.removeLast()
        }
        return value
            .split(separator: "|", omittingEmptySubsequences: false)
            .map { $0.trimmingCharacters(in: .whitespaces) }
    }

    private static func inlineText(_ text: String) -> Text {
        let options = AttributedString.MarkdownParsingOptions(
            interpretedSyntax: .inlineOnlyPreservingWhitespace
        )
        if let attributed = try? AttributedString(markdown: text, options: options) {
            return Text(attributed)
        }
        return Text(text)
    }

    private struct MarkdownTablePreview: View {
        var rows: [[String]]

        private var columnCount: Int {
            rows.map(\.count).max() ?? 0
        }

        var body: some View {
            ScrollView(.horizontal) {
                Grid(alignment: .leading, horizontalSpacing: 0, verticalSpacing: 0) {
                    ForEach(rows.indices, id: \.self) { rowIndex in
                        GridRow {
                            ForEach(0..<columnCount, id: \.self) { columnIndex in
                                let cell = columnIndex < rows[rowIndex].count ? rows[rowIndex][columnIndex] : ""
                                MarkdownResultPreview.inlineText(cell.isEmpty ? " " : cell)
                                    .font(.system(size: 12, weight: rowIndex == 0 ? .semibold : .regular))
                                    .lineLimit(nil)
                                    .frame(minWidth: 82, maxWidth: 180, alignment: .leading)
                                    .padding(.horizontal, 8)
                                    .padding(.vertical, 6)
                                    .background(rowIndex == 0 ? Color.secondary.opacity(0.10) : Color.clear)
                                    .overlay(
                                        Rectangle()
                                            .stroke(Color.secondary.opacity(0.16), lineWidth: 0.5)
                                    )
                            }
                        }
                    }
                }
                .clipShape(RoundedRectangle(cornerRadius: 6))
                .overlay(RoundedRectangle(cornerRadius: 6).stroke(Color.secondary.opacity(0.18)))
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }
}

private struct CompactSwitch: View {
    @Binding var isOn: Bool

    var body: some View {
        Button {
            isOn.toggle()
        } label: {
            ZStack(alignment: isOn ? .trailing : .leading) {
                RoundedRectangle(cornerRadius: 11, style: .continuous)
                    .fill(isOn ? Color.accentColor : Color.secondary.opacity(0.18))
                    .frame(width: 26, height: 16)
                Circle()
                    .fill(Color(NSColor.controlBackgroundColor))
                    .shadow(color: .black.opacity(0.16), radius: 1.5, y: 1)
                    .frame(width: 12, height: 12)
                    .padding(2)
            }
            .frame(width: 26, height: 16)
            .contentShape(Capsule())
        }
        .frame(width: 26, height: 16)
        .buttonStyle(.plain)
        .accessibilityLabel("Toggle")
        .accessibilityValue(isOn ? "On" : "Off")
    }
}

final class CommandFriendlyTextView: NSTextView {
    var onSubmit: (() -> Void)?
    var copyFallbackText: String?

    override func keyDown(with event: NSEvent) {
        if let onSubmit,
           event.keyCode == 36 || event.keyCode == 76,
           !event.modifierFlags.intersection(.deviceIndependentFlagsMask).contains(.shift),
           !hasMarkedText() {
            onSubmit()
            return
        }

        super.keyDown(with: event)
    }

    override func copy(_ sender: Any?) {
        if let copyFallbackText,
           !copyFallbackText.isEmpty,
           !selectedRanges.contains(where: { $0.rangeValue.length > 0 }) {
            NSPasteboard.general.clearContents()
            NSPasteboard.general.setString(copyFallbackText, forType: .string)
            return
        }

        super.copy(sender)
    }

    override func performKeyEquivalent(with event: NSEvent) -> Bool {
        guard event.modifierFlags.intersection(.deviceIndependentFlagsMask).contains(.command),
              let characters = event.charactersIgnoringModifiers?.lowercased() else {
            return super.performKeyEquivalent(with: event)
        }

        switch characters {
        case "a":
            selectAll(nil)
            return true
        case "c":
            copy(nil)
            return true
        case "v":
            paste(nil)
            return true
        case "x":
            cut(nil)
            return true
        case "z":
            if event.modifierFlags.contains(.shift) {
                undoManager?.redo()
            } else {
                undoManager?.undo()
            }
            return true
        default:
            return super.performKeyEquivalent(with: event)
        }
    }
}

private final class CommandFriendlyTextScrollView: NSScrollView {
    override var acceptsFirstResponder: Bool {
        true
    }

    override func mouseDown(with event: NSEvent) {
        if let textView = documentView as? NSTextView {
            window?.makeFirstResponder(textView)
        }
        super.mouseDown(with: event)
    }

    override func performKeyEquivalent(with event: NSEvent) -> Bool {
        guard event.modifierFlags.intersection(.deviceIndependentFlagsMask).contains(.command),
              let characters = event.charactersIgnoringModifiers?.lowercased(),
              let textView = documentView as? NSTextView else {
            return super.performKeyEquivalent(with: event)
        }

        switch characters {
        case "a":
            textView.selectAll(nil)
            return true
        case "c":
            textView.copy(nil)
            return true
        default:
            return super.performKeyEquivalent(with: event)
        }
    }
}

struct CommandFriendlyTextField: NSViewRepresentable {
    @Binding var text: String
    var placeholder: String
    var isSecure: Bool = false

    func makeCoordinator() -> Coordinator {
        Coordinator(text: $text)
    }

    func makeNSView(context: Context) -> NSTextField {
        let textField: NSTextField = isSecure ? CommandFriendlySecureTextField() : CommandFriendlyPlainTextField()
        textField.delegate = context.coordinator
        textField.stringValue = text
        textField.placeholderString = placeholder
        textField.isBordered = true
        textField.isBezeled = true
        textField.bezelStyle = .roundedBezel
        textField.drawsBackground = true
        textField.isEditable = true
        textField.isSelectable = true
        textField.font = .systemFont(ofSize: NSFont.systemFontSize)
        textField.lineBreakMode = .byTruncatingMiddle
        return textField
    }

    func updateNSView(_ textField: NSTextField, context: Context) {
        context.coordinator.text = $text
        if textField.stringValue != text {
            textField.stringValue = text
        }
        textField.placeholderString = placeholder
        textField.isEnabled = context.environment.isEnabled
    }

    final class Coordinator: NSObject, NSTextFieldDelegate {
        var text: Binding<String>

        init(text: Binding<String>) {
            self.text = text
        }

        func controlTextDidChange(_ notification: Notification) {
            guard let textField = notification.object as? NSTextField else {
                return
            }
            text.wrappedValue = textField.stringValue
        }
    }
}

private final class CommandFriendlyPlainTextField: NSTextField {
    override func performKeyEquivalent(with event: NSEvent) -> Bool {
        performCommandShortcut(event) || super.performKeyEquivalent(with: event)
    }
}

private final class CommandFriendlySecureTextField: NSSecureTextField {
    override func performKeyEquivalent(with event: NSEvent) -> Bool {
        performCommandShortcut(event) || super.performKeyEquivalent(with: event)
    }
}

private extension NSTextField {
    func performCommandShortcut(_ event: NSEvent) -> Bool {
        guard event.modifierFlags.intersection(.deviceIndependentFlagsMask).contains(.command),
              let characters = event.charactersIgnoringModifiers?.lowercased(),
              let editor = currentEditor() else {
            return false
        }

        switch characters {
        case "a":
            editor.selectAll(nil)
            return true
        case "c":
            editor.copy(nil)
            return true
        case "v":
            editor.paste(nil)
            return true
        case "x":
            editor.cut(nil)
            return true
        case "z":
            if event.modifierFlags.contains(.shift) {
                undoManager?.redo()
            } else {
                undoManager?.undo()
            }
            return true
        default:
            return false
        }
    }
}

struct FloatingWidgetView: View {
    @ObservedObject var appState: AppState
    @ObservedObject var pinState: WindowPinState

    private var language: AppLanguage {
        appState.preferences.appLanguage
    }

    private var displayedOutputText: String {
        appState.displayedOutputText
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text(L10n.text("Widget", language: language))
                    .font(.headline)
                Spacer()
                Text(appState.statusMessage)
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                WindowPinButton(pinState: pinState, language: language)
            }

            Picker(L10n.text("Task", language: language), selection: $appState.selectedTask) {
                ForEach(TaskKind.interactiveCases) { task in
                    Text(task.title(language: language)).tag(task)
                }
            }
            .pickerStyle(.menu)

            TaskOptionsView(appState: appState)
            ModelPickerView(appState: appState)

            EditableTextView(text: Binding(
                get: { appState.inputText },
                set: { newValue in
                    appState.setInputText(newValue, origin: .manual)
                }
            ))
                .frame(height: 180)
                .overlay(RoundedRectangle(cornerRadius: 10).stroke(Color.secondary.opacity(0.2)))
                .clipShape(RoundedRectangle(cornerRadius: 10))

            HStack {
                Button {
                    if appState.isRunning {
                        appState.cancelCurrentTask(unloadModel: true)
                    } else {
                        appState.runCurrentTask()
                    }
                } label: {
                    Label(
                        L10n.text(appState.isRunning ? "Cancel" : "Run", language: language),
                        systemImage: appState.isRunning ? "stop.fill" : "play.fill"
                    )
                }

                Button {
                    NSPasteboard.general.clearContents()
                    NSPasteboard.general.setString(displayedOutputText, forType: .string)
                } label: {
                    Label(L10n.text("Copy", language: language), systemImage: "doc.on.doc")
                }
                .disabled(displayedOutputText.isEmpty)

                Spacer()
            }

            if displayedOutputText.isEmpty {
                Text(L10n.text("Drop text or paste here.", language: language))
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .textSelection(.enabled)
            } else {
                ReadOnlyTextView(text: displayedOutputText)
            }

            if appState.hasDifferentRawOutput {
                Button {
                    appState.showsRawOutput.toggle()
                } label: {
                    Label(
                        L10n.text(appState.showsRawOutput ? "Show result" : "Show raw output", language: language),
                        systemImage: appState.showsRawOutput ? "text.badge.checkmark" : "curlybraces"
                    )
                }
                .buttonStyle(.borderless)
                .font(.caption)
                .foregroundStyle(.secondary)
            }
        }
        .padding(12)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .onDrop(of: [.fileURL, .plainText, .text], isTargeted: nil) { providers in
            handleDrop(providers)
        }
    }

    private func handleDrop(_ providers: [NSItemProvider]) -> Bool {
        handleTextDrop(providers) || handleFileDrop(providers)
    }

    private func handleTextDrop(_ providers: [NSItemProvider]) -> Bool {
        guard let provider = providers.first(where: { $0.canLoadObject(ofClass: NSString.self) }) else {
            return false
        }
        provider.loadObject(ofClass: NSString.self) { item, _ in
            guard let text = item as? String else {
                return
            }
            DispatchQueue.main.async {
                appState.setInputText(text, origin: .manual)
                appState.statusMessage = L10n.text("Loaded dropped text", language: appState.preferences.appLanguage)
            }
        }
        return true
    }

    private func handleFileDrop(_ providers: [NSItemProvider]) -> Bool {
        guard let provider = providers.first(where: { $0.hasItemConformingToTypeIdentifier(UTType.fileURL.identifier) }) else {
            return false
        }
        provider.loadItem(forTypeIdentifier: UTType.fileURL.identifier, options: nil) { item, _ in
            let url: URL?
            if let data = item as? Data {
                url = URL(dataRepresentation: data, relativeTo: nil)
            } else {
                url = item as? URL
            }
            guard let url else {
                return
            }
            DispatchQueue.main.async {
                appState.loadInputFile(from: url)
            }
        }
        return true
    }
}

struct LiveMeetingView: View {
    @ObservedObject var appState: AppState
    @ObservedObject var pinState: WindowPinState
    @State private var selectedMergeTargetBySpeaker: [String: String] = [:]
    @State private var speakerNameDrafts: [String: String] = [:]
    @State private var showFileImporter = false

    private var session: LiveMeetingSession? { appState.liveMeetingSession }
    private var isStopped: Bool {
        guard let state = session?.state else { return false }
        return state == .stopped || state == .restored || state == .failed
    }

    var body: some View {
        VStack(spacing: 0) {
            header
            Divider()
            if appState.liveMeetingRecoveryDraft != nil && session == nil {
                recoveryBanner
                Divider()
            }
            HSplitView {
                transcriptPanel
                    .frame(minWidth: 470, maxWidth: .infinity, maxHeight: .infinity)
                sidePanel
                    .frame(minWidth: 310, idealWidth: 350, maxWidth: 420, maxHeight: .infinity)
            }
        }
        .frame(minWidth: 760, minHeight: 520)
        .fileImporter(
            isPresented: $showFileImporter,
            allowedContentTypes: [.audio, .movie, .video],
            allowsMultipleSelection: false
        ) { result in
            if case .success(let urls) = result, let url = urls.first {
                appState.processLiveMeetingFile(url)
            }
        }
    }

    private var header: some View {
        HStack(spacing: 10) {
            VStack(alignment: .leading, spacing: 3) {
                Text("会议转写与纪要")
                    .font(.system(size: 17, weight: .semibold))
                Text(headerStatus)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
            Spacer()
            Picker("讲话人数", selection: Binding(
                get: { session?.speakerCountHint ?? appState.liveMeetingSpeakerCountHint },
                set: { appState.updateLiveMeetingSpeakerCountHint($0) }
            )) {
                ForEach(LiveMeetingSpeakerCountHint.allCases) { hint in
                    Text(hint.displayName).tag(hint)
                }
            }
            .labelsHidden()
            .pickerStyle(.menu)
            Picker("音频来源", selection: Binding(
                get: { appState.liveMeetingAudioSource },
                set: { appState.setLiveMeetingAudioSource($0) }
            )) {
                Text("麦克风").tag(LiveMeetingAudioSource.microphone)
                Text("系统音频").tag(LiveMeetingAudioSource.systemAudio)
            }
            .labelsHidden()
            .pickerStyle(.menu)
            .frame(width: 118, alignment: .leading)
            .disabled(appState.liveMeetingIsRunning)
            Button {
                showFileImporter = true
            } label: {
                Label("本地文件", systemImage: "folder")
            }
            .disabled(appState.liveMeetingIsRunning || appState.liveMeetingHasUnresolvedRecoveryDraft)
            if session?.state == .stopping {
                Button {
                    appState.cancelLiveMeetingStop()
                } label: {
                    Label("结束收尾", systemImage: "xmark.circle.fill")
                }
                .keyboardShortcut("r", modifiers: [.command, .shift])
                .help("保留当前转写并结束剩余处理")
            } else if appState.liveMeetingIsRunning {
                Button {
                    appState.stopLiveMeeting()
                } label: {
                    Label("停止", systemImage: "stop.fill")
                }
                .keyboardShortcut("r", modifiers: [.command, .shift])
            } else {
                Button {
                    appState.startLiveMeeting()
                } label: {
                    Label("开始转写", systemImage: "record.circle")
                }
                .disabled(appState.liveMeetingHasUnresolvedRecoveryDraft)
            }
            WindowPinButton(pinState: pinState, language: appState.preferences.appLanguage)
        }
        .padding(.horizontal, 18)
        .padding(.vertical, 13)
        .background(Color(nsColor: .windowBackgroundColor))
    }

    private var recoveryBanner: some View {
        HStack(spacing: 10) {
            Image(systemName: "arrow.clockwise.circle.fill")
                .foregroundStyle(.orange)
            Text("检测到未正常结束的本地会议草稿。草稿不包含临时音频。")
                .font(.caption)
            Spacer()
            Button("恢复草稿") { appState.restoreLiveMeetingRecoveryDraft() }
            Button("删除草稿", role: .destructive) { appState.deleteLiveMeetingRecoveryDraft() }
        }
        .padding(.horizontal, 18)
        .padding(.vertical, 10)
        .background(Color.orange.opacity(0.09))
    }

    private var transcriptPanel: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack {
                Text("完整转写")
                    .font(.headline)
                Spacer()
                if appState.liveMeetingASRInFlight {
                    ProgressView().controlSize(.small)
                    Text("正在本地处理").font(.caption).foregroundStyle(.secondary)
                }
                if let session, session.transcriptLagMilliseconds > 0 {
                    Text(transcriptLagLabel(session))
                        .font(.caption.monospacedDigit())
                        .foregroundStyle(.secondary)
                }
            }
            .padding(.horizontal, 18)
            .padding(.vertical, 12)

            if appState.liveMeetingLongSessionReminderVisible {
                Label("会议已达到 60 分钟。建议停止后最终整理并导出，会议不会自动停止。", systemImage: "clock.badge.exclamationmark")
                    .font(.caption)
                    .foregroundStyle(.orange)
                    .padding(.horizontal, 18)
                    .padding(.bottom, 9)
            }

            if appState.liveMeetingSegments.isEmpty {
                ContentUnavailableView(
                    "等待转写",
                    systemImage: "text.line.first.and.arrowtriangle.forward",
                    description: Text(emptyTranscriptDescription)
                )
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                List {
                    ForEach(appState.liveMeetingSegments) { segment in
                        meetingSegmentRow(segment)
                            .listRowInsets(EdgeInsets(top: 8, leading: 14, bottom: 8, trailing: 14))
                    }
                }
                .listStyle(.plain)
            }
        }
        .background(Color(nsColor: .textBackgroundColor).opacity(0.32))
    }

    private func meetingSegmentRow(_ segment: LiveMeetingSegment) -> some View {
        HStack(alignment: .top, spacing: 10) {
            Text(timestamp(segment.startTime))
                .font(.caption.monospacedDigit())
                .foregroundStyle(.secondary)
                .frame(width: 60, alignment: .leading)
            VStack(alignment: .leading, spacing: 5) {
                HStack(spacing: 6) {
                    Text(segment.speakerLabel ?? "Unknown")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(segment.state == .lowConfidence ? Color.orange : Color.accentColor)
                    if segment.state == .partial {
                        Text("草稿").font(.caption2).foregroundStyle(.secondary)
                    } else if segment.state == .lowConfidence {
                        Text("低置信").font(.caption2).foregroundStyle(.orange)
                    }
                    if segment.userEditedText {
                        Image(systemName: "pencil.circle.fill")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
                if segment.state == .partial {
                    Text(segment.text)
                        .font(.body)
                        .foregroundStyle(.secondary)
                } else {
                    TextField("", text: Binding(
                        get: { segment.text },
                        set: { appState.editLiveMeetingSegmentText(id: segment.id, text: $0) }
                    ), axis: .vertical)
                    .textFieldStyle(.plain)
                    .font(.body)
                    .lineLimit(2...)
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(5)
                    .background(Color(nsColor: .controlBackgroundColor))
                    .clipShape(RoundedRectangle(cornerRadius: 5))
                }
            }
        }
    }

    private var sidePanel: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                sessionCard
                speakerCard
                actionsCard
                notesCard
                diagnosticsCard
            }
            .padding(16)
        }
        .background(Color(nsColor: .windowBackgroundColor))
    }

    private var sessionCard: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("会话")
                .font(.headline)
            labeledValue("来源", session?.source.displayName ?? "未选择")
            labeledValue("ASR", session?.asrModelName ?? "未选择")
            labeledValue("识别策略", meetingRecognitionStrategyName)
            if let runtime = session?.diarizationRuntimeID {
                labeledValue("Speaker Runtime", runtime)
            }
            if let message = appState.liveMeetingDiarizationMessage ?? appState.liveMeetingDiarizationHealth?.message {
                Text(message).font(.caption2).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
            }
            Button("检查本地说话人分离") { appState.refreshLiveMeetingDiarizationHealth() }
                .controlSize(.small)
        }
    }

    private var speakerCard: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("讲话人")
                .font(.headline)
            if appState.liveMeetingSpeakers.isEmpty {
                Text(emptySpeakerMessage)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            } else {
                ForEach(appState.liveMeetingSpeakers.filter { $0.mergedIntoSpeakerID == nil }) { speaker in
                    VStack(alignment: .leading, spacing: 6) {
                        HStack {
                            TextField(
                                "讲话人名称",
                                text: Binding(
                                    get: { speakerNameDrafts[speaker.id] ?? speaker.renderedName },
                                    set: { speakerNameDrafts[speaker.id] = $0 }
                                )
                            )
                            .textFieldStyle(.roundedBorder)
                            Button {
                                appState.renameLiveMeetingSpeaker(id: speaker.id, name: speakerNameDrafts[speaker.id] ?? speaker.renderedName)
                            } label: {
                                Image(systemName: "checkmark")
                            }
                            .buttonStyle(.borderless)
                            .help("保存名称")
                        }
                        if appState.liveMeetingSpeakers.filter({ $0.id != speaker.id && $0.mergedIntoSpeakerID == nil }).isEmpty == false {
                            HStack(spacing: 6) {
                                Picker("合并到", selection: Binding(
                                    get: { selectedMergeTargetBySpeaker[speaker.id] ?? "" },
                                    set: { selectedMergeTargetBySpeaker[speaker.id] = $0 }
                                )) {
                                    Text("合并到...").tag("")
                                    ForEach(appState.liveMeetingSpeakers.filter { $0.id != speaker.id && $0.mergedIntoSpeakerID == nil }) { target in
                                        Text(target.renderedName).tag(target.id)
                                    }
                                }
                                .labelsHidden()
                                .pickerStyle(.menu)
                                Button {
                                    if let target = selectedMergeTargetBySpeaker[speaker.id], !target.isEmpty {
                                        appState.mergeLiveMeetingSpeaker(sourceID: speaker.id, into: target)
                                    }
                                } label: {
                                    Image(systemName: "arrow.triangle.merge")
                                }
                                .disabled((selectedMergeTargetBySpeaker[speaker.id] ?? "").isEmpty)
                                .help("合并讲话人")
                            }
                        }
                    }
                    .padding(.bottom, 3)
                }
            }
        }
    }

    private var actionsCard: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("停止后操作")
                .font(.headline)
            HStack(spacing: 8) {
                Button {
                    appState.liveMeetingFinalizeTaskIsRunning ? appState.cancelLiveMeetingFinalization() : appState.finalizeLiveMeeting()
                } label: {
                    Label(appState.liveMeetingFinalizeTaskIsRunning ? "取消整理" : "最终整理", systemImage: appState.liveMeetingFinalizeTaskIsRunning ? "xmark" : "wand.and.stars")
                }
                .disabled(!isStopped && !appState.liveMeetingFinalizeTaskIsRunning)
                Button {
                    appState.liveMeetingNotesTaskIsRunning ? appState.cancelLiveMeetingNotes() : appState.generateLiveMeetingNotes()
                } label: {
                    Label(appState.liveMeetingNotesTaskIsRunning ? "取消纪要" : "生成纪要", systemImage: appState.liveMeetingNotesTaskIsRunning ? "xmark" : "note.text.badge.plus")
                }
                .disabled((!appState.liveMeetingCanGenerateNotes && !appState.liveMeetingNotesTaskIsRunning) || (!isStopped && !appState.liveMeetingNotesTaskIsRunning))
            }
            if let disabled = appState.liveMeetingNotesDisabledMessage {
                Text(disabled)
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Menu {
                Button("Markdown") { appState.exportLiveMeetingToDownloads(format: "markdown") }
                Button("TXT") { appState.exportLiveMeetingToDownloads(format: "txt") }
                Button("JSON") { appState.exportLiveMeetingToDownloads(format: "json") }
            } label: {
                Label("导出", systemImage: "square.and.arrow.up")
            }
            .disabled(!isStopped)
        }
    }

    private var notesCard: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text("中文会议纪要")
                    .font(.headline)
                Spacer()
                if appState.liveMeetingNotes?.isStale == true {
                    Text("需重新生成").font(.caption2).foregroundStyle(.orange)
                }
            }
            if let notes = appState.liveMeetingNotes, notes.hasContent {
                noteSection("摘要", notes.summary)
                noteList("关键决策", notes.decisions)
                noteList("待办事项", notes.actionItems)
                noteList("开放问题", notes.openQuestions)
                noteList("讨论主题", notes.topics)
                Text("本地分块：\(notes.chunkCount) 段")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            } else {
                Text("停止后手动生成。不会使用远程文本 provider。")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    private var diagnosticsCard: some View {
        VStack(alignment: .leading, spacing: 5) {
            Text("状态")
                .font(.headline)
            Text(appState.liveMeetingStatusMessage ?? "就绪")
                .font(.caption)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
            if let diagnostics = appState.liveMeetingDiagnostics {
                Text("\(diagnostics.transcriptSegmentCount) 段 · \(diagnostics.speakerCount) 位讲话人 · \(diagnostics.durationBucket)")
                    .font(.caption2.monospacedDigit())
                    .foregroundStyle(.secondary)
            }
        }
    }

    private func labeledValue(_ label: String, _ value: String) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 8) {
            Text(label).font(.caption).foregroundStyle(.secondary).frame(width: 74, alignment: .leading)
            Text(value).font(.caption).lineLimit(1).truncationMode(.middle)
        }
    }

    private var meetingRecognitionStrategyName: String {
        switch session?.recognitionStrategy {
        case .nativeSpeakerASR: return "原生转写 + 说话人"
        case .delayedSpeakerLabels: return "先转写，后补说话人"
        case .diarizationFirst: return "先分离说话人，再转写"
        case .transcriptOnly: return "仅转写"
        case nil: return "尚未开始"
        }
    }

    private var emptySpeakerMessage: String {
        switch session?.recognitionStrategy {
        case .nativeSpeakerASR:
            return "speaker 会在明显停顿、120 秒技术窗口或停止后随转写一起输出。"
        case .delayedSpeakerLabels:
            return "文字会在自然停顿后先输出；speaker 由本地 pyannote 在后台延迟回填。"
        case .diarizationFirst:
            return "本地文件会先按稳定 speaker turn 切分音频，再逐段转写。"
        case .transcriptOnly:
            return "当前为仅转写模式。仍可编辑文本、生成纪要、导出和恢复草稿。"
        case nil:
            return "开始会议或导入本地文件后，这里会显示识别出的讲话人。"
        }
    }

    private var emptyTranscriptDescription: String {
        switch session?.recognitionStrategy {
        case .nativeSpeakerASR:
            return "明显停顿后开始处理；连续讲话按 120 秒技术窗口分批推理，逻辑讲话仍按自然边界整理。"
        case .delayedSpeakerLabels:
            return "转写在自然停顿后先输出，连续讲话最迟约 30 秒提交；speaker 随后回填。"
        case .diarizationFirst:
            return "本地文件正在按 speaker turn 分段转写。"
        case .transcriptOnly:
            return "当前讲话会在自然停顿后整理，连续讲话最迟约 30 秒提交。"
        case nil:
            return "开始会议，或选择本地音频/视频文件。"
        }
    }

    private func transcriptLagLabel(_ session: LiveMeetingSession) -> String {
        let lag = timestamp(Double(session.transcriptLagMilliseconds) / 1_000)
        switch session.recognitionStrategy ?? .transcriptOnly {
        case .nativeSpeakerASR:
            if session.transcriptLagMilliseconds >= LiveMeetingNativeBatchPolicy.preferredBatchMilliseconds {
                return "已采集 \(lag)，等待下一次自然停顿"
            }
            return "已采集 \(lag)，等待明显停顿"
        case .delayedSpeakerLabels:
            if session.transcriptLagMilliseconds > 0 {
                return "待转写 \(lag)"
            }
            if session.speakerLagMilliseconds > 0, !appState.liveMeetingSegments.isEmpty {
                return "说话人待回填 \(timestamp(Double(session.speakerLagMilliseconds) / 1_000))"
            }
            return appState.liveMeetingSegments.isEmpty ? "等待讲话" : "转写已跟上"
        case .diarizationFirst:
            return "待稳定处理 \(lag)"
        case .transcriptOnly:
            return "当前讲话 \(lag)，等待停顿"
        }
    }

    private func noteSection(_ title: String, _ text: String) -> some View {
        VStack(alignment: .leading, spacing: 3) {
            Text(title).font(.caption.weight(.semibold))
            Text(text).font(.caption).fixedSize(horizontal: false, vertical: true)
        }
    }

    private func noteList(_ title: String, _ values: [String]) -> some View {
        VStack(alignment: .leading, spacing: 3) {
            Text(title).font(.caption.weight(.semibold))
            if values.isEmpty {
                Text("暂无").font(.caption).foregroundStyle(.secondary)
            } else {
                ForEach(Array(values.enumerated()), id: \.offset) { _, value in
                    Text("- \(value)").font(.caption).fixedSize(horizontal: false, vertical: true)
                }
            }
        }
    }

    private var headerStatus: String {
        guard let session else { return "本地 ASR、说话人分离与本地中文纪要" }
        switch session.state {
        case .starting: return "正在启动 \(session.source.displayName)"
        case .running:
            switch session.source {
            case .microphone: return "正在转写麦克风，按停顿整理段落"
            case .systemAudio: return "正在转写系统音频，按停顿整理段落"
            case .localFile: return "正在处理 Local File"
            }
        case .stopping: return "采集已停止，正在处理剩余内容"
        case .stopped: return "已停止，可手动最终整理、生成纪要或导出"
        case .restored: return "已从本地草稿恢复"
        case .failed: return "会话需要处理"
        case .idle: return "就绪"
        }
    }

    private func timestamp(_ value: TimeInterval) -> String {
        let total = max(0, Int(value.rounded(.down)))
        return String(format: "%02d:%02d:%02d", total / 3600, (total % 3600) / 60, total % 60)
    }
}

struct LiveSubtitleFloatingView: View {
    @ObservedObject var appState: AppState
    @ObservedObject var pinState: WindowPinState
    var onClose: () -> Void

    private var language: AppLanguage {
        appState.preferences.appLanguage
    }

    private var backgroundOpacity: Double {
        appState.preferences.mediaSubtitles.liveWindowOpacity
    }

    private var targetLanguageIsActive: Bool {
        appState.appLiveSubtitleDisplayMode != .original
    }

    private var liveSubtitleMinimumHeight: CGFloat {
        appState.appLiveSubtitleIsImmersive
            ? immersiveWindowHeight
            : CGFloat(MediaSubtitlePreferences.minimumLiveWindowHeight)
    }

    private var liveSubtitleIdealHeight: CGFloat {
        appState.appLiveSubtitleIsImmersive
            ? immersiveWindowHeight
            : CGFloat(MediaSubtitlePreferences.defaultLiveWindowHeight)
    }

    private var immersiveWindowHeight: CGFloat {
        appState.appLiveSubtitleDisplayMode == .bilingual ? 128 : 96
    }

    private var scrollBottomID: String {
        "live-subtitle-scroll-bottom"
    }

    var body: some View {
        ZStack(alignment: .topTrailing) {
            if appState.appLiveSubtitleIsImmersive {
                immersiveSubtitleLines
            } else {
                standardSubtitleWindow
            }
            if appState.appLiveSubtitleIsImmersive {
                immersiveWindowButtons
                    .padding(.top, 7)
                    .padding(.trailing, 8)
            }
        }
        .frame(
            minWidth: CGFloat(MediaSubtitlePreferences.minimumLiveWindowWidth),
            idealWidth: CGFloat(MediaSubtitlePreferences.defaultLiveWindowWidth),
            maxWidth: .infinity,
            minHeight: liveSubtitleMinimumHeight,
            idealHeight: liveSubtitleIdealHeight,
            maxHeight: appState.appLiveSubtitleIsImmersive ? liveSubtitleIdealHeight : .infinity
        )
        .background(Color.black.opacity(backgroundOpacity), in: RoundedRectangle(cornerRadius: 8))
        .overlay(
            RoundedRectangle(cornerRadius: 8)
                .stroke(Color.white.opacity(0.16 * backgroundOpacity), lineWidth: 0.8)
        )
        .shadow(color: .black.opacity(0.26 * backgroundOpacity), radius: 10, y: 4)
    }

    private var standardSubtitleWindow: some View {
        VStack(spacing: 0) {
            chrome
                .padding(.horizontal, 10)
                .padding(.top, 6)
                .padding(.bottom, 6)

            Rectangle()
                .fill(Color.white.opacity(0.10))
                .frame(height: 0.8)

            subtitleLines
        }
    }

    private var chrome: some View {
        HStack(alignment: .center, spacing: 8) {
            Label(statusTitle, systemImage: sourceIcon)
                .font(.system(size: 11, weight: .medium))
                .foregroundStyle(.white.opacity(0.72))
                .lineLimit(1)
                .minimumScaleFactor(0.72)
                .frame(maxWidth: .infinity, alignment: .leading)
                .layoutPriority(0)
            HStack(spacing: 6) {
                realtimeASRPicker
                targetLanguagePicker
                sourceLanguagePicker
                displayModePicker
                audioSourcePicker
            }
            .foregroundStyle(.white)
            .layoutPriority(2)
            WindowPinButton(
                pinState: pinState,
                language: language,
                appearance: .subtitle
            )
            enterImmersiveButton
            liveSubtitleToggleButton
            closeButton
        }
    }

    private var realtimeASRPicker: some View {
        Menu {
            Button {
                appState.setRealtimeASRModel(id: nil)
            } label: {
                liveSubtitleMenuItem(
                    L10n.text("No model", language: language),
                    selected: appState.preferences.mediaSubtitles.realtimeASRModelID == nil
                )
            }
            ForEach(appState.realtimeSpeechModels) { model in
                Button {
                    appState.setRealtimeASRModel(id: model.id)
                } label: {
                    liveSubtitleMenuItem(
                        AppState.condensedModelName(model.name, limit: 36),
                        selected: appState.preferences.mediaSubtitles.realtimeASRModelID == model.id
                    )
                }
            }
        } label: {
            liveSubtitleControlLabel(currentASRModelName, width: 164)
        }
        .buttonStyle(.plain)
        .disabled(appState.realtimeSpeechModels.isEmpty)
        .help("\(L10n.text("Realtime ASR", language: language)): \(currentASRModelName)")
    }

    private var targetLanguagePicker: some View {
        Menu {
            ForEach(["zh-Hans", "en", "Japanese", "Korean"], id: \.self) { targetLanguage in
                Button {
                    appState.setMediaSubtitleTargetLanguage(targetLanguage)
                } label: {
                    liveSubtitleMenuItem(
                        L10n.targetLanguageName(targetLanguage, language: language),
                        selected: appState.preferences.mediaSubtitles.defaultTargetLanguage == targetLanguage
                    )
                }
            }
        } label: {
            liveSubtitleControlLabel(
                L10n.targetLanguageName(appState.preferences.mediaSubtitles.defaultTargetLanguage, language: language),
                width: 58
            )
        }
        .buttonStyle(.plain)
        .disabled(!targetLanguageIsActive)
        .help(targetLanguageIsActive
            ? L10n.text("Target", language: language)
            : L10n.text("Target language applies when Display is Translated or Bilingual.", language: language)
        )
    }

    private var sourceLanguagePicker: some View {
        Menu {
            ForEach(ASRSourceLanguageHint.allCases) { hint in
                Button {
                    appState.setMediaSubtitleSourceLanguageHint(hint)
                } label: {
                    liveSubtitleMenuItem(
                        sourceLanguageHintName(hint),
                        selected: appState.preferences.mediaSubtitles.sourceLanguageHint == hint
                    )
                }
            }
        } label: {
            liveSubtitleControlLabel(
                sourceLanguageHintName(appState.preferences.mediaSubtitles.sourceLanguageHint),
                width: 68
            )
        }
        .buttonStyle(.plain)
        .help(L10n.text("Source language", language: language))
    }

    private var displayModePicker: some View {
        HStack(spacing: 2) {
            ForEach(SubtitleDisplayMode.allCases) { mode in
                Button {
                    appState.setMediaSubtitleMode(mode)
                } label: {
                    Text(subtitleModeName(mode))
                        .font(.system(size: 10, weight: .medium))
                        .foregroundStyle(.white)
                        .lineLimit(1)
                        .minimumScaleFactor(0.76)
                        .frame(maxWidth: .infinity, minHeight: 18)
                        .padding(.horizontal, 4)
                        .background(
                            RoundedRectangle(cornerRadius: 4)
                                .fill(mode == appState.appLiveSubtitleDisplayMode ? Color.white.opacity(0.22) : Color.clear)
                        )
                }
                .buttonStyle(.plain)
            }
        }
        .padding(2)
        .frame(width: 126, height: 22)
        .background(liveSubtitleControlBackground)
        .clipShape(RoundedRectangle(cornerRadius: 5))
        .help(L10n.text("Display", language: language))
    }

    private var audioSourcePicker: some View {
        Menu {
            ForEach(LiveSubtitleAudioSource.allCases) { source in
                Button {
                    appState.setLiveSubtitleAudioSource(source)
                } label: {
                    liveSubtitleMenuItem(
                        liveAudioSourceName(source),
                        selected: appState.appLiveSubtitleAudioSource == source
                    )
                }
            }
        } label: {
            liveSubtitleControlLabel(liveAudioSourceName(appState.appLiveSubtitleAudioSource), width: 112)
        }
        .buttonStyle(.plain)
        .help(L10n.text("Audio source", language: language))
    }

    private var liveSubtitleControlBackground: some ShapeStyle {
        Color.white.opacity(0.12)
    }

    private func liveSubtitleControlLabel(_ title: String, width: CGFloat) -> some View {
        HStack(spacing: 4) {
            Text(title)
                .font(.system(size: 10, weight: .medium))
                .foregroundStyle(.white)
                .lineLimit(1)
                .minimumScaleFactor(0.72)
            Image(systemName: "chevron.down")
                .font(.system(size: 7, weight: .bold))
                .foregroundStyle(.white.opacity(0.78))
        }
        .frame(width: width, height: 22)
        .padding(.horizontal, 7)
        .background(liveSubtitleControlBackground)
        .clipShape(RoundedRectangle(cornerRadius: 5))
    }

    private func liveSubtitleMenuItem(_ title: String, selected: Bool) -> some View {
        HStack {
            Text(title)
            Spacer()
            if selected {
                Image(systemName: "checkmark")
            }
        }
    }

    private var liveSubtitleToggleButton: some View {
        Button {
            Task { @MainActor in
                if appState.appLiveSubtitlesAreRunning {
                    _ = await appState.stopAppLiveSubtitles()
                } else {
                    _ = try? await appState.startAppLiveSubtitles()
                }
            }
        } label: {
            Image(systemName: appState.appLiveSubtitlesAreRunning ? "stop.fill" : "play.fill")
                .font(.system(size: 11, weight: .semibold))
        }
        .buttonStyle(.borderless)
        .foregroundStyle(.white.opacity(0.82))
        .help(L10n.text(appState.appLiveSubtitlesAreRunning ? "Stop live subtitles" : "Start live subtitles", language: language))
    }

    private var enterImmersiveButton: some View {
        Button {
            appState.setLiveSubtitleImmersive(true)
        } label: {
            Image(systemName: "rectangle.compress.vertical")
                .font(.system(size: 11, weight: .semibold))
        }
        .buttonStyle(.borderless)
        .foregroundStyle(.white.opacity(0.82))
        .help(L10n.text("Enter immersive subtitles", language: language))
    }

    private var exitImmersiveButton: some View {
        Button {
            appState.setLiveSubtitleImmersive(false)
        } label: {
            immersiveButtonIcon("arrow.down.right.and.arrow.up.left")
        }
        .buttonStyle(.plain)
        .foregroundStyle(.white.opacity(0.86))
        .help(L10n.text("Exit immersive subtitles", language: language))
    }

    private var immersiveCloseButton: some View {
        Button {
            onClose()
        } label: {
            immersiveButtonIcon("xmark")
        }
        .buttonStyle(.plain)
        .foregroundStyle(.white.opacity(0.86))
        .help(L10n.text("Close", language: language))
    }

    private var immersiveWindowButtons: some View {
        HStack(spacing: 6) {
            WindowPinButton(
                pinState: pinState,
                language: language,
                appearance: .immersiveSubtitle
            )
            exitImmersiveButton
            immersiveCloseButton
        }
    }

    private func immersiveButtonIcon(_ systemName: String) -> some View {
        Image(systemName: systemName)
            .font(.system(size: 11, weight: .bold))
            .frame(width: 26, height: 26)
            .background(Color.black.opacity(0.38), in: Circle())
            .overlay(Circle().stroke(Color.white.opacity(0.16), lineWidth: 0.8))
    }

    private var closeButton: some View {
        Button {
            onClose()
        } label: {
            Image(systemName: "xmark")
                .font(.system(size: 11, weight: .bold))
        }
        .buttonStyle(.borderless)
        .foregroundStyle(.white.opacity(0.72))
        .help(L10n.text("Close", language: language))
    }

    @ViewBuilder
    private var immersiveSubtitleLines: some View {
        if appState.appLiveSubtitleDisplayMode == .bilingual {
            VStack(alignment: .center, spacing: 5) {
                immersiveTextLine(immersivePreviousTranslatedText, size: 16, weight: .medium, opacity: 0.62)
                immersiveTextLine(immersiveCurrentOriginalText, size: 20, weight: .semibold, opacity: 0.95)
                immersiveTextLine(immersiveCurrentTranslatedText, size: 18, weight: .semibold, opacity: 0.82)
            }
            .padding(.horizontal, 82)
            .padding(.vertical, 12)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        } else {
            VStack(alignment: .center, spacing: 6) {
                immersiveTextLine(immersivePreviousDisplayText, size: 17, weight: .medium, opacity: 0.62)
                immersiveTextLine(immersiveCurrentDisplayText, size: 22, weight: .semibold, opacity: 0.96)
            }
            .padding(.horizontal, 82)
            .padding(.vertical, 12)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
    }

    private func immersiveTextLine(
        _ text: String,
        size: CGFloat,
        weight: Font.Weight,
        opacity: Double
    ) -> some View {
        Text(text.isEmpty ? " " : text)
            .font(.system(size: size, weight: weight))
            .foregroundStyle(.white.opacity(text.isEmpty ? 0 : opacity))
            .lineLimit(1)
            .minimumScaleFactor(0.72)
            .truncationMode(.tail)
            .multilineTextAlignment(.center)
            .frame(maxWidth: .infinity, minHeight: size + 8)
            .textSelection(.enabled)
    }

    private var immersivePreviousSegment: SubtitleSegment? {
        if hasDraftSubtitle {
            return appState.appLiveSubtitleHistory.last
        }
        return appState.appLiveSubtitleHistory.dropLast().last
    }

    private var immersivePreviousDisplayText: String {
        guard let segment = immersivePreviousSegment else {
            return ""
        }
        return subtitleTexts(original: segment.originalText, translated: segment.translatedText).primary
    }

    private var immersivePreviousTranslatedText: String {
        guard let segment = immersivePreviousSegment else {
            return ""
        }
        let translated = trimmed(segment.translatedText ?? "")
        return translated.isEmpty ? trimmed(segment.originalText) : translated
    }

    private var immersiveCurrentDisplayText: String {
        primarySubtitleText
    }

    private var immersiveCurrentOriginalText: String {
        let original = trimmed(appState.appLiveSubtitleOriginalText)
        return original.isEmpty ? listeningText : original
    }

    private var immersiveCurrentTranslatedText: String {
        trimmed(appState.appLiveSubtitleTranslatedText)
    }

    @ViewBuilder
    private var subtitleLines: some View {
        ScrollViewReader { proxy in
            ScrollView(.vertical) {
                VStack(alignment: .center, spacing: 12) {
                    if appState.appLiveSubtitleHistory.isEmpty && !hasDraftSubtitle {
                        liveSubtitleTextBlock(
                            primary: primarySubtitleText,
                            secondary: secondarySubtitleText,
                            isDraft: appState.appLiveSubtitleIsPartial
                        )
                    } else {
                        ForEach(appState.appLiveSubtitleHistory) { segment in
                            let texts = subtitleTexts(
                                original: segment.originalText,
                                translated: segment.translatedText
                            )
                            liveSubtitleTextBlock(
                                primary: texts.primary,
                                secondary: texts.secondary,
                                isDraft: false
                            )
                            .id(segment.id)
                        }
                        if hasDraftSubtitle {
                            liveSubtitleTextBlock(
                                primary: draftSubtitleTexts.primary,
                                secondary: draftSubtitleTexts.secondary,
                                isDraft: true
                            )
                            .id("live-subtitle-draft")
                        }
                    }
                    Color.clear
                        .frame(height: 1)
                        .id(scrollBottomID)
                }
                .frame(maxWidth: .infinity)
                .padding(.horizontal, 46)
                .padding(.top, 12)
                .padding(.bottom, 16)
            }
            .onAppear {
                scrollToLiveSubtitleBottom(proxy)
            }
            .onChange(of: appState.appLiveSubtitleHistory) { _, _ in
                scrollToLiveSubtitleBottom(proxy)
            }
            .onChange(of: appState.appLiveSubtitleOriginalText) { _, _ in
                scrollToLiveSubtitleBottom(proxy)
            }
            .onChange(of: appState.appLiveSubtitleTranslatedText) { _, _ in
                scrollToLiveSubtitleBottom(proxy)
            }
        }
    }

    private func liveSubtitleTextBlock(primary: String, secondary: String?, isDraft: Bool) -> some View {
        VStack(alignment: .center, spacing: 4) {
            Text(primary)
                .font(.system(size: 22, weight: .semibold))
                .foregroundStyle(.white.opacity(isDraft ? 0.78 : 1))
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)
                .frame(maxWidth: .infinity)
                .textSelection(.enabled)
            if let secondary {
                Text(secondary)
                    .font(.system(size: 14, weight: .medium))
                    .foregroundStyle(.white.opacity(isDraft ? 0.58 : 0.74))
                    .multilineTextAlignment(.center)
                    .fixedSize(horizontal: false, vertical: true)
                    .frame(maxWidth: .infinity)
                    .textSelection(.enabled)
            }
        }
    }

    private func scrollToLiveSubtitleBottom(_ proxy: ScrollViewProxy) {
        DispatchQueue.main.async {
            withAnimation(.easeOut(duration: 0.16)) {
                proxy.scrollTo(scrollBottomID, anchor: .bottom)
            }
        }
    }

    private var primarySubtitleText: String {
        let texts = subtitleTexts(
            original: appState.appLiveSubtitleOriginalText,
            translated: appState.appLiveSubtitleTranslatedText
        )
        guard !texts.primary.isEmpty else {
            return listeningText
        }
        return texts.primary
    }

    private var secondarySubtitleText: String? {
        subtitleTexts(
            original: appState.appLiveSubtitleOriginalText,
            translated: appState.appLiveSubtitleTranslatedText
        ).secondary
    }

    private var hasDraftSubtitle: Bool {
        appState.appLiveSubtitleIsPartial
            && (!trimmed(appState.appLiveSubtitleOriginalText).isEmpty
                || !trimmed(appState.appLiveSubtitleTranslatedText).isEmpty)
    }

    private var draftSubtitleTexts: (primary: String, secondary: String?) {
        let texts = subtitleTexts(
            original: appState.appLiveSubtitleOriginalText,
            translated: appState.appLiveSubtitleTranslatedText
        )
        return (texts.primary.isEmpty ? listeningText : texts.primary, texts.secondary)
    }

    private func subtitleTexts(original rawOriginal: String, translated rawTranslated: String?) -> (primary: String, secondary: String?) {
        let original = trimmed(rawOriginal)
        let translated = trimmed(rawTranslated ?? "")
        switch appState.appLiveSubtitleDisplayMode {
        case .original:
            return (original, nil)
        case .translated:
            if !translated.isEmpty {
                return (translated, nil)
            }
            return (original, nil)
        case .bilingual:
            if !translated.isEmpty {
                let secondary = (!original.isEmpty && translated != original) ? original : nil
                return (translated, secondary)
            }
            return (original, nil)
        }
    }

    private var listeningText: String {
        switch appState.appLiveSubtitleRunState {
        case .starting:
            return L10n.text("Starting live subtitles", language: language)
        case .running:
            if appState.appLiveSubtitleASRInFlight {
                return L10n.text("Transcribing...", language: language)
            }
            if let message = appState.appLiveSubtitleMessage?.trimmingCharacters(in: .whitespacesAndNewlines),
               !message.isEmpty {
                return message
            }
            if appState.appLiveSubtitleSpeechDetected {
                return L10n.text("Speech detected. Waiting for ASR...", language: language)
            }
            if appState.appLiveSubtitleBufferedMilliseconds > 0 || appState.appLiveSubtitleAudioLevel > 0.02 {
                return connectedAudioWaitingText
            }
            return L10n.text("Listening...", language: language)
        case .stopping:
            return L10n.text("Stopping live subtitles", language: language)
        case .failed:
            return appState.appLiveSubtitleMessage ?? L10n.text("Live subtitles failed", language: language)
        case .stopped:
            return L10n.text("Live subtitles stopped", language: language)
        }
    }

    private var connectedAudioWaitingText: String {
        switch appState.appLiveSubtitleAudioSource {
        case .systemAudio:
            return L10n.text("System audio connected. Waiting for speech...", language: language)
        case .microphone:
            return L10n.text("Microphone connected. Waiting for speech...", language: language)
        case .systemAndMicrophone:
            return L10n.text("System audio and microphone connected. Waiting for speech...", language: language)
        }
    }

    private var statusTitle: String {
        let source = liveAudioSourceName(appState.appLiveSubtitleAudioSource)
        let model = currentASRModelName
        if appState.appLiveSubtitleIsPartial {
            return "\(model) · \(source) · \(L10n.text("Draft", language: language))"
        }
        return "\(model) · \(source)"
    }

    private var currentASRModelName: String {
        AppState.condensedModelName(
            appState.appLiveSubtitleModelName ?? appState.selectedRealtimeASRModel?.name ?? L10n.text("No model", language: language),
            limit: 24
        )
    }

    private var sourceIcon: String {
        switch appState.appLiveSubtitleAudioSource {
        case .systemAudio:
            return "speaker.wave.2.fill"
        case .microphone:
            return "mic.fill"
        case .systemAndMicrophone:
            return "waveform.and.mic"
        }
    }

    private func liveAudioSourceName(_ source: LiveSubtitleAudioSource) -> String {
        switch source {
        case .systemAudio:
            return L10n.text("System audio", language: language)
        case .microphone:
            return L10n.text("Microphone", language: language)
        case .systemAndMicrophone:
            return L10n.text("System + Microphone", language: language)
        }
    }

    private func subtitleModeName(_ mode: SubtitleDisplayMode) -> String {
        switch (language, mode) {
        case (.chinese, .original):
            return "原文"
        case (.chinese, .translated):
            return "译文"
        case (.chinese, .bilingual):
            return "双语"
        case (.english, .original):
            return "Original"
        case (.english, .translated):
            return "Translated"
        case (.english, .bilingual):
            return "Bilingual"
        }
    }

    private func sourceLanguageHintName(_ hint: ASRSourceLanguageHint) -> String {
        switch (language, hint) {
        case (.chinese, .auto):
            return "自动"
        case (.chinese, .zh):
            return "中文"
        case (.chinese, .yue):
            return "粤语"
        case (.chinese, .en):
            return "英文"
        case (.chinese, .ja):
            return "日文"
        case (.chinese, .ko):
            return "韩文"
        default:
            return hint.rawValue
        }
    }

    private func trimmed(_ value: String) -> String {
        value.trimmingCharacters(in: .whitespacesAndNewlines)
    }
}

struct ModelPickerView: View {
    @ObservedObject var appState: AppState

    private var language: AppLanguage {
        appState.preferences.appLanguage
    }

    var body: some View {
        Picker(L10n.text("Model", language: language), selection: Binding(
            get: { appState.selectedModelID },
            set: { appState.selectedModelID = $0 }
        )) {
            if appState.models.isEmpty {
                Text(L10n.text("No model", language: language)).tag(UUID?.none)
            } else {
                ForEach(appState.models) { model in
                    Text(modelPickerTitle(model))
                        .tag(Optional(model.id))
                }
            }
        }
        .pickerStyle(.menu)
        .disabled(appState.models.isEmpty || appState.isRunning)
    }

    private func modelPickerTitle(_ model: ModelDescriptor) -> String {
        if model.isRemoteProvider {
            return "\(model.name) · \(model.providerDisplayName)"
        }
        return "\(model.name) · \(model.format.rawValue.uppercased()) · \(model.sizeClass)"
    }
}

struct TaskOptionsView: View {
    @ObservedObject var appState: AppState

    private var language: AppLanguage {
        appState.preferences.appLanguage
    }

    var body: some View {
        switch appState.selectedTask {
        case .translate:
            Picker(L10n.text("Target", language: language), selection: Binding(
                get: { appState.preferences.defaultTranslationTarget },
                set: { newValue in
                    appState.updatePreferences { $0.defaultTranslationTarget = newValue }
                }
            )) {
                Text(L10n.targetLanguageName("auto", language: language)).tag("auto")
                Text(L10n.targetLanguageName("Chinese", language: language)).tag("Chinese")
                Text(L10n.targetLanguageName("English", language: language)).tag("English")
                Text(L10n.targetLanguageName("Japanese", language: language)).tag("Japanese")
                Text(L10n.targetLanguageName("Korean", language: language)).tag("Korean")
            }
            .pickerStyle(.menu)
            .disabled(appState.isRunning)
        case .polish:
            Picker(L10n.text("Style", language: language), selection: Binding(
                get: { appState.preferences.defaultPolishStyle },
                set: { newValue in
                    appState.updatePreferences { $0.defaultPolishStyle = newValue }
                }
            )) {
                Text(L10n.polishStyleName("natural", language: language)).tag("natural")
                Text(L10n.polishStyleName("formal", language: language)).tag("formal")
                Text(L10n.polishStyleName("concise", language: language)).tag("concise")
                Text(L10n.polishStyleName("conversational", language: language)).tag("conversational")
                Text(L10n.polishStyleName("technical", language: language)).tag("technical")
            }
            .pickerStyle(.menu)
            .disabled(appState.isRunning)
        case .summarize:
            Picker(L10n.text("Summary mode", language: language), selection: Binding(
                get: { appState.preferences.defaultSummaryMode },
                set: { newValue in
                    appState.updatePreferences { $0.defaultSummaryMode = newValue }
                }
            )) {
                ForEach(SummaryMode.allCases) { mode in
                    Text(L10n.summaryModeName(mode, language: language)).tag(mode)
                }
            }
            .pickerStyle(.menu)
            .disabled(appState.isRunning)
        case .explain:
            Picker(L10n.text("Explanation mode", language: language), selection: Binding(
                get: { appState.preferences.defaultExplanationMode },
                set: { newValue in
                    appState.updatePreferences { $0.defaultExplanationMode = newValue }
                }
            )) {
                ForEach(ExplanationMode.allCases) { mode in
                    Text(L10n.explanationModeName(mode, language: language)).tag(mode)
                }
            }
            .pickerStyle(.menu)
            .disabled(appState.isRunning)
        case .extractTodos:
            Picker(L10n.text("TODO mode", language: language), selection: Binding(
                get: { appState.preferences.defaultTodoExtractionMode },
                set: { newValue in
                    appState.updatePreferences { $0.defaultTodoExtractionMode = newValue }
                }
            )) {
                ForEach(TodoExtractionMode.allCases) { mode in
                    Text(L10n.todoExtractionModeName(mode, language: language)).tag(mode)
                }
            }
            .pickerStyle(.menu)
            .disabled(appState.isRunning)
        case .webPageTranslate:
            EmptyView()
        case .ocr:
            EmptyView()
        }
    }
}

enum SettingsTab: CaseIterable, Identifiable {
    case general
    case shortcuts
    case models
    case defaults
    case ocr
    case media
    case meeting
    case webPage
    case prompts
    case about

    var id: Self { self }

    var systemImage: String {
        switch self {
        case .general:
            return "gearshape"
        case .shortcuts:
            return "keyboard"
        case .models:
            return "cpu"
        case .ocr:
            return "text.viewfinder"
        case .media:
            return "waveform.and.magnifyingglass"
        case .meeting:
            return "person.2.wave.2"
        case .webPage:
            return "safari"
        case .defaults:
            return "dial.low"
        case .prompts:
            return "text.quote"
        case .about:
            return "info.circle"
        }
    }

    func title(language: AppLanguage) -> String {
        switch self {
        case .general:
            return L10n.text("General", language: language)
        case .shortcuts:
            return L10n.text("Shortcuts", language: language)
        case .models:
            return L10n.text("Models", language: language)
        case .ocr:
            return L10n.text("OCR", language: language)
        case .media:
            return L10n.text("Media", language: language)
        case .meeting:
            return L10n.text("Meeting", language: language)
        case .webPage:
            return L10n.text("Web Page Translation", language: language)
        case .defaults:
            return L10n.text("Text", language: language)
        case .prompts:
            return L10n.text("Prompts", language: language)
        case .about:
            return L10n.text("About", language: language)
        }
    }

    func tabTitle(language: AppLanguage) -> String {
        switch self {
        case .webPage:
            return L10n.text("Webpage", language: language)
        case .ocr:
            return L10n.text("Image", language: language)
        case .media:
            return L10n.text("Media", language: language)
        case .meeting:
            return L10n.text("Meeting", language: language)
        case .defaults:
            return L10n.text("Text", language: language)
        case .prompts:
            return L10n.text("Prompts", language: language)
        default:
            return title(language: language)
        }
    }
}

private struct SupportedModelDownloadSection: Identifiable {
    var id: String
    var chineseTitle: String
    var englishTitle: String
    var entries: [SupportedModelDownloadEntry]

    func title(language: AppLanguage) -> String {
        language == .chinese ? chineseTitle : englishTitle
    }
}

private struct SupportedModelDownloadEntry: Identifiable {
    var id: String
    var chineseName: String
    var englishName: String
    var modelName: String
    var downloadURL: String
    var mirrorURL: String?
    var copyCommand: String
    var installerScript: String?
    var chineseNote: String
    var englishNote: String

    func name(language: AppLanguage) -> String {
        language == .chinese ? chineseName : englishName
    }

    func note(language: AppLanguage) -> String {
        language == .chinese ? chineseNote : englishNote
    }
}

private let supportedModelDownloadSections: [SupportedModelDownloadSection] = [
    SupportedModelDownloadSection(
        id: "text-ocr",
        chineseTitle: "文本 / OCR",
        englishTitle: "Text / OCR",
        entries: [
            SupportedModelDownloadEntry(
                id: "mlx-text",
                chineseName: "MLX 文本模型目录",
                englishName: "MLX text model folder",
                modelName: "MLX Swift LM-compatible text model",
                downloadURL: "https://huggingface.co/models?library=mlx&pipeline_tag=text-generation",
                mirrorURL: nil,
                copyCommand: "huggingface-cli download <model-id> --local-dir ~/code/models/<model-id>",
                installerScript: nil,
                chineseNote: "用于翻译、润色、总结、解释、网页翻译等本地 LLM 任务；下载后在模型页添加包含 config/tokenizer/weights 的目录。",
                englishNote: "Used for local LLM tasks such as translate, polish, summarize, explain, and webpage translation. Add the downloaded folder that contains config, tokenizer, and weights."
            ),
            SupportedModelDownloadEntry(
                id: "mlx-vision",
                chineseName: "MLX 视觉语言模型目录",
                englishName: "MLX vision-language model folder",
                modelName: "MLX Swift LM-compatible VLM",
                downloadURL: "https://huggingface.co/models?library=mlx&pipeline_tag=image-text-to-text",
                mirrorURL: nil,
                copyCommand: "huggingface-cli download <model-id> --local-dir ~/code/models/<model-id>",
                installerScript: nil,
                chineseNote: "用于图片 OCR、结构化提取和图片解释；需要模型目录带 vision/processor 配置。",
                englishNote: "Used for image OCR, structured extraction, and image explanation. The model folder must include vision and processor metadata."
            ),
            SupportedModelDownloadEntry(
                id: "gguf-text",
                chineseName: "GGUF 文本模型文件",
                englishName: "GGUF text model file",
                modelName: "GGUF text-generation model",
                downloadURL: "https://huggingface.co/models?library=gguf&pipeline_tag=text-generation",
                mirrorURL: nil,
                copyCommand: "huggingface-cli download <model-id> <file.gguf> --local-dir ~/code/models/<model-id>",
                installerScript: nil,
                chineseNote: "用于本地文本 LLM；添加模型时选择具体 .gguf 文件。GGUF 当前不作为本地视觉 OCR 默认路径。",
                englishNote: "Used for local text LLM tasks. Pick the exact .gguf file when adding it. GGUF is not the default local vision/OCR route."
            )
        ]
    ),
    SupportedModelDownloadSection(
        id: "media-asr",
        chineseTitle: "媒体 ASR",
        englishTitle: "Media ASR",
        entries: [
            SupportedModelDownloadEntry(
                id: "qwen3-asr-06b-bf16",
                chineseName: "Qwen3-ASR-0.6B bf16",
                englishName: "Qwen3-ASR-0.6B bf16",
                modelName: "mlx-community/Qwen3-ASR-0.6B-bf16",
                downloadURL: "https://huggingface.co/mlx-community/Qwen3-ASR-0.6B-bf16",
                mirrorURL: "https://hf-mirror.com/mlx-community/Qwen3-ASR-0.6B-bf16",
                copyCommand: "HF_ENDPOINT=https://hf-mirror.com huggingface-cli download mlx-community/Qwen3-ASR-0.6B-bf16 --local-dir ~/code/models/mlx-community/Qwen3-ASR-0.6B-bf16",
                installerScript: "scripts/install-phase4-mlx-asr-runtime.sh",
                chineseNote: "当前中英混合实时字幕优先候选，也可用于文件转写。",
                englishNote: "Current preferred mixed Chinese/English realtime candidate; also supports file transcription."
            ),
            SupportedModelDownloadEntry(
                id: "qwen3-asr-06b-4bit",
                chineseName: "Qwen3-ASR-0.6B 4bit",
                englishName: "Qwen3-ASR-0.6B 4bit",
                modelName: "mlx-community/Qwen3-ASR-0.6B-4bit",
                downloadURL: "https://huggingface.co/mlx-community/Qwen3-ASR-0.6B-4bit",
                mirrorURL: "https://hf-mirror.com/mlx-community/Qwen3-ASR-0.6B-4bit",
                copyCommand: "HF_ENDPOINT=https://hf-mirror.com huggingface-cli download mlx-community/Qwen3-ASR-0.6B-4bit --local-dir ~/code/models/mlx-community/Qwen3-ASR-0.6B-4bit",
                installerScript: "scripts/install-phase4-mlx-asr-runtime.sh",
                chineseNote: "Qwen3-ASR 低内存/更快备选；量化质量可接受时适合实时字幕。",
                englishNote: "Lower-memory faster Qwen3-ASR alternative; useful for realtime subtitles when quantized quality is acceptable."
            ),
            SupportedModelDownloadEntry(
                id: "qwen3-asr-17b-bf16",
                chineseName: "Qwen3-ASR-1.7B bf16",
                englishName: "Qwen3-ASR-1.7B bf16",
                modelName: "mlx-community/Qwen3-ASR-1.7B-bf16",
                downloadURL: "https://huggingface.co/mlx-community/Qwen3-ASR-1.7B-bf16",
                mirrorURL: "https://hf-mirror.com/mlx-community/Qwen3-ASR-1.7B-bf16",
                copyCommand: "HF_ENDPOINT=https://hf-mirror.com huggingface-cli download mlx-community/Qwen3-ASR-1.7B-bf16 --local-dir ~/code/models/mlx-community/Qwen3-ASR-1.7B-bf16",
                installerScript: "scripts/install-phase4-mlx-asr-runtime.sh",
                chineseNote: "更大的 Qwen3-ASR 文件转写候选；实时性能取决于机器和窗口配置。",
                englishNote: "Larger Qwen3-ASR file-transcription candidate; realtime performance depends on machine and window settings."
            ),
            SupportedModelDownloadEntry(
                id: "fun-asr-mlt",
                chineseName: "Fun-ASR-MLT-Nano",
                englishName: "Fun-ASR-MLT-Nano",
                modelName: "mlx-community/Fun-ASR-MLT-Nano-2512-fp16",
                downloadURL: "https://huggingface.co/mlx-community/Fun-ASR-MLT-Nano-2512-fp16",
                mirrorURL: "https://hf-mirror.com/mlx-community/Fun-ASR-MLT-Nano-2512-fp16",
                copyCommand: "HF_ENDPOINT=https://hf-mirror.com huggingface-cli download mlx-community/Fun-ASR-MLT-Nano-2512-fp16 --local-dir ~/code/models/mlx-community/Fun-ASR-MLT-Nano-2512-fp16",
                installerScript: "scripts/install-phase4-funasr-mlx-runtime.sh",
                chineseNote: "多语言实时字幕候选；使用独立 mlx-audio-plus 运行时。",
                englishNote: "Multilingual realtime subtitle candidate. Uses the isolated mlx-audio-plus runtime."
            ),
            SupportedModelDownloadEntry(
                id: "fun-asr-nano",
                chineseName: "Fun-ASR-Nano",
                englishName: "Fun-ASR-Nano",
                modelName: "mlx-community/Fun-ASR-Nano-2512-fp16",
                downloadURL: "https://huggingface.co/mlx-community/Fun-ASR-Nano-2512-fp16",
                mirrorURL: "https://hf-mirror.com/mlx-community/Fun-ASR-Nano-2512-fp16",
                copyCommand: "HF_ENDPOINT=https://hf-mirror.com huggingface-cli download mlx-community/Fun-ASR-Nano-2512-fp16 --local-dir ~/code/models/mlx-community/Fun-ASR-Nano-2512-fp16",
                installerScript: "scripts/install-phase4-funasr-nano-mlx-runtime.sh",
                chineseNote: "中文/英文/日文低延迟实时字幕候选；也支持文件字幕。",
                englishNote: "Low-latency Chinese/English/Japanese realtime candidate; also supports file subtitles."
            ),
            SupportedModelDownloadEntry(
                id: "sensevoice",
                chineseName: "SenseVoiceSmall",
                englishName: "SenseVoiceSmall",
                modelName: "mlx-community/SenseVoiceSmall",
                downloadURL: "https://huggingface.co/mlx-community/SenseVoiceSmall",
                mirrorURL: "https://hf-mirror.com/mlx-community/SenseVoiceSmall",
                copyCommand: "HF_ENDPOINT=https://hf-mirror.com huggingface-cli download mlx-community/SenseVoiceSmall --local-dir ~/code/models/mlx-community/SenseVoiceSmall",
                installerScript: "scripts/install-phase4-sensevoice-mlx-runtime.sh",
                chineseNote: "短窗口低延迟 ASR 备选；适合已有 SenseVoice 运行时的机器。",
                englishNote: "Short-window low-latency ASR alternative, useful on machines that already have the SenseVoice runtime."
            ),
            SupportedModelDownloadEntry(
                id: "vibevoice",
                chineseName: "VibeVoice-ASR",
                englishName: "VibeVoice-ASR",
                modelName: "mlx-community/VibeVoice-ASR-4bit",
                downloadURL: "https://huggingface.co/mlx-community/VibeVoice-ASR-4bit",
                mirrorURL: "https://hf-mirror.com/mlx-community/VibeVoice-ASR-4bit",
                copyCommand: "HF_ENDPOINT=https://hf-mirror.com huggingface-cli download mlx-community/VibeVoice-ASR-4bit --local-dir ~/code/models/mlx-community/VibeVoice-ASR-4bit",
                installerScript: "scripts/install-phase4-mlx-asr-runtime.sh",
                chineseNote: "重型 file-only MLX rich transcription 模型；可保留说话人和时间戳元数据。",
                englishNote: "Heavy file-only MLX rich transcription model that can preserve speaker and timestamp metadata."
            ),
            SupportedModelDownloadEntry(
                id: "whisper-coreml",
                chineseName: "whisper.cpp Core ML",
                englishName: "whisper.cpp Core ML",
                modelName: "OpenAI Whisper base / ggml-base.bin",
                downloadURL: "https://github.com/ggml-org/whisper.cpp",
                mirrorURL: nil,
                copyCommand: "LLMTOOLS_WHISPER_CPP_MODEL=base ./scripts/install-phase4-whisper-coreml-runtime.sh",
                installerScript: "scripts/install-phase4-whisper-coreml-runtime.sh",
                chineseNote: "安装脚本会下载 Whisper checkpoint、转换 ggml，并生成相邻的 Core ML encoder。",
                englishNote: "The installer downloads the Whisper checkpoint, converts ggml, and generates the adjacent Core ML encoder."
            )
        ]
    ),
    SupportedModelDownloadSection(
        id: "diarization",
        chineseTitle: "说话人分离",
        englishTitle: "Speaker Diarization",
        entries: [
            SupportedModelDownloadEntry(
                id: "pyannote",
                chineseName: "pyannote speaker diarization 3.1",
                englishName: "pyannote speaker diarization 3.1",
                modelName: "pyannote/speaker-diarization-3.1 + pyannote/segmentation-3.0",
                downloadURL: "https://huggingface.co/pyannote/speaker-diarization-3.1",
                mirrorURL: "https://hf-mirror.com/pyannote/speaker-diarization-3.1",
                copyCommand: "HF_ENDPOINT=https://hf-mirror.com huggingface-cli download pyannote/speaker-diarization-3.1 --local-dir ~/code/models/pyannote/speaker-diarization-3.1 && HF_HUB_DISABLE_XET=1 HF_ENDPOINT=https://hf-mirror.com huggingface-cli download pyannote/segmentation-3.0 --local-dir ~/code/models/pyannote/segmentation-3.0 && HF_ENDPOINT=https://hf-mirror.com huggingface-cli download pyannote/wespeaker-voxceleb-resnet34-LM --local-dir ~/code/models/pyannote/wespeaker-voxceleb-resnet34-LM",
                installerScript: "scripts/install-phase4x-pyannote-diarization.sh",
                chineseNote: "需要先用同一个 Hugging Face 账号接受 speaker-diarization-3.1 和 segmentation-3.0 两个条款，并在设置里保存 HF Token。",
                englishNote: "Requires accepting both speaker-diarization-3.1 and segmentation-3.0 terms with the same Hugging Face account and saving an HF token in Settings."
            )
        ]
    ),
    SupportedModelDownloadSection(
        id: "language-id",
        chineseTitle: "语言识别",
        englishTitle: "Language ID",
        entries: [
            SupportedModelDownloadEntry(
                id: "fasttext-ftz",
                chineseName: "fastText lid.176.ftz",
                englishName: "fastText lid.176.ftz",
                modelName: "lid.176.ftz",
                downloadURL: "https://dl.fbaipublicfiles.com/fasttext/supervised-models/lid.176.ftz",
                mirrorURL: nil,
                copyCommand: "curl -L -o ~/Library/Application\\ Support/llmTools/lid-runtime/lid.176.ftz https://dl.fbaipublicfiles.com/fasttext/supervised-models/lid.176.ftz",
                installerScript: "scripts/install-phase4x-fasttext-lid.sh",
                chineseNote: "默认小模型；用于字幕、网页、OCR 或文本任务的本地语言识别。",
                englishNote: "Default compact model for local language identification across subtitles, webpages, OCR, and text tasks."
            ),
            SupportedModelDownloadEntry(
                id: "fasttext-bin",
                chineseName: "fastText lid.176.bin",
                englishName: "fastText lid.176.bin",
                modelName: "lid.176.bin",
                downloadURL: "https://dl.fbaipublicfiles.com/fasttext/supervised-models/lid.176.bin",
                mirrorURL: nil,
                copyCommand: "curl -L -o ~/Library/Application\\ Support/llmTools/lid-runtime/lid.176.bin https://dl.fbaipublicfiles.com/fasttext/supervised-models/lid.176.bin",
                installerScript: "LLMTOOLS_LID_MODEL_VARIANT=bin scripts/install-phase4x-fasttext-lid.sh",
                chineseNote: "可选大模型；准确性/速度取舍更好，但文件明显更大。",
                englishNote: "Optional larger model with a better accuracy/speed tradeoff, but much larger on disk."
            )
        ]
    ),
    SupportedModelDownloadSection(
        id: "fast-mt",
        chineseTitle: "快速机器翻译",
        englishTitle: "Fast MT",
        entries: [
            SupportedModelDownloadEntry(
                id: "opus-en-zh",
                chineseName: "OPUS-MT 英译中",
                englishName: "OPUS-MT en->zh",
                modelName: "Helsinki-NLP/opus-mt-en-zh",
                downloadURL: "https://huggingface.co/Helsinki-NLP/opus-mt-en-zh",
                mirrorURL: "https://hf-mirror.com/Helsinki-NLP/opus-mt-en-zh",
                copyCommand: "HF_ENDPOINT=https://hf-mirror.com ./scripts/install-phase4x-ctranslate2-en-zh.sh",
                installerScript: "scripts/install-phase4x-ctranslate2-en-zh.sh",
                chineseNote: "最快的英译中 CTranslate2 路径；安装脚本会下载并转换模型。",
                englishNote: "Fastest CTranslate2 path for English to Chinese. The installer downloads and converts the model."
            ),
            SupportedModelDownloadEntry(
                id: "nllb-600m",
                chineseName: "NLLB 200 distilled 600M",
                englishName: "NLLB 200 distilled 600M",
                modelName: "facebook/nllb-200-distilled-600M",
                downloadURL: "https://huggingface.co/facebook/nllb-200-distilled-600M",
                mirrorURL: "https://hf-mirror.com/facebook/nllb-200-distilled-600M",
                copyCommand: "HF_ENDPOINT=https://hf-mirror.com ./scripts/install-phase4x-nllb-200-distilled-600m.sh",
                installerScript: "scripts/install-phase4x-nllb-200-distilled-600m.sh",
                chineseNote: "覆盖常用多语言互译，延迟高于 OPUS；安装脚本会转换为 CTranslate2 int8。",
                englishNote: "Covers common multilingual translation pairs with higher latency than OPUS. The installer converts it to CTranslate2 int8."
            ),
            SupportedModelDownloadEntry(
                id: "argos",
                chineseName: "Argos Translate en->zh package",
                englishName: "Argos Translate en->zh package",
                modelName: "Argos package index",
                downloadURL: "https://github.com/argosopentech/argos-translate",
                mirrorURL: nil,
                copyCommand: "./scripts/install-phase4x-argos.sh",
                installerScript: "scripts/install-phase4x-argos.sh",
                chineseNote: "备用离线翻译引擎；安装脚本会从 Argos package index 安装英译中语言包。",
                englishNote: "Fallback offline translation engine. The installer installs the en->zh language package from the Argos package index."
            )
        ]
    )
]

@MainActor
final class SettingsNavigationState: ObservableObject {
    @Published var selectedTab: SettingsTab = .general
}

private enum ShortcutCaptureTarget: Identifiable, Hashable {
    case quickAction
    case quickActionWithoutSelection
    case liveSubtitles
    case quickActionTextMode
    case quickActionImageMode
    case quickActionMediaMode
    case textTask(TaskKind)
    case imageOCRMode(OCRMode)

    var id: String {
        switch self {
        case .quickAction:
            return "quickAction"
        case .quickActionWithoutSelection:
            return "quickActionWithoutSelection"
        case .liveSubtitles:
            return "liveSubtitles"
        case .quickActionTextMode:
            return "quickActionTextMode"
        case .quickActionImageMode:
            return "quickActionImageMode"
        case .quickActionMediaMode:
            return "quickActionMediaMode"
        case .textTask(let task):
            return "textTask:\(task.rawValue)"
        case .imageOCRMode(let mode):
            return "imageOCRMode:\(mode.rawValue)"
        }
    }
}

private enum WebPageDomainRuleKind {
    case alwaysTranslate
    case neverTranslate
}

private enum ModelSettingsPane: String, CaseIterable, Identifiable {
    case settings
    case management

    var id: Self { self }

    func title(language: AppLanguage) -> String {
        switch self {
        case .settings:
            return L10n.text("Model Settings", language: language)
        case .management:
            return L10n.text("Model Management", language: language)
        }
    }
}

struct SettingsView: View {
    @ObservedObject var appState: AppState
    @ObservedObject var navigation: SettingsNavigationState
    @State private var providerDraftID: ModelProviderID = .siliconFlow
    @State private var providerDraftName = ""
    @State private var providerDraftModelID = ""
    @State private var providerDraftAPIKey = ""
    @State private var providerDraftBaseURL = ModelProviderCatalog.preset(for: .siliconFlow)?.defaultBaseURL ?? ""
    @State private var providerDraftContextLength = ModelProviderCatalog.preset(for: .siliconFlow)?.defaultContextLength ?? 32768
    @State private var editingProviderModelID: UUID?
    @State private var browserIntegrationStates = BrowserIntegrationService.shared.browserStates()
    @State private var shortcutCaptureTarget: ShortcutCaptureTarget?
    @State private var shortcutRecorderMessage: String?
    @State private var showSelectionLimitAppImporter = false
    @State private var selectionLimitDraftLineCount = 2
    @State private var webPageDomainDraft = ""
    @State private var speakerDiarizationTokenDraft = ""
    @State private var selectedModelSettingsPane: ModelSettingsPane = .settings

    private var language: AppLanguage {
        appState.preferences.appLanguage
    }

    private var selectedTab: SettingsTab {
        navigation.selectedTab
    }

    var body: some View {
        VStack(spacing: 0) {
            toolbar
            Divider()
            contentArea
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .frame(minWidth: 700, maxWidth: 700, minHeight: 380)
        .background(Color(NSColor.windowBackgroundColor))
        .background {
            ShortcutCaptureBridge(
                target: $shortcutCaptureTarget,
                onShortcut: { target, shortcut in
                    applyShortcut(shortcut, for: target)
                },
                onInvalidShortcut: {
                    shortcutRecorderMessage = L10n.text("Use Command, Option, or Control with a key", language: language)
                },
                onCancel: {
                    shortcutCaptureTarget = nil
                    shortcutRecorderMessage = nil
                }
            )
            .frame(width: 0, height: 0)
        }
        .fileImporter(isPresented: $showSelectionLimitAppImporter, allowedContentTypes: [.applicationBundle, .application, .item], allowsMultipleSelection: false) { result in
            if case let .success(urls) = result, let url = urls.first {
                addSelectionLineLimitRule(from: url)
            }
        }
        .onAppear {
            refreshBrowserIntegrationStates()
            initializeProviderDraftIfNeeded()
        }
        .onDisappear {
            shortcutCaptureTarget = nil
            shortcutRecorderMessage = nil
        }
    }

    private var toolbar: some View {
        VStack(spacing: 5) {
            Text(selectedTab.title(language: language))
                .font(.headline)
                .frame(maxWidth: .infinity)

            HStack(spacing: 2) {
                ForEach(SettingsTab.allCases) { tab in
                    settingsTabButton(tab)
                }
            }
            .frame(maxWidth: .infinity)
        }
        .padding(.top, 6)
        .padding(.bottom, 6)
        .padding(.horizontal, 16)
    }

    @ViewBuilder
    private var contentArea: some View {
        if selectedTab == .models {
            modelSettingsPage
                .padding(.horizontal, 18)
                .padding(.top, 12)
                .padding(.bottom, 16)
        } else {
            ScrollView {
                selectedContent
                    .padding(.horizontal, 18)
                    .padding(.top, 12)
                    .padding(.bottom, 16)
            }
        }
    }

    @ViewBuilder
    private var selectedContent: some View {
        switch selectedTab {
        case .general:
            generalSettingsPage
        case .shortcuts:
            shortcutSettingsPage
        case .models:
            modelSettingsPage
        case .ocr:
            ocrSettingsPage
        case .media:
            mediaSubtitleSettingsPage
        case .meeting:
            liveMeetingSettingsPage
        case .webPage:
            webPageTranslationPage
        case .defaults:
            defaultsSettingsPage
        case .prompts:
            promptSettingsPage
        case .about:
            aboutSettingsPage
        }
    }

    private var generalSettingsPage: some View {
        settingsForm(maxWidth: 620) {
            settingRow(title: L10n.text("Launch", language: language)) {
                VStack(alignment: .leading, spacing: 8) {
                    checkboxLine(
                        title: L10n.text("Launch at login", language: language),
                        isOn: Binding(
                            get: { appState.preferences.launchAtLogin },
                            set: { newValue in
                                appState.setLaunchAtLogin(newValue)
                            }
                        ),
                        trailing: AnyView(statusBadge(appState.launchAtLoginStatusText(), systemImage: launchStatusIcon))
                    )
                }
            }

            settingRow(title: L10n.text("Interface", language: language)) {
                VStack(alignment: .leading, spacing: 8) {
                    checkboxLine(
                        title: L10n.text("Widget visible on all Spaces", language: language),
                        isOn: Binding(
                            get: { appState.preferences.widgetVisibleOnAllSpaces },
                            set: { newValue in
                                appState.updatePreferences { $0.widgetVisibleOnAllSpaces = newValue }
                            }
                        )
                    )
                    checkboxLine(
                        title: L10n.text("Auto-collapse widget at screen edge", language: language),
                        isOn: Binding(
                            get: { appState.preferences.autoCollapseWidget },
                            set: { newValue in
                                appState.updatePreferences { $0.autoCollapseWidget = newValue }
                            }
                        )
                    )
                }
            }

            settingRow(title: L10n.text("Text", language: language)) {
                checkboxLine(
                    title: L10n.text("Replace original text after processing", language: language),
                    isOn: Binding(
                        get: { appState.preferences.replaceOriginalText },
                        set: { newValue in
                            appState.updatePreferences { $0.replaceOriginalText = newValue }
                        }
                    )
                )
            }

            settingRow(title: L10n.text("Selection", language: language)) {
                selectionActionControls
            }

            settingRow(title: L10n.text("Language", language: language)) {
                appLanguagePicker
            }
        }
    }

    private var shortcutSettingsPage: some View {
        settingsForm(maxWidth: 620) {
            settingRow(title: L10n.text("Global shortcuts", language: language)) {
                VStack(alignment: .leading, spacing: 10) {
                    shortcutRecorderLine(
                        title: L10n.text("Open Quick Action", language: language),
                        shortcut: appState.preferences.quickActionShortcut,
                        target: .quickAction
                    )
                    shortcutRecorderLine(
                        title: L10n.text("Open Quick Action without selected text", language: language),
                        shortcut: appState.preferences.quickActionWithoutSelectionShortcut,
                        target: .quickActionWithoutSelection
                    )
                    shortcutRecorderLine(
                        title: L10n.text("Open live subtitles", language: language),
                        shortcut: appState.preferences.liveSubtitleShortcut,
                        target: .liveSubtitles
                    )
                }
            }

            settingRow(title: L10n.text("Quick Action mode shortcuts", language: language)) {
                VStack(alignment: .leading, spacing: 10) {
                    shortcutRecorderLine(
                        title: L10n.text("Switch to text mode", language: language),
                        shortcut: appState.preferences.quickActionPopupShortcuts.textMode,
                        target: .quickActionTextMode
                    )
                    shortcutRecorderLine(
                        title: L10n.text("Switch to image mode", language: language),
                        shortcut: appState.preferences.quickActionPopupShortcuts.imageMode,
                        target: .quickActionImageMode
                    )
                    shortcutRecorderLine(
                        title: L10n.text("Switch to media mode", language: language),
                        shortcut: appState.preferences.quickActionPopupShortcuts.mediaMode,
                        target: .quickActionMediaMode
                    )
                }
            }

            settingRow(title: L10n.text("Text action shortcuts", language: language)) {
                VStack(alignment: .leading, spacing: 10) {
                    ForEach(TaskKind.interactiveCases) { task in
                        if let shortcut = appState.preferences.quickActionPopupShortcuts.textTaskShortcut(for: task) {
                            shortcutRecorderLine(
                                title: task.title(language: language),
                                shortcut: shortcut,
                                target: .textTask(task)
                            )
                        }
                    }
                }
            }

            settingRow(title: L10n.text("Image action shortcuts", language: language)) {
                VStack(alignment: .leading, spacing: 10) {
                    ForEach(OCRMode.allCases) { mode in
                        shortcutRecorderLine(
                            title: L10n.ocrModeName(mode, language: language),
                            shortcut: appState.preferences.quickActionPopupShortcuts.ocrModeShortcut(for: mode),
                            target: .imageOCRMode(mode)
                        )
                    }
                }
            }

            if let shortcutRecorderMessage {
                Text(shortcutRecorderMessage)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(.leading, 108)
            }
        }
    }

    private var selectionActionControls: some View {
        VStack(alignment: .leading, spacing: 8) {
            checkboxLine(
                title: L10n.text("Show selection action panel", language: language),
                isOn: Binding(
                    get: { appState.preferences.selectionActionEnabled },
                    set: { newValue in
                        appState.updatePreferences { $0.selectionActionEnabled = newValue }
                    }
                )
            )

            VStack(alignment: .leading, spacing: 8) {
                checkboxLine(
                    title: L10n.text("Trigger after mouse drag selection", language: language),
                    isOn: Binding(
                        get: { appState.preferences.selectionActionTriggerMouseDrag },
                        set: { newValue in
                            appState.updatePreferences { $0.selectionActionTriggerMouseDrag = newValue }
                        }
                    )
                )
                checkboxLine(
                    title: L10n.text("Trigger after double-click selection", language: language),
                    isOn: Binding(
                        get: { appState.preferences.selectionActionTriggerDoubleClick },
                        set: { newValue in
                            appState.updatePreferences { $0.selectionActionTriggerDoubleClick = newValue }
                        }
                    )
                )
                checkboxLine(
                    title: L10n.text("Trigger after Command-A selection", language: language),
                    isOn: Binding(
                        get: { appState.preferences.selectionActionTriggerSelectAll },
                        set: { newValue in
                            appState.updatePreferences { $0.selectionActionTriggerSelectAll = newValue }
                        }
                    )
                )
                selectionLineLimitRulesControl
            }
            .padding(.leading, 18)
            .disabled(!appState.preferences.selectionActionEnabled)
            .opacity(appState.preferences.selectionActionEnabled ? 1 : 0.45)
        }
    }

    private var selectionLineLimitRulesControl: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(L10n.text("Special app line limits", language: language))
                .font(.subheadline)
            ForEach(appState.preferences.selectionLineLimitRules) { rule in
                HStack(spacing: 8) {
                    Text(rule.bundleIdentifier)
                        .font(.caption.monospaced())
                        .lineLimit(1)
                        .truncationMode(.middle)
                        .frame(width: 210, alignment: .leading)
                    selectionLineCountStepper(
                        value: rule.maximumLineCount,
                        setValue: { newValue in
                            updateSelectionLineLimitRule(id: rule.id) { $0.maximumLineCount = newValue }
                        }
                    )
                    iconToolButton(
                        systemImage: "trash",
                        help: L10n.text("Remove", language: language),
                        role: .destructive
                    ) {
                        removeSelectionLineLimitRule(id: rule.id)
                    }
                }
            }

            HStack(spacing: 8) {
                selectionLineCountStepper(
                    value: selectionLimitDraftLineCount,
                    setValue: { selectionLimitDraftLineCount = $0 }
                )
                Button {
                    showSelectionLimitAppImporter = true
                } label: {
                    Label(L10n.text("Choose App", language: language), systemImage: "app.badge")
                }
                .controlSize(.small)
            }
        }
    }

    private func selectionLineCountStepper(value: Int, setValue: @escaping (Int) -> Void) -> some View {
        HStack(spacing: 6) {
            Text("\(value)")
                .font(.caption.monospacedDigit())
                .foregroundStyle(.secondary)
                .frame(width: 22)
                .padding(.horizontal, 6)
                .padding(.vertical, 3)
                .background(.quaternary.opacity(0.65))
                .clipShape(RoundedRectangle(cornerRadius: 6))
            Text(L10n.text("lines", language: language))
                .font(.caption)
                .foregroundStyle(.secondary)
            Stepper(
                "",
                value: Binding(
                    get: { value },
                    set: { setValue($0) }
                ),
                in: 1...10,
                step: 1
            )
            .labelsHidden()
        }
    }

    private var modelSettingsPage: some View {
        VStack(alignment: .leading, spacing: 12) {
            Picker("", selection: $selectedModelSettingsPane) {
                ForEach(ModelSettingsPane.allCases) { pane in
                    Text(pane.title(language: language)).tag(pane)
                }
            }
            .labelsHidden()
            .pickerStyle(.segmented)
            .frame(width: 240, alignment: .leading)

            switch selectedModelSettingsPane {
            case .settings:
                modelConfigurationPage
            case .management:
                modelManagementPage
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }

    private var modelConfigurationPage: some View {
        ScrollView {
            settingsForm(maxWidth: 620) {
                languageRoutingSettingsSection
                speakerDiarizationSettingsSection
                fastTranslationSettingsSection
            }
            .padding(.bottom, 2)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }

    private var modelManagementPage: some View {
        VStack(alignment: .leading, spacing: 12) {
            modelSettingsHeader
                .frame(maxWidth: 650, alignment: .topLeading)
                .frame(maxWidth: .infinity, alignment: .topLeading)
            providerAddPanel
                .frame(maxWidth: 650, alignment: .topLeading)
                .frame(maxWidth: .infinity, alignment: .topLeading)

            Group {
                if appState.models.isEmpty {
                    emptyModelsView
                        .frame(maxWidth: 650, alignment: .topLeading)
                        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
                } else {
                    modelList
                }
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }

    private var modelSettingsHeader: some View {
        HStack(alignment: .center, spacing: 10) {
            Text(L10n.text("Registered Models", language: language))
                .font(.headline)
            statusBadge(modelCountText, systemImage: "shippingbox")
            Spacer()
            Button {
                openLocalModelPanel()
            } label: {
                Label(L10n.text("Add Local Model", language: language), systemImage: "externaldrive.badge.plus")
            }
            .controlSize(.small)
        }
    }

    private var providerAddPanel: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .firstTextBaseline, spacing: 8) {
                Label(
                    editingProviderModelID == nil
                        ? L10n.text("Add Provider", language: language)
                        : L10n.text("Save Provider", language: language),
                    systemImage: editingProviderModelID == nil ? "cloud.badge.plus" : "square.and.pencil"
                )
                    .font(.subheadline.weight(.semibold))
                Spacer(minLength: 8)
                Text(selectedProviderPreset.note)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .truncationMode(.tail)
            }

            HStack(alignment: .top, spacing: 10) {
                fieldStack(title: L10n.text("Provider", language: language), width: 170) {
                    Picker("", selection: Binding(
                        get: { providerDraftID },
                        set: { newValue in
                            providerDraftID = newValue
                            applyProviderPreset(newValue)
                        }
                    )) {
                        ForEach(ModelProviderCatalog.remotePresets) { preset in
                            Text(preset.name).tag(preset.id)
                        }
                    }
                    .labelsHidden()
                    .pickerStyle(.menu)
                }

                fieldStack(title: L10n.text("Provider model", language: language), width: 190) {
                    CommandFriendlyTextField(
                        text: $providerDraftModelID,
                        placeholder: providerModelPlaceholder
                    )
                }

                fieldStack(title: L10n.text("Base URL", language: language), width: 250) {
                    CommandFriendlyTextField(
                        text: $providerDraftBaseURL,
                        placeholder: "https://api.example.com/v1"
                    )
                }
            }

            HStack(alignment: .top, spacing: 10) {
                fieldStack(title: L10n.text("Provider name", language: language), width: 170) {
                    CommandFriendlyTextField(
                        text: $providerDraftName,
                        placeholder: L10n.text("Optional display name", language: language)
                    )
                }

                fieldStack(title: L10n.text("API Key", language: language), width: 250) {
                    CommandFriendlyTextField(
                        text: $providerDraftAPIKey,
                        placeholder: selectedProviderPreset.requiresAPIKey ? "sk-..." : "optional",
                        isSecure: true
                    )
                }
                .disabled(!selectedProviderPreset.requiresAPIKey)
                .opacity(selectedProviderPreset.requiresAPIKey ? 1 : 0.55)

                VStack(alignment: .leading, spacing: 4) {
                    Text(L10n.text("Context", language: language))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    Stepper(
                        "\(providerDraftContextLength)",
                        value: $providerDraftContextLength,
                        in: 1024...1_000_000,
                        step: 1024
                    )
                    .font(.caption.monospacedDigit())
                    .frame(width: 118, alignment: .leading)
                }

                Spacer(minLength: 0)

                HStack(spacing: 6) {
                    iconToolButton(
                        systemImage: editingProviderModelID == nil ? "plus" : "checkmark",
                        help: editingProviderModelID == nil
                            ? L10n.text("Add Provider", language: language)
                            : L10n.text("Save Provider", language: language),
                        isDisabled: addProviderDisabled,
                        action: addProviderDraft
                    )

                    if editingProviderModelID != nil {
                        iconToolButton(
                            systemImage: "xmark",
                            help: L10n.text("Cancel Edit", language: language),
                            action: resetProviderDraft
                        )
                    }
                }
                .frame(height: 24, alignment: .center)
                .padding(.top, 17)
            }
        }
        .padding(12)
        .background(Color(NSColor.controlBackgroundColor).opacity(0.72))
        .overlay(RoundedRectangle(cornerRadius: 8).stroke(Color.secondary.opacity(0.14)))
        .clipShape(RoundedRectangle(cornerRadius: 8))
    }

    private var modelList: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 0) {
                LazyVStack(spacing: 10) {
                    ForEach(appState.models) { model in
                        modelCard(model)
                    }
                }
                .padding(.trailing, 4)
                .padding(.bottom, 2)
            }
            .frame(maxWidth: 650, alignment: .topLeading)
            .frame(maxWidth: .infinity, alignment: .topLeading)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }

    private var webPageTranslationPage: some View {
        settingsForm(maxWidth: 620) {
            settingRow(title: L10n.text("Webpage", language: language)) {
                checkboxLine(
                    title: L10n.text("Enable webpage translation", language: language),
                    isOn: Binding(
                        get: { appState.preferences.webPageTranslation.enabled },
                        set: { newValue in
                            appState.updatePreferences { $0.webPageTranslation.enabled = newValue }
                        }
                    )
                )
            }

            settingRow(title: L10n.text("Translation model", language: language)) {
                webPageTranslationModelPicker
            }

            webPageTranslationEngineSettingsSection

            settingRow(title: L10n.text("Site rules", language: language)) {
                webPageDomainRulesControl
            }

            settingRow(title: L10n.text("Site defaults", language: language)) {
                webPageSiteDefaultsControl
            }

            settingRow(title: L10n.text("Cache & Privacy", language: language)) {
                webPagePrivacyControl
            }

            settingRow(title: L10n.text("Browser", language: language)) {
                browserIntegrationList
            }

            settingRow(title: L10n.text("Extension folder", language: language)) {
                pathText(BrowserIntegrationService.shared.extensionFolderPath())
            }
        }
    }

    private var ocrSettingsPage: some View {
        settingsForm(maxWidth: 620) {
            settingRow(title: L10n.text("Feature", language: language)) {
                VStack(alignment: .leading, spacing: 8) {
                    checkboxLine(
                        title: L10n.text("Enable image OCR", language: language),
                        isOn: Binding(
                            get: { appState.preferences.ocr.enabled },
                            set: { newValue in
                                appState.updatePreferences { $0.ocr.enabled = newValue }
                            }
                        )
                    )
                    checkboxLine(
                        title: L10n.text("Run recognition after image loads", language: language),
                        isOn: Binding(
                            get: { appState.preferences.ocr.useModelRecognitionByDefault },
                            set: { newValue in
                                appState.updatePreferences { $0.ocr.useModelRecognitionByDefault = newValue }
                            }
                        )
                    )
                }
            }

            settingRow(title: L10n.text("Default recognition model", language: language)) {
                VStack(alignment: .leading, spacing: 7) {
                    ocrSettingsModelPicker
                    if let model = appState.selectedOCRModel {
                        HStack(spacing: 8) {
                            statusBadge(capabilityName(model.capabilities), systemImage: capabilityIcon(model.capabilities))
                            if model.isRemoteProvider {
                                statusBadge(model.providerDisplayName, systemImage: "network")
                            }
                        }
                        capabilityDetails(model.capabilities)
                    } else {
                        Text(L10n.text("Choose a vision-capable OCR model in Settings.", language: language))
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
            }

            settingRow(title: L10n.text("Default recognition mode", language: language)) {
                Picker("", selection: Binding(
                    get: { appState.preferences.ocr.defaultMode },
                    set: { newValue in
                        appState.setOCRMode(newValue)
                    }
                )) {
                    ForEach(OCRMode.allCases) { mode in
                        Text(L10n.ocrModeName(mode, language: language)).tag(mode)
                    }
                }
                .labelsHidden()
                .pickerStyle(.menu)
                .frame(width: 190, alignment: .leading)
            }

            settingRow(title: L10n.text("History", language: language)) {
                VStack(alignment: .leading, spacing: 8) {
                    checkboxLine(
                        title: L10n.text("Save OCR results to recent history", language: language),
                        isOn: Binding(
                            get: { appState.preferences.ocr.persistHistory },
                            set: { newValue in
                                appState.updatePreferences { $0.ocr.persistHistory = newValue }
                            }
                        )
                    )
                    Text(L10n.text("Raw images are never saved to recent history.", language: language))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }

            settingRow(title: L10n.text("Privacy", language: language)) {
                webPagePrivacyLine(
                    systemImage: "lock.doc",
                    title: L10n.text("Remote provider image payload", language: language),
                    body: L10n.text("When the OCR model is remote, the normalized local image payload is sent to that configured provider. Remote image URLs are downloaded locally first and are not passed through.", language: language)
                )
            }
        }
    }

    private var languageRoutingSettingsSection: some View {
        settingRow(title: L10n.text("Language Routing", language: language)) {
            VStack(alignment: .leading, spacing: 7) {
                languageRoutingToggle(
                    title: L10n.text("Enable language routing", language: language),
                    isOn: Binding(
                        get: { appState.preferences.languageRouting.enabled },
                        set: { newValue in
                            appState.updatePreferences { $0.languageRouting.enabled = newValue }
                        }
                    )
                )

                HStack(alignment: .center, spacing: 8) {
                    Text(L10n.text("fastText model", language: language))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .frame(width: 96, alignment: .leading)
                    languageRoutingModelPicker
                }

                languageRoutingModelPathFields

                HStack(alignment: .top, spacing: 18) {
                    VStack(alignment: .leading, spacing: 5) {
                        languageRoutingToggle(
                            title: L10n.text("Use for text tasks", language: language),
                            isOn: Binding(
                                get: { appState.preferences.languageRouting.useForTextTasks },
                                set: { newValue in
                                    appState.updatePreferences { $0.languageRouting.useForTextTasks = newValue }
                                }
                            )
                        )
                        languageRoutingToggle(
                            title: L10n.text("Use for webpage translation", language: language),
                            isOn: Binding(
                                get: { appState.preferences.languageRouting.useForWebpage },
                                set: { newValue in
                                    appState.updatePreferences { $0.languageRouting.useForWebpage = newValue }
                                }
                            )
                        )
                    }
                    .frame(width: 188, alignment: .topLeading)

                    VStack(alignment: .leading, spacing: 5) {
                        languageRoutingToggle(
                            title: L10n.text("Use for OCR", language: language),
                            isOn: Binding(
                                get: { appState.preferences.languageRouting.useForOCR },
                                set: { newValue in
                                    appState.updatePreferences { $0.languageRouting.useForOCR = newValue }
                                }
                            )
                        )
                        languageRoutingToggle(
                            title: L10n.text("Use for subtitles", language: language),
                            isOn: Binding(
                                get: { appState.preferences.languageRouting.useForSubtitles },
                                set: { newValue in
                                    appState.updatePreferences { $0.languageRouting.useForSubtitles = newValue }
                                }
                            )
                        )
                    }
                    .frame(width: 150, alignment: .topLeading)
                }

                VStack(alignment: .leading, spacing: 6) {
                    Stepper(
                        "\(L10n.text("Latin short-text minimum", language: language)): \(appState.preferences.languageRouting.shortTextMinimumCharactersLatin)",
                        value: Binding(
                            get: { appState.preferences.languageRouting.shortTextMinimumCharactersLatin },
                            set: { newValue in
                                appState.updatePreferences { $0.languageRouting.shortTextMinimumCharactersLatin = newValue }
                            }
                        ),
                        in: 1...200
                    )
                    Stepper(
                        "\(L10n.text("CJK short-text minimum", language: language)): \(appState.preferences.languageRouting.shortTextMinimumCharactersCJK)",
                        value: Binding(
                            get: { appState.preferences.languageRouting.shortTextMinimumCharactersCJK },
                            set: { newValue in
                                appState.updatePreferences { $0.languageRouting.shortTextMinimumCharactersCJK = newValue }
                            }
                        ),
                        in: 1...80
                    )
                    HStack(spacing: 10) {
                        Label(L10n.text("Low confidence threshold", language: language), systemImage: "gauge.with.dots.needle.33percent")
                            .frame(width: 180, alignment: .leading)
                        Slider(
                            value: Binding(
                                get: { appState.preferences.languageRouting.lowConfidenceThreshold },
                                set: { newValue in
                                    appState.updatePreferences { $0.languageRouting.lowConfidenceThreshold = newValue }
                                }
                            ),
                            in: 0...1
                        )
                        Text(String(format: "%.2f", appState.preferences.languageRouting.lowConfidenceThreshold))
                            .font(.caption.monospacedDigit())
                            .foregroundStyle(.secondary)
                            .frame(width: 42, alignment: .trailing)
                    }
                    .frame(width: 380, alignment: .leading)
                    HStack(spacing: 10) {
                        Label(L10n.text("OCR confidence boost", language: language), systemImage: "text.viewfinder")
                            .frame(width: 180, alignment: .leading)
                        Slider(
                            value: Binding(
                                get: { appState.preferences.languageRouting.ocrConfidenceBoost },
                                set: { newValue in
                                    appState.updatePreferences { $0.languageRouting.ocrConfidenceBoost = newValue }
                                }
                            ),
                            in: 0...1
                        )
                        Text(String(format: "%.2f", appState.preferences.languageRouting.ocrConfidenceBoost))
                            .font(.caption.monospacedDigit())
                            .foregroundStyle(.secondary)
                            .frame(width: 42, alignment: .trailing)
                    }
                    .frame(width: 380, alignment: .leading)
                }

                mediaASRCommandField(
                    title: L10n.text("Language ID command", language: language),
                    text: Binding(
                        get: { appState.preferences.languageRouting.commandTemplate },
                        set: { newValue in
                            appState.updatePreferences { $0.languageRouting.commandTemplate = newValue }
                        }
                    ),
                    placeholder: "{python} {sidecar} --model {model_ftz}"
                )
                Text(L10n.text("Use {python}, {sidecar}, {model_ftz}, {model_bin}, and {variant}. Empty field uses the bundled fastText sidecar when the local model is installed.", language: language))
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)

                fieldStack(title: L10n.text("Sample detection text", language: language), width: 500) {
                    CommandFriendlyTextField(
                        text: $appState.languageDetectionSampleText,
                        placeholder: L10n.text("This is a language detection health check.", language: language)
                    )
                }
                HStack(spacing: 8) {
                    Button {
                        appState.checkLanguageDetectionHealth()
                    } label: {
                        Label(
                            L10n.text("Health Check", language: language),
                            systemImage: appState.languageDetectionHealthCheckInProgress ? "clock" : "stethoscope"
                        )
                    }
                    .controlSize(.small)
                    .disabled(appState.languageDetectionHealthCheckInProgress)
                    Text(L10n.text("Fixture mode uses LLMTOOLS_LID_FIXTURE_JSON for dependency-free checks.", language: language))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                if let report = appState.languageDetectionHealthReport {
                    languageDetectionHealthReportView(report)
                }
            }
        }
    }

    private var languageRoutingModelPicker: some View {
        Picker(L10n.text("fastText model", language: language), selection: Binding(
            get: { appState.preferences.languageRouting.modelVariant },
            set: { newValue in
                appState.updatePreferences { $0.languageRouting.modelVariant = newValue }
            }
        )) {
            ForEach(LanguageIDModelVariant.allCases, id: \.self) { variant in
                Text(languageIDModelVariantName(variant)).tag(variant)
            }
        }
        .labelsHidden()
        .pickerStyle(.segmented)
        .controlSize(.small)
        .frame(width: 260, alignment: .leading)
    }

    private var languageRoutingModelPathFields: some View {
        VStack(alignment: .leading, spacing: 6) {
            modelPathField(
                title: L10n.text("FTZ model file", language: language),
                text: Binding(
                    get: { appState.preferences.languageRouting.ftzModelPath },
                    set: { newValue in
                        appState.updatePreferences { $0.languageRouting.ftzModelPath = newValue }
                    }
                ),
                placeholder: FastTextLIDCommandRunner.defaultFTZModelPath,
                chooseAction: { openLanguageRoutingModelPanel(.ftz) }
            )
            modelPathField(
                title: L10n.text("BIN model file", language: language),
                text: Binding(
                    get: { appState.preferences.languageRouting.binModelPath },
                    set: { newValue in
                        appState.updatePreferences { $0.languageRouting.binModelPath = newValue }
                    }
                ),
                placeholder: FastTextLIDCommandRunner.defaultBINModelPath,
                chooseAction: { openLanguageRoutingModelPanel(.bin) }
            )
            Text(L10n.text("Leave empty to use the installed fastText model under Application Support, or the LLMTOOLS_LID_MODEL_* environment variables.", language: language))
                .font(.caption)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    private func languageRoutingToggle(
        title: String,
        isOn: Binding<Bool>
    ) -> some View {
        Toggle(title, isOn: isOn)
            .toggleStyle(.checkbox)
            .font(.subheadline)
            .fixedSize(horizontal: false, vertical: true)
    }

    private var speakerDiarizationSettingsSection: some View {
        settingRow(title: L10n.text("Speaker Diarization", language: language)) {
            VStack(alignment: .leading, spacing: 8) {
                checkboxLine(
                    title: L10n.text("Enable for file subtitles", language: language),
                    isOn: Binding(
                        get: { appState.preferences.speakerDiarization.enabledForFileSubtitles },
                        set: { newValue in
                            appState.setFileSpeakerDiarizationEnabled(newValue)
                        }
                    )
                )
                checkboxLine(
                    title: L10n.text("Enable for live subtitles", language: language),
                    isOn: Binding(
                        get: { appState.preferences.speakerDiarization.enabledForLiveSubtitles },
                        set: { _ in }
                    )
                )
                .disabled(true)
                Text(L10n.text("Live speaker diarization remains disabled until the realtime spike passes.", language: language))
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)

                fieldStack(title: L10n.text("pyannote model", language: language), width: 500) {
                    CommandFriendlyTextField(
                        text: Binding(
                            get: { appState.preferences.speakerDiarization.modelIdentifier },
                            set: { newValue in
                                appState.updatePreferences { $0.speakerDiarization.modelIdentifier = newValue }
                            }
                        ),
                        placeholder: SpeakerDiarizationPreferences.defaultModelIdentifier
                    )
                }
                HStack(spacing: 8) {
                    Button {
                        appState.updatePreferences {
                            $0.speakerDiarization.modelIdentifier = SpeakerDiarizationPreferences.defaultModelIdentifier
                        }
                    } label: {
                        Label(L10n.text("Use default model", language: language), systemImage: "arrow.counterclockwise")
                    }
                    .controlSize(.small)
                    Button {
                        openSpeakerDiarizationModelPanel()
                    } label: {
                        Label(L10n.text("Choose local pyannote config", language: language), systemImage: "folder")
                    }
                    .controlSize(.small)
                }
                Text(L10n.text("Use a Hugging Face repo id such as pyannote/speaker-diarization-3.1, or choose a local pyannote config.yaml if the model is already downloaded.", language: language))
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)

                fieldStack(title: L10n.text("HF cache directory", language: language), width: 500) {
                    CommandFriendlyTextField(
                        text: Binding(
                            get: { appState.preferences.speakerDiarization.cacheDirectory },
                            set: { newValue in
                                appState.updatePreferences { $0.speakerDiarization.cacheDirectory = newValue }
                            }
                        ),
                        placeholder: SpeakerDiarizationCommandRunner.defaultHFHomeDirectory.path
                    )
                }
                HStack(spacing: 8) {
                    Button {
                        openSpeakerDiarizationCachePanel()
                    } label: {
                        Label(L10n.text("Choose cache folder", language: language), systemImage: "folder")
                    }
                    .controlSize(.small)
                    Button {
                        revealSpeakerDiarizationCacheFolder()
                    } label: {
                        Label(L10n.text("Open cache folder", language: language), systemImage: "arrow.up.forward.app")
                    }
                    .controlSize(.small)
                }
                Text(
                    String(
                        format: L10n.text("Leave empty to use the Hugging Face default cache: %@.", language: language),
                        SpeakerDiarizationCommandRunner.defaultHFHomeDirectory.path
                    )
                )
                .font(.caption)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)

                mediaASRCommandField(
                    title: L10n.text("Diarization command", language: language),
                    text: Binding(
                        get: { appState.preferences.speakerDiarization.commandTemplate },
                        set: { newValue in
                            appState.updatePreferences { $0.speakerDiarization.commandTemplate = newValue }
                        }
                    ),
                    placeholder: "{python} {sidecar} --model {diarization_model} --audio {audio_wav_16k_mono} --output {output_json}"
                )
                Text(L10n.text("Use {audio_wav_16k_mono}, {output_json}, {diarization_model}, {hf_cache}, and {hf_token}. Empty field uses the bundled pyannote sidecar when the local runtime is installed.", language: language))
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)

                VStack(alignment: .leading, spacing: 4) {
                    Text(L10n.text("HF token local storage", language: language))
                        .font(.caption.weight(.semibold))
                    Text(SpeakerDiarizationTokenStore.tokenFileURL.path)
                        .font(.caption2.monospaced())
                        .foregroundStyle(.secondary)
                        .textSelection(.enabled)
                        .lineLimit(2)
                        .fixedSize(horizontal: false, vertical: true)
                }
                HStack(alignment: .bottom, spacing: 8) {
                    fieldStack(title: L10n.text("HF token", language: language), width: 360) {
                        CommandFriendlyTextField(
                            text: $speakerDiarizationTokenDraft,
                            placeholder: "hf_...",
                            isSecure: true
                        )
                    }
                    Button {
                        appState.saveSpeakerDiarizationHFToken(speakerDiarizationTokenDraft)
                        speakerDiarizationTokenDraft = ""
                    } label: {
                        Label(L10n.text("Save Token", language: language), systemImage: "key.fill")
                    }
                    .controlSize(.small)
                    .disabled(speakerDiarizationTokenDraft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                    Button {
                        appState.deleteSpeakerDiarizationHFToken()
                        speakerDiarizationTokenDraft = ""
                    } label: {
                        Label(L10n.text("Delete Token", language: language), systemImage: "trash")
                    }
                    .controlSize(.small)
                }
                HStack(spacing: 8) {
                    Button {
                        openPyannoteModelTerms()
                    } label: {
                        Label(L10n.text("Open model terms", language: language), systemImage: "checkmark.seal")
                    }
                    .controlSize(.small)
                    Button {
                        openExternalURL("https://huggingface.co/settings/tokens")
                    } label: {
                        Label(L10n.text("Create HF token", language: language), systemImage: "safari")
                    }
                    .controlSize(.small)
                }
                checkboxLine(
                    title: L10n.text("Persist speaker embeddings", language: language),
                    isOn: Binding(
                        get: { appState.preferences.speakerDiarization.persistSpeakerEmbeddings },
                        set: { newValue in
                            appState.updatePreferences { $0.speakerDiarization.persistSpeakerEmbeddings = newValue }
                        }
                    )
                )
                Text(L10n.text("pyannote requires accepting the Hugging Face terms for both speaker-diarization-3.1 and segmentation-3.0 unless you point to a fully cached local config. Tokens stay in a local Application Support file or environment variables; llmTools does not upload audio.", language: language))
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)

                HStack(spacing: 8) {
                    Button {
                        appState.checkSpeakerDiarizationHealth()
                    } label: {
                        Label(
                            L10n.text("Health Check", language: language),
                            systemImage: appState.speakerDiarizationHealthCheckInProgress ? "clock" : "stethoscope"
                        )
                    }
                    .controlSize(.small)
                    .disabled(appState.speakerDiarizationHealthCheckInProgress)
                    Text(L10n.text("Fixture mode uses LLMTOOLS_DIARIZATION_FIXTURE_JSON for dependency-free checks.", language: language))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                if let report = appState.speakerDiarizationHealthReport {
                    speakerDiarizationHealthReportView(report)
                }
            }
        }
    }

    private func fastTranslationSurfaceEnginePicker(selection: Binding<FastTranslationSurfaceEngine>) -> some View {
        Picker("", selection: selection) {
            ForEach(FastTranslationSurfaceEngine.allCases, id: \.self) { engine in
                Text(fastTranslationSurfaceEngineName(engine)).tag(engine)
            }
        }
        .labelsHidden()
        .pickerStyle(.segmented)
        .frame(width: 300, alignment: .leading)
    }

    private var textTranslationEngineSettingsSection: some View {
        settingRow(title: L10n.text("Text translation engine", language: language)) {
            VStack(alignment: .leading, spacing: 6) {
                fastTranslationSurfaceEnginePicker(selection: Binding(
                    get: { appState.preferences.fastTranslation.textEngine },
                    set: { newValue in
                        appState.updatePreferences { $0.fastTranslation.textEngine = newValue }
                    }
                ))
                Text(L10n.text("Only Translate can use fast MT. Polish, summary, explanation, and TODO always use the default LLM model.", language: language))
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    private var subtitleTranslationEngineSettingsSection: some View {
        settingRow(title: L10n.text("Subtitle translation engine", language: language)) {
            VStack(alignment: .leading, spacing: 6) {
                fastTranslationSurfaceEnginePicker(selection: Binding(
                    get: { appState.preferences.fastTranslation.subtitleEngine },
                    set: { newValue in
                        appState.updatePreferences { $0.fastTranslation.subtitleEngine = newValue }
                    }
                ))
                Text(L10n.text("Subtitles can use LLM or the shared Fast MT runtime configured under Models.", language: language))
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    private var webPageTranslationEngineSettingsSection: some View {
        settingRow(title: L10n.text("Webpage translation engine", language: language)) {
            VStack(alignment: .leading, spacing: 6) {
                fastTranslationSurfaceEnginePicker(selection: Binding(
                    get: { appState.preferences.fastTranslation.webpageEngine },
                    set: { newValue in
                        appState.updatePreferences { $0.fastTranslation.webpageEngine = newValue }
                    }
                ))
                Text(L10n.text("Webpage translation can use LLM or the shared Fast MT runtime configured under Models.", language: language))
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    private var fastTranslationSettingsSection: some View {
        settingRow(title: L10n.text("Fast MT", language: language)) {
            VStack(alignment: .leading, spacing: 8) {
                checkboxLine(
                    title: L10n.text("Force LLM translation", language: language),
                    isOn: Binding(
                        get: { appState.preferences.fastTranslation.forceLLM },
                        set: { newValue in
                            appState.updatePreferences { $0.fastTranslation.forceLLM = newValue }
                        }
                    )
                )
                Text(L10n.text("When enabled, all fast MT routes immediately fall back to the normal LLM path.", language: language))
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)

                Picker(L10n.text("Fast MT model", language: language), selection: Binding(
                    get: { appState.preferences.fastTranslation.modelVariant },
                    set: { newValue in
                        appState.updatePreferences { $0.fastTranslation.modelVariant = newValue }
                    }
                )) {
                    ForEach(FastTranslationModelVariant.allCases, id: \.self) { variant in
                        Text(fastTranslationModelVariantName(variant)).tag(variant)
                    }
                }
                .pickerStyle(.menu)
                .frame(width: 300, alignment: .leading)
                Text(L10n.text("OPUS is fastest for English to Chinese. NLLB 600M supports common multilingual pairs with higher latency but much better coverage.", language: language))
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)

                fastTranslationModelPathFields

                Picker(L10n.text("Fallback policy", language: language), selection: Binding(
                    get: { appState.preferences.fastTranslation.fallbackPolicy },
                    set: { newValue in
                        appState.updatePreferences { $0.fastTranslation.fallbackPolicy = newValue }
                    }
                )) {
                    ForEach(FastTranslationFallbackPolicy.allCases, id: \.self) { policy in
                        Text(fastTranslationFallbackPolicyName(policy)).tag(policy)
                    }
                }
                .pickerStyle(.segmented)
                .frame(width: 300, alignment: .leading)
                Text(L10n.text("When fallback is enabled, any Fast MT route uses the normal LLM path if fast MT is unavailable or does not support the language pair.", language: language))
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)

                Stepper(
                    "\(L10n.text("Fast MT max concurrent batches", language: language)): \(appState.preferences.fastTranslation.maxConcurrentBatches)",
                    value: Binding(
                        get: { appState.preferences.fastTranslation.maxConcurrentBatches },
                        set: { newValue in
                            appState.updatePreferences { $0.fastTranslation.maxConcurrentBatches = newValue }
                        }
                    ),
                    in: 1...8
                )

                mediaASRCommandField(
                    title: L10n.text("CTranslate2 command", language: language),
                    text: Binding(
                        get: { appState.preferences.fastTranslation.commandTemplates.ctranslate2 },
                        set: { newValue in
                            appState.updatePreferences { $0.fastTranslation.commandTemplates.ctranslate2 = newValue }
                        }
                    ),
                    placeholder: "{python} {sidecar} --engine ctranslate2 --model {model_ct2}"
                )
                mediaASRCommandField(
                    title: L10n.text("Argos command", language: language),
                    text: Binding(
                        get: { appState.preferences.fastTranslation.commandTemplates.argos },
                        set: { newValue in
                            appState.updatePreferences { $0.fastTranslation.commandTemplates.argos = newValue }
                        }
                    ),
                    placeholder: "{python} {sidecar} --engine argos"
                )
                mediaASRCommandField(
                    title: L10n.text("Generic fast MT command", language: language),
                    text: Binding(
                        get: { appState.preferences.fastTranslation.commandTemplates.generic },
                        set: { newValue in
                            appState.updatePreferences { $0.fastTranslation.commandTemplates.generic = newValue }
                        }
                    ),
                    placeholder: "fastmt-sidecar --stdio"
                )
                Text(L10n.text("Use {python}, {sidecar}, {engine}, and {model_ct2}. These commands are used only by fast MT routes.", language: language))
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)

                HStack(spacing: 8) {
                    Button {
                        appState.checkFastTranslationHealth()
                    } label: {
                        Label(
                            L10n.text("Health Check", language: language),
                            systemImage: appState.fastTranslationHealthCheckInProgress ? "clock" : "stethoscope"
                        )
                    }
                    .controlSize(.small)
                    .disabled(appState.fastTranslationHealthCheckInProgress)
                    Text(L10n.text("Fixture mode uses LLMTOOLS_FAST_MT_FIXTURE_JSON for dependency-free checks.", language: language))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                if let report = appState.fastTranslationHealthReport {
                    fastTranslationHealthReportView(report)
                }
            }
        }
    }

    private var fastTranslationModelPathFields: some View {
        VStack(alignment: .leading, spacing: 6) {
            modelPathField(
                title: L10n.text("OPUS CTranslate2 model folder", language: language),
                text: Binding(
                    get: { appState.preferences.fastTranslation.opusMTEnZhCT2ModelPath },
                    set: { newValue in
                        appState.updatePreferences { $0.fastTranslation.opusMTEnZhCT2ModelPath = newValue }
                    }
                ),
                placeholder: FastTranslationCommandRunner.defaultOPUSCT2ModelPath,
                chooseAction: { openFastTranslationModelPanel(.opusMTEnZh) }
            )
            modelPathField(
                title: L10n.text("NLLB CTranslate2 model folder", language: language),
                text: Binding(
                    get: { appState.preferences.fastTranslation.nllb200Distilled600MCT2ModelPath },
                    set: { newValue in
                        appState.updatePreferences { $0.fastTranslation.nllb200Distilled600MCT2ModelPath = newValue }
                    }
                ),
                placeholder: FastTranslationCommandRunner.defaultNLLB600MCT2ModelPath,
                chooseAction: { openFastTranslationModelPanel(.nllb200Distilled600M) }
            )
            Text(L10n.text("Leave empty to use the installed Fast MT model under Application Support, or the LLMTOOLS_FASTMT_* environment variables.", language: language))
                .font(.caption)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    private var ocrSettingsModelPicker: some View {
        Picker("", selection: Binding<UUID?>(
            get: { appState.preferences.ocr.modelID },
            set: { newValue in
                appState.updatePreferences { $0.ocr.modelID = newValue }
            }
        )) {
            Text(L10n.text("No model", language: language)).tag(UUID?.none)
            ForEach(appState.visionCapableModels) { model in
                Text(defaultModelPickerTitle(model)).tag(Optional(model.id))
            }
        }
        .labelsHidden()
        .pickerStyle(.menu)
        .frame(width: 260, alignment: .leading)
        .disabled(appState.visionCapableModels.isEmpty)
    }

    private var settingsMediaFileASRPicker: some View {
        Picker("", selection: Binding<UUID?>(
            get: { appState.preferences.mediaSubtitles.fileASRModelID },
            set: { newValue in
                appState.updatePreferences { $0.mediaSubtitles.fileASRModelID = newValue }
            }
        )) {
            Text(L10n.text("No model", language: language)).tag(UUID?.none)
            ForEach(appState.fileSpeechModels) { model in
                Text(settingsSpeechModelPickerTitle(model)).tag(Optional(model.id))
            }
        }
        .labelsHidden()
        .pickerStyle(.menu)
        .frame(width: 320, alignment: .leading)
        .disabled(appState.fileSpeechModels.isEmpty)
    }

    private var settingsMediaRealtimeASRPicker: some View {
        Picker("", selection: Binding<UUID?>(
            get: { appState.preferences.mediaSubtitles.realtimeASRModelID },
            set: { newValue in
                appState.setRealtimeASRModel(id: newValue)
            }
        )) {
            Text(L10n.text("No model", language: language)).tag(UUID?.none)
            ForEach(appState.realtimeSpeechModels) { model in
                Text(settingsSpeechModelPickerTitle(model)).tag(Optional(model.id))
            }
        }
        .labelsHidden()
        .pickerStyle(.menu)
        .frame(width: 320, alignment: .leading)
        .disabled(appState.realtimeSpeechModels.isEmpty)
    }

    private var settingsLiveMeetingFileASRPicker: some View {
        Picker("", selection: Binding<UUID?>(
            get: { appState.preferences.liveMeeting.fileASRModelID },
            set: { newValue in
                appState.updatePreferences { $0.liveMeeting.fileASRModelID = newValue }
            }
        )) {
            Text(L10n.text("No model", language: language)).tag(UUID?.none)
            ForEach(appState.fileSpeechModels) { model in
                Text(settingsSpeechModelPickerTitle(model)).tag(Optional(model.id))
            }
        }
        .labelsHidden()
        .pickerStyle(.menu)
        .frame(width: 320, alignment: .leading)
        .disabled(appState.fileSpeechModels.isEmpty)
    }

    private var settingsLiveMeetingRealtimeASRPicker: some View {
        Picker("", selection: Binding<UUID?>(
            get: { appState.preferences.liveMeeting.realtimeASRModelID },
            set: { newValue in
                appState.updatePreferences { $0.liveMeeting.realtimeASRModelID = newValue }
            }
        )) {
            Text(L10n.text("No model", language: language)).tag(UUID?.none)
            ForEach(appState.meetingCaptureSpeechModels) { model in
                Text(settingsMeetingSpeechModelPickerTitle(model)).tag(Optional(model.id))
            }
        }
        .labelsHidden()
        .pickerStyle(.menu)
        .frame(width: 320, alignment: .leading)
        .disabled(appState.meetingCaptureSpeechModels.isEmpty)
    }

    private var settingsLiveMeetingNotesModelPicker: some View {
        Picker("", selection: Binding<UUID?>(
            get: { appState.preferences.liveMeeting.notesModelID },
            set: { newValue in
                appState.updatePreferences { $0.liveMeeting.notesModelID = newValue }
            }
        )) {
            Text(L10n.text("No model", language: language)).tag(UUID?.none)
            ForEach(appState.models.filter { $0.enabled && $0.capabilities.supportsText && !$0.isRemoteProvider && ($0.format == .gguf || $0.format == .mlx) }) { model in
                Text(defaultModelPickerTitle(model)).tag(Optional(model.id))
            }
        }
        .labelsHidden()
        .pickerStyle(.menu)
        .frame(width: 320, alignment: .leading)
        .disabled(appState.models.allSatisfy { !$0.enabled || !$0.capabilities.supportsText || $0.isRemoteProvider || ($0.format != .gguf && $0.format != .mlx) })
    }

    private func settingsLiveASRPartialControl(for model: ModelDescriptor) -> some View {
        let effective = appState.effectiveLiveASRPartialMilliseconds(for: model)
        let defaultValue = appState.defaultLiveASRPartialMilliseconds(for: model)
        let hasOverride = appState.liveASRPartialMillisecondsOverride(for: model) != nil
        return VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 10) {
                Label(L10n.text("Partial window", language: language), systemImage: "waveform")
                    .frame(width: 120, alignment: .leading)
                Slider(
                    value: Binding<Double>(
                        get: { Double(appState.effectiveLiveASRPartialMilliseconds(for: model)) },
                        set: { newValue in
                            appState.setLiveASRPartialMillisecondsOverride(Int(newValue), for: model)
                        }
                    ),
                    in: Double(MediaSubtitlePreferences.minimumLiveASRPartialMilliseconds)...Double(MediaSubtitlePreferences.maximumLiveASRPartialMilliseconds),
                    step: Double(MediaSubtitlePreferences.liveASRPartialStepMilliseconds)
                )
                Text("\(effective) ms")
                    .font(.caption.monospacedDigit())
                    .foregroundStyle(.secondary)
                    .frame(width: 70, alignment: .trailing)
                Button {
                    appState.setLiveASRPartialMillisecondsOverride(nil, for: model)
                } label: {
                    Label(L10n.text("Reset", language: language), systemImage: "arrow.counterclockwise")
                        .labelStyle(.iconOnly)
                }
                .buttonStyle(.borderless)
                .disabled(!hasOverride)
                .help(L10n.text("Reset partial window to the tested default for this model.", language: language))
            }
            .frame(width: 420, alignment: .leading)
            Text(liveASRPartialWindowHelp(defaultValue: defaultValue))
                .font(.caption)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    private func liveASRPartialWindowHelp(defaultValue: Int) -> String {
        switch language {
        case .chinese:
            return "控制 ASR partial 文本的窗口/节奏，不是底层 PCM 切片大小。数值越低首条字幕延迟越小，数值越高 partial 文本上下文越多。当前模型默认值：\(defaultValue) ms。"
        case .english:
            return "This controls the partial ASR window/cadence, not the low-level PCM slice size. Lower values reduce first-subtitle latency; higher values give the ASR model more context for partial text. Default for the selected model: \(defaultValue) ms."
        }
    }

    private var mediaSubtitleSettingsPage: some View {
        settingsForm(maxWidth: 620) {
            settingRow(title: L10n.text("Feature", language: language)) {
                VStack(alignment: .leading, spacing: 8) {
                    checkboxLine(
                        title: L10n.text("Enable media subtitles", language: language),
                        isOn: Binding(
                            get: { appState.preferences.mediaSubtitles.isEnabled },
                            set: { newValue in
                                appState.updatePreferences { $0.mediaSubtitles.isEnabled = newValue }
                            }
                        )
                    )
                    Text(L10n.text("ASR is local-only in Phase 4. No remote ASR fallback is used.", language: language))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }

            settingRow(title: L10n.text("Default realtime model", language: language)) {
                VStack(alignment: .leading, spacing: 8) {
                    settingsMediaRealtimeASRPicker
                    if let model = appState.selectedRealtimeASRModel {
                        settingsLiveASRPartialControl(for: model)
                    }
                    HStack(spacing: 8) {
                        Button {
                            appState.checkMediaSubtitleASRHealth(mode: .realtime)
                        } label: {
                            Label(L10n.text("Health Check", language: language), systemImage: appState.mediaSubtitleHealthCheckMode == .realtime ? "clock" : "stethoscope")
                        }
                        .controlSize(.small)
                        .disabled(appState.mediaSubtitleHealthCheckMode != nil || appState.selectedRealtimeASRModel == nil)
                        Text(L10n.text("Fun-ASR-MLT-Nano remains the broad-language default; MLX Qwen3-ASR and whisper.cpp Core ML also run realtime through persistent local sidecars.", language: language))
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    if let report = appState.mediaSubtitleHealthReport,
                       report.modelID == appState.selectedRealtimeASRModel?.id {
                        mediaASRHealthReportView(report, mode: .realtime)
                    }
                }
            }

            settingRow(title: L10n.text("Default file model", language: language)) {
                VStack(alignment: .leading, spacing: 8) {
                    settingsMediaFileASRPicker
                    HStack(spacing: 8) {
                        Button {
                            appState.checkMediaSubtitleASRHealth(mode: .fileOnly)
                        } label: {
                            Label(L10n.text("Health Check", language: language), systemImage: appState.mediaSubtitleHealthCheckMode == .fileOnly ? "clock" : "stethoscope")
                        }
                        .controlSize(.small)
                        .disabled(appState.mediaSubtitleHealthCheckMode != nil || appState.selectedFileASRModel == nil)
                        Text(L10n.text("VibeVoice-ASR is a heavy file-only rich transcription model; native speaker/timestamp output is used before external diarization.", language: language))
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    if let report = appState.mediaSubtitleHealthReport,
                       report.modelID == appState.selectedFileASRModel?.id {
                        mediaASRHealthReportView(report, mode: .fileOnly)
                    }
                }
            }

            settingRow(title: L10n.text("Local ASR runtime", language: language)) {
                VStack(alignment: .leading, spacing: 8) {
                    mediaASRCommandField(
                        title: L10n.text("Fun-ASR command", language: language),
                        text: Binding(
                            get: { appState.preferences.mediaSubtitles.funASRCommandTemplate },
                            set: { newValue in
                                appState.updatePreferences { $0.mediaSubtitles.funASRCommandTemplate = newValue }
                            }
                        ),
                        placeholder: "fun-asr-stream --model {model} --audio {audio} --language {language}"
                    )
                    mediaASRCommandField(
                        title: L10n.text("SenseVoice command", language: language),
                        text: Binding(
                            get: { appState.preferences.mediaSubtitles.senseVoiceCommandTemplate },
                            set: { newValue in
                                appState.updatePreferences { $0.mediaSubtitles.senseVoiceCommandTemplate = newValue }
                            }
                        ),
                        placeholder: "sensevoice --model {model} --audio {audio} --language {language}"
                    )
                    mediaASRCommandField(
                        title: L10n.text("Qwen3-ASR command", language: language),
                        text: Binding(
                            get: { appState.preferences.mediaSubtitles.qwen3ASRCommandTemplate },
                            set: { newValue in
                                appState.updatePreferences { $0.mediaSubtitles.qwen3ASRCommandTemplate = newValue }
                            }
                        ),
                        placeholder: "qwen3-asr --model {model} --audio {audio} --language {language}"
                    )
                    mediaASRCommandField(
                        title: L10n.text("VibeVoice-ASR command", language: language),
                        text: Binding(
                            get: { appState.preferences.mediaSubtitles.vibeVoiceASRCommandTemplate },
                            set: { newValue in
                                appState.updatePreferences { $0.mediaSubtitles.vibeVoiceASRCommandTemplate = newValue }
                            }
                        ),
                        placeholder: "vibevoice-asr --model {model} --audio {audio}"
                    )
                    mediaASRCommandField(
                        title: L10n.text("Whisper command", language: language),
                        text: Binding(
                            get: { appState.preferences.mediaSubtitles.whisperCommandTemplate },
                            set: { newValue in
                                appState.updatePreferences { $0.mediaSubtitles.whisperCommandTemplate = newValue }
                            }
                        ),
                        placeholder: "whisper-cli -m {model} -f {audio} -l {language}"
                    )
                    mediaASRCommandField(
                        title: L10n.text("Generic ASR command", language: language),
                        text: Binding(
                            get: { appState.preferences.mediaSubtitles.genericASRCommandTemplate },
                            set: { newValue in
                                appState.updatePreferences { $0.mediaSubtitles.genericASRCommandTemplate = newValue }
                            }
                        ),
                        placeholder: "local-asr --model {model} --audio {audio} --language {language}"
                    )
                    Text(L10n.text("Use {model}, {audio}, {language}, {mode}, and {isFinal}. Empty fields fall back to environment variables or detected local runtimes.", language: language))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }

            settingRow(title: L10n.text("Speaker Diarization", language: language)) {
                VStack(alignment: .leading, spacing: 8) {
                    checkboxLine(
                        title: L10n.text("Enable for file subtitles", language: language),
                        isOn: Binding(
                            get: { appState.preferences.speakerDiarization.enabledForFileSubtitles },
                            set: { newValue in
                                appState.setFileSpeakerDiarizationEnabled(newValue)
                            }
                        )
                    )
                    Text(L10n.text("pyannote model, token, cache, command, and runtime are managed under Models > Model Settings.", language: language))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                    HStack(spacing: 8) {
                        Button {
                            navigation.selectedTab = .models
                            selectedModelSettingsPane = .settings
                        } label: {
                            Label(L10n.text("Configure pyannote in Model Settings", language: language), systemImage: "slider.horizontal.3")
                        }
                        .controlSize(.small)
                        Label(appState.preferences.speakerDiarization.modelIdentifier, systemImage: "person.wave.2")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                            .truncationMode(.middle)
                            .frame(maxWidth: 280, alignment: .leading)
                            .help(appState.preferences.speakerDiarization.modelIdentifier)
                    }
                    if let report = appState.speakerDiarizationHealthReport {
                        Text(report.message)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
            }

            subtitleTranslationEngineSettingsSection

            settingRow(title: L10n.text("Default subtitle settings", language: language)) {
                VStack(alignment: .leading, spacing: 8) {
                    Picker(L10n.text("Target", language: language), selection: Binding(
                        get: { appState.preferences.mediaSubtitles.defaultTargetLanguage },
                        set: { newValue in
                            appState.setMediaSubtitleTargetLanguage(newValue)
                        }
                    )) {
                        Text(L10n.targetLanguageName("Chinese", language: language)).tag("zh-Hans")
                        Text(L10n.targetLanguageName("English", language: language)).tag("en")
                        Text(L10n.targetLanguageName("Japanese", language: language)).tag("Japanese")
                        Text(L10n.targetLanguageName("Korean", language: language)).tag("Korean")
                    }
                    .pickerStyle(.menu)
                    .frame(width: 220, alignment: .leading)
                    .disabled(appState.preferences.mediaSubtitles.defaultSubtitleMode == .original)
                    .help(appState.preferences.mediaSubtitles.defaultSubtitleMode == .original
                        ? L10n.text("Target language applies when Display is Translated or Bilingual.", language: language)
                        : L10n.text("Target", language: language)
                    )

                    Picker(L10n.text("Source language", language: language), selection: Binding(
                        get: { appState.preferences.mediaSubtitles.sourceLanguageHint },
                        set: { newValue in
                            appState.setMediaSubtitleSourceLanguageHint(newValue)
                        }
                    )) {
                        ForEach(ASRSourceLanguageHint.allCases) { hint in
                            Text(sourceLanguageHintName(hint)).tag(hint)
                        }
                    }
                    .pickerStyle(.menu)
                    .frame(width: 220, alignment: .leading)

                    Picker(L10n.text("Display", language: language), selection: Binding(
                        get: { appState.preferences.mediaSubtitles.defaultSubtitleMode },
                        set: { newValue in
                            appState.setMediaSubtitleMode(newValue)
                        }
                    )) {
                        ForEach(SubtitleDisplayMode.allCases) { mode in
                            Text(subtitleModeName(mode)).tag(mode)
                        }
                    }
                    .pickerStyle(.segmented)
                    .frame(width: 220, alignment: .leading)

                    Picker(L10n.text("Audio source", language: language), selection: Binding(
                        get: { appState.preferences.mediaSubtitles.liveAudioSource },
                        set: { newValue in
                            appState.setLiveSubtitleAudioSource(newValue)
                        }
                    )) {
                        ForEach(LiveSubtitleAudioSource.allCases) { source in
                            Text(liveAudioSourceName(source)).tag(source)
                        }
                    }
                    .pickerStyle(.menu)
                    .frame(width: 220, alignment: .leading)

                    HStack(spacing: 10) {
                        Label(L10n.text("Window opacity", language: language), systemImage: "circle.lefthalf.filled")
                            .frame(width: 150, alignment: .leading)
                        Slider(
                            value: Binding(
                                get: { appState.preferences.mediaSubtitles.liveWindowOpacity },
                                set: { appState.setLiveSubtitleWindowOpacity($0) }
                            ),
                            in: 0.0...1.0
                        )
                        Text("\(Int(appState.preferences.mediaSubtitles.liveWindowOpacity * 100))%")
                            .font(.caption.monospacedDigit())
                            .foregroundStyle(.secondary)
                            .frame(width: 44, alignment: .trailing)
                    }
                    .frame(width: 320, alignment: .leading)
                }
            }

            settingRow(title: L10n.text("History", language: language)) {
                VStack(alignment: .leading, spacing: 8) {
                    checkboxLine(
                        title: L10n.text("Save transcript history", language: language),
                        isOn: Binding(
                            get: { appState.preferences.mediaSubtitles.saveTranscriptHistory },
                            set: { newValue in
                                appState.updatePreferences { $0.mediaSubtitles.saveTranscriptHistory = newValue }
                            }
                        )
                    )
                    checkboxLine(
                        title: L10n.text("Save translated subtitle history", language: language),
                        isOn: Binding(
                            get: { appState.preferences.mediaSubtitles.saveTranslatedSubtitleHistory },
                            set: { newValue in
                                appState.updatePreferences { $0.mediaSubtitles.saveTranslatedSubtitleHistory = newValue }
                            }
                        )
                    )
                    Text(L10n.text("Raw audio, full page URLs, page titles, transcripts, and translated subtitles are not saved by default.", language: language))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }

        }
    }

    private var liveMeetingSettingsPage: some View {
        settingsForm(maxWidth: 620) {
            settingRow(title: localizedSettingsText(chinese: "会议采集模型", english: "Meeting Capture Model")) {
                VStack(alignment: .leading, spacing: 8) {
                    settingsLiveMeetingRealtimeASRPicker
                    Text(localizedSettingsText(
                        chinese: "用于麦克风和系统音频。VibeVoice 等模型原生联合输出转写与说话人；普通 ASR 先在自然停顿处输出文字，再由本地 pyannote 延迟回填 speaker。该选择不影响实时字幕。",
                        english: "Used for microphone and system audio. Speaker-aware models such as VibeVoice emit transcript and speakers jointly; ordinary ASR emits text at natural pauses and receives delayed local pyannote speaker labels. This does not affect Live Subtitles."
                    ))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                    Button {
                        appState.checkLiveMeetingASRHealth(mode: .realtime)
                    } label: {
                        Label(localizedSettingsText(chinese: "健康检查", english: "Health Check"), systemImage: appState.liveMeetingASRHealthCheckMode == .realtime ? "clock" : "stethoscope")
                    }
                    .controlSize(.small)
                    .disabled(appState.liveMeetingASRHealthCheckMode != nil || appState.selectedLiveMeetingRealtimeASRModel == nil)
                    if let report = appState.liveMeetingASRHealthReport,
                       report.modelID == appState.selectedLiveMeetingRealtimeASRModel?.id {
                        mediaASRHealthReportView(
                            report,
                            mode: appState.selectedLiveMeetingRealtimeASRModel?.capabilities.meetingCaptureRuntimeMode ?? .realtime
                        )
                    }
                }
            }

            settingRow(title: localizedSettingsText(chinese: "会议文件 ASR", english: "Meeting File ASR")) {
                VStack(alignment: .leading, spacing: 8) {
                    settingsLiveMeetingFileASRPicker
                    Text(localizedSettingsText(
                        chinese: "用于本地音频和视频文件的离线会议转写；视频仍通过现有媒体管线抽取音频。",
                        english: "Used for offline meeting transcription from local audio and video files. Video audio is still extracted through the existing media pipeline."
                    ))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                    Button {
                        appState.checkLiveMeetingASRHealth(mode: .fileOnly)
                    } label: {
                        Label(localizedSettingsText(chinese: "健康检查", english: "Health Check"), systemImage: appState.liveMeetingASRHealthCheckMode == .fileOnly ? "clock" : "stethoscope")
                    }
                    .controlSize(.small)
                    .disabled(appState.liveMeetingASRHealthCheckMode != nil || appState.selectedLiveMeetingFileASRModel == nil)
                    if let report = appState.liveMeetingASRHealthReport,
                       report.modelID == appState.selectedLiveMeetingFileASRModel?.id {
                        mediaASRHealthReportView(report, mode: .fileOnly)
                    }
                }
            }

            settingRow(title: localizedSettingsText(chinese: "会议纪要模型", english: "Meeting Notes Model")) {
                VStack(alignment: .leading, spacing: 8) {
                    settingsLiveMeetingNotesModelPicker
                    Text(localizedSettingsText(
                        chinese: "只允许本地 GGUF 或 MLX 文本模型。会议纪要默认中文，绝不使用远程 provider。",
                        english: "Only local GGUF or MLX text models are allowed. Notes default to Chinese and never use a remote provider."
                    ))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }

            settingRow(title: localizedSettingsText(chinese: "默认会议输入", english: "Default Meeting Input")) {
                VStack(alignment: .leading, spacing: 8) {
                    Picker(localizedSettingsText(chinese: "音频来源", english: "Audio Source"), selection: Binding(
                        get: { appState.preferences.liveMeeting.defaultAudioSource },
                        set: { newValue in
                            appState.setLiveMeetingAudioSource(newValue)
                        }
                    )) {
                        Text(localizedSettingsText(chinese: "麦克风", english: "Microphone")).tag(LiveMeetingAudioSource.microphone)
                        Text(localizedSettingsText(chinese: "系统音频", english: "System Audio")).tag(LiveMeetingAudioSource.systemAudio)
                    }
                    .pickerStyle(.menu)
                    .frame(width: 220, alignment: .leading)
                    .disabled(appState.liveMeetingIsRunning)

                    Picker(localizedSettingsText(chinese: "源语言", english: "Source Language"), selection: Binding(
                        get: { appState.preferences.liveMeeting.sourceLanguageHint },
                        set: { newValue in
                            appState.updatePreferences { $0.liveMeeting.sourceLanguageHint = newValue }
                        }
                    )) {
                        ForEach(ASRSourceLanguageHint.allCases) { hint in
                            Text(sourceLanguageHintName(hint)).tag(hint)
                        }
                    }
                    .pickerStyle(.menu)
                    .frame(width: 220, alignment: .leading)
                }
            }

            settingRow(title: localizedSettingsText(chinese: "说话人分离", english: "Speaker Diarization")) {
                VStack(alignment: .leading, spacing: 8) {
                    Text(localizedSettingsText(
                        chinese: "普通实时 ASR 复用模型设置中的本地 pyannote 运行时、模型缓存与健康检查，并在文字出现后延迟回填 speaker；普通本地文件仍可先按 speaker turn 切分再转写。原生说话人 ASR 不重复运行 pyannote；运行时不可用时仍保持仅转写。",
                        english: "Ordinary live ASR reuses the local pyannote runtime, cache, and health check to backfill speakers after text appears; ordinary local files can still be split into speaker turns before ASR. Native speaker ASR skips pyannote. Transcript-only remains available when diarization is unavailable."
                    ))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                    Button {
                        navigation.selectedTab = .models
                        selectedModelSettingsPane = .settings
                    } label: {
                        Label(localizedSettingsText(chinese: "打开说话人分离设置", english: "Open Diarization Settings"), systemImage: "slider.horizontal.3")
                    }
                    .controlSize(.small)
                }
            }
        }
    }

    private var browserIntegrationList: some View {
        VStack(alignment: .leading, spacing: 12) {
            ForEach(browserIntegrationStates) { state in
                browserIntegrationCard(state)
            }
        }
    }

    private func browserIntegrationCard(_ state: BrowserIntegrationState) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 8) {
                Text(state.name)
                    .font(.subheadline.weight(.medium))
                statusBadge(browserStatusName(state.status), systemImage: browserStatusIcon(state.status))
            }
            if let message = state.lastErrorMessage {
                Text(message)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            browserDiagnostics(state)
            VStack(alignment: .leading, spacing: 4) {
                Text(browserExtensionInstallModeText(for: state))
                    .font(.caption.weight(.medium))
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
                Text(browserExtensionManualInstallText(for: state))
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
                Text(browserExtensionPermissionText(for: state))
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            HStack(spacing: 8) {
                Button {
                    repairBrowserBridge(state)
                } label: {
                    Label(browserRepairButtonTitle(for: state), systemImage: "wrench.and.screwdriver")
                }
                .controlSize(.small)

                Button {
                    BrowserIntegrationService.shared.revealExtensionFolder()
                } label: {
                    Label(L10n.text("Reveal Extension Folder", language: language), systemImage: "folder")
                }
                .controlSize(.small)

                Button {
                    BrowserIntegrationService.shared.openExtensionsPage(browserID: state.id)
                } label: {
                    Label(browserOpenExtensionsButtonTitle(for: state), systemImage: "arrow.up.forward.app")
                }
                .controlSize(.small)
            }
        }
        .padding(.bottom, 4)
    }

    private func browserDiagnostics(_ state: BrowserIntegrationState) -> some View {
        VStack(alignment: .leading, spacing: 5) {
            diagnosticLine(
                L10n.text("Extension channel", language: language),
                browserExtensionChannelName(state.extensionChannel)
            )
            diagnosticLine(
                L10n.text("Extension ID", language: language),
                state.extensionID ?? "-"
            )
            diagnosticLine(
                L10n.text("Extension version", language: language),
                state.extensionVersion ?? "-"
            )
            diagnosticLine(
                L10n.text("Native Host", language: language),
                BrowserIntegrationService.shared.nativeHostExecutableDisplayPath()
            )
            diagnosticLine(
                L10n.text("Manifest", language: language),
                state.nativeHostManifestPath ?? "-"
            )
            diagnosticLine(
                L10n.text("Last error code", language: language),
                state.lastErrorCode ?? "-"
            )
            diagnosticLine(
                L10n.text("Last check", language: language),
                state.lastPingAt.map(browserDiagnosticDateFormatter.string(from:)) ?? "-"
            )
        }
        .padding(.vertical, 4)
    }

    private var webPageDomainRulesControl: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 8) {
                CommandFriendlyTextField(
                    text: $webPageDomainDraft,
                    placeholder: L10n.text("example.com", language: language)
                )
                .frame(width: 220)

                Button {
                    addWebPageDomainRule(rule: .alwaysTranslate)
                } label: {
                    Label(L10n.text("Auto translate", language: language), systemImage: "bolt.badge.checkmark")
                }
                .controlSize(.small)
                .disabled(normalizedWebPageDomain(webPageDomainDraft).isEmpty)

                Button {
                    addWebPageDomainRule(rule: .neverTranslate)
                } label: {
                    Label(L10n.text("Never translate", language: language), systemImage: "nosign")
                }
                .controlSize(.small)
                .disabled(normalizedWebPageDomain(webPageDomainDraft).isEmpty)
            }

            VStack(alignment: .leading, spacing: 8) {
                webPageDomainList(
                    title: L10n.text("Auto-translate domains", language: language),
                    domains: appState.preferences.webPageTranslation.autoTranslateDomains,
                    emptyText: L10n.text("No auto-translate domains.", language: language),
                    rule: .alwaysTranslate
                )
                webPageDomainList(
                    title: L10n.text("Never-translate domains", language: language),
                    domains: appState.preferences.webPageTranslation.disabledDomains,
                    emptyText: L10n.text("No never-translate domains.", language: language),
                    rule: .neverTranslate
                )
            }

            Button(role: .destructive) {
                resetWebPageDomainRules()
            } label: {
                Label(L10n.text("Reset site rules", language: language), systemImage: "trash")
            }
            .controlSize(.small)
            .disabled(appState.preferences.webPageTranslation.autoTranslateDomains.isEmpty && appState.preferences.webPageTranslation.disabledDomains.isEmpty)
        }
    }

    private var webPagePrivacyControl: some View {
        VStack(alignment: .leading, spacing: 9) {
            checkboxLine(
                title: L10n.text("Save webpage translations to recent history", language: language),
                isOn: Binding(
                    get: { appState.preferences.webPageTranslation.persistWebHistory },
                    set: { newValue in
                        appState.updatePreferences { $0.webPageTranslation.persistWebHistory = newValue }
                    }
                )
            )

            Text(webPageHistoryPolicyText)
                .font(.caption)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)

            Divider()
                .frame(maxWidth: 420)

            webPagePrivacyLine(
                systemImage: "externaldrive",
                title: L10n.text("Extension cache", language: language),
                body: L10n.text("Stored locally in browser extension storage, capped at 2,000 entries, and clearable from the popup by page, site, or all webpage cache.", language: language)
            )

            webPagePrivacyLine(
                systemImage: "number.square",
                title: L10n.text("Popup diagnostics", language: language),
                body: L10n.text("Uses hashes, counts, timings, model name, and error codes by default; it does not show raw page URL, domain, source text, translated text, or DOM content.", language: language)
            )
        }
    }

    private var webPageSiteDefaultsControl: some View {
        VStack(alignment: .leading, spacing: 8) {
            webPageReadingDefaultsList
            webPageQualityDefaultsList

            Button(role: .destructive) {
                resetWebPageSiteDefaults()
            } label: {
                Label(L10n.text("Reset site defaults", language: language), systemImage: "trash")
            }
            .controlSize(.small)
            .disabled(
                appState.preferences.webPageTranslation.domainReadingModes.isEmpty
                    && appState.preferences.webPageTranslation.domainTranslationQualities.isEmpty
            )
        }
    }

    private var webPageReadingDefaultsList: some View {
        webPageModeDefaultsList(
            title: L10n.text("Reading defaults", language: language),
            emptyText: L10n.text("No reading defaults.", language: language),
            rows: appState.preferences.webPageTranslation.domainReadingModes
                .map { (domain: $0.key, value: L10n.webPageReadingModeName($0.value, language: language)) }
                .sorted { $0.domain < $1.domain },
            remove: { domain in
                removeWebPageReadingDefault(domain: domain)
            }
        )
    }

    private var webPageQualityDefaultsList: some View {
        webPageModeDefaultsList(
            title: L10n.text("Quality defaults", language: language),
            emptyText: L10n.text("No quality defaults.", language: language),
            rows: appState.preferences.webPageTranslation.domainTranslationQualities
                .map { (domain: $0.key, value: L10n.webPageTranslationQualityName($0.value, language: language)) }
                .sorted { $0.domain < $1.domain },
            remove: { domain in
                removeWebPageQualityDefault(domain: domain)
            }
        )
    }

    private var defaultsSettingsPage: some View {
        settingsForm(maxWidth: 620) {
            settingRow(title: L10n.text("Default LLM model", language: language)) {
                VStack(alignment: .leading, spacing: 4) {
                    defaultModelPicker
                    Text(L10n.text("Used by text-mode LLM actions. Webpage translation can choose its own model on the Webpage tab.", language: language))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }

            settingRow(title: L10n.text("Target", language: language)) {
                translationTargetPicker
            }

            settingRow(title: L10n.text("Translation quality", language: language)) {
                defaultTranslationQualityPicker
            }

            textTranslationEngineSettingsSection

            settingRow(title: L10n.text("Style", language: language)) {
                polishStylePicker
            }

            settingRow(title: L10n.text("Summary", language: language)) {
                summaryModeSettingsPicker
            }

            settingRow(title: L10n.text("Explanation", language: language)) {
                explanationModeSettingsPicker
            }

            settingRow(title: L10n.text("TODOs", language: language)) {
                todoExtractionModeSettingsPicker
            }

            settingRow(title: L10n.text("History", language: language)) {
                historyLimitControl
            }
        }
    }

    private var promptSettingsPage: some View {
        settingsForm(maxWidth: 640) {
            settingRow(title: L10n.text("Text prompts", language: language)) {
                VStack(alignment: .leading, spacing: 10) {
                    promptVariablesLine(textPromptVariableText)
                    ForEach(TaskKind.interactiveCases) { task in
                        textPromptEditor(for: task)
                    }
                }
            }

            settingRow(title: L10n.text("Image prompts", language: language)) {
                VStack(alignment: .leading, spacing: 10) {
                    promptVariablesLine(imagePromptVariableText)
                    ocrSystemPromptEditor
                    ForEach(OCRMode.allCases) { mode in
                        ocrPromptEditor(for: mode)
                    }
                }
            }
        }
    }

    private func textPromptEditor(for task: TaskKind) -> some View {
        let prompt = appState.preferences.promptTemplates.textPrompt(for: task)
        let isCustom = prompt.hasCustomPrompt

        return DisclosureGroup {
            VStack(alignment: .leading, spacing: 10) {
                promptTextEditor(
                    title: L10n.text("System prompt", language: language),
                    text: Binding(
                        get: { appState.preferences.promptTemplates.textPrompt(for: task).systemPrompt },
                        set: { newValue in
                            appState.updatePreferences { $0.promptTemplates.setSystemPrompt(newValue, for: task) }
                        }
                    ),
                    defaultText: PromptTemplates.defaultSystemPrompt(for: task),
                    height: 86
                )

                promptTextEditor(
                    title: L10n.text("User prompt", language: language),
                    text: Binding(
                        get: { appState.preferences.promptTemplates.textPrompt(for: task).userPrompt },
                        set: { newValue in
                            appState.updatePreferences { $0.promptTemplates.setUserPrompt(newValue, for: task) }
                        }
                    ),
                    defaultText: defaultUserPromptPreview(for: task),
                    height: 148
                )
            }
            .padding(.top, 8)
        } label: {
            promptDisclosureLabel(
                title: task.title(language: language),
                systemImage: promptIcon(for: task),
                isCustom: isCustom
            )
        }
    }

    private var ocrSystemPromptEditor: some View {
        DisclosureGroup {
            promptTextEditor(
                title: L10n.text("System prompt", language: language),
                text: Binding(
                    get: { appState.preferences.promptTemplates.ocrSystemPrompt },
                    set: { newValue in
                        appState.updatePreferences { $0.promptTemplates.ocrSystemPrompt = newValue }
                    }
                ),
                defaultText: PromptTemplates.defaultSystemPrompt(for: .ocr),
                height: 86
            )
            .padding(.top, 8)
        } label: {
            promptDisclosureLabel(
                title: L10n.text("Image recognition system", language: language),
                systemImage: "text.viewfinder",
                isCustom: appState.preferences.promptTemplates.hasCustomOCRSystemPrompt
            )
        }
    }

    private func ocrPromptEditor(for mode: OCRMode) -> some View {
        DisclosureGroup {
            promptTextEditor(
                title: L10n.text("Mode prompt", language: language),
                text: Binding(
                    get: { appState.preferences.promptTemplates.ocrPrompt(for: mode) },
                    set: { newValue in
                        appState.updatePreferences { $0.promptTemplates.setOCRPrompt(newValue, for: mode) }
                    }
                ),
                defaultText: PromptTemplates.defaultOCRPrompt(
                    mode: mode,
                    targetLanguage: appState.preferences.defaultTranslationTarget
                ),
                height: 148
            )
            .padding(.top, 8)
        } label: {
            promptDisclosureLabel(
                title: L10n.ocrModeName(mode, language: language),
                systemImage: ocrPromptIcon(for: mode),
                isCustom: appState.preferences.promptTemplates.hasCustomOCRPrompt(for: mode)
            )
        }
    }

    private func promptTextEditor(
        title: String,
        text: Binding<String>,
        defaultText: String,
        height: CGFloat
    ) -> some View {
        let hasCustomValue = !text.wrappedValue.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty

        return VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 8) {
                Text(title)
                    .font(.caption.weight(.medium))
                    .foregroundStyle(.secondary)
                Spacer(minLength: 8)
                Button {
                    text.wrappedValue = ""
                } label: {
                    Label(L10n.text("Use built-in default", language: language), systemImage: "arrow.counterclockwise")
                }
                .controlSize(.small)
                .disabled(!hasCustomValue)
            }

            EditableTextView(text: text)
                .frame(height: height)
                .background(Color(NSColor.textBackgroundColor))
                .overlay(RoundedRectangle(cornerRadius: 6).stroke(Color.secondary.opacity(0.18)))
                .clipShape(RoundedRectangle(cornerRadius: 6))

            Text(L10n.text("Empty uses the built-in default.", language: language))
                .font(.caption)
                .foregroundStyle(.secondary)

            DisclosureGroup(L10n.text("Built-in default", language: language)) {
                ReadOnlyTextView(text: defaultText)
                    .frame(height: min(max(height, 92), 170))
                    .background(Color(NSColor.textBackgroundColor).opacity(0.72))
                    .overlay(RoundedRectangle(cornerRadius: 6).stroke(Color.secondary.opacity(0.14)))
                    .clipShape(RoundedRectangle(cornerRadius: 6))
                    .padding(.top, 5)
            }
            .font(.caption)
        }
    }

    private func promptDisclosureLabel(title: String, systemImage: String, isCustom: Bool) -> some View {
        HStack(spacing: 8) {
            Label(title, systemImage: systemImage)
                .font(.subheadline)
            Spacer(minLength: 8)
            if isCustom {
                statusBadge(L10n.text("Custom", language: language), systemImage: "slider.horizontal.3")
            }
        }
        .contentShape(Rectangle())
    }

    private func promptVariablesLine(_ text: String) -> some View {
        Text(text)
            .font(.caption)
            .foregroundStyle(.secondary)
            .fixedSize(horizontal: false, vertical: true)
    }

    private var textPromptVariableText: String {
        switch language {
        case .chinese:
            return "占位符：{input}、{targetLanguage}、{translationQuality}、{polishStyle}、{summaryMode}、{explanationMode}、{todoMode}、{retryInstruction}"
        case .english:
            return "Variables: {input}, {targetLanguage}, {translationQuality}, {polishStyle}, {summaryMode}, {explanationMode}, {todoMode}, {retryInstruction}"
        }
    }

    private var imagePromptVariableText: String {
        switch language {
        case .chinese:
            return "占位符：{targetLanguage}、{modeName}。图片本身会作为模型图片输入发送。"
        case .english:
            return "Variables: {targetLanguage}, {modeName}. The image is sent as the model image input."
        }
    }

    private func defaultUserPromptPreview(for task: TaskKind) -> String {
        PromptTemplates.defaultUserPrompt(
            for: TaskRequest(task: task, inputText: "{input}"),
            preferences: appState.preferences
        )
    }

    private func promptIcon(for task: TaskKind) -> String {
        switch task {
        case .translate:
            return "character.book.closed"
        case .polish:
            return "wand.and.stars"
        case .summarize:
            return "doc.text"
        case .explain:
            return "questionmark.circle"
        case .extractTodos:
            return "list.bullet.clipboard"
        case .webPageTranslate:
            return "safari"
        case .ocr:
            return "text.viewfinder"
        }
    }

    private func ocrPromptIcon(for mode: OCRMode) -> String {
        switch mode {
        case .plainText:
            return "text.viewfinder"
        case .structured:
            return "tablecells"
        case .extractThenTranslate:
            return "character.book.closed"
        case .explainImage:
            return "eye"
        }
    }

    private var aboutSettingsPage: some View {
        settingsForm(maxWidth: 640) {
            settingRow(title: L10n.text("Application", language: language)) {
                VStack(alignment: .leading, spacing: 7) {
                    Text("llmTools")
                        .font(.subheadline.weight(.medium))
                    Text("\(L10n.text("Version", language: language)): \(appVersionText)")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }

            settingRow(title: L10n.text("Status", language: language)) {
                VStack(alignment: .leading, spacing: 7) {
                    statusBadge(appState.statusMessage, systemImage: "bolt.horizontal.circle")
                    if let error = appState.validationError {
                        Text(error)
                            .font(.caption)
                            .foregroundStyle(.red)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
            }

            settingRow(title: L10n.text("Data", language: language)) {
                VStack(alignment: .leading, spacing: 8) {
                    Button {
                        openApplicationSupportFolder()
                    } label: {
                        Label(L10n.text("Open Data Folder", language: language), systemImage: "folder")
                    }
                    .controlSize(.small)
                    pathText(AppPaths.applicationSupportDirectory.path)
                }
            }

            settingRow(title: localizedSettingsText(chinese: "模型下载", english: "Model Downloads")) {
                modelDownloadChecklist
            }

            settingRow(title: L10n.text("Quit", language: language)) {
                Button {
                    NSApp.terminate(nil)
                } label: {
                    Text(L10n.text("Quit llmTools", language: language))
                }
                .controlSize(.small)
            }
        }
    }

    private var modelDownloadChecklist: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(localizedSettingsText(
                chinese: "新电脑迁移时，先按用途下载下面的模型/运行时文件，再回到模型页添加本地目录或运行对应安装脚本。",
                english: "On a new Mac, download the model or runtime files below by use case, then add the local folder on the Models tab or run the matching installer script."
            ))
            .font(.caption)
            .foregroundStyle(.secondary)
            .fixedSize(horizontal: false, vertical: true)

            ForEach(supportedModelDownloadSections) { section in
                VStack(alignment: .leading, spacing: 7) {
                    Text(section.title(language: language))
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.primary)
                    ForEach(section.entries) { entry in
                        modelDownloadEntryView(entry)
                    }
                }
            }
        }
    }

    private func modelDownloadEntryView(_ entry: SupportedModelDownloadEntry) -> some View {
        VStack(alignment: .leading, spacing: 5) {
            HStack(alignment: .firstTextBaseline, spacing: 8) {
                Text(entry.name(language: language))
                    .font(.subheadline.weight(.medium))
                    .lineLimit(1)
                Spacer(minLength: 8)
                HStack(spacing: 6) {
                    Button {
                        openExternalURL(entry.downloadURL)
                    } label: {
                        Label(localizedSettingsText(chinese: "打开", english: "Open"), systemImage: "safari")
                    }
                    .controlSize(.small)

                    if let mirrorURL = entry.mirrorURL {
                        Button {
                            openExternalURL(mirrorURL)
                        } label: {
                            Label(localizedSettingsText(chinese: "镜像", english: "Mirror"), systemImage: "globe.asia.australia")
                        }
                        .controlSize(.small)
                    }

                    Button {
                        copyToPasteboard(entry.copyCommand)
                    } label: {
                        Label(L10n.text("Copy", language: language), systemImage: "doc.on.doc")
                    }
                    .controlSize(.small)
                }
            }

            modelDownloadLine(
                title: localizedSettingsText(chinese: "模型", english: "Model"),
                value: entry.modelName
            )
            modelDownloadLine(
                title: localizedSettingsText(chinese: "地址", english: "URL"),
                value: entry.downloadURL
            )
            if let installerScript = entry.installerScript {
                modelDownloadLine(
                    title: localizedSettingsText(chinese: "脚本", english: "Script"),
                    value: installerScript
                )
            }
            Text(entry.note(language: language))
                .font(.caption)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(.vertical, 5)
    }

    private func modelDownloadLine(title: String, value: String) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 6) {
            Text(title)
                .font(.caption2)
                .foregroundStyle(.secondary)
                .frame(width: 38, alignment: .leading)
            Text(value)
                .font(.caption2.monospaced())
                .foregroundStyle(.secondary)
                .lineLimit(1)
                .truncationMode(.middle)
                .textSelection(.enabled)
                .help(value)
        }
    }

    private func localizedSettingsText(chinese: String, english: String) -> String {
        language == .chinese ? chinese : english
    }

    private var appLanguagePicker: some View {
        Picker("", selection: Binding(
            get: { appState.preferences.appLanguage },
            set: { newValue in
                appState.updatePreferences { $0.appLanguage = newValue }
            }
        )) {
            ForEach(AppLanguage.allCases) { appLanguage in
                Text(appLanguage.displayName).tag(appLanguage)
            }
        }
        .labelsHidden()
        .pickerStyle(.menu)
        .frame(width: 150, alignment: .leading)
    }

    private var defaultModelPicker: some View {
        Picker("", selection: Binding<UUID?>(
            get: { appState.preferences.defaultModelID },
            set: { newValue in
                if let newValue {
                    appState.setDefaultModel(id: newValue)
                } else {
                    appState.updatePreferences { $0.defaultModelID = nil }
                }
            }
        )) {
            Text(L10n.text("No model", language: language)).tag(UUID?.none)
            ForEach(appState.textCapableModels) { model in
                Text(defaultModelPickerTitle(model)).tag(Optional(model.id))
            }
        }
        .labelsHidden()
        .pickerStyle(.menu)
        .frame(width: 230, alignment: .leading)
        .disabled(appState.textCapableModels.isEmpty)
    }

    private var webPageTranslationModelPicker: some View {
        Picker("", selection: Binding<UUID?>(
            get: { appState.preferences.webPageTranslation.modelID },
            set: { newValue in
                appState.updatePreferences { $0.webPageTranslation.modelID = newValue }
            }
        )) {
            Text(L10n.text("Use text default model", language: language)).tag(UUID?.none)
            ForEach(appState.textCapableModels) { model in
                Text(defaultModelPickerTitle(model)).tag(Optional(model.id))
            }
        }
        .labelsHidden()
        .pickerStyle(.menu)
        .frame(width: 230, alignment: .leading)
        .disabled(appState.textCapableModels.isEmpty)
    }

    private var translationTargetPicker: some View {
        Picker("", selection: Binding(
            get: { appState.preferences.defaultTranslationTarget },
            set: { newValue in
                appState.updatePreferences { $0.defaultTranslationTarget = newValue }
            }
        )) {
            Text(L10n.targetLanguageName("auto", language: language)).tag("auto")
            Text(L10n.targetLanguageName("Chinese", language: language)).tag("Chinese")
            Text(L10n.targetLanguageName("English", language: language)).tag("English")
            Text(L10n.targetLanguageName("Japanese", language: language)).tag("Japanese")
            Text(L10n.targetLanguageName("Korean", language: language)).tag("Korean")
        }
        .labelsHidden()
        .pickerStyle(.menu)
        .frame(width: 150, alignment: .leading)
    }

    private var defaultTranslationQualityPicker: some View {
        Picker("", selection: Binding(
            get: { appState.preferences.defaultTranslationQuality },
            set: { newValue in
                appState.updatePreferences { $0.defaultTranslationQuality = newValue }
            }
        )) {
            ForEach(WebPageTranslationQualityMode.allCases) { mode in
                Text(L10n.webPageTranslationQualityName(mode, language: language)).tag(mode)
            }
        }
        .labelsHidden()
        .pickerStyle(.menu)
        .frame(width: 150, alignment: .leading)
    }

    private var polishStylePicker: some View {
        Picker("", selection: Binding(
            get: { appState.preferences.defaultPolishStyle },
            set: { newValue in
                appState.updatePreferences { $0.defaultPolishStyle = newValue }
            }
        )) {
            Text(L10n.polishStyleName("natural", language: language)).tag("natural")
            Text(L10n.polishStyleName("formal", language: language)).tag("formal")
            Text(L10n.polishStyleName("concise", language: language)).tag("concise")
            Text(L10n.polishStyleName("conversational", language: language)).tag("conversational")
            Text(L10n.polishStyleName("technical", language: language)).tag("technical")
        }
        .labelsHidden()
        .pickerStyle(.menu)
        .frame(width: 150, alignment: .leading)
    }

    private var summaryModeSettingsPicker: some View {
        Picker("", selection: Binding(
            get: { appState.preferences.defaultSummaryMode },
            set: { newValue in
                appState.updatePreferences { $0.defaultSummaryMode = newValue }
            }
        )) {
            ForEach(SummaryMode.allCases) { mode in
                Text(L10n.summaryModeName(mode, language: language)).tag(mode)
            }
        }
        .labelsHidden()
        .pickerStyle(.menu)
        .frame(width: 170, alignment: .leading)
    }

    private var explanationModeSettingsPicker: some View {
        Picker("", selection: Binding(
            get: { appState.preferences.defaultExplanationMode },
            set: { newValue in
                appState.updatePreferences { $0.defaultExplanationMode = newValue }
            }
        )) {
            ForEach(ExplanationMode.allCases) { mode in
                Text(L10n.explanationModeName(mode, language: language)).tag(mode)
            }
        }
        .labelsHidden()
        .pickerStyle(.menu)
        .frame(width: 170, alignment: .leading)
    }

    private var todoExtractionModeSettingsPicker: some View {
        Picker("", selection: Binding(
            get: { appState.preferences.defaultTodoExtractionMode },
            set: { newValue in
                appState.updatePreferences { $0.defaultTodoExtractionMode = newValue }
            }
        )) {
            ForEach(TodoExtractionMode.allCases) { mode in
                Text(L10n.todoExtractionModeName(mode, language: language)).tag(mode)
            }
        }
        .labelsHidden()
        .pickerStyle(.menu)
        .frame(width: 170, alignment: .leading)
    }

    private var historyLimitControl: some View {
        HStack(spacing: 10) {
            Text("\(appState.preferences.recentHistoryLimit)")
                .font(.caption.monospacedDigit())
                .foregroundStyle(.secondary)
                .frame(width: 30)
                .padding(.horizontal, 6)
                .padding(.vertical, 4)
                .background(.quaternary.opacity(0.65))
                .clipShape(RoundedRectangle(cornerRadius: 6))
            Stepper(
                "",
                value: Binding(
                    get: { appState.preferences.recentHistoryLimit },
                    set: { newValue in
                        appState.updatePreferences { $0.recentHistoryLimit = newValue }
                    }
                ),
                in: 1...20,
                step: 1
            )
            .labelsHidden()
        }
    }

    private var webPageHistoryPolicyText: String {
        if appState.preferences.webPageTranslation.persistWebHistory {
            return L10n.text("Webpage translation batches will be saved to Recent History and can include page text snippets.", language: language)
        }
        return L10n.text("Default: webpage source text and translated text are not saved to the app recent history.", language: language)
    }

    private func webPagePrivacyLine(systemImage: String, title: String, body: String) -> some View {
        HStack(alignment: .top, spacing: 8) {
            Image(systemName: systemImage)
                .font(.system(size: 12, weight: .medium))
                .foregroundStyle(.secondary)
                .frame(width: 16, height: 18)
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.caption.weight(.medium))
                    .foregroundStyle(.primary)
                Text(body)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    private var emptyModelsView: some View {
        VStack(spacing: 10) {
            Image(systemName: "shippingbox")
                .font(.system(size: 28, weight: .medium))
                .foregroundStyle(.secondary)
            Text(L10n.text("No models registered yet.", language: language))
                .font(.subheadline)
                .foregroundStyle(.secondary)
            Button {
                openLocalModelPanel()
            } label: {
                Label(L10n.text("Add Local Model", language: language), systemImage: "externaldrive.badge.plus")
            }
            .controlSize(.small)
        }
        .frame(maxWidth: .infinity, minHeight: 220)
        .background(Color(NSColor.controlBackgroundColor).opacity(0.65))
        .overlay(RoundedRectangle(cornerRadius: 8).stroke(Color.secondary.opacity(0.14)))
        .clipShape(RoundedRectangle(cornerRadius: 8))
    }

    private var modelCountText: String {
        switch language {
        case .chinese:
            return "\(appState.models.count) 个模型"
        case .english:
            return appState.models.count == 1 ? "1 model" : "\(appState.models.count) models"
        }
    }

    private var launchStatusIcon: String {
        switch appState.launchAtLoginStatusText() {
        case L10n.text("Enabled", language: language):
            return "checkmark.circle.fill"
        case L10n.text("Disabled", language: language):
            return "minus.circle"
        case L10n.text("Needs approval", language: language):
            return "exclamationmark.triangle.fill"
        default:
            return "clock"
        }
    }

    private var appVersionText: String {
        let info = Bundle.main.infoDictionary
        let version = info?["CFBundleShortVersionString"] as? String ?? "0.4.0"
        let build = info?["CFBundleVersion"] as? String ?? "dev"
        return "\(version) (\(build))"
    }

    private var browserDiagnosticDateFormatter: DateFormatter {
        let formatter = DateFormatter()
        formatter.dateStyle = .none
        formatter.timeStyle = .medium
        return formatter
    }

    private func defaultModelPickerTitle(_ model: ModelDescriptor) -> String {
        if model.isRemoteProvider {
            return "\(model.name) · \(model.providerDisplayName)"
        }
        return model.name
    }

    private func settingsTabButton(_ tab: SettingsTab) -> some View {
        let isSelected = selectedTab == tab
        return Button {
            navigation.selectedTab = tab
            if tab == .webPage {
                refreshBrowserIntegrationStates()
            }
        } label: {
            VStack(spacing: 3) {
                ZStack {
                    RoundedRectangle(cornerRadius: 7, style: .continuous)
                        .fill(isSelected ? Color.accentColor.opacity(0.12) : Color.clear)
                    Image(systemName: tab.systemImage)
                        .font(.system(size: 20, weight: .medium))
                        .symbolRenderingMode(.hierarchical)
                        .foregroundStyle(isSelected ? Color.accentColor : Color.secondary)
                }
                .frame(width: 48, height: 32)

                Text(tab.tabTitle(language: language))
                    .font(.caption2)
                    .lineLimit(1)
                    .truncationMode(.tail)
                    .foregroundStyle(isSelected ? Color.accentColor : Color.secondary)
            }
            .frame(width: 64, height: 52)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .help(tab.title(language: language))
    }

    private var selectedProviderPreset: ModelProviderPreset {
        ModelProviderCatalog.preset(for: providerDraftID)
            ?? ModelProviderCatalog.remotePresets.first
            ?? ModelProviderPreset(id: .customOpenAICompatible, name: "Custom OpenAI-Compatible", apiStyle: .openAICompatible)
    }

    private var providerModelPlaceholder: String {
        selectedProviderPreset.defaultModelID.isEmpty ? "model-id" : selectedProviderPreset.defaultModelID
    }

    private var addProviderDisabled: Bool {
        providerDraftModelID.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            || providerDraftBaseURL.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            || (selectedProviderPreset.requiresAPIKey && providerDraftAPIKey.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
    }

    private func initializeProviderDraftIfNeeded() {
        guard providerDraftBaseURL.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            return
        }
        applyProviderPreset(providerDraftID)
    }

    private func applyProviderPreset(_ providerID: ModelProviderID) {
        guard let preset = ModelProviderCatalog.preset(for: providerID) else {
            return
        }
        providerDraftBaseURL = preset.defaultBaseURL
        providerDraftModelID = preset.defaultModelID
        providerDraftContextLength = preset.defaultContextLength
        if !preset.requiresAPIKey {
            providerDraftAPIKey = ""
        }
    }

    private func addProviderDraft() {
        if let editingProviderModelID {
            appState.updateProviderModel(
                id: editingProviderModelID,
                providerID: providerDraftID,
                name: providerDraftName,
                modelID: providerDraftModelID,
                apiKey: providerDraftAPIKey,
                baseURL: providerDraftBaseURL,
                contextLength: providerDraftContextLength
            )
        } else {
            appState.addProviderModel(
                providerID: providerDraftID,
                name: providerDraftName,
                modelID: providerDraftModelID,
                apiKey: providerDraftAPIKey,
                baseURL: providerDraftBaseURL,
                contextLength: providerDraftContextLength
            )
        }
        resetProviderDraft()
    }

    private func openLocalModelPanel() {
        NSApp.activate(ignoringOtherApps: true)

        let panel = NSOpenPanel()
        panel.title = L10n.text("Add Local Model", language: language)
        panel.prompt = L10n.text("Add", language: language)
        panel.message = localModelPanelMessage
        panel.canChooseFiles = true
        panel.canChooseDirectories = true
        panel.allowsMultipleSelection = false
        panel.canCreateDirectories = false
        panel.resolvesAliases = true

        let completion: (NSApplication.ModalResponse) -> Void = { response in
            guard response == .OK, let url = panel.url else {
                return
            }
            appState.addModel(from: url)
        }

        if let window = NSApp.keyWindow ?? NSApp.mainWindow {
            panel.beginSheetModal(for: window, completionHandler: completion)
        } else {
            completion(panel.runModal())
        }
    }

    private func openLanguageRoutingModelPanel(_ variant: LanguageIDModelVariant) {
        NSApp.activate(ignoringOtherApps: true)

        let panel = NSOpenPanel()
        panel.title = L10n.text("Choose fastText model file", language: language)
        panel.prompt = L10n.text("Choose", language: language)
        panel.message = languageRoutingModelPanelMessage(variant)
        panel.canChooseFiles = true
        panel.canChooseDirectories = false
        panel.allowsMultipleSelection = false
        panel.canCreateDirectories = false
        panel.resolvesAliases = true

        let completion: (NSApplication.ModalResponse) -> Void = { response in
            guard response == .OK, let url = panel.url else {
                return
            }
            appState.updatePreferences { preferences in
                switch variant {
                case .ftz, .customCommand:
                    preferences.languageRouting.ftzModelPath = url.path
                case .bin:
                    preferences.languageRouting.binModelPath = url.path
                }
            }
        }

        if let window = NSApp.keyWindow ?? NSApp.mainWindow {
            panel.beginSheetModal(for: window, completionHandler: completion)
        } else {
            completion(panel.runModal())
        }
    }

    private func openFastTranslationModelPanel(_ variant: FastTranslationModelVariant) {
        NSApp.activate(ignoringOtherApps: true)

        let panel = NSOpenPanel()
        panel.title = L10n.text("Choose CTranslate2 model folder", language: language)
        panel.prompt = L10n.text("Choose", language: language)
        panel.message = fastTranslationModelPanelMessage(variant)
        panel.canChooseFiles = false
        panel.canChooseDirectories = true
        panel.allowsMultipleSelection = false
        panel.canCreateDirectories = false
        panel.resolvesAliases = true

        let completion: (NSApplication.ModalResponse) -> Void = { response in
            guard response == .OK, let url = panel.url else {
                return
            }
            appState.updatePreferences { preferences in
                switch variant {
                case .opusMTEnZh:
                    preferences.fastTranslation.opusMTEnZhCT2ModelPath = url.path
                case .nllb200Distilled600M:
                    preferences.fastTranslation.nllb200Distilled600MCT2ModelPath = url.path
                }
            }
        }

        if let window = NSApp.keyWindow ?? NSApp.mainWindow {
            panel.beginSheetModal(for: window, completionHandler: completion)
        } else {
            completion(panel.runModal())
        }
    }

    private func openSpeakerDiarizationModelPanel() {
        NSApp.activate(ignoringOtherApps: true)

        let panel = NSOpenPanel()
        panel.title = L10n.text("Choose local pyannote config", language: language)
        panel.prompt = L10n.text("Choose", language: language)
        panel.message = speakerDiarizationModelPanelMessage
        panel.canChooseFiles = true
        panel.canChooseDirectories = true
        panel.allowsMultipleSelection = false
        panel.canCreateDirectories = false
        panel.resolvesAliases = true

        let completion: (NSApplication.ModalResponse) -> Void = { response in
            guard response == .OK, let url = panel.url else {
                return
            }
            appState.updatePreferences { $0.speakerDiarization.modelIdentifier = url.path }
        }

        if let window = NSApp.keyWindow ?? NSApp.mainWindow {
            panel.beginSheetModal(for: window, completionHandler: completion)
        } else {
            completion(panel.runModal())
        }
    }

    private func openSpeakerDiarizationCachePanel() {
        NSApp.activate(ignoringOtherApps: true)

        let panel = NSOpenPanel()
        panel.title = L10n.text("Choose cache folder", language: language)
        panel.prompt = L10n.text("Choose", language: language)
        panel.message = speakerDiarizationCachePanelMessage
        panel.canChooseFiles = false
        panel.canChooseDirectories = true
        panel.allowsMultipleSelection = false
        panel.canCreateDirectories = true
        panel.resolvesAliases = true

        let completion: (NSApplication.ModalResponse) -> Void = { response in
            guard response == .OK, let url = panel.url else {
                return
            }
            appState.updatePreferences { $0.speakerDiarization.cacheDirectory = url.path }
        }

        if let window = NSApp.keyWindow ?? NSApp.mainWindow {
            panel.beginSheetModal(for: window, completionHandler: completion)
        } else {
            completion(panel.runModal())
        }
    }

    private func revealSpeakerDiarizationCacheFolder() {
        let configured = appState.preferences.speakerDiarization.cacheDirectory
            .trimmingCharacters(in: .whitespacesAndNewlines)
        let url = configured.isEmpty
            ? SpeakerDiarizationCommandRunner.defaultHFHomeDirectory
            : URL(fileURLWithPath: NSString(string: configured).expandingTildeInPath, isDirectory: true)
        try? FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        NSWorkspace.shared.open(url)
    }

    private var localModelPanelMessage: String {
        switch language {
        case .chinese:
            return "选择 GGUF 文件、MLX 模型目录或其他本地模型文件。"
        case .english:
            return "Choose a GGUF file, MLX model folder, or another local model file."
        }
    }

    private func languageRoutingModelPanelMessage(_ variant: LanguageIDModelVariant) -> String {
        switch (language, variant) {
        case (.chinese, .ftz), (.chinese, .customCommand):
            return "选择 fastText 语言识别小模型文件，通常名为 lid.176.ftz。"
        case (.chinese, .bin):
            return "选择 fastText 语言识别高精度模型文件，通常名为 lid.176.bin。"
        case (.english, .ftz), (.english, .customCommand):
            return "Choose the compact fastText language ID model file, usually named lid.176.ftz."
        case (.english, .bin):
            return "Choose the full fastText language ID model file, usually named lid.176.bin."
        }
    }

    private func fastTranslationModelPanelMessage(_ variant: FastTranslationModelVariant) -> String {
        switch (language, variant) {
        case (.chinese, .opusMTEnZh):
            return "选择 OPUS 英译中 CTranslate2 模型目录。目录内应包含 model.bin、config.json 等文件。"
        case (.chinese, .nllb200Distilled600M):
            return "选择 NLLB 200 distilled 600M CTranslate2 模型目录。目录内应包含 model.bin、config.json 等文件。"
        case (.english, .opusMTEnZh):
            return "Choose the OPUS English-to-Chinese CTranslate2 model folder. It should contain files such as model.bin and config.json."
        case (.english, .nllb200Distilled600M):
            return "Choose the NLLB 200 distilled 600M CTranslate2 model folder. It should contain files such as model.bin and config.json."
        }
    }

    private var speakerDiarizationModelPanelMessage: String {
        switch language {
        case .chinese:
            return "选择本地 pyannote pipeline 的 config.yaml，或选择包含 config.yaml 的模型目录。"
        case .english:
            return "Choose the local pyannote pipeline config.yaml, or a model folder that contains config.yaml."
        }
    }

    private var speakerDiarizationCachePanelMessage: String {
        switch language {
        case .chinese:
            return "选择 Hugging Face cache 目录。留空时默认使用 ~/.cache/huggingface。"
        case .english:
            return "Choose the Hugging Face cache directory. Empty uses ~/.cache/huggingface."
        }
    }

    private func editProviderDraft(_ model: ModelDescriptor) {
        guard let configuration = model.providerConfiguration, configuration.isRemote else {
            return
        }
        editingProviderModelID = model.id
        providerDraftID = configuration.providerID
        providerDraftName = model.name
        providerDraftModelID = configuration.modelID
        providerDraftAPIKey = ""
        providerDraftBaseURL = configuration.baseURL?.absoluteString ?? ""
        providerDraftContextLength = model.contextLength
    }

    private func resetProviderDraft() {
        editingProviderModelID = nil
        providerDraftName = ""
        providerDraftAPIKey = ""
        applyProviderPreset(providerDraftID)
    }

    private func settingsForm<Content: View>(
        maxWidth: CGFloat,
        @ViewBuilder content: () -> Content
    ) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            content()
        }
        .frame(maxWidth: maxWidth, alignment: .topLeading)
        .frame(maxWidth: .infinity, alignment: .topLeading)
    }

    private func fieldStack<Content: View>(
        title: String,
        width: CGFloat,
        @ViewBuilder content: () -> Content
    ) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(title)
                .font(.caption)
                .foregroundStyle(.secondary)
            content()
        }
        .frame(width: width, alignment: .topLeading)
    }

    private func modelPathField(
        title: String,
        text: Binding<String>,
        placeholder: String,
        chooseAction: @escaping () -> Void
    ) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(title)
                .font(.caption)
                .foregroundStyle(.secondary)
            HStack(alignment: .center, spacing: 8) {
                CommandFriendlyTextField(
                    text: text,
                    placeholder: placeholder
                )
                .frame(width: 392)
                Button {
                    chooseAction()
                } label: {
                    Label(L10n.text("Choose", language: language), systemImage: "folder")
                }
                .controlSize(.small)
            }
        }
        .frame(width: 500, alignment: .topLeading)
    }

    private func mediaASRCommandField(
        title: String,
        text: Binding<String>,
        placeholder: String
    ) -> some View {
        fieldStack(title: title, width: 500) {
            CommandFriendlyTextField(
                text: text,
                placeholder: placeholder
            )
        }
    }

    private func webPageDomainList(
        title: String,
        domains: [String],
        emptyText: String,
        rule: WebPageDomainRuleKind
    ) -> some View {
        VStack(alignment: .leading, spacing: 5) {
            Text(title)
                .font(.caption)
                .foregroundStyle(.secondary)
            if domains.isEmpty {
                Text(emptyText)
                    .font(.caption)
                    .foregroundStyle(.tertiary)
            } else {
                ForEach(domains, id: \.self) { domain in
                    HStack(spacing: 8) {
                        Text(domain)
                            .font(.caption.monospaced())
                            .lineLimit(1)
                            .truncationMode(.middle)
                            .frame(width: 250, alignment: .leading)
                        iconToolButton(
                            systemImage: "trash",
                            help: L10n.text("Remove", language: language),
                            role: .destructive
                        ) {
                            removeWebPageDomainRule(domain: domain, rule: rule)
                        }
                    }
                }
            }
        }
    }

    private func webPageModeDefaultsList(
        title: String,
        emptyText: String,
        rows: [(domain: String, value: String)],
        remove: @escaping (String) -> Void
    ) -> some View {
        VStack(alignment: .leading, spacing: 5) {
            Text(title)
                .font(.caption)
                .foregroundStyle(.secondary)
            if rows.isEmpty {
                Text(emptyText)
                    .font(.caption)
                    .foregroundStyle(.tertiary)
            } else {
                ForEach(rows, id: \.domain) { row in
                    HStack(spacing: 8) {
                        Text(row.domain)
                            .font(.caption.monospaced())
                            .lineLimit(1)
                            .truncationMode(.middle)
                            .frame(width: 210, alignment: .leading)
                        Text(row.value)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .frame(width: 80, alignment: .leading)
                        iconToolButton(
                            systemImage: "trash",
                            help: L10n.text("Remove", language: language),
                            role: .destructive
                        ) {
                            remove(row.domain)
                        }
                    }
                }
            }
        }
    }

    private func settingRow<Content: View>(
        title: String,
        @ViewBuilder content: () -> Content
    ) -> some View {
        HStack(alignment: .top, spacing: 12) {
            Text("\(title):")
                .font(.subheadline)
                .foregroundStyle(.primary)
                .frame(width: 96, alignment: .trailing)
                .padding(.top, 2)

            VStack(alignment: .leading, spacing: 6) {
                content()
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    private func checkboxLine(
        title: String,
        isOn: Binding<Bool>,
        trailing: AnyView? = nil
    ) -> some View {
        HStack(alignment: .center, spacing: 8) {
            Toggle(title, isOn: isOn)
                .toggleStyle(.checkbox)
                .font(.subheadline)
                .fixedSize(horizontal: false, vertical: true)
            if let trailing {
                trailing
            }
            Spacer(minLength: 0)
        }
    }

    private func shortcutRecorderLine(
        title: String,
        shortcut: KeyboardShortcutPreference,
        target: ShortcutCaptureTarget
    ) -> some View {
        let isRecording = shortcutCaptureTarget == target

        return HStack(spacing: 12) {
            Text(title)
                .font(.subheadline)
                .lineLimit(2)
                .fixedSize(horizontal: false, vertical: true)
            Spacer(minLength: 10)

            Button {
                shortcutCaptureTarget = target
                shortcutRecorderMessage = nil
            } label: {
                HStack(spacing: 4) {
                    if isRecording {
                        Text(L10n.text("Press shortcut", language: language))
                            .font(.caption.monospaced())
                            .foregroundStyle(.secondary)
                            .frame(minWidth: 112, minHeight: 20)
                            .padding(.horizontal, 5)
                            .background(Color.accentColor.opacity(0.12))
                            .clipShape(RoundedRectangle(cornerRadius: 5))
                    } else {
                        shortcutKeyCaps(shortcut.displayKeys)
                    }
                }
            }
            .buttonStyle(.plain)
            .help(L10n.text("Change shortcut", language: language))

            Button {
                resetShortcut(for: target)
            } label: {
                Image(systemName: "arrow.counterclockwise")
                    .font(.system(size: 12, weight: .semibold))
                    .frame(width: 22, height: 22)
            }
            .buttonStyle(.plain)
            .foregroundStyle(.secondary)
            .help(L10n.text("Reset shortcut", language: language))
        }
    }

    private func shortcutKeyCaps(_ keys: [String]) -> some View {
        HStack(spacing: 4) {
            ForEach(keys, id: \.self) { key in
                Text(key)
                    .font(.caption.monospaced())
                    .foregroundStyle(.secondary)
                    .frame(minWidth: key == "Space" ? 48 : 22, minHeight: 20)
                    .padding(.horizontal, 3)
                    .background(.quaternary.opacity(0.72))
                    .clipShape(RoundedRectangle(cornerRadius: 5))
            }
        }
    }

    private func applyShortcut(_ shortcut: KeyboardShortcutPreference, for target: ShortcutCaptureTarget) {
        guard !isShortcutAlreadyAssigned(shortcut, target: target) else {
            shortcutRecorderMessage = L10n.text("Shortcut is already assigned", language: language)
            NSSound.beep()
            shortcutCaptureTarget = nil
            return
        }

        appState.updatePreferences { preferences in
            switch target {
            case .quickAction:
                preferences.quickActionShortcut = shortcut
            case .quickActionWithoutSelection:
                preferences.quickActionWithoutSelectionShortcut = shortcut
            case .liveSubtitles:
                preferences.liveSubtitleShortcut = shortcut
            case .quickActionTextMode:
                preferences.quickActionPopupShortcuts.textMode = shortcut
            case .quickActionImageMode:
                preferences.quickActionPopupShortcuts.imageMode = shortcut
            case .quickActionMediaMode:
                preferences.quickActionPopupShortcuts.mediaMode = shortcut
            case .textTask(let task):
                preferences.quickActionPopupShortcuts.setTextTaskShortcut(shortcut, for: task)
            case .imageOCRMode(let mode):
                preferences.quickActionPopupShortcuts.setOCRModeShortcut(shortcut, for: mode)
            }
        }
        shortcutRecorderMessage = nil
        shortcutCaptureTarget = nil
    }

    private func resetShortcut(for target: ShortcutCaptureTarget) {
        applyShortcut(defaultShortcut(for: target), for: target)
    }

    private func addSelectionLineLimitRule(from url: URL) {
        let didAccess = url.startAccessingSecurityScopedResource()
        defer {
            if didAccess {
                url.stopAccessingSecurityScopedResource()
            }
        }
        guard let bundle = Bundle(url: url),
              let bundleIdentifier = bundle.bundleIdentifier,
              !bundleIdentifier.isEmpty else {
            return
        }
        let maximumLineCount = min(max(selectionLimitDraftLineCount, 1), 10)
        appState.updatePreferences { preferences in
            if let index = preferences.selectionLineLimitRules.firstIndex(where: { $0.bundleIdentifier == bundleIdentifier }) {
                preferences.selectionLineLimitRules[index].maximumLineCount = maximumLineCount
            } else {
                preferences.selectionLineLimitRules.append(
                    SelectionLineLimitRule(
                        bundleIdentifier: bundleIdentifier,
                        maximumLineCount: maximumLineCount
                    )
                )
            }
        }
        selectionLimitDraftLineCount = 2
    }

    private func updateSelectionLineLimitRule(id: UUID, update: @escaping (inout SelectionLineLimitRule) -> Void) {
        appState.updatePreferences { preferences in
            guard let index = preferences.selectionLineLimitRules.firstIndex(where: { $0.id == id }) else {
                return
            }
            update(&preferences.selectionLineLimitRules[index])
            preferences.selectionLineLimitRules[index].maximumLineCount = min(
                max(preferences.selectionLineLimitRules[index].maximumLineCount, 1),
                10
            )
        }
    }

    private func removeSelectionLineLimitRule(id: UUID) {
        appState.updatePreferences { preferences in
            preferences.selectionLineLimitRules.removeAll { $0.id == id }
        }
    }

    private func addWebPageDomainRule(rule: WebPageDomainRuleKind) {
        let domain = normalizedWebPageDomain(webPageDomainDraft)
        guard !domain.isEmpty else {
            return
        }
        appState.updatePreferences { preferences in
            applyWebPageDomainRule(domain: domain, rule: rule, preferences: &preferences)
        }
        webPageDomainDraft = ""
    }

    private func removeWebPageDomainRule(domain: String, rule: WebPageDomainRuleKind) {
        let normalizedDomain = normalizedWebPageDomain(domain)
        appState.updatePreferences { preferences in
            switch rule {
            case .alwaysTranslate:
                preferences.webPageTranslation.autoTranslateDomains.removeAll { normalizedWebPageDomain($0) == normalizedDomain }
            case .neverTranslate:
                preferences.webPageTranslation.disabledDomains.removeAll { normalizedWebPageDomain($0) == normalizedDomain }
            }
        }
    }

    private func resetWebPageDomainRules() {
        appState.updatePreferences { preferences in
            preferences.webPageTranslation.autoTranslateDomains = []
            preferences.webPageTranslation.disabledDomains = []
        }
    }

    private func removeWebPageReadingDefault(domain: String) {
        let normalizedDomain = normalizedWebPageDomain(domain)
        appState.updatePreferences { preferences in
            preferences.webPageTranslation.domainReadingModes.removeValue(forKey: normalizedDomain)
        }
    }

    private func removeWebPageQualityDefault(domain: String) {
        let normalizedDomain = normalizedWebPageDomain(domain)
        appState.updatePreferences { preferences in
            preferences.webPageTranslation.domainTranslationQualities.removeValue(forKey: normalizedDomain)
        }
    }

    private func resetWebPageSiteDefaults() {
        appState.updatePreferences { preferences in
            preferences.webPageTranslation.domainReadingModes = [:]
            preferences.webPageTranslation.domainTranslationQualities = [:]
        }
    }

    private func applyWebPageDomainRule(
        domain: String,
        rule: WebPageDomainRuleKind,
        preferences: inout AppPreferences
    ) {
        preferences.webPageTranslation.autoTranslateDomains = normalizedUniqueDomains(
            preferences.webPageTranslation.autoTranslateDomains.filter { normalizedWebPageDomain($0) != domain }
        )
        preferences.webPageTranslation.disabledDomains = normalizedUniqueDomains(
            preferences.webPageTranslation.disabledDomains.filter { normalizedWebPageDomain($0) != domain }
        )
        switch rule {
        case .alwaysTranslate:
            preferences.webPageTranslation.autoTranslateDomains = normalizedUniqueDomains(
                preferences.webPageTranslation.autoTranslateDomains + [domain]
            )
        case .neverTranslate:
            preferences.webPageTranslation.disabledDomains = normalizedUniqueDomains(
                preferences.webPageTranslation.disabledDomains + [domain]
            )
        }
    }

    private func normalizedUniqueDomains(_ domains: [String]) -> [String] {
        Array(Set(domains.map(normalizedWebPageDomain).filter { !$0.isEmpty })).sorted()
    }

    private func normalizedWebPageDomain(_ value: String) -> String {
        let trimmed = value
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .lowercased()
        let withoutScheme = trimmed
            .replacingOccurrences(of: #"^https?://"#, with: "", options: .regularExpression)
        let host = withoutScheme
            .split(separator: "/", maxSplits: 1)
            .first?
            .split(separator: ":", maxSplits: 1)
            .first
            .map(String.init) ?? ""
        if host.hasPrefix("www.") {
            return String(host.dropFirst(4))
        }
        return host
    }

    private func isShortcutAlreadyAssigned(_ shortcut: KeyboardShortcutPreference, target: ShortcutCaptureTarget) -> Bool {
        shortcutAssignments().contains { assignment in
            assignment.target != target
                && assignment.shortcut == shortcut
                && !canShareShortcut(target, assignment.target)
        }
    }

    private func shortcutAssignments() -> [(target: ShortcutCaptureTarget, shortcut: KeyboardShortcutPreference)] {
        let popupShortcuts = appState.preferences.quickActionPopupShortcuts
        var assignments: [(target: ShortcutCaptureTarget, shortcut: KeyboardShortcutPreference)] = [
            (.quickAction, appState.preferences.quickActionShortcut),
            (.quickActionWithoutSelection, appState.preferences.quickActionWithoutSelectionShortcut),
            (.liveSubtitles, appState.preferences.liveSubtitleShortcut),
            (.quickActionTextMode, popupShortcuts.textMode),
            (.quickActionImageMode, popupShortcuts.imageMode),
            (.quickActionMediaMode, popupShortcuts.mediaMode)
        ]
        for task in TaskKind.interactiveCases {
            if let shortcut = popupShortcuts.textTaskShortcut(for: task) {
                assignments.append((.textTask(task), shortcut))
            }
        }
        for mode in OCRMode.allCases {
            assignments.append((.imageOCRMode(mode), popupShortcuts.ocrModeShortcut(for: mode)))
        }
        return assignments
    }

    private func canShareShortcut(_ lhs: ShortcutCaptureTarget, _ rhs: ShortcutCaptureTarget) -> Bool {
        switch (lhs, rhs) {
        case (.textTask, .imageOCRMode), (.imageOCRMode, .textTask):
            return true
        default:
            return false
        }
    }

    private func defaultShortcut(for target: ShortcutCaptureTarget) -> KeyboardShortcutPreference {
        let popupDefaults = QuickActionPopupShortcuts()
        switch target {
        case .quickAction:
            return .optionSpace
        case .quickActionWithoutSelection:
            return .optionShiftSpace
        case .liveSubtitles:
            return .commandOptionControlL
        case .quickActionTextMode:
            return popupDefaults.textMode
        case .quickActionImageMode:
            return popupDefaults.imageMode
        case .quickActionMediaMode:
            return popupDefaults.mediaMode
        case .textTask(let task):
            return popupDefaults.textTaskShortcut(for: task) ?? .commandNumber(1)
        case .imageOCRMode(let mode):
            return popupDefaults.ocrModeShortcut(for: mode)
        }
    }

    private func pathText(_ text: String) -> some View {
        Text(text)
            .font(.caption2.monospaced())
            .foregroundStyle(.secondary)
            .lineLimit(2)
            .truncationMode(.middle)
            .help(text)
    }

    private func diagnosticLine(_ title: String, _ value: String) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 8) {
            Text(title)
                .font(.caption)
                .foregroundStyle(.secondary)
                .frame(width: 92, alignment: .leading)
            Text(value)
                .font(.caption2.monospaced())
                .foregroundStyle(.secondary)
                .lineLimit(1)
                .truncationMode(.middle)
                .help(value)
        }
    }

    private func iconToolButton(
        systemImage: String,
        help: String,
        isDisabled: Bool = false,
        role: ButtonRole? = nil,
        action: @escaping () -> Void
    ) -> some View {
        Button(role: role) {
            action()
        } label: {
            Image(systemName: systemImage)
                .font(.system(size: 12, weight: .medium))
                .frame(width: 24, height: 24)
                .contentShape(Rectangle())
        }
        .buttonStyle(.borderless)
        .disabled(isDisabled)
        .help(help)
    }

    private func modelCard(_ model: ModelDescriptor) -> some View {
        let isDefault = model.id == appState.preferences.defaultModelID
        let isTestingThisProvider = appState.providerTestModelID == model.id
        let isTestingVision = appState.visionProbeModelID == model.id

        return VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .top, spacing: 12) {
                ZStack {
                    RoundedRectangle(cornerRadius: 8)
                        .fill(modelTint(for: model.format).opacity(0.16))
                    Image(systemName: modelIcon(for: model.format))
                        .font(.system(size: 18, weight: .semibold))
                        .foregroundStyle(modelTint(for: model.format))
                }
                .frame(width: 40, height: 40)

                VStack(alignment: .leading, spacing: 5) {
                    HStack(alignment: .firstTextBaseline, spacing: 8) {
                        Text(model.name)
                            .font(.subheadline.bold())
                            .lineLimit(1)
                            .truncationMode(.tail)
                        Spacer(minLength: 8)
                        formatBadge(model.isRemoteProvider ? model.providerDisplayName : model.format.rawValue.uppercased(), tint: modelTint(for: model.format))
                        if model.isRemoteProvider {
                            formatBadge(model.format.rawValue.uppercased(), tint: .gray)
                        }
                        if isDefault {
                            formatBadge(L10n.text("Default", language: language), tint: .green)
                        }
                        formatBadge(capabilityName(model.capabilities), tint: capabilityTint(model.capabilities))
                        if model.capabilities.source == .manual {
                            formatBadge(L10n.text("Manual", language: language), tint: .purple)
                        }
                    }

                    Text(model.displayPath)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                        .truncationMode(.middle)
                        .help(model.displayPath)
                }
            }

            HStack(spacing: 6) {
                metaChip("\(L10n.text("Role", language: language)): \(roleName(model.role))", systemImage: "person.badge.key")
                if model.isRemoteProvider {
                    metaChip("\(L10n.text("Model", language: language)): \(model.apiModelID ?? model.sizeClass)", systemImage: "cube")
                } else {
                    metaChip("\(L10n.text("Size", language: language)): \(model.sizeClass)", systemImage: "externaldrive")
                }
                metaChip("\(L10n.text("Ctx", language: language)): \(model.contextLength)", systemImage: "text.alignleft")
                metaChip("\(L10n.text("Capability source", language: language)): \(capabilitySourceName(model.capabilities.source))", systemImage: capabilityIcon(model.capabilities))
                Spacer(minLength: 8)
                statusBadge(modelValidationBadgeText(model), systemImage: validationIcon(model.validationState))
            }

            capabilityDetails(model.capabilities)

            if let message = model.lastErrorMessage, !message.isEmpty {
                Text(message)
                    .font(.caption)
                    .foregroundStyle(.red)
                    .lineLimit(2)
            }

            HStack(alignment: .center, spacing: 6) {
                Spacer()
                if model.isRemoteProvider {
                    iconToolButton(
                        systemImage: "square.and.pencil",
                        help: L10n.text("Edit", language: language),
                        isDisabled: isTestingThisProvider
                    ) {
                        editProviderDraft(model)
                    }

                    iconToolButton(
                        systemImage: isTestingThisProvider ? "clock" : "network",
                        help: isTestingThisProvider
                            ? L10n.text("Testing", language: language)
                            : L10n.text("Test", language: language),
                        isDisabled: isTestingThisProvider
                    ) {
                        appState.testProviderModel(id: model.id)
                    }

                    iconToolButton(
                        systemImage: isTestingVision ? "clock" : "eye",
                        help: isTestingVision
                            ? L10n.text("Testing vision", language: language)
                            : L10n.text("Test vision", language: language),
                        isDisabled: isTestingThisProvider || isTestingVision
                    ) {
                        appState.testVisionCapability(id: model.id)
                    }
                }

                if model.capabilities.supportsSpeech {
                    iconToolButton(
                        systemImage: "stethoscope",
                        help: L10n.text("Health Check", language: language),
                        isDisabled: appState.mediaSubtitleHealthCheckMode != nil
                    ) {
                        appState.checkMediaSubtitleASRHealth(mode: model.capabilities.supportsRealtimeSpeech ? .realtime : .fileOnly)
                    }
                } else if model.capabilities.supportsImage {
                    iconToolButton(
                        systemImage: "textformat",
                        help: L10n.text("Mark text-only", language: language),
                        isDisabled: isTestingThisProvider || isTestingVision
                    ) {
                        appState.markModelTextOnly(id: model.id)
                    }
                } else {
                    iconToolButton(
                        systemImage: "photo.badge.plus",
                        help: L10n.text("Mark vision-capable", language: language),
                        isDisabled: isTestingThisProvider || isTestingVision
                    ) {
                        appState.markModelVisionCapable(id: model.id)
                    }
                }

                if model.capabilities.source == .manual || model.capabilities.source == .failedProbe {
                    iconToolButton(
                        systemImage: "arrow.counterclockwise",
                        help: L10n.text("Reset capability", language: language),
                        isDisabled: isTestingThisProvider || isTestingVision
                    ) {
                        appState.resetModelCapabilities(id: model.id)
                    }
                }

                if !isDefault {
                    Button {
                        appState.setDefaultModel(id: model.id)
                    } label: {
                        Label(L10n.text("Use as Default", language: language), systemImage: "checkmark.circle")
                    }
                    .buttonStyle(.borderless)
                }

                iconToolButton(
                    systemImage: "trash",
                    help: L10n.text("Remove", language: language),
                    isDisabled: isTestingThisProvider,
                    role: .destructive
                ) {
                    appState.removeModel(id: model.id)
                }
            }
            .frame(height: 24, alignment: .center)
        }
        .padding(13)
        .background(Color(NSColor.controlBackgroundColor).opacity(0.8))
        .overlay(RoundedRectangle(cornerRadius: 8).stroke(Color.secondary.opacity(0.14)))
        .clipShape(RoundedRectangle(cornerRadius: 8))
    }

    private func statusBadge(_ text: String, systemImage: String) -> some View {
        Label(text, systemImage: systemImage)
            .font(.caption)
            .lineLimit(1)
            .foregroundStyle(.secondary)
            .padding(.horizontal, 8)
            .padding(.vertical, 4)
            .background(.quaternary.opacity(0.65))
            .clipShape(Capsule())
    }

    private func formatBadge(_ text: String, tint: Color) -> some View {
        Text(text)
            .font(.caption2.bold())
            .foregroundStyle(tint)
            .padding(.horizontal, 7)
            .padding(.vertical, 3)
            .background(tint.opacity(0.12))
            .clipShape(Capsule())
    }

    private func capabilityDetails(_ capabilities: ModelCapabilities) -> some View {
        VStack(alignment: .leading, spacing: 3) {
            HStack(spacing: 8) {
                Text("\(L10n.text("Confidence", language: language)): \(Int(capabilities.confidence * 100))%")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                if let lastCheckedAt = capabilities.lastCheckedAt {
                    Text(browserDiagnosticDateFormatter.string(from: lastCheckedAt))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
            if let note = capabilities.note, !note.isEmpty {
                Text(note)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(2)
            }
            if let speech = capabilities.speech {
                Text("\(speech.family.rawValue) · \(speech.modes.map { $0.rawValue }.joined(separator: ", "))")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
            if let failure = capabilities.lastFailureMessage, !failure.isEmpty {
                Text(failure)
                    .font(.caption)
                    .foregroundStyle(.red)
                    .lineLimit(2)
            }
        }
    }

    private func metaChip(_ text: String, systemImage: String) -> some View {
        Label(text, systemImage: systemImage)
            .font(.caption)
            .foregroundStyle(.secondary)
            .lineLimit(1)
            .padding(.horizontal, 7)
            .padding(.vertical, 4)
            .background(.quaternary.opacity(0.5))
            .clipShape(RoundedRectangle(cornerRadius: 6))
    }

    private func modelIcon(for format: ModelFormat) -> String {
        switch format {
        case .mlx:
            return "cpu"
        case .gguf:
            return "memorychip"
        case .openAICompatible:
            return "network"
        case .anthropicMessages:
            return "cloud"
        case .speech:
            return "waveform"
        case .unknown:
            return "questionmark.square.dashed"
        }
    }

    private func modelTint(for format: ModelFormat) -> Color {
        switch format {
        case .mlx:
            return .pink
        case .gguf:
            return .blue
        case .openAICompatible:
            return .indigo
        case .anthropicMessages:
            return .orange
        case .speech:
            return .green
        case .unknown:
            return .gray
        }
    }

    private func roleName(_ role: ModelRole) -> String {
        switch (language, role) {
        case (.chinese, .fast):
            return "快速"
        case (.chinese, .default):
            return "默认"
        case (.chinese, .quality):
            return "高质量"
        case (.english, _):
            return role.rawValue
        }
    }

    private func validationName(_ state: ModelValidationState) -> String {
        switch (language, state) {
        case (.chinese, .unknown):
            return "未确认"
        case (.chinese, .valid):
            return "有效"
        case (.chinese, .invalid):
            return "无效"
        case (.chinese, .loading):
            return "加载中"
        case (.chinese, .ready):
            return "可用"
        case (.chinese, .failed):
            return "失败"
        case (.english, _):
            return state.rawValue
        }
    }

    private func modelValidationBadgeText(_ model: ModelDescriptor) -> String {
        if model.isRemoteProvider && model.validationState == .ready {
            return L10n.text("Provider test succeeded", language: language)
        }
        return validationName(model.validationState)
    }

    private func validationIcon(_ state: ModelValidationState) -> String {
        switch state {
        case .valid, .ready:
            return "checkmark.circle.fill"
        case .invalid, .failed:
            return "xmark.octagon.fill"
        case .loading:
            return "clock"
        case .unknown:
            return "questionmark.circle"
        }
    }

    private func capabilityName(_ capabilities: ModelCapabilities) -> String {
        if capabilities.supportsSpeech {
            if capabilities.supportsRealtimeSpeech {
                return L10n.text("Speech realtime", language: language)
            }
            return L10n.text("Speech file-only", language: language)
        }
        if capabilities.supportsImage {
            return L10n.text("Vision", language: language)
        }
        return L10n.text("Text only", language: language)
    }

    private func capabilityIcon(_ capabilities: ModelCapabilities) -> String {
        if capabilities.supportsSpeech {
            return "waveform"
        }
        if capabilities.supportsImage {
            return "eye"
        }
        return "textformat"
    }

    private func capabilityTint(_ capabilities: ModelCapabilities) -> Color {
        if capabilities.supportsSpeech {
            return .green
        }
        if capabilities.supportsImage {
            return .teal
        }
        return .secondary
    }

    private func capabilitySourceName(_ source: ModelCapabilitySource) -> String {
        switch (language, source) {
        case (.chinese, .detected):
            return "已检测"
        case (.chinese, .inferred):
            return "推断"
        case (.chinese, .probePassed):
            return "探测通过"
        case (.chinese, .failedProbe):
            return "探测失败"
        case (.chinese, .manual):
            return "手动"
        case (.chinese, .unknown):
            return "未知"
        case (.english, _):
            return source.rawValue
        }
    }

    private func browserStatusName(_ status: BrowserIntegrationStatus) -> String {
        switch (language, status) {
        case (.chinese, .notInstalled):
            return "未安装"
        case (.chinese, .extensionMissing):
            return "需手动加载"
        case (.chinese, .extensionInstalledDisabled):
            return "扩展已关闭"
        case (.chinese, .permissionMissing):
            return "缺少权限"
        case (.chinese, .nativeHostMissing):
            return "桥接缺失"
        case (.chinese, .nativeHostInvalid):
            return "桥接无效"
        case (.chinese, .appNotRunning):
            return "应用未运行"
        case (.chinese, .pairingRequired):
            return "需要配对"
        case (.chinese, .ready):
            return "可用"
        case (.chinese, .failed):
            return "失败"
        case (.english, _):
            return status.rawValue
        }
    }

    private func refreshBrowserIntegrationStates() {
        browserIntegrationStates = BrowserIntegrationService.shared.browserStates()
    }

    private func updateBrowserIntegrationState(_ updatedState: BrowserIntegrationState) {
        if let index = browserIntegrationStates.firstIndex(where: { $0.id == updatedState.id }) {
            browserIntegrationStates[index] = updatedState
        } else {
            browserIntegrationStates.append(updatedState)
        }
    }

    private func repairBrowserBridge(_ state: BrowserIntegrationState) {
        do {
            let updatedState = try BrowserIntegrationService.shared.installOrRepairDevelopmentHost(browserID: state.id)
            updateBrowserIntegrationState(updatedState)
            BrowserIntegrationService.shared.openExtensionsPage(browserID: state.id)
            appState.statusMessage = browserBridgeRepairedMessage(for: state)
        } catch {
            appState.validationError = error.localizedDescription
            updateBrowserIntegrationState(BrowserIntegrationService.shared.browserState(id: state.id))
        }
    }

    private func browserBridgeRepairedMessage(for state: BrowserIntegrationState) -> String {
        switch language {
        case .chinese:
            return "\(state.name) 桥接已修复"
        case .english:
            return "\(state.name) bridge repaired"
        }
    }

    private func browserRepairButtonTitle(for state: BrowserIntegrationState) -> String {
        switch language {
        case .chinese:
            return "修复 \(state.name) 桥接"
        case .english:
            return "Repair \(state.name) Bridge"
        }
    }

    private func browserOpenExtensionsButtonTitle(for state: BrowserIntegrationState) -> String {
        switch language {
        case .chinese:
            return "打开 \(state.name) 扩展"
        case .english:
            return "Open \(state.name) Extensions"
        }
    }

    private func browserExtensionManualInstallText(for state: BrowserIntegrationState) -> String {
        switch language {
        case .chinese:
            return "开发版安装：打开 \(state.name) 扩展，开启“开发者模式”，点击“加载已解压的扩展程序”，选择下方扩展文件夹。"
        case .english:
            return "Development install: open \(state.name) Extensions, enable Developer mode, choose Load unpacked, then select the extension folder below."
        }
    }

    private func browserExtensionInstallModeText(for state: BrowserIntegrationState) -> String {
        switch language {
        case .chinese:
            return "Phase 2 中 \(state.name) 明确保持 development-only；生产扩展 ID 和商店安装链接留到后续发布决策。"
        case .english:
            return "For Phase 2, \(state.name) explicitly remains development-only; production extension ID and store install links are deferred to a later release decision."
        }
    }

    private func browserExtensionPermissionText(for state: BrowserIntegrationState) -> String {
        switch language {
        case .chinese:
            return "llmTools 只能写入 \(state.name) 本地桥接清单并打开扩展页；加载扩展、启用扩展和站点权限仍需在浏览器中确认。"
        case .english:
            return "llmTools can write the \(state.name) native bridge manifest and open its extensions page; loading, enabling, and site permissions still require browser confirmation."
        }
    }

    private func browserExtensionChannelName(_ channel: String?) -> String {
        switch (language, channel) {
        case (.chinese, "development"):
            return "开发版"
        case (.chinese, "production"):
            return "生产版"
        case (.english, .some(let channel)):
            return channel
        default:
            return "-"
        }
    }

    private func browserStatusIcon(_ status: BrowserIntegrationStatus) -> String {
        switch status {
        case .ready:
            return "checkmark.circle.fill"
        case .extensionMissing, .nativeHostMissing, .pairingRequired:
            return "exclamationmark.triangle.fill"
        case .failed, .nativeHostInvalid, .notInstalled:
            return "xmark.octagon.fill"
        default:
            return "circle.dashed"
        }
    }

    private func mediaASRStatusName(_ status: ASRHealthReport.Status) -> String {
        switch (language, status) {
        case (.chinese, .ready):
            return "就绪"
        case (.chinese, .modelMissing):
            return "模型缺失"
        case (.chinese, .runtimeMissing):
            return "运行时缺失"
        case (.chinese, .incompatibleModel):
            return "模型不兼容"
        case (.chinese, .loadFailed):
            return "加载失败"
        case (.chinese, .inferenceFailed):
            return "推理失败"
        case (.english, .ready):
            return "Ready"
        case (.english, .modelMissing):
            return "Model missing"
        case (.english, .runtimeMissing):
            return "Runtime missing"
        case (.english, .incompatibleModel):
            return "Incompatible"
        case (.english, .loadFailed):
            return "Load failed"
        case (.english, .inferenceFailed):
            return "Inference failed"
        }
    }

    private func mediaASRStatusIcon(_ status: ASRHealthReport.Status) -> String {
        switch status {
        case .ready:
            return "checkmark.circle.fill"
        case .runtimeMissing, .modelMissing, .incompatibleModel:
            return "exclamationmark.triangle.fill"
        case .loadFailed, .inferenceFailed:
            return "xmark.octagon.fill"
        }
    }

    @ViewBuilder
    private func mediaASRHealthReportView(_ report: ASRHealthReport, mode: SpeechRuntimeMode) -> some View {
        statusBadge(mediaASRStatusName(report.status), systemImage: mediaASRStatusIcon(report.status))
        Text(report.message)
            .font(.caption)
            .foregroundStyle(report.status == .ready ? Color.secondary : Color.red)
            .fixedSize(horizontal: false, vertical: true)
        Text("\(L10n.text("Runtime source", language: language)): \(mediaASRRuntimeSourceName(report.runtimeSource))")
            .font(.caption2)
            .foregroundStyle(.secondary)
        if appState.canRepairMediaSubtitleASRRuntime(report: report) {
            HStack(spacing: 8) {
                Button {
                    appState.repairMediaSubtitleASRRuntime(mode: mode)
                } label: {
                    Label(
                        L10n.text("Repair Runtime", language: language),
                        systemImage: appState.mediaSubtitleASRRepairMode == mode ? "clock" : "wrench.and.screwdriver"
                    )
                }
                .controlSize(.small)
                .disabled(appState.mediaSubtitleASRRepairMode != nil || appState.mediaSubtitleHealthCheckMode != nil)
                Text(L10n.text("Installs or reuses the matching isolated MLX ASR runtime, then writes the command template.", language: language))
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    private func languageIDModelVariantName(_ variant: LanguageIDModelVariant) -> String {
        switch (language, variant) {
        case (.chinese, .ftz):
            return "FTZ 小模型"
        case (.chinese, .bin):
            return "BIN 高精度"
        case (.chinese, .customCommand):
            return "自定义命令"
        case (.english, .ftz):
            return "FTZ compact"
        case (.english, .bin):
            return "BIN full"
        case (.english, .customCommand):
            return "Custom command"
        }
    }

    private func languageDetectionHealthStatusName(_ status: LanguageDetectionHealthStatus) -> String {
        switch (language, status) {
        case (.chinese, .ready):
            return "可用"
        case (.chinese, .disabled):
            return "已关闭"
        case (.chinese, .skippedShortText):
            return "文本过短"
        case (.chinese, .modelMissing):
            return "模型缺失"
        case (.chinese, .runtimeMissing):
            return "运行时缺失"
        case (.chinese, .failed):
            return "失败"
        case (.english, .ready):
            return "Ready"
        case (.english, .disabled):
            return "Disabled"
        case (.english, .skippedShortText):
            return "Skipped short text"
        case (.english, .modelMissing):
            return "Model missing"
        case (.english, .runtimeMissing):
            return "Runtime missing"
        case (.english, .failed):
            return "Failed"
        }
    }

    private func languageDetectionHealthIcon(_ status: LanguageDetectionHealthStatus) -> String {
        switch status {
        case .ready:
            return "checkmark.seal.fill"
        case .disabled, .skippedShortText:
            return "pause.circle"
        case .modelMissing, .runtimeMissing:
            return "exclamationmark.triangle.fill"
        case .failed:
            return "xmark.octagon.fill"
        }
    }

    @ViewBuilder
    private func languageDetectionHealthReportView(_ report: LanguageDetectionHealth) -> some View {
        statusBadge(
            languageDetectionHealthStatusName(report.status),
            systemImage: languageDetectionHealthIcon(report.status)
        )
        Text(report.message)
            .font(.caption)
            .foregroundStyle(report.status == .ready || report.status == .disabled ? Color.secondary : Color.red)
            .fixedSize(horizontal: false, vertical: true)
        Text("\(L10n.text("Runtime source", language: language)): \(languageDetectionRuntimeSourceName(report.source))")
            .font(.caption2)
            .foregroundStyle(.secondary)
        if let result = report.sampleResult, let detectedLanguage = result.language {
            Text("\(L10n.text("Detected source", language: language)): \(detectedLanguage) · \(String(format: "%.2f", result.confidence))")
                .font(.caption2.monospacedDigit())
                .foregroundStyle(result.isReliable ? Color.secondary : Color.orange)
        }
        if appState.canRepairLanguageDetectionRuntime(report: report) {
            HStack(spacing: 8) {
                Button {
                    appState.repairLanguageDetectionRuntime()
                } label: {
                    Label(
                        L10n.text("Repair Runtime", language: language),
                        systemImage: appState.languageDetectionRuntimeRepairInProgress ? "clock" : "wrench.and.screwdriver"
                    )
                }
                .controlSize(.small)
                .disabled(appState.languageDetectionRuntimeRepairInProgress || appState.languageDetectionHealthCheckInProgress)
                Text(L10n.text("Installs or reuses the isolated fastText language routing runtime, downloads the compact model, then smoke-tests the sidecar.", language: language))
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    private func languageDetectionRuntimeSourceName(_ source: LanguageDetectionRuntimeSource) -> String {
        switch (language, source) {
        case (.chinese, .fixtureJSON):
            return "测试夹具"
        case (.chinese, .settingsCommand):
            return "设置命令"
        case (.chinese, .bundledFastTextSidecar):
            return "内置 fastText sidecar"
        case (.chinese, .unavailable):
            return "不可用"
        case (.english, .fixtureJSON):
            return "Fixture"
        case (.english, .settingsCommand):
            return "Settings command"
        case (.english, .bundledFastTextSidecar):
            return "Bundled fastText sidecar"
        case (.english, .unavailable):
            return "Unavailable"
        }
    }

    private func fastTranslationSurfaceEngineName(_ engine: FastTranslationSurfaceEngine) -> String {
        switch (language, engine) {
        case (.chinese, .auto):
            return "自动"
        case (.chinese, .llm):
            return "LLM"
        case (.chinese, .fastMT):
            return "快速 MT"
        case (.english, .auto):
            return "Auto"
        case (.english, .llm):
            return "LLM"
        case (.english, .fastMT):
            return "Fast MT"
        }
    }

    private func fastTranslationModelVariantName(_ variant: FastTranslationModelVariant) -> String {
        switch (language, variant) {
        case (.chinese, .opusMTEnZh):
            return "OPUS 英译中"
        case (.chinese, .nllb200Distilled600M):
            return "NLLB 200 600M 多语言"
        case (.english, .opusMTEnZh):
            return "OPUS English to Chinese"
        case (.english, .nllb200Distilled600M):
            return "NLLB 200 600M Multilingual"
        }
    }

    private func fastTranslationFallbackPolicyName(_ policy: FastTranslationFallbackPolicy) -> String {
        switch (language, policy) {
        case (.chinese, .fallbackToLLM):
            return "回退 LLM"
        case (.chinese, .showError):
            return "显示错误"
        case (.english, .fallbackToLLM):
            return "Fallback to LLM"
        case (.english, .showError):
            return "Show error"
        }
    }

    private func fastTranslationHealthStatusName(_ status: FastTranslationHealthStatus) -> String {
        switch (language, status) {
        case (.chinese, .ready):
            return "可用"
        case (.chinese, .disabled):
            return "已关闭"
        case (.chinese, .runtimeMissing):
            return "运行时缺失"
        case (.chinese, .unsupportedLanguagePair):
            return "语言对不支持"
        case (.chinese, .failed):
            return "失败"
        case (.english, .ready):
            return "Ready"
        case (.english, .disabled):
            return "Disabled"
        case (.english, .runtimeMissing):
            return "Runtime missing"
        case (.english, .unsupportedLanguagePair):
            return "Unsupported pair"
        case (.english, .failed):
            return "Failed"
        }
    }

    private func fastTranslationHealthIcon(_ status: FastTranslationHealthStatus) -> String {
        switch status {
        case .ready:
            return "checkmark.seal.fill"
        case .disabled:
            return "pause.circle"
        case .runtimeMissing, .unsupportedLanguagePair:
            return "exclamationmark.triangle.fill"
        case .failed:
            return "xmark.octagon.fill"
        }
    }

    @ViewBuilder
    private func fastTranslationHealthReportView(_ report: FastTranslationHealth) -> some View {
        statusBadge(
            fastTranslationHealthStatusName(report.status),
            systemImage: fastTranslationHealthIcon(report.status)
        )
        Text(report.message)
            .font(.caption)
            .foregroundStyle(report.status == .ready || report.status == .disabled ? Color.secondary : Color.red)
            .fixedSize(horizontal: false, vertical: true)
        Text("\(L10n.text("Runtime source", language: language)): \(fastTranslationRuntimeSourceName(report.source))")
            .font(.caption2)
            .foregroundStyle(.secondary)
        if let engineID = report.engineID {
            Text("\(L10n.text("Engine", language: language)): \(engineID.rawValue)")
                .font(.caption2.monospacedDigit())
                .foregroundStyle(.secondary)
        }
        if let modelID = report.modelID {
            Text("\(L10n.text("Model", language: language)): \(modelID)")
                .font(.caption2.monospacedDigit())
                .foregroundStyle(.secondary)
        }
        if !report.supportedPairs.isEmpty {
            let preview = report.supportedPairs.prefix(12).map { "\($0.source)->\($0.target)" }.joined(separator: ", ")
            let suffix = report.supportedPairs.count > 12 ? " … +\(report.supportedPairs.count - 12)" : ""
            Text("\(L10n.text("Supported pairs", language: language)): \(preview)\(suffix)")
                .font(.caption2.monospacedDigit())
                .foregroundStyle(.secondary)
        }
        if appState.canRepairFastTranslationRuntime(report: report) {
            HStack(spacing: 8) {
                Button {
                    appState.repairFastTranslationRuntime()
                } label: {
                    Label(
                        L10n.text("Repair Runtime", language: language),
                        systemImage: appState.fastTranslationRuntimeRepairInProgress ? "clock" : "wrench.and.screwdriver"
                    )
                }
                .controlSize(.small)
                .disabled(appState.fastTranslationRuntimeRepairInProgress || appState.fastTranslationHealthCheckInProgress)
                Text(L10n.text("Installs or reuses the isolated CTranslate2 fast MT runtime, converts the selected fast MT model, then smoke-tests the sidecar.", language: language))
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    private func fastTranslationRuntimeSourceName(_ source: FastTranslationRuntimeSource) -> String {
        switch (language, source) {
        case (.chinese, .fixtureJSON):
            return "测试夹具"
        case (.chinese, .settingsCommand):
            return "设置命令"
        case (.chinese, .bundledCTranslate2Sidecar):
            return "内置 CTranslate2 sidecar"
        case (.chinese, .bundledArgosSidecar):
            return "内置 Argos sidecar"
        case (.chinese, .unavailable):
            return "不可用"
        case (.english, .fixtureJSON):
            return "Fixture"
        case (.english, .settingsCommand):
            return "Settings command"
        case (.english, .bundledCTranslate2Sidecar):
            return "Bundled CTranslate2 sidecar"
        case (.english, .bundledArgosSidecar):
            return "Bundled Argos sidecar"
        case (.english, .unavailable):
            return "Unavailable"
        }
    }

    private func speakerDiarizationHealthStatusName(_ status: SpeakerDiarizationHealthStatus) -> String {
        switch (language, status) {
        case (.chinese, .ready):
            return "运行时已配置"
        case (.chinese, .disabled):
            return "已关闭"
        case (.chinese, .requiresUserToken):
            return "需要 Token"
        case (.chinese, .runtimeMissing):
            return "运行时缺失"
        case (.chinese, .failed):
            return "失败"
        case (.english, .ready):
            return "Runtime configured"
        case (.english, .disabled):
            return "Disabled"
        case (.english, .requiresUserToken):
            return "Requires token"
        case (.english, .runtimeMissing):
            return "Runtime missing"
        case (.english, .failed):
            return "Failed"
        }
    }

    private func speakerDiarizationHealthIcon(_ status: SpeakerDiarizationHealthStatus) -> String {
        switch status {
        case .ready:
            return "checkmark.seal.fill"
        case .disabled:
            return "pause.circle"
        case .requiresUserToken, .runtimeMissing:
            return "exclamationmark.triangle.fill"
        case .failed:
            return "xmark.octagon.fill"
        }
    }

    @ViewBuilder
    private func speakerDiarizationHealthReportView(_ report: SpeakerDiarizationHealth) -> some View {
        statusBadge(
            speakerDiarizationHealthStatusName(report.status),
            systemImage: speakerDiarizationHealthIcon(report.status)
        )
        Text(report.message)
            .font(.caption)
            .foregroundStyle(report.status == .ready || report.status == .disabled ? Color.secondary : Color.red)
            .fixedSize(horizontal: false, vertical: true)
        Text("\(L10n.text("Runtime source", language: language)): \(speakerDiarizationRuntimeSourceName(report.source))")
            .font(.caption2)
            .foregroundStyle(.secondary)
        Text("\(L10n.text("Token present", language: language)): \(report.tokenPresent ? L10n.text("Yes", language: language) : L10n.text("No", language: language))")
            .font(.caption2)
            .foregroundStyle(.secondary)
        speakerDiarizationResolutionView(report)
    }

    @ViewBuilder
    private func speakerDiarizationResolutionView(_ report: SpeakerDiarizationHealth) -> some View {
        if report.status == .requiresUserToken {
            VStack(alignment: .leading, spacing: 6) {
                Text(L10n.text("Fix path", language: language))
                    .font(.caption.weight(.semibold))
                Text(L10n.text("1. Open the pyannote model pages and accept both speaker-diarization-3.1 and segmentation-3.0 terms with your Hugging Face account.", language: language))
                    .font(.caption)
                Text(L10n.text("2. Create a Hugging Face token, paste it into the HF token field above, then click Save Token.", language: language))
                    .font(.caption)
                Text(L10n.text("3. Run Health Check again. If the next status is runtime missing, click Repair Runtime here.", language: language))
                    .font(.caption)
                HStack(spacing: 8) {
                    Button {
                        openPyannoteModelTerms()
                    } label: {
                        Label(L10n.text("Open model terms", language: language), systemImage: "checkmark.seal")
                    }
                    .controlSize(.small)
                    Button {
                        openExternalURL("https://huggingface.co/settings/tokens")
                    } label: {
                        Label(L10n.text("Create HF token", language: language), systemImage: "safari")
                    }
                    .controlSize(.small)
                }
            }
            .padding(8)
            .background(Color(nsColor: .controlBackgroundColor))
            .clipShape(RoundedRectangle(cornerRadius: 6))
        }
        if appState.canRepairSpeakerDiarizationRuntime(report: report) {
            HStack(spacing: 8) {
                Button {
                    appState.repairSpeakerDiarizationRuntime()
                } label: {
                    Label(
                        L10n.text("Repair Runtime", language: language),
                        systemImage: appState.speakerDiarizationRuntimeRepairInProgress ? "clock" : "wrench.and.screwdriver"
                    )
                }
                .controlSize(.small)
                .disabled(appState.speakerDiarizationRuntimeRepairInProgress || appState.speakerDiarizationHealthCheckInProgress)
                Text(L10n.text("Installs or reuses the local pyannote runtime used by file subtitle speaker diarization.", language: language))
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    private func speakerDiarizationRuntimeSourceName(_ source: SpeakerDiarizationRuntimeSource) -> String {
        switch (language, source) {
        case (.chinese, .fixtureJSON):
            return "测试夹具"
        case (.chinese, .settingsCommand):
            return "设置命令"
        case (.chinese, .bundledPyannoteSidecar):
            return "内置 pyannote sidecar"
        case (.chinese, .unavailable):
            return "不可用"
        case (.english, .fixtureJSON):
            return "Fixture"
        case (.english, .settingsCommand):
            return "Settings command"
        case (.english, .bundledPyannoteSidecar):
            return "Bundled pyannote sidecar"
        case (.english, .unavailable):
            return "Unavailable"
        }
    }

    private func mediaASRRuntimeSourceName(_ source: ASRRuntimeSource) -> String {
        switch (language, source) {
        case (.chinese, .settingsCommand):
            return "设置命令"
        case (.chinese, .environmentCommand):
            return "环境变量"
        case (.chinese, .fixtureTranscript):
            return "测试夹具"
        case (.chinese, .mlxAudioRunner):
            return "本地 mlx-audio"
        case (.chinese, .sherpaOnnxAuto):
            return "自动 sherpa-onnx"
        case (.chinese, .sherpaOnnxQwen3Runner):
            return "已移除 sherpa-onnx Qwen3"
        case (.chinese, .whisperCppCoreMLRunner):
            return "whisper.cpp CoreML"
        case (.chinese, .funASRGGUFAuto):
            return "自动 FunASR GGUF"
        case (.chinese, .vibeVoiceASRRunner):
            return "VibeVoice-ASR"
        case (.chinese, .unavailable):
            return "未配置"
        case (.english, .settingsCommand):
            return "Settings command"
        case (.english, .environmentCommand):
            return "Environment variable"
        case (.english, .fixtureTranscript):
            return "Fixture transcript"
        case (.english, .mlxAudioRunner):
            return "Local mlx-audio"
        case (.english, .sherpaOnnxAuto):
            return "Auto sherpa-onnx"
        case (.english, .sherpaOnnxQwen3Runner):
            return "Removed sherpa-onnx Qwen3"
        case (.english, .whisperCppCoreMLRunner):
            return "whisper.cpp Core ML"
        case (.english, .funASRGGUFAuto):
            return "Auto FunASR GGUF"
        case (.english, .vibeVoiceASRRunner):
            return "VibeVoice-ASR"
        case (.english, .unavailable):
            return "Unavailable"
        }
    }

    private func settingsSpeechModelPickerTitle(_ model: ModelDescriptor) -> String {
        let modeLabel = model.capabilities.supportsRealtimeSpeech
            ? L10n.text("Realtime", language: language)
            : L10n.text("File only", language: language)
        let family = model.capabilities.speech?.family.rawValue ?? model.sizeClass
        return "\(model.name) · \(family) · \(modeLabel)"
    }

    private func settingsMeetingSpeechModelPickerTitle(_ model: ModelDescriptor) -> String {
        let modeLabel: String
        if model.capabilities.speech?.canEmitSpeakerLabels == true {
            modeLabel = localizedSettingsText(chinese: "原生说话人", english: "Native speakers")
        } else {
            modeLabel = localizedSettingsText(chinese: "先分离后转写", english: "Diarization first")
        }
        let family = model.capabilities.speech?.family.rawValue ?? model.sizeClass
        return "\(model.name) · \(family) · \(modeLabel)"
    }

    private func subtitleModeName(_ mode: SubtitleDisplayMode) -> String {
        switch (language, mode) {
        case (.chinese, .original):
            return "原文"
        case (.chinese, .translated):
            return "译文"
        case (.chinese, .bilingual):
            return "双语"
        case (.english, .original):
            return "Original"
        case (.english, .translated):
            return "Translated"
        case (.english, .bilingual):
            return "Bilingual"
        }
    }

    private func sourceLanguageHintName(_ hint: ASRSourceLanguageHint) -> String {
        switch (language, hint) {
        case (.chinese, .auto):
            return "自动"
        case (.chinese, .zh):
            return "中文"
        case (.chinese, .yue):
            return "粤语"
        case (.chinese, .en):
            return "英文"
        case (.chinese, .ja):
            return "日语"
        case (.chinese, .ko):
            return "韩语"
        case (.chinese, .vi):
            return "越南语"
        case (.chinese, .id):
            return "印尼语"
        case (.chinese, .th):
            return "泰语"
        case (.chinese, .ms):
            return "马来语"
        case (.chinese, .fil):
            return "菲律宾语"
        case (.chinese, .ar):
            return "阿拉伯语"
        case (.chinese, .hi):
            return "印地语"
        case (.chinese, .de):
            return "德语"
        case (.chinese, .fr):
            return "法语"
        case (.chinese, .es):
            return "西班牙语"
        case (.chinese, .pt):
            return "葡萄牙语"
        case (.chinese, .it):
            return "意大利语"
        case (.chinese, .ru):
            return "俄语"
        case (.english, .auto):
            return "Auto"
        case (.english, .zh):
            return "Chinese"
        case (.english, .yue):
            return "Cantonese"
        case (.english, .en):
            return "English"
        case (.english, .ja):
            return "Japanese"
        case (.english, .ko):
            return "Korean"
        case (.english, .vi):
            return "Vietnamese"
        case (.english, .id):
            return "Indonesian"
        case (.english, .th):
            return "Thai"
        case (.english, .ms):
            return "Malay"
        case (.english, .fil):
            return "Filipino"
        case (.english, .ar):
            return "Arabic"
        case (.english, .hi):
            return "Hindi"
        case (.english, .de):
            return "German"
        case (.english, .fr):
            return "French"
        case (.english, .es):
            return "Spanish"
        case (.english, .pt):
            return "Portuguese"
        case (.english, .it):
            return "Italian"
        case (.english, .ru):
            return "Russian"
        }
    }

    private func liveAudioSourceName(_ source: LiveSubtitleAudioSource) -> String {
        switch (language, source) {
        case (.chinese, .systemAudio):
            return "系统音频"
        case (.chinese, .microphone):
            return "麦克风"
        case (.chinese, .systemAndMicrophone):
            return "系统音频 + 麦克风"
        case (.english, .systemAudio):
            return "System audio"
        case (.english, .microphone):
            return "Microphone"
        case (.english, .systemAndMicrophone):
            return "System + Microphone"
        }
    }

    private func openApplicationSupportFolder() {
        let url = AppPaths.applicationSupportDirectory
        try? FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        NSWorkspace.shared.open(url)
    }

    private func openExternalURL(_ value: String) {
        guard let url = URL(string: value) else {
            return
        }
        NSWorkspace.shared.open(url)
    }

    private func openPyannoteModelTerms() {
        for value in [
            "https://huggingface.co/pyannote/speaker-diarization-3.1",
            "https://huggingface.co/pyannote/segmentation-3.0"
        ] {
            openExternalURL(value)
        }
    }

    private func copyToPasteboard(_ value: String) {
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(value, forType: .string)
    }
}

private struct ShortcutCaptureBridge: NSViewRepresentable {
    @Binding var target: ShortcutCaptureTarget?
    var onShortcut: (ShortcutCaptureTarget, KeyboardShortcutPreference) -> Void
    var onInvalidShortcut: () -> Void
    var onCancel: () -> Void

    func makeNSView(context: Context) -> ShortcutCaptureNSView {
        ShortcutCaptureNSView()
    }

    func updateNSView(_ nsView: ShortcutCaptureNSView, context: Context) {
        nsView.isCapturing = target != nil
        nsView.onShortcut = { shortcut in
            guard let target else {
                return
            }
            onShortcut(target, shortcut)
        }
        nsView.onInvalidShortcut = onInvalidShortcut
        nsView.onCancel = onCancel

        if target != nil {
            DispatchQueue.main.async {
                nsView.window?.makeFirstResponder(nsView)
            }
        }
    }
}

private final class ShortcutCaptureNSView: NSView {
    var isCapturing = false
    var onShortcut: ((KeyboardShortcutPreference) -> Void)?
    var onInvalidShortcut: (() -> Void)?
    var onCancel: (() -> Void)?

    override var acceptsFirstResponder: Bool {
        true
    }

    override func keyDown(with event: NSEvent) {
        guard isCapturing else {
            super.keyDown(with: event)
            return
        }

        if event.keyCode == UInt16(kVK_Escape) {
            onCancel?()
            return
        }

        guard let shortcut = KeyboardShortcutPreference(event: event) else {
            NSSound.beep()
            onInvalidShortcut?()
            return
        }

        onShortcut?(shortcut)
    }
}

extension KeyboardShortcutPreference {
    init?(event: NSEvent) {
        let keyCode = UInt32(event.keyCode)
        guard !Self.modifierKeyCodes.contains(keyCode) else {
            return nil
        }

        let flags = event.modifierFlags.intersection(.deviceIndependentFlagsMask)
        var carbonModifiers: UInt32 = 0
        if flags.contains(.command) {
            carbonModifiers |= Self.commandModifier
        }
        if flags.contains(.shift) {
            carbonModifiers |= Self.shiftModifier
        }
        if flags.contains(.option) {
            carbonModifiers |= Self.optionModifier
        }
        if flags.contains(.control) {
            carbonModifiers |= Self.controlModifier
        }

        let requiredModifiers = Self.commandModifier | Self.optionModifier | Self.controlModifier
        guard carbonModifiers & requiredModifiers != 0 else {
            return nil
        }

        self.init(keyCode: keyCode, modifiers: carbonModifiers)
    }

    var displayKeys: [String] {
        var keys: [String] = []
        if modifiers & Self.commandModifier != 0 {
            keys.append("⌘")
        }
        if modifiers & Self.optionModifier != 0 {
            keys.append("⌥")
        }
        if modifiers & Self.controlModifier != 0 {
            keys.append("⌃")
        }
        if modifiers & Self.shiftModifier != 0 {
            keys.append("⇧")
        }
        keys.append(Self.keyName(for: keyCode))
        return keys
    }

    private static let modifierKeyCodes: Set<UInt32> = [
        54, 55, 56, 57, 58, 59, 60, 61, 62, 63
    ]

    private static func keyName(for keyCode: UInt32) -> String {
        switch keyCode {
        case UInt32(kVK_ANSI_A): return "A"
        case UInt32(kVK_ANSI_S): return "S"
        case UInt32(kVK_ANSI_D): return "D"
        case UInt32(kVK_ANSI_F): return "F"
        case UInt32(kVK_ANSI_H): return "H"
        case UInt32(kVK_ANSI_G): return "G"
        case UInt32(kVK_ANSI_Z): return "Z"
        case UInt32(kVK_ANSI_X): return "X"
        case UInt32(kVK_ANSI_C): return "C"
        case UInt32(kVK_ANSI_V): return "V"
        case UInt32(kVK_ANSI_B): return "B"
        case UInt32(kVK_ANSI_Q): return "Q"
        case UInt32(kVK_ANSI_W): return "W"
        case UInt32(kVK_ANSI_E): return "E"
        case UInt32(kVK_ANSI_R): return "R"
        case UInt32(kVK_ANSI_Y): return "Y"
        case UInt32(kVK_ANSI_T): return "T"
        case UInt32(kVK_ANSI_1): return "1"
        case UInt32(kVK_ANSI_2): return "2"
        case UInt32(kVK_ANSI_3): return "3"
        case UInt32(kVK_ANSI_4): return "4"
        case UInt32(kVK_ANSI_6): return "6"
        case UInt32(kVK_ANSI_5): return "5"
        case UInt32(kVK_ANSI_Equal): return "="
        case UInt32(kVK_ANSI_9): return "9"
        case UInt32(kVK_ANSI_7): return "7"
        case UInt32(kVK_ANSI_Minus): return "-"
        case UInt32(kVK_ANSI_8): return "8"
        case UInt32(kVK_ANSI_0): return "0"
        case UInt32(kVK_ANSI_RightBracket): return "]"
        case UInt32(kVK_ANSI_O): return "O"
        case UInt32(kVK_ANSI_U): return "U"
        case UInt32(kVK_ANSI_LeftBracket): return "["
        case UInt32(kVK_ANSI_I): return "I"
        case UInt32(kVK_ANSI_P): return "P"
        case UInt32(kVK_ANSI_L): return "L"
        case UInt32(kVK_ANSI_J): return "J"
        case UInt32(kVK_ANSI_Quote): return "'"
        case UInt32(kVK_ANSI_K): return "K"
        case UInt32(kVK_ANSI_Semicolon): return ";"
        case UInt32(kVK_ANSI_Backslash): return "\\"
        case UInt32(kVK_ANSI_Comma): return ","
        case UInt32(kVK_ANSI_Slash): return "/"
        case UInt32(kVK_ANSI_N): return "N"
        case UInt32(kVK_ANSI_M): return "M"
        case UInt32(kVK_ANSI_Period): return "."
        case UInt32(kVK_ANSI_Grave): return "`"
        case UInt32(kVK_Space): return "Space"
        case UInt32(kVK_Return): return "Return"
        case UInt32(kVK_Tab): return "Tab"
        case UInt32(kVK_Delete): return "Delete"
        case UInt32(kVK_ForwardDelete): return "Del"
        case UInt32(kVK_LeftArrow): return "←"
        case UInt32(kVK_RightArrow): return "→"
        case UInt32(kVK_DownArrow): return "↓"
        case UInt32(kVK_UpArrow): return "↑"
        case UInt32(kVK_F1): return "F1"
        case UInt32(kVK_F2): return "F2"
        case UInt32(kVK_F3): return "F3"
        case UInt32(kVK_F4): return "F4"
        case UInt32(kVK_F5): return "F5"
        case UInt32(kVK_F6): return "F6"
        case UInt32(kVK_F7): return "F7"
        case UInt32(kVK_F8): return "F8"
        case UInt32(kVK_F9): return "F9"
        case UInt32(kVK_F10): return "F10"
        case UInt32(kVK_F11): return "F11"
        case UInt32(kVK_F12): return "F12"
        default: return "#\(keyCode)"
        }
    }
}
