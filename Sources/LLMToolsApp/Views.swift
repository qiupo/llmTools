import AppKit
import Carbon.HIToolbox
import SwiftUI
import UniformTypeIdentifiers
import LLMToolsCore

struct SelectionActionView: View {
    @ObservedObject var appState: AppState
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
        HStack(spacing: 8) {
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
        }
        .padding(.horizontal, 11)
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

struct LiveSubtitleFloatingView: View {
    @ObservedObject var appState: AppState
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
                exitImmersiveButton
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
                .stroke(Color.white.opacity(0.16), lineWidth: 0.8)
        )
        .shadow(color: .black.opacity(0.26), radius: 10, y: 4)
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
            Image(systemName: "arrow.down.right.and.arrow.up.left")
                .font(.system(size: 11, weight: .bold))
                .frame(width: 26, height: 26)
                .background(Color.black.opacity(0.38), in: Circle())
                .overlay(Circle().stroke(Color.white.opacity(0.16), lineWidth: 0.8))
        }
        .buttonStyle(.plain)
        .foregroundStyle(.white.opacity(0.86))
        .help(L10n.text("Exit immersive subtitles", language: language))
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
            .padding(.horizontal, 52)
            .padding(.vertical, 12)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        } else {
            VStack(alignment: .center, spacing: 6) {
                immersiveTextLine(immersivePreviousDisplayText, size: 17, weight: .medium, opacity: 0.62)
                immersiveTextLine(immersiveCurrentDisplayText, size: 22, weight: .semibold, opacity: 0.96)
            }
            .padding(.horizontal, 52)
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
    case ocr
    case media
    case webPage
    case defaults
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
        case .webPage:
            return L10n.text("Web Page Translation", language: language)
        case .defaults:
            return L10n.text("Defaults", language: language)
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
            return L10n.text("OCR", language: language)
        case .media:
            return L10n.text("Media", language: language)
        case .prompts:
            return L10n.text("Prompts", language: language)
        default:
            return title(language: language)
        }
    }
}

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

            HStack(spacing: 4) {
                ForEach(SettingsTab.allCases) { tab in
                    settingsTabButton(tab)
                }
            }
            .frame(maxWidth: .infinity)
        }
        .padding(.top, 6)
        .padding(.bottom, 6)
        .padding(.horizontal, 18)
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
            settingRow(title: L10n.text("Image OCR", language: language)) {
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
                        title: L10n.text("Use model recognition by default", language: language),
                        isOn: Binding(
                            get: { appState.preferences.ocr.useModelRecognitionByDefault },
                            set: { newValue in
                                appState.updatePreferences { $0.ocr.useModelRecognitionByDefault = newValue }
                            }
                        )
                    )
                }
            }

            settingRow(title: L10n.text("OCR model", language: language)) {
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

            settingRow(title: L10n.text("OCR mode", language: language)) {
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

            settingRow(title: L10n.text("OCR history", language: language)) {
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

    private var mediaSubtitleSettingsPage: some View {
        settingsForm(maxWidth: 620) {
            settingRow(title: L10n.text("Media subtitles", language: language)) {
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

            settingRow(title: L10n.text("Realtime ASR", language: language)) {
                VStack(alignment: .leading, spacing: 8) {
                    settingsMediaRealtimeASRPicker
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

            settingRow(title: L10n.text("File ASR", language: language)) {
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
                        Text(L10n.text("Qwen3-ASR-0.6B is quality-oriented for file transcription. Fun-ASR uses local streaming or GGUF sidecars for lower-latency live captions.", language: language))
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

            settingRow(title: L10n.text("Subtitle defaults", language: language)) {
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
                            in: 0.25...1.0
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
        settingsForm(maxWidth: 540) {
            settingRow(title: L10n.text("Default model", language: language)) {
                defaultModelPicker
            }

            settingRow(title: L10n.text("Target", language: language)) {
                translationTargetPicker
            }

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
            return "占位符：{input}、{targetLanguage}、{polishStyle}、{summaryMode}、{explanationMode}、{todoMode}、{retryInstruction}"
        case .english:
            return "Variables: {input}, {targetLanguage}, {polishStyle}, {summaryMode}, {explanationMode}, {todoMode}, {retryInstruction}"
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
        settingsForm(maxWidth: 560) {
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
            Text(L10n.text("Use default model", language: language)).tag(UUID?.none)
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
        let version = info?["CFBundleShortVersionString"] as? String ?? "0.3.0"
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
                    RoundedRectangle(cornerRadius: 8, style: .continuous)
                        .fill(isSelected ? Color.accentColor.opacity(0.12) : Color.clear)
                    Image(systemName: tab.systemImage)
                        .font(.system(size: 22, weight: .medium))
                        .symbolRenderingMode(.hierarchical)
                        .foregroundStyle(isSelected ? Color.accentColor : Color.secondary)
                }
                .frame(width: 54, height: 36)

                Text(tab.tabTitle(language: language))
                    .font(.caption2)
                    .lineLimit(1)
                    .truncationMode(.tail)
                    .foregroundStyle(isSelected ? Color.accentColor : Color.secondary)
            }
            .frame(width: 76, height: 56)
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

    private var localModelPanelMessage: String {
        switch language {
        case .chinese:
            return "选择 GGUF 文件、MLX 模型目录或其他本地模型文件。"
        case .english:
            return "Choose a GGUF file, MLX model folder, or another local model file."
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
