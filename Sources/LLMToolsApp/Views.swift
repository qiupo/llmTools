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
    }

    private var controlsBar: some View {
        HStack(spacing: 10) {
            Picker("", selection: $appState.selectedTask) {
                ForEach(TaskKind.interactiveCases) { task in
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
        case .webPageTranslate:
            EmptyView()
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
                if appState.isRunning {
                    appState.cancelCurrentTask(unloadModel: true)
                } else {
                    appState.runCurrentTask()
                }
            } label: {
                if appState.isRunning {
                    Label(L10n.text("Cancel", language: language), systemImage: "stop.fill")
                } else {
                    Label(appState.outputText.isEmpty ? L10n.text("Run", language: language) : L10n.text("Regenerate", language: language), systemImage: appState.outputText.isEmpty ? "play.fill" : "arrow.clockwise")
                }
            }

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
        }
    }

    private var resultPlaceholder: String {
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
    var onSubmit: (() -> Void)?

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
        case .webPageTranslate:
            EmptyView()
        default:
            EmptyView()
        }
    }
}

private enum SettingsTab: CaseIterable, Identifiable {
    case general
    case shortcuts
    case models
    case webPage
    case defaults
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
        case .webPage:
            return "safari"
        case .defaults:
            return "dial.low"
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
        case .webPage:
            return L10n.text("Web Page Translation", language: language)
        case .defaults:
            return L10n.text("Defaults", language: language)
        case .about:
            return L10n.text("About", language: language)
        }
    }

    func tabTitle(language: AppLanguage) -> String {
        switch self {
        case .webPage:
            return L10n.text("Webpage", language: language)
        default:
            return title(language: language)
        }
    }
}

private enum ShortcutCaptureTarget: Identifiable {
    case quickAction
    case quickActionWithoutSelection

    var id: Self { self }
}

struct SettingsView: View {
    @ObservedObject var appState: AppState
    @State private var selectedTab: SettingsTab = .general
    @State private var showImporter = false
    @State private var providerDraftID: ModelProviderID = .siliconFlow
    @State private var providerDraftName = ""
    @State private var providerDraftModelID = ""
    @State private var providerDraftAPIKey = ""
    @State private var providerDraftBaseURL = ModelProviderCatalog.preset(for: .siliconFlow)?.defaultBaseURL ?? ""
    @State private var providerDraftContextLength = ModelProviderCatalog.preset(for: .siliconFlow)?.defaultContextLength ?? 32768
    @State private var editingProviderModelID: UUID?
    @State private var chromeIntegrationState = BrowserIntegrationService.shared.chromeState()
    @State private var shortcutCaptureTarget: ShortcutCaptureTarget?
    @State private var shortcutRecorderMessage: String?
    @State private var showSelectionLimitAppImporter = false
    @State private var selectionLimitDraftLineCount = 2

    private var language: AppLanguage {
        appState.preferences.appLanguage
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
        .fileImporter(isPresented: $showImporter, allowedContentTypes: [.folder, .item], allowsMultipleSelection: false) { result in
            if case let .success(urls) = result, let url = urls.first {
                appState.addModel(from: url)
            }
        }
        .fileImporter(isPresented: $showSelectionLimitAppImporter, allowedContentTypes: [.applicationBundle, .application, .item], allowsMultipleSelection: false) { result in
            if case let .success(urls) = result, let url = urls.first {
                addSelectionLineLimitRule(from: url)
            }
        }
        .onAppear {
            chromeIntegrationState = BrowserIntegrationService.shared.chromeState()
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
        case .webPage:
            webPageTranslationPage
        case .defaults:
            defaultsSettingsPage
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
                    if let shortcutRecorderMessage {
                        Text(shortcutRecorderMessage)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
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
                showImporter = true
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

            settingRow(title: L10n.text("Pending translation style", language: language)) {
                pendingIndicatorStylePicker
            }

            settingRow(title: L10n.text("Translation model", language: language)) {
                webPageTranslationModelPicker
            }

            settingRow(title: L10n.text("Browser", language: language)) {
                VStack(alignment: .leading, spacing: 8) {
                    HStack(spacing: 8) {
                        Text(chromeIntegrationState.name)
                            .font(.subheadline.weight(.medium))
                        statusBadge(browserStatusName(chromeIntegrationState.status), systemImage: browserStatusIcon(chromeIntegrationState.status))
                    }
                    if let message = chromeIntegrationState.lastErrorMessage {
                        Text(message)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    Text(chromeExtensionManualInstallText)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                    HStack(spacing: 8) {
                        Button {
                            do {
                                chromeIntegrationState = try BrowserIntegrationService.shared.installOrRepairChromeDevelopmentHost()
                                BrowserIntegrationService.shared.openChromeExtensionsPage()
                                appState.statusMessage = L10n.text("Chrome bridge repaired", language: language)
                            } catch {
                                appState.validationError = error.localizedDescription
                                chromeIntegrationState = BrowserIntegrationService.shared.chromeState()
                            }
                        } label: {
                            Label(L10n.text("Repair Chrome Bridge", language: language), systemImage: "wrench.and.screwdriver")
                        }
                        .controlSize(.small)

                        Button {
                            BrowserIntegrationService.shared.openChromeExtensionsPage()
                        } label: {
                            Label(L10n.text("Open Chrome Extensions", language: language), systemImage: "arrow.up.forward.app")
                        }
                        .controlSize(.small)
                    }
                }
            }

            settingRow(title: L10n.text("Extension folder", language: language)) {
                pathText(BrowserIntegrationService.shared.extensionFolderPath())
            }
        }
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

            settingRow(title: L10n.text("History", language: language)) {
                historyLimitControl
            }
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
            ForEach(appState.models) { model in
                Text(defaultModelPickerTitle(model)).tag(Optional(model.id))
            }
        }
        .labelsHidden()
        .pickerStyle(.menu)
        .frame(width: 230, alignment: .leading)
        .disabled(appState.models.isEmpty)
    }

    private var webPageTranslationModelPicker: some View {
        Picker("", selection: Binding<UUID?>(
            get: { appState.preferences.webPageTranslation.modelID },
            set: { newValue in
                appState.updatePreferences { $0.webPageTranslation.modelID = newValue }
            }
        )) {
            Text(L10n.text("Use default model", language: language)).tag(UUID?.none)
            ForEach(appState.models.filter { $0.enabled }) { model in
                Text(defaultModelPickerTitle(model)).tag(Optional(model.id))
            }
        }
        .labelsHidden()
        .pickerStyle(.menu)
        .frame(width: 230, alignment: .leading)
        .disabled(appState.models.isEmpty)
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

    private var pendingIndicatorStylePicker: some View {
        Picker("", selection: Binding(
            get: { appState.preferences.webPageTranslation.pendingIndicatorStyle },
            set: { newValue in
                appState.updatePreferences { $0.webPageTranslation.pendingIndicatorStyle = newValue }
            }
        )) {
            ForEach(WebPagePendingIndicatorStyle.allCases) { style in
                Text(L10n.pendingIndicatorStyleName(style, language: language)).tag(style)
            }
        }
        .labelsHidden()
        .pickerStyle(.segmented)
        .frame(width: 210, alignment: .leading)
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
        let version = info?["CFBundleShortVersionString"] as? String ?? "0.1.0"
        let build = info?["CFBundleVersion"] as? String ?? "dev"
        return "\(version) (\(build))"
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
            selectedTab = tab
            if tab == .webPage {
                chromeIntegrationState = BrowserIntegrationService.shared.chromeState()
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
            .frame(width: 82, height: 56)
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

    private func isShortcutAlreadyAssigned(_ shortcut: KeyboardShortcutPreference, target: ShortcutCaptureTarget) -> Bool {
        switch target {
        case .quickAction:
            return shortcut == appState.preferences.quickActionWithoutSelectionShortcut
        case .quickActionWithoutSelection:
            return shortcut == appState.preferences.quickActionShortcut
        }
    }

    private func defaultShortcut(for target: ShortcutCaptureTarget) -> KeyboardShortcutPreference {
        switch target {
        case .quickAction:
            return .optionSpace
        case .quickActionWithoutSelection:
            return .optionShiftSpace
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
                Spacer(minLength: 8)
                statusBadge(modelValidationBadgeText(model), systemImage: validationIcon(model.validationState))
            }

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

    private var chromeExtensionManualInstallText: String {
        switch language {
        case .chinese:
            return "如果 Chrome 扩展页里没有 llmTools：打开 Chrome 扩展，开启“开发者模式”，点击“加载已解压的扩展程序”，选择下方扩展文件夹。"
        case .english:
            return "If llmTools is not listed in Chrome Extensions: open Chrome Extensions, enable Developer mode, choose Load unpacked, then select the extension folder below."
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

private extension KeyboardShortcutPreference {
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
