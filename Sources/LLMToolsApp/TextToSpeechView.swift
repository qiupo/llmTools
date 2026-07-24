import AppKit
import SwiftUI
import LLMToolsCore

struct TTSVoicePickerOptions: View {
    let sections: [TTSVoiceSection]

    @ViewBuilder
    var body: some View {
        if sections.count == 1, sections[0].groupName == nil {
            voiceRows(sections[0].voices)
        } else {
            ForEach(sections) { section in
                Section(section.groupName ?? "未分组") {
                    voiceRows(section.voices)
                }
            }
        }
    }

    private func voiceRows(_ voices: [TTSVoiceProfile]) -> some View {
        ForEach(voices) { voice in
            Text(voice.name.isEmpty ? "未命名音色" : voice.name)
                .tag(Optional(voice.id))
        }
    }
}

private struct TTSVoiceChoice: Identifiable, Equatable {
    let id: UUID
    let name: String
}

private struct TTSVoiceChoiceSection: Identifiable, Equatable {
    let id: String
    let groupName: String?
    let voices: [TTSVoiceChoice]

    init(_ section: TTSVoiceSection) {
        id = section.id
        groupName = section.groupName
        voices = section.voices.map {
            TTSVoiceChoice(id: $0.id, name: $0.name.isEmpty ? "未命名音色" : $0.name)
        }
    }
}

private struct TTSSegmentRow: View, Equatable {
    let segment: TTSSegment
    let mode: TTSProjectMode
    let voiceSections: [TTSVoiceChoiceSection]
    let isGenerating: Bool
    let isAnalyzing: Bool
    let isPlaying: Bool
    let onRoleChange: (UUID) -> Void
    let onDeliveryStyleChange: (String) -> Void
    let onPauseChange: (Int) -> Void
    let onTextChange: (String) -> Void
    let onPlay: () -> Void
    let onRegenerate: () -> Void

    nonisolated static func == (lhs: Self, rhs: Self) -> Bool {
        lhs.segment == rhs.segment
            && lhs.mode == rhs.mode
            && lhs.voiceSections == rhs.voiceSections
            && lhs.isGenerating == rhs.isGenerating
            && lhs.isAnalyzing == rhs.isAnalyzing
            && lhs.isPlaying == rhs.isPlaying
    }

    var body: some View {
        HStack(alignment: .top, spacing: 8) {
            Text("\(segment.index + 1)")
                .font(.caption.monospacedDigit())
                .foregroundStyle(.secondary)
                .frame(width: 24, alignment: .trailing)
                .padding(.top, 6)

            VStack(alignment: .leading, spacing: 6) {
                HStack(spacing: 8) {
                    if mode == .multiRole,
                       let speakerName = segment.speakerName,
                       !speakerName.isEmpty {
                        Text(speakerName)
                            .font(.caption)
                            .lineLimit(1)
                            .truncationMode(.tail)
                            .frame(maxWidth: 90, alignment: .leading)
                            .help(speakerName)
                        Image(systemName: "arrow.right")
                            .font(.caption2)
                            .foregroundStyle(.tertiary)
                    }

                    voiceMenu

                    Label(segmentStateTitle, systemImage: segmentStateIcon)
                        .font(.caption2)
                        .foregroundStyle(segmentStateColor)
                    Spacer()
                    if segment.generationState == .completed {
                        iconButton(isPlaying ? "暂停片段" : "播放片段", systemImage: isPlaying ? "pause.fill" : "play.fill") {
                            onPlay()
                        }
                    }
                    iconButton("重新生成", systemImage: "arrow.clockwise") {
                        onRegenerate()
                    }
                    .disabled(isGenerating || isAnalyzing)
                }

                HStack(spacing: 8) {
                    Label("语气", systemImage: "theatermasks")
                        .foregroundStyle(.secondary)
                    TextField(
                        "自然表达",
                        text: Binding(
                            get: { segment.deliveryStyle ?? "" },
                            set: { onDeliveryStyleChange($0) }
                        )
                    )
                    .textFieldStyle(.roundedBorder)
                    .controlSize(.small)

                    Label("间隔", systemImage: "timer")
                        .foregroundStyle(.secondary)
                    Stepper(
                        value: Binding(
                            get: { segment.pauseAfterMilliseconds },
                            set: { onPauseChange($0) }
                        ),
                        in: 150...2_000,
                        step: 50
                    ) {
                        Text("\(segment.pauseAfterMilliseconds) ms")
                            .monospacedDigit()
                            .frame(width: 58, alignment: .trailing)
                    }
                    .controlSize(.small)
                    .fixedSize()
                }
                .font(.caption)

                TextField(
                    "朗读文本",
                    text: Binding(get: { segment.spokenText }, set: { onTextChange($0) }),
                    axis: .vertical
                )
                .textFieldStyle(.plain)
                .lineLimit(2...5)
                .padding(6)
                .background(Color(nsColor: .controlBackgroundColor))
                .clipShape(RoundedRectangle(cornerRadius: 5))

                if let error = segment.errorMessage, !error.isEmpty {
                    Text(error)
                        .font(.caption2)
                        .foregroundStyle(.red)
                        .lineLimit(2)
                }
            }
        }
    }

    private var voiceMenu: some View {
        Menu {
            if voiceSections.count == 1, voiceSections[0].groupName == nil {
                voiceButtons(voiceSections[0].voices)
            } else {
                ForEach(voiceSections) { section in
                    Section(section.groupName ?? "未分组") {
                        voiceButtons(section.voices)
                    }
                }
            }
        } label: {
            Text(selectedVoiceName)
                .lineLimit(1)
                .truncationMode(.tail)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.horizontal, 7)
                .frame(width: 100, height: 24)
                .background(Color(nsColor: .controlBackgroundColor))
                .clipShape(RoundedRectangle(cornerRadius: 5))
        }
        .menuStyle(.borderlessButton)
        .frame(width: 116)
        .accessibilityLabel("音色：\(selectedVoiceName)")
    }

    private func voiceButtons(_ voices: [TTSVoiceChoice]) -> some View {
        ForEach(voices) { voice in
            Button {
                onRoleChange(voice.id)
            } label: {
                if voice.id == segment.roleID {
                    Label(voice.name, systemImage: "checkmark")
                } else {
                    Text(voice.name)
                }
            }
        }
    }

    private var selectedVoiceName: String {
        for section in voiceSections {
            if let voice = section.voices.first(where: { $0.id == segment.roleID }) {
                return voice.name
            }
        }
        return "未选择音色"
    }

    private func iconButton(
        _ help: String,
        systemImage: String,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            Image(systemName: systemImage)
        }
        .buttonStyle(.borderless)
        .help(help)
    }

    private var segmentStateTitle: String {
        switch segment.generationState {
        case .pending: return "待生成"
        case .generating: return "生成中"
        case .completed: return "已完成"
        case .failed: return "失败"
        case .stale: return "需更新"
        }
    }

    private var segmentStateIcon: String {
        switch segment.generationState {
        case .pending: return "circle"
        case .generating: return "clock.fill"
        case .completed: return "checkmark.circle.fill"
        case .failed: return "exclamationmark.circle.fill"
        case .stale: return "arrow.triangle.2.circlepath"
        }
    }

    private var segmentStateColor: Color {
        switch segment.generationState {
        case .completed: return .green
        case .failed: return .red
        case .generating: return .accentColor
        case .stale: return .orange
        case .pending: return .secondary
        }
    }
}

struct TextToSpeechView: View {
    @ObservedObject var appState: AppState
    @ObservedObject var pinState: WindowPinState
    var onManageVoices: () -> Void

    var body: some View {
        VStack(spacing: 0) {
            toolbar
            Divider()
            runtimeBar
            Divider()
            HSplitView {
                sourcePanel
                    .frame(minWidth: 300, idealWidth: 400, maxHeight: .infinity)
                scriptPanel
                    .frame(minWidth: 440, idealWidth: 620, maxHeight: .infinity)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            Divider()
            actionBar
        }
        .frame(
            minWidth: 900,
            maxWidth: .infinity,
            minHeight: 600,
            maxHeight: .infinity,
            alignment: .top
        )
    }

    private var toolbar: some View {
        HStack(spacing: 12) {
            Image(systemName: "waveform.and.mic")
                .font(.title3)
                .foregroundStyle(Color.accentColor)
            TextField(
                "项目名称",
                text: Binding(
                    get: { appState.ttsProject.name },
                    set: { appState.updateTTSProjectName($0) }
                )
            )
            .textFieldStyle(.plain)
            .font(.headline)
            .frame(minWidth: 130, maxWidth: 220)
            .onSubmit { appState.saveTTSProject() }

            Picker(
                "模式",
                selection: Binding(
                    get: { appState.ttsProject.mode },
                    set: { appState.setTTSMode($0) }
                )
            ) {
                Text("单人朗读").tag(TTSProjectMode.singleNarrator)
                Text("多角色").tag(TTSProjectMode.multiRole)
            }
            .pickerStyle(.segmented)
            .frame(width: 210)

            Spacer(minLength: 8)

            if appState.ttsProject.mode == .singleNarrator {
                Picker(
                    "音色",
                    selection: Binding(
                        get: { appState.ttsSelectedVoiceID },
                        set: { value in
                            if let value { appState.selectTTSVoice(value) }
                        }
                    )
                ) {
                    TTSVoicePickerOptions(sections: appState.ttsVoiceSections)
                }
                .pickerStyle(.menu)
                .frame(width: 130)
            }

            Picker(
                "模型",
                selection: Binding(
                    get: { appState.ttsProject.modelVariant },
                    set: { appState.setTTSModelVariant($0) }
                )
            ) {
                Text("高质量 · bf16").tag(TTSModelVariant.voxCPM2BF16)
                Text("低内存 · 4bit").tag(TTSModelVariant.voxCPM2FourBit)
            }
            .pickerStyle(.menu)
            .frame(width: 150)
            .disabled(
                appState.ttsIsGenerating
                    || appState.quickTTSIsGenerating
                    || appState.quickTranslationSpeechGeneratingTarget != nil
                    || appState.ttsVoicePreviewInProgressID != nil
            )

            Button(action: onManageVoices) {
                Image(systemName: "person.wave.2")
            }
            .buttonStyle(.borderless)
            .help("音色管理")

            WindowPinButton(pinState: pinState, language: appState.preferences.appLanguage)
        }
        .padding(.horizontal, 14)
        .frame(height: 48)
        .background(Color(nsColor: .windowBackgroundColor))
    }

    private var runtimeBar: some View {
        HStack(spacing: 8) {
            Image(systemName: runtimeIcon)
                .foregroundStyle(runtimeColor)
            Text(appState.ttsHealth?.message ?? appState.ttsStatusMessage)
                .font(.caption)
                .foregroundStyle(.secondary)
                .lineLimit(1)
            Spacer()
            if appState.ttsHealth?.status == .runtimeMissing {
                Button {
                    appState.installTTSRuntime()
                } label: {
                    Label(
                        appState.ttsRuntimeInstallInProgress ? "安装中" : "安装 Runtime",
                        systemImage: appState.ttsRuntimeInstallInProgress ? "clock" : "wrench.and.screwdriver"
                    )
                }
                .controlSize(.small)
                .disabled(appState.ttsRuntimeInstallInProgress)
            } else if appState.ttsHealth?.status == .modelMissing {
                Button {
                    appState.installTTSRuntime(downloadModel: true)
                } label: {
                    Label(
                        appState.ttsRuntimeInstallInProgress ? "下载中" : "下载模型",
                        systemImage: appState.ttsRuntimeInstallInProgress ? "clock" : "arrow.down.circle"
                    )
                }
                .controlSize(.small)
                .disabled(appState.ttsRuntimeInstallInProgress)
            }
            Button {
                Task { await appState.refreshTTSHealth() }
            } label: {
                Image(systemName: "arrow.clockwise")
            }
            .buttonStyle(.borderless)
            .help("重新检查")
        }
        .padding(.horizontal, 14)
        .frame(height: 36)
        .background(Color(nsColor: .controlBackgroundColor).opacity(0.45))
    }

    private var sourcePanel: some View {
        VStack(spacing: 0) {
            panelHeader(
                title: "文案",
                detail: "\(appState.ttsProject.sourceText.count) 字"
            )
            Divider()
            TextEditor(text: Binding(
                get: { appState.ttsProject.sourceText },
                set: { appState.updateTTSSourceText($0) }
            ))
            .font(.body)
            .scrollContentBackground(.hidden)
            .padding(10)
            .background(Color(nsColor: .textBackgroundColor))

            Divider()
            VStack(alignment: .leading, spacing: 8) {
                if appState.ttsProject.mode == .multiRole {
                    Picker(
                        "角色分析模型",
                        selection: Binding(
                            get: { appState.ttsAnalysisModelID },
                            set: { appState.ttsAnalysisModelID = $0 }
                        )
                    ) {
                        Text("选择本地文本模型").tag(UUID?.none)
                        ForEach(appState.localTTSAnalysisModels) { model in
                            Text(model.name).tag(Optional(model.id))
                        }
                    }
                    .pickerStyle(.menu)
                    .frame(maxWidth: .infinity)
                }
                Button {
                    if appState.ttsIsAnalyzing {
                        appState.cancelTTSAnalysis()
                    } else {
                        appState.analyzeTTSProject()
                    }
                } label: {
                    Label(
                        analysisButtonTitle,
                        systemImage: appState.ttsIsAnalyzing ? "stop.fill" : "wand.and.stars"
                    )
                    .frame(maxWidth: .infinity)
                }
                .disabled(
                    appState.ttsIsGenerating
                        || appState.quickTTSIsGenerating
                        || appState.quickTranslationSpeechGeneratingTarget != nil
                        || appState.ttsVoicePreviewInProgressID != nil
                )
            }
            .padding(12)
            .background(Color(nsColor: .windowBackgroundColor))
        }
    }

    private var scriptPanel: some View {
        let voiceSections = appState.ttsVoiceSections.map(TTSVoiceChoiceSection.init)
        let mode = appState.ttsProject.mode
        let isGenerating = appState.ttsIsGenerating
        let isAnalyzing = appState.ttsIsAnalyzing

        return VStack(spacing: 0) {
            panelHeader(
                title: "脚本",
                detail: "\(appState.ttsProject.segments.count) 段"
            )
            Divider()
            if appState.ttsProject.segments.isEmpty {
                ContentUnavailableView(
                    "暂无脚本",
                    systemImage: "text.quote",
                    description: Text("输入文案后整理脚本")
                )
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                List {
                    ForEach(appState.ttsProject.segments) { segment in
                        TTSSegmentRow(
                            segment: segment,
                            mode: mode,
                            voiceSections: voiceSections,
                            isGenerating: isGenerating,
                            isAnalyzing: isAnalyzing,
                            isPlaying: appState.isTTSPlaying(.segment(segment.id)),
                            onRoleChange: { appState.setTTSSegmentRole(id: segment.id, roleID: $0) },
                            onDeliveryStyleChange: {
                                appState.updateTTSSegmentDeliveryStyle(id: segment.id, style: $0)
                            },
                            onPauseChange: {
                                appState.updateTTSSegmentPause(id: segment.id, milliseconds: $0)
                            },
                            onTextChange: { appState.updateTTSSegmentText(id: segment.id, text: $0) },
                            onPlay: { appState.playTTSSegment(segment.id) },
                            onRegenerate: { appState.regenerateTTSSegment(segment.id) }
                        )
                        .equatable()
                        .listRowInsets(EdgeInsets(top: 7, leading: 10, bottom: 7, trailing: 10))
                    }
                }
                .listStyle(.plain)
            }
        }
        .background(Color(nsColor: .textBackgroundColor).opacity(0.45))
    }

    private var actionBar: some View {
        HStack(spacing: 10) {
            if appState.ttsIsGenerating {
                ProgressView(value: appState.ttsGenerationProgress)
                    .frame(width: 120)
            }
            Text(appState.ttsStatusMessage)
                .font(.caption)
                .foregroundStyle(.secondary)
                .lineLimit(1)
            Spacer()
            Button {
                appState.playTTSProject()
            } label: {
                let target = TTSPlaybackTarget.project
                let isPlaying = appState.isTTSPlaying(target)
                Label(
                    isPlaying ? "暂停" : (appState.ttsPlaybackTarget == target ? "继续试听" : "试听成片"),
                    systemImage: isPlaying ? "pause.circle.fill" : "play.circle"
                )
            }
            .disabled(
                completedSegmentCount == 0
                    || appState.ttsIsGenerating
                    || appState.quickTranslationSpeechGeneratingTarget != nil
            )

            Menu {
                Button("WAV") { appState.exportTTSProject(format: .wav) }
                Button("M4A") { appState.exportTTSProject(format: .m4a) }
                Divider()
                Button("SRT 字幕") { appState.exportTTSSRT() }
            } label: {
                Label("导出", systemImage: "square.and.arrow.up")
            }
            .disabled(
                completedSegmentCount == 0
                    || appState.ttsIsGenerating
                    || appState.quickTranslationSpeechGeneratingTarget != nil
            )

            Button {
                if appState.ttsIsGenerating {
                    appState.cancelTTSGeneration()
                } else {
                    appState.generateTTSQueue()
                }
            } label: {
                Label(
                    appState.ttsIsGenerating ? "停止" : queueButtonTitle,
                    systemImage: appState.ttsIsGenerating ? "stop.fill" : "waveform.badge.plus"
                )
            }
            .keyboardShortcut(.return, modifiers: [.command])
            .disabled(
                appState.ttsIsAnalyzing
                    || appState.quickTTSIsGenerating
                    || appState.quickTranslationSpeechGeneratingTarget != nil
                    || appState.ttsVoicePreviewInProgressID != nil
            )
        }
        .padding(.horizontal, 14)
        .frame(height: 50)
        .background(Color(nsColor: .windowBackgroundColor))
    }

    private func panelHeader(title: String, detail: String) -> some View {
        HStack {
            Text(title).font(.headline)
            Spacer()
            Text(detail)
                .font(.caption.monospacedDigit())
                .foregroundStyle(.secondary)
        }
        .padding(.horizontal, 12)
        .frame(height: 42)
        .background(Color(nsColor: .windowBackgroundColor))
    }

    private var analysisButtonTitle: String {
        if appState.ttsIsAnalyzing { return "停止分析" }
        return appState.ttsProject.mode == .multiRole ? "识别角色并生成脚本" : "整理朗读脚本"
    }

    private var completedSegmentCount: Int {
        appState.ttsProject.segments.filter { $0.generationState == .completed }.count
    }

    private var queueButtonTitle: String {
        completedSegmentCount > 0 ? "继续生成" : "生成音频"
    }

    private var runtimeIcon: String {
        switch appState.ttsHealth?.status {
        case .ready: return "checkmark.circle.fill"
        case .runtimeMissing, .modelMissing: return "exclamationmark.triangle.fill"
        case .failed: return "xmark.octagon.fill"
        case nil: return "questionmark.circle"
        }
    }

    private var runtimeColor: Color {
        switch appState.ttsHealth?.status {
        case .ready: return .green
        case .runtimeMissing, .modelMissing: return .orange
        case .failed: return .red
        case nil: return .secondary
        }
    }

}

private enum TTSVoiceGroupEditor: Identifiable {
    case create(UUID)
    case rename(String)

    var id: String {
        switch self {
        case .create(let voiceID): return "create:\(voiceID.uuidString)"
        case .rename(let groupName): return "rename:\(groupName)"
        }
    }
}

struct TTSVoiceManagementView: View {
    @ObservedObject var appState: AppState
    @ObservedObject var pinState: WindowPinState
    @State private var groupEditor: TTSVoiceGroupEditor?
    @State private var groupDraft = ""

    var body: some View {
        VStack(spacing: 0) {
            header
            Divider()
            HSplitView {
                voiceList
                    .frame(minWidth: 210, idealWidth: 230, maxWidth: 280, maxHeight: .infinity)
                voiceDetail
                    .frame(minWidth: 450, maxWidth: .infinity, maxHeight: .infinity)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            Divider()
            footer
        }
        .frame(
            minWidth: 720,
            maxWidth: .infinity,
            minHeight: 520,
            maxHeight: .infinity,
            alignment: .top
        )
        .alert(groupEditorTitle, isPresented: groupEditorPresented) {
            TextField("分组名称", text: $groupDraft)
            Button("取消", role: .cancel) { groupEditor = nil }
            Button(groupEditorActionTitle) { commitGroupEditor() }
                .disabled(TTSVoiceCatalog.normalizedGroupName(groupDraft) == nil)
        } message: {
            Text(groupEditorMessage)
        }
    }

    private var header: some View {
        HStack(spacing: 12) {
            Image(systemName: "person.wave.2")
                .font(.title3)
                .foregroundStyle(Color.accentColor)
            Text("音色管理")
                .font(.headline)
            Spacer()
            Picker(
                "模型",
                selection: Binding(
                    get: { appState.ttsProject.modelVariant },
                    set: { appState.setTTSModelVariant($0) }
                )
            ) {
                Text("高质量 · bf16").tag(TTSModelVariant.voxCPM2BF16)
                Text("低内存 · 4bit").tag(TTSModelVariant.voxCPM2FourBit)
            }
            .pickerStyle(.menu)
            .frame(width: 150)
            .disabled(
                appState.ttsIsGenerating
                    || appState.quickTTSIsGenerating
                    || appState.quickTranslationSpeechGeneratingTarget != nil
                    || appState.ttsVoicePreviewInProgressID != nil
            )
            WindowPinButton(pinState: pinState, language: appState.preferences.appLanguage)
        }
        .padding(.horizontal, 14)
        .frame(height: 48)
        .background(Color(nsColor: .windowBackgroundColor))
    }

    private var voiceList: some View {
        VStack(spacing: 0) {
            HStack(spacing: 8) {
                Text("项目音色")
                    .font(.headline)
                Spacer()
                Button {
                    if let id = appState.ttsSelectedVoiceID { appState.moveTTSVoice(id, by: -1) }
                } label: {
                    Image(systemName: "arrow.up")
                }
                .buttonStyle(.borderless)
                .help("在当前分组中上移")
                .disabled(!canMoveSelectedVoice(by: -1))

                Button {
                    if let id = appState.ttsSelectedVoiceID { appState.moveTTSVoice(id, by: 1) }
                } label: {
                    Image(systemName: "arrow.down")
                }
                .buttonStyle(.borderless)
                .help("在当前分组中下移")
                .disabled(!canMoveSelectedVoice(by: 1))

                Menu {
                    Button {
                        appState.addTTSVoice()
                    } label: {
                        Label("添加音色", systemImage: "person.badge.plus")
                    }
                    if let id = appState.ttsSelectedVoiceID {
                        Button {
                            beginCreatingGroup(for: id)
                        } label: {
                            Label("新建分组并移入", systemImage: "folder.badge.plus")
                        }
                    }
                } label: {
                    Image(systemName: "plus")
                }
                .menuStyle(.borderlessButton)
                .help("添加音色或分组")
            }
            .padding(.horizontal, 12)
            .frame(height: 42)
            Divider()
            List(selection: voiceSelection) {
                ForEach(appState.ttsVoiceSections) { section in
                    Section {
                        ForEach(section.voices) { voice in
                            voiceRow(voice)
                                .tag(voice.id)
                        }
                    } header: {
                        voiceGroupHeader(section)
                    }
                }
            }
            .listStyle(.sidebar)
        }
        .background(Color(nsColor: .controlBackgroundColor).opacity(0.35))
    }

    @ViewBuilder
    private var voiceDetail: some View {
        if let voice = selectedVoice {
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    labeledControl("名称") {
                        TextField(
                            "音色名称",
                            text: Binding(
                                get: { voice.name },
                                set: { value in
                                    appState.updateTTSVoice(voice.id) { $0.name = value }
                                }
                            )
                        )
                    }

                    labeledControl("分组") {
                        HStack(spacing: 8) {
                            Picker(
                                "分组",
                                selection: Binding(
                                    get: { TTSVoiceCatalog.normalizedGroupName(voice.groupName) },
                                    set: { appState.setTTSVoiceGroup(voice.id, groupName: $0) }
                                )
                            ) {
                                Text("未分组").tag(String?.none)
                                ForEach(appState.ttsVoiceGroupNames, id: \.self) { groupName in
                                    Text(groupName).tag(Optional(groupName))
                                }
                            }
                            .labelsHidden()
                            .frame(width: 220)

                            Button {
                                beginCreatingGroup(for: voice.id)
                            } label: {
                                Image(systemName: "folder.badge.plus")
                            }
                            .buttonStyle(.borderless)
                            .help("新建分组并移入")
                        }
                    }

                    labeledControl("来源") {
                        Picker(
                            "来源",
                            selection: Binding(
                                get: { voice.origin },
                                set: { value in
                                    appState.updateTTSVoice(voice.id) { $0.origin = value }
                                }
                            )
                        ) {
                            Text("设计").tag(TTSVoiceOrigin.designed)
                            Text("克隆").tag(TTSVoiceOrigin.cloned)
                        }
                        .pickerStyle(.segmented)
                        .labelsHidden()
                        .frame(width: 220)
                    }

                    if voice.origin == .designed {
                        designedVoiceEditor(voice)
                    } else {
                        clonedVoiceEditor(voice)
                    }

                    labeledControl("试听文案") {
                        TextField(
                            "输入用于确认音色的短句",
                            text: Binding(
                                get: { appState.ttsVoicePreviewText },
                                set: { appState.updateTTSVoicePreviewText($0) }
                            ),
                            axis: .vertical
                        )
                        .lineLimit(2...4)
                    }

                    Divider()
                    Button(role: .destructive) {
                        appState.removeTTSVoice(voice.id)
                    } label: {
                        Label("删除音色", systemImage: "trash")
                    }
                    .disabled(
                        appState.ttsProject.voices.count <= 1
                            || appState.ttsVoicePreviewInProgressID != nil
                            || appState.ttsIsGenerating
                            || appState.quickTTSIsGenerating
                            || appState.quickTranslationSpeechGeneratingTarget != nil
                    )
                }
                .padding(18)
                .frame(maxWidth: .infinity, alignment: .leading)
            }
        } else {
            ContentUnavailableView("未选择音色", systemImage: "person.wave.2")
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
    }

    private func designedVoiceEditor(_ voice: TTSVoiceProfile) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            labeledControl("音色描述") {
                TextField(
                    "例如：沉稳、温暖、语速适中",
                    text: Binding(
                        get: { voice.instruction },
                        set: { value in
                            appState.updateTTSVoice(voice.id) { $0.instruction = value }
                        }
                    ),
                    axis: .vertical
                )
                .lineLimit(2...4)
            }
            voiceAnchorStatus(voice)
        }
    }

    private func clonedVoiceEditor(_ voice: TTSVoiceProfile) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            labeledControl("参考音频") {
                HStack(spacing: 8) {
                    Button {
                        appState.chooseTTSReferenceAudio(for: voice.id)
                    } label: {
                        Label(
                            voice.referenceAudioRelativePath == nil ? "选择音频" : "更换音频",
                            systemImage: "waveform.badge.plus"
                        )
                    }
                    if voice.referenceAudioRelativePath != nil {
                        Button {
                            appState.clearTTSReferenceAudio(for: voice.id)
                        } label: {
                            Image(systemName: "trash")
                        }
                        .buttonStyle(.borderless)
                        .help("移除参考音频")
                    }
                }
            }
            Toggle(
                "我确认拥有该声音的使用授权",
                isOn: Binding(
                    get: { voice.usageRightsConfirmed },
                    set: { value in
                        appState.updateTTSVoice(voice.id) { $0.usageRightsConfirmed = value }
                    }
                )
            )
            voiceAnchorStatus(voice)
        }
    }

    private func voiceAnchorStatus(_ voice: TTSVoiceProfile) -> some View {
        Label(
            voice.referenceAudioRelativePath == nil ? "待生成试听并固化" : "音色已固化",
            systemImage: voice.referenceAudioRelativePath == nil ? "circle.dashed" : "checkmark.seal.fill"
        )
        .font(.caption)
        .foregroundStyle(voice.referenceAudioRelativePath == nil ? Color.secondary : Color.green)
    }

    private var footer: some View {
        HStack(spacing: 10) {
            Text(appState.ttsStatusMessage)
                .font(.caption)
                .foregroundStyle(.secondary)
                .lineLimit(1)
            Spacer()
            if let voice = selectedVoice {
                if voice.previewAudioRelativePath != nil || voice.referenceAudioRelativePath != nil {
                    Button {
                        appState.playTTSVoicePreview(voice.id)
                    } label: {
                        let target = TTSPlaybackTarget.voice(voice.id)
                        let isPlaying = appState.isTTSPlaying(target)
                        Label(
                            isPlaying ? "暂停" : (appState.ttsPlaybackTarget == target ? "继续试听" : "播放试听"),
                            systemImage: isPlaying ? "pause.fill" : "play.fill"
                        )
                    }
                }
                Button {
                    if appState.ttsVoicePreviewInProgressID == voice.id {
                        appState.cancelTTSVoicePreview()
                    } else {
                        appState.generateTTSVoicePreview(voice.id)
                    }
                } label: {
                    let title: String = if voice.origin == .designed {
                        voice.referenceAudioRelativePath == nil ? "生成试听并固化" : "重新生成并固化"
                    } else {
                        voice.previewAudioRelativePath == nil ? "生成试听" : "重新生成试听"
                    }
                    Label(
                        appState.ttsVoicePreviewInProgressID == voice.id ? "停止" : title,
                        systemImage: appState.ttsVoicePreviewInProgressID == voice.id
                            ? "stop.fill"
                            : "waveform.badge.plus"
                    )
                }
                .disabled(
                    appState.ttsIsGenerating
                        || appState.ttsIsAnalyzing
                        || appState.quickTTSIsGenerating
                        || appState.quickTranslationSpeechGeneratingTarget != nil
                        || (appState.ttsVoicePreviewInProgressID != nil
                            && appState.ttsVoicePreviewInProgressID != voice.id)
                )
            }
        }
        .padding(.horizontal, 14)
        .frame(height: 50)
        .background(Color(nsColor: .windowBackgroundColor))
    }

    private var voiceSelection: Binding<UUID?> {
        Binding(
            get: { appState.ttsSelectedVoiceID },
            set: { value in
                if let value { appState.selectTTSVoice(value) }
            }
        )
    }

    private var selectedVoice: TTSVoiceProfile? {
        guard let id = appState.ttsSelectedVoiceID else { return appState.ttsProject.voices.first }
        return appState.ttsProject.voices.first { $0.id == id }
    }

    private func voiceRow(_ voice: TTSVoiceProfile) -> some View {
        HStack(spacing: 8) {
            Image(systemName: voice.origin == .designed ? "slider.horizontal.3" : "waveform")
                .foregroundStyle(.secondary)
                .frame(width: 16)
            VStack(alignment: .leading, spacing: 2) {
                Text(voice.name.isEmpty ? "未命名音色" : voice.name)
                    .lineLimit(1)
                    .help(voice.name)
                Text(voice.origin == .designed ? "设计" : "克隆")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }
            Spacer(minLength: 4)
            if voice.referenceAudioRelativePath != nil {
                Image(systemName: "checkmark.seal.fill")
                    .foregroundStyle(.green)
                    .help("已固化")
            }
        }
    }

    private func voiceGroupHeader(_ section: TTSVoiceSection) -> some View {
        HStack(spacing: 6) {
            Image(systemName: section.groupName == nil ? "tray" : "folder")
            Text(section.groupName ?? "未分组")
                .lineLimit(1)
            Text("\(section.voices.count)")
                .font(.caption2.monospacedDigit())
                .foregroundStyle(.secondary)
            Spacer()
            if let groupName = section.groupName {
                Menu {
                    Button {
                        beginRenamingGroup(groupName)
                    } label: {
                        Label("重命名分组", systemImage: "pencil")
                    }
                    Button(role: .destructive) {
                        appState.removeTTSVoiceGroup(groupName)
                    } label: {
                        Label("取消分组", systemImage: "folder.badge.minus")
                    }
                } label: {
                    Image(systemName: "ellipsis")
                }
                .menuStyle(.borderlessButton)
                .help("管理分组")
            }
        }
        .textCase(nil)
    }

    private func canMoveSelectedVoice(by offset: Int) -> Bool {
        guard let id = appState.ttsSelectedVoiceID else { return false }
        return TTSVoiceCatalog.movingVoice(id, by: offset, in: appState.ttsProject.voices) != nil
    }

    private func beginCreatingGroup(for voiceID: UUID) {
        groupDraft = ""
        groupEditor = .create(voiceID)
    }

    private func beginRenamingGroup(_ groupName: String) {
        groupDraft = groupName
        groupEditor = .rename(groupName)
    }

    private var groupEditorPresented: Binding<Bool> {
        Binding(
            get: { groupEditor != nil },
            set: { if !$0 { groupEditor = nil } }
        )
    }

    private var groupEditorTitle: String {
        switch groupEditor {
        case .rename: return "重命名分组"
        case .create, nil: return "新建分组"
        }
    }

    private var groupEditorActionTitle: String {
        switch groupEditor {
        case .rename: return "重命名"
        case .create, nil: return "创建"
        }
    }

    private var groupEditorMessage: String {
        switch groupEditor {
        case .rename: return "同名分组会自动合并，音色顺序保持不变。"
        case .create, nil: return "当前音色会移动到新分组。"
        }
    }

    private func commitGroupEditor() {
        guard let groupEditor,
              let groupName = TTSVoiceCatalog.normalizedGroupName(groupDraft) else { return }
        switch groupEditor {
        case .create(let voiceID):
            appState.setTTSVoiceGroup(voiceID, groupName: groupName)
        case .rename(let currentName):
            appState.renameTTSVoiceGroup(currentName, to: groupName)
        }
        self.groupEditor = nil
    }

    private func labeledControl<Content: View>(
        _ title: String,
        @ViewBuilder content: () -> Content
    ) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(title)
                .font(.caption)
                .foregroundStyle(.secondary)
            content()
        }
    }
}
