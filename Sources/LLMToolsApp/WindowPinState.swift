import AppKit
import SwiftUI
import LLMToolsCore

@MainActor
final class WindowPinState: ObservableObject {
    @Published private(set) var isPinned = false

    private weak var window: NSWindow?

    init(isPinned: Bool = false) {
        self.isPinned = isPinned
    }

    func attach(to window: NSWindow) {
        self.window = window
        applyWindowLevel()
    }

    func toggle() {
        isPinned.toggle()
        applyWindowLevel()
    }

    private func applyWindowLevel() {
        window?.level = isPinned ? .floating : .normal
    }
}

enum WindowPinButtonAppearance {
    case standard
    case selectionAction
    case subtitle
    case immersiveSubtitle
}

struct WindowPinButton: View {
    @ObservedObject var pinState: WindowPinState
    let language: AppLanguage
    var appearance: WindowPinButtonAppearance = .standard

    private var actionTitle: String {
        L10n.text(
            pinState.isPinned ? "Stop keeping window on top" : "Keep window on top",
            language: language
        )
    }

    var body: some View {
        Button {
            pinState.toggle()
        } label: {
            Image(systemName: pinState.isPinned ? "pin.fill" : "pin")
                .font(.system(size: iconSize, weight: .semibold))
                .symbolRenderingMode(.hierarchical)
                .frame(width: buttonSize.width, height: buttonSize.height)
                .background(backgroundColor, in: RoundedRectangle(cornerRadius: cornerRadius, style: .continuous))
                .overlay(
                    RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                        .strokeBorder(borderColor, lineWidth: 0.8)
                )
                .contentShape(RoundedRectangle(cornerRadius: cornerRadius, style: .continuous))
        }
        .buttonStyle(.plain)
        .foregroundStyle(foregroundColor)
        .help(actionTitle)
        .accessibilityLabel(actionTitle)
    }

    private var buttonSize: CGSize {
        switch appearance {
        case .standard:
            return CGSize(width: 26, height: 24)
        case .selectionAction:
            return CGSize(width: 26, height: 32)
        case .subtitle:
            return CGSize(width: 20, height: 22)
        case .immersiveSubtitle:
            return CGSize(width: 26, height: 26)
        }
    }

    private var iconSize: CGFloat {
        switch appearance {
        case .standard:
            return 12
        case .selectionAction:
            return 14
        case .subtitle, .immersiveSubtitle:
            return 11
        }
    }

    private var cornerRadius: CGFloat {
        switch appearance {
        case .standard, .subtitle:
            return 6
        case .selectionAction:
            return 9
        case .immersiveSubtitle:
            return 13
        }
    }

    private var foregroundColor: Color {
        switch appearance {
        case .standard:
            return pinState.isPinned ? .accentColor : .secondary
        case .selectionAction:
            return pinState.isPinned ? .accentColor : .primary.opacity(0.78)
        case .subtitle, .immersiveSubtitle:
            return .white.opacity(pinState.isPinned ? 0.98 : 0.76)
        }
    }

    private var backgroundColor: Color {
        switch appearance {
        case .standard, .selectionAction:
            return pinState.isPinned ? Color.accentColor.opacity(0.14) : .clear
        case .subtitle:
            return pinState.isPinned ? Color.white.opacity(0.18) : .clear
        case .immersiveSubtitle:
            return Color.black.opacity(pinState.isPinned ? 0.58 : 0.38)
        }
    }

    private var borderColor: Color {
        switch appearance {
        case .immersiveSubtitle:
            return Color.white.opacity(0.16)
        case .standard, .selectionAction, .subtitle:
            return .clear
        }
    }
}
