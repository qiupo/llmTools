import AppKit
import SwiftUI
import UniformTypeIdentifiers
import LLMTranslateCore

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
        case .polish: return "wand.and.stars"
        case .summarize: return "doc.text"
        case .explain: return "questionmark.circle"
        case .extractTodos: return "list.bullet.clipboard"
        }
    }

    private var actionBar: some View {
        HStack(spacing: 8) {
            ForEach(TaskKind.allCases) { task in
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
    @State private var showInput = true

    private var language: AppLanguage {
        appState.preferences.appLanguage
    }

    private var displayedOutputText: String {
        appState.displayedOutputText
    }

    var body: some View {
        VStack(spacing: 0) {
            controlsBar
            Divider()
            mainContent
            Divider()
            bottomBar
        }
        .frame(minWidth: 560, minHeight: 380)
        .background(Color(NSColor.windowBackgroundColor))
        .fileImporter(isPresented: $showFileImporter, allowedContentTypes: [.plainText, .text, .item], allowsMultipleSelection: false) { result in
            if case let .success(urls) = result, let url = urls.first {
                appState.loadInputFile(from: url)
            }
        }
        .onDrop(of: [.fileURL, .plainText, .text], isTargeted: nil) { providers in
            handleDrop(providers)
        }
        .onChange(of: appState.outputText) { _, newValue in
            if !newValue.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                showInput = false
            }
        }
    }

    private var controlsBar: some View {
        HStack(spacing: 10) {
            Picker("", selection: $appState.selectedTask) {
                ForEach(TaskKind.allCases) { task in
                    Text(task.title(language: language)).tag(task)
                }
            }
            .labelsHidden()
            .frame(width: 108)
            .disabled(appState.isRunning)

            modeOptions
                .frame(minWidth: 220, alignment: .leading)

            Spacer()

            Button {
                showInput.toggle()
            } label: {
                HStack(spacing: 4) {
                    Text(L10n.text(showInput ? "Hide source" : "Show source", language: language))
                    Image(systemName: showInput ? "chevron.up" : "chevron.down")
                        .font(.caption2)
                }
            }
            .buttonStyle(.borderless)
            .disabled(appState.inputText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            .fixedSize(horizontal: true, vertical: false)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
    }

    @ViewBuilder
    private var modeOptions: some View {
        switch appState.selectedTask {
        case .translate:
            HStack(spacing: 8) {
                Text(L10n.text("Auto detect", language: language))
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .fixedSize(horizontal: true, vertical: false)
                    .frame(width: 68)
                    .padding(.horizontal, 10)
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
                .frame(width: 118)
                .disabled(appState.isRunning)
            }
            .fixedSize(horizontal: true, vertical: false)
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
            modeBadge("Key points", systemImage: "list.bullet.rectangle")
        case .explain:
            modeBadge("Plain explanation", systemImage: "questionmark.circle")
        case .extractTodos:
            modeBadge("Action items", systemImage: "checklist")
        }
    }

    private func modeBadge(_ key: String, systemImage: String) -> some View {
        Label(L10n.text(key, language: language), systemImage: systemImage)
            .font(.subheadline)
            .foregroundStyle(.secondary)
            .lineLimit(1)
            .fixedSize(horizontal: true, vertical: false)
            .padding(.horizontal, 10)
            .padding(.vertical, 5)
            .background(.quaternary.opacity(0.45))
            .clipShape(RoundedRectangle(cornerRadius: 6))
    }

    private var mainContent: some View {
        VStack(spacing: 10) {
            if showInput || appState.outputText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                inputPanel
            }
            resultPanel
            if appState.hasDifferentRawOutput {
                rawOutputToggle
            }
        }
        .padding(12)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
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
            ))
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
            } else if displayedOutputText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                Text(resultPlaceholder)
                    .foregroundStyle(.secondary)
                    .padding(12)
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
                appState.runCurrentTask()
            } label: {
                Label(appState.outputText.isEmpty ? L10n.text("Run", language: language) : L10n.text("Regenerate", language: language), systemImage: appState.outputText.isEmpty ? "play.fill" : "arrow.clockwise")
            }
            .disabled(appState.isRunning)

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

    private var rawOutputToggle: some View {
        HStack {
            Spacer()
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

    private var inputPlaceholder: String {
        switch appState.selectedTask {
        case .translate:
            return L10n.text("Paste text to translate.", language: language)
        case .polish:
            return L10n.text("Paste text to polish.", language: language)
        case .summarize:
            return L10n.text("Paste text to summarize.", language: language)
        case .explain:
            return L10n.text("Paste text to explain.", language: language)
        case .extractTodos:
            return L10n.text("Paste text to extract TODOs.", language: language)
        }
    }

    private var resultPlaceholder: String {
        switch appState.selectedTask {
        case .translate:
            return L10n.text("Translation will appear here.", language: language)
        case .polish:
            return L10n.text("Polished text will appear here.", language: language)
        case .summarize:
            return L10n.text("Summary will appear here.", language: language)
        case .explain:
            return L10n.text("Explanation will appear here.", language: language)
        case .extractTodos:
            return L10n.text("TODOs will appear here.", language: language)
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

struct EditableTextView: NSViewRepresentable {
    @Binding var text: String

    func makeCoordinator() -> Coordinator {
        Coordinator(text: $text)
    }

    func makeNSView(context: Context) -> NSScrollView {
        let scrollView = NSScrollView()
        scrollView.drawsBackground = false
        scrollView.hasVerticalScroller = true
        scrollView.borderType = .noBorder

        let textView = CommandFriendlyTextView()
        textView.delegate = context.coordinator
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
        if textView.string != text {
            let selectedRanges = textView.selectedRanges
            textView.string = text
            textView.selectedRanges = selectedRanges
        }
    }

    final class Coordinator: NSObject, NSTextViewDelegate {
        @Binding var text: String
        weak var textView: NSTextView?

        init(text: Binding<String>) {
            _text = text
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
        let scrollView = NSScrollView()
        scrollView.drawsBackground = false
        scrollView.hasVerticalScroller = true
        scrollView.borderType = .noBorder

        let textView = CommandFriendlyTextView()
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
                ForEach(TaskKind.allCases) { task in
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
                    appState.runCurrentTask()
                } label: {
                    Label(L10n.text("Run", language: language), systemImage: "play.fill")
                }
                .disabled(appState.isRunning)

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
                    Text("\(model.name) · \(model.format.rawValue.uppercased()) · \(model.sizeClass)")
                        .tag(Optional(model.id))
                }
            }
        }
        .pickerStyle(.menu)
        .disabled(appState.models.isEmpty || appState.isRunning)
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
        default:
            EmptyView()
        }
    }
}

struct SettingsView: View {
    @ObservedObject var appState: AppState
    @State private var showImporter = false

    private var language: AppLanguage {
        appState.preferences.appLanguage
    }

    var body: some View {
        VStack(spacing: 0) {
            header
            Divider()
            HStack(alignment: .top, spacing: 16) {
                VStack(spacing: 14) {
                    preferencesSection
                    defaultsSection
                }
                .frame(width: 326, alignment: .top)
                .frame(maxHeight: .infinity, alignment: .top)

                modelSection
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
            }
            .padding(16)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        }
        .frame(minWidth: 780, minHeight: 500)
        .background(Color(NSColor.windowBackgroundColor))
        .fileImporter(isPresented: $showImporter, allowedContentTypes: [.folder, .item], allowsMultipleSelection: false) { result in
            if case let .success(urls) = result, let url = urls.first {
                appState.addModel(from: url)
            }
        }
    }

    private var header: some View {
        HStack(spacing: 12) {
            VStack(alignment: .leading, spacing: 4) {
                Text(L10n.text("Models & Settings", language: language))
                    .font(.title3.bold())
                Text(headerSubtitle)
                    .font(.caption)
                    .foregroundStyle(appState.validationError == nil ? Color.secondary : Color.red)
                    .lineLimit(1)
                    .truncationMode(.tail)
            }
            Spacer()
            statusBadge(appState.statusMessage, systemImage: "bolt.horizontal.circle")
            Button {
                showImporter = true
            } label: {
                Label(L10n.text("Add Model", language: language), systemImage: "plus")
            }
            .controlSize(.regular)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 13)
    }

    private var preferencesSection: some View {
        settingsPanel(title: L10n.text("Preferences", language: language), systemImage: "slider.horizontal.3", fillsVertical: false) {
            VStack(spacing: 8) {
                toggleRow(
                    title: L10n.text("Launch at login", language: language),
                    systemImage: "power",
                    isOn: Binding(
                        get: { appState.preferences.launchAtLogin },
                        set: { newValue in
                            appState.setLaunchAtLogin(newValue)
                        }
                    ),
                    trailing: AnyView(statusBadge(appState.launchAtLoginStatusText(), systemImage: launchStatusIcon))
                )

                Divider()

                toggleRow(
                    title: L10n.text("Widget visible on all Spaces", language: language),
                    systemImage: "rectangle.on.rectangle",
                    isOn: Binding(
                        get: { appState.preferences.widgetVisibleOnAllSpaces },
                        set: { newValue in
                            appState.updatePreferences { $0.widgetVisibleOnAllSpaces = newValue }
                        }
                    )
                )

                toggleRow(
                    title: L10n.text("Auto-collapse widget at screen edge", language: language),
                    systemImage: "sidebar.trailing",
                    isOn: Binding(
                        get: { appState.preferences.autoCollapseWidget },
                        set: { newValue in
                            appState.updatePreferences { $0.autoCollapseWidget = newValue }
                        }
                    )
                )

                toggleRow(
                    title: L10n.text("Replace original text after processing", language: language),
                    systemImage: "arrow.triangle.2.circlepath",
                    isOn: Binding(
                        get: { appState.preferences.replaceOriginalText },
                        set: { newValue in
                            appState.updatePreferences { $0.replaceOriginalText = newValue }
                        }
                    )
                )

                toggleRow(
                    title: L10n.text("Show action panel after mouse selection", language: language),
                    systemImage: "cursorarrow.click.2",
                    isOn: Binding(
                        get: { appState.preferences.selectionActionEnabled },
                        set: { newValue in
                            appState.updatePreferences { $0.selectionActionEnabled = newValue }
                        }
                    )
                )
            }
        }
    }

    private var defaultsSection: some View {
        settingsPanel(title: L10n.text("Defaults", language: language), systemImage: "dial.low", fillsVertical: true) {
            VStack(spacing: 9) {
                menuRow(title: L10n.text("App language", language: language), systemImage: "globe") {
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
                    .frame(width: 118)
                }

                menuRow(title: L10n.text("Default translation target", language: language), systemImage: "character.book.closed") {
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
                    .frame(width: 118)
                }

                menuRow(title: L10n.text("Default polish style", language: language), systemImage: "wand.and.stars") {
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
                    .frame(width: 118)
                }

                historyLimitRow
            }
        }
    }

    private var modelSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text(L10n.text("Registered Models", language: language))
                    .font(.headline)
                Text(modelCountText)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 3)
                    .background(.quaternary.opacity(0.65))
                    .clipShape(Capsule())
                Spacer()
            }

            if appState.models.isEmpty {
                emptyModelsView
            } else {
                ScrollView {
                    LazyVStack(spacing: 10) {
                        ForEach(appState.models) { model in
                            modelCard(model)
                        }
                    }
                    .padding(.trailing, 2)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
        .padding(14)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .background(Color(NSColor.controlBackgroundColor).opacity(0.44))
        .overlay(RoundedRectangle(cornerRadius: 8).stroke(Color.secondary.opacity(0.14)))
        .clipShape(RoundedRectangle(cornerRadius: 8))
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
                showImporter = true
            } label: {
                Label(L10n.text("Add Model", language: language), systemImage: "plus")
            }
        }
        .frame(maxWidth: .infinity, minHeight: 220)
        .background(Color(NSColor.controlBackgroundColor).opacity(0.65))
        .overlay(RoundedRectangle(cornerRadius: 8).stroke(Color.secondary.opacity(0.14)))
        .clipShape(RoundedRectangle(cornerRadius: 8))
    }

    private var historyLimitRow: some View {
        HStack(spacing: 10) {
            settingIcon("clock.arrow.circlepath")
            Text(L10n.text("Recent history limit", language: language))
                .font(.subheadline)
                .lineLimit(1)
            Spacer()
            Text("\(appState.preferences.recentHistoryLimit)")
                .font(.caption.monospacedDigit())
                .foregroundStyle(.secondary)
                .frame(width: 26)
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

    private var headerSubtitle: String {
        if let error = appState.validationError {
            return error
        }
        return "\(modelCountText) · \(appState.launchAtLoginStatusText())"
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

    private func settingsPanel<Content: View>(
        title: String,
        systemImage: String,
        fillsVertical: Bool,
        @ViewBuilder content: () -> Content
    ) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            Label(title, systemImage: systemImage)
                .font(.headline)
            content()
            if fillsVertical {
                Spacer(minLength: 0)
            }
        }
        .padding(14)
        .frame(maxWidth: .infinity, maxHeight: fillsVertical ? .infinity : nil, alignment: .topLeading)
        .background(Color(NSColor.controlBackgroundColor).opacity(0.72))
        .overlay(RoundedRectangle(cornerRadius: 8).stroke(Color.secondary.opacity(0.14)))
        .clipShape(RoundedRectangle(cornerRadius: 8))
    }

    private func toggleRow(
        title: String,
        systemImage: String,
        isOn: Binding<Bool>,
        trailing: AnyView? = nil
    ) -> some View {
        HStack(spacing: 10) {
            settingIcon(systemImage)
            Text(title)
                .font(.subheadline)
                .lineLimit(2)
                .fixedSize(horizontal: false, vertical: true)
            Spacer(minLength: 8)
            if let trailing {
                trailing
            }
            CompactSwitch(isOn: isOn)
        }
    }

    private func menuRow<Control: View>(
        title: String,
        systemImage: String,
        @ViewBuilder control: () -> Control
    ) -> some View {
        HStack(spacing: 10) {
            settingIcon(systemImage)
            Text(title)
                .font(.subheadline)
                .lineLimit(2)
                .fixedSize(horizontal: false, vertical: true)
            Spacer(minLength: 8)
            control()
        }
    }

    private func modelCard(_ model: ModelDescriptor) -> some View {
        let isDefault = model.id == appState.preferences.defaultModelID

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
                        formatBadge(model.format.rawValue.uppercased(), tint: modelTint(for: model.format))
                        if isDefault {
                            formatBadge(L10n.text("Default", language: language), tint: .green)
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
                metaChip("\(L10n.text("Size", language: language)): \(model.sizeClass)", systemImage: "externaldrive")
                metaChip("\(L10n.text("Ctx", language: language)): \(model.contextLength)", systemImage: "text.alignleft")
                Spacer(minLength: 8)
                statusBadge(validationName(model.validationState), systemImage: validationIcon(model.validationState))
            }

            if let message = model.lastErrorMessage, !message.isEmpty {
                Text(message)
                    .font(.caption)
                    .foregroundStyle(.red)
                    .lineLimit(2)
            }

            HStack(spacing: 8) {
                Spacer()
                if !isDefault {
                    Button {
                        appState.setDefaultModel(id: model.id)
                    } label: {
                        Label(L10n.text("Use as Default", language: language), systemImage: "checkmark.circle")
                    }
                    .buttonStyle(.borderless)
                }

                Button(role: .destructive) {
                    appState.removeModel(id: model.id)
                } label: {
                    Image(systemName: "trash")
                }
                .buttonStyle(.borderless)
                .help(L10n.text("Remove", language: language))
            }
        }
        .padding(13)
        .background(Color(NSColor.controlBackgroundColor).opacity(0.8))
        .overlay(RoundedRectangle(cornerRadius: 8).stroke(Color.secondary.opacity(0.14)))
        .clipShape(RoundedRectangle(cornerRadius: 8))
    }

    private func settingIcon(_ systemImage: String) -> some View {
        Image(systemName: systemImage)
            .font(.system(size: 13, weight: .semibold))
            .foregroundStyle(.secondary)
            .frame(width: 20)
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
}
