import SwiftUI
import SweepCore

extension Rule.Level {
    var symbol: String {
        switch self {
        case .recommended: "checkmark.shield.fill"
        case .rebuildable: "arrow.clockwise"
        case .review: "eye.fill"
        }
    }

    var tint: Color {
        switch self {
        case .recommended: .green
        case .rebuildable: .blue
        case .review: .orange
        }
    }
}

/// The level's symbol in a soft tinted circle.
struct LevelIcon: View {
    let level: Rule.Level

    var body: some View {
        Image(systemName: level.symbol)
            .font(.title3)
            .foregroundStyle(level.tint)
            .frame(width: 34, height: 34)
            .background(level.tint.opacity(0.12), in: Circle())
            .accessibilityHidden(true)
    }
}

/// "Recommended" etc. as a small capsule label.
struct LevelPill: View {
    let level: Rule.Level

    var body: some View {
        Label(level.title, systemImage: level.symbol)
            .font(.caption.weight(.semibold))
            .foregroundStyle(level.tint)
            .padding(.horizontal, 8)
            .padding(.vertical, 3)
            .background(level.tint.opacity(0.12), in: Capsule())
    }
}

/// The one primary action. Large on the overview, regular in the toolbar.
struct CleanButton: View {
    @Bindable var model: Model
    var large = false

    var body: some View {
        Button {
            model.confirming = true
        } label: {
            Text(title)
                .contentTransition(.numericText())
                .frame(minWidth: large ? 200 : nil)
        }
        .buttonStyle(.borderedProminent)
        .controlSize(large ? .extraLarge : .regular)
        .keyboardShortcut(.delete, modifiers: .command)
        .disabled(model.phase != .ready || model.selectedItems.isEmpty)
    }

    private var title: String {
        switch model.phase {
        case .cleaning: "Cleaning…"
        case .scanning: "Clean"
        case .ready: model.selectedItems.isEmpty ? "Clean" : "Clean \(formatBytes(model.selectedBytes))"
        }
    }
}

/// A short-lived confirmation that slides up from the bottom.
struct Banner: View {
    let text: String?

    var body: some View {
        if let text {
            Label(text, systemImage: "checkmark.circle.fill")
                .font(.callout.weight(.medium))
                .padding(.horizontal, 14)
                .padding(.vertical, 8)
                .background(.regularMaterial, in: Capsule())
                .shadow(color: .black.opacity(0.12), radius: 8, y: 2)
                .padding(.bottom, 16)
                .transition(.move(edge: .bottom).combined(with: .opacity))
        }
    }
}
