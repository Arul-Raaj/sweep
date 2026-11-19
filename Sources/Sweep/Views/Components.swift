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

    /// Green means safe, orange means look first; blue sits in between.
    var tint: Color {
        switch self {
        case .recommended: .green
        case .rebuildable: .blue
        case .review: .orange
        }
    }

    /// How a selection at this level is summed up next to the Clean up button.
    var selectionWord: String {
        switch self {
        case .recommended: "safe"
        case .rebuildable: "rebuildable"
        case .review: "to review"
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

/// The one primary action, pinned to the bottom of the window whenever something is
/// selected: what the selection is made of on the left, a green Clean up button on the right.
/// After a clean it shows the result in the same place.
struct CleanBar: View {
    @Bindable var model: Model

    var body: some View {
        HStack(spacing: 16) {
            if let banner = model.banner {
                Label(banner.text, systemImage: banner.success ? "checkmark.circle.fill" : "exclamationmark.circle.fill")
                    .font(.callout.weight(.medium))
                    .foregroundStyle(banner.success ? Color.green : Color.orange)
                    .transition(.opacity)
            } else {
                SelectionSummary(model: model)
                    .transition(.opacity)
            }
            Spacer(minLength: 12)
            Button {
                model.confirming = true
            } label: {
                Label(title, systemImage: "sparkles")
                    .contentTransition(.numericText())
            }
            .buttonStyle(CleanButtonStyle())
            .keyboardShortcut(.delete, modifiers: .command)
            .disabled(model.phase != .ready || model.selectedItems.isEmpty)
            .help("Clean up the selected items (⌘⌫)")
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
        .frame(maxWidth: .infinity)
        .background(.bar)
        .overlay(alignment: .top) { Divider() }
    }

    private var title: String {
        switch model.phase {
        case .cleaning: "Cleaning…"
        case .scanning, .ready:
            model.selectedItems.isEmpty ? "Clean up" : "Clean up \(formatBytes(model.selectedBytes))"
        }
    }
}

/// "● 1.69 GB safe  ● 268 MB to review": what's selected, by level colour.
private struct SelectionSummary: View {
    @Bindable var model: Model

    var body: some View {
        HStack(spacing: 14) {
            ForEach(Rule.Level.allCases, id: \.self) { level in
                let bytes = model.selectedBytes(in: level)
                if bytes > 0 {
                    HStack(spacing: 6) {
                        Circle().fill(level.tint).frame(width: 8, height: 8)
                        Text(formatBytes(bytes)).monospacedDigit().contentTransition(.numericText())
                        Text(level.selectionWord).foregroundStyle(.secondary)
                    }
                    .accessibilityElement(children: .combine)
                }
            }
        }
        .font(.callout)
        .lineLimit(1)
    }
}

/// A solid green button, 36 points tall. The green is darkened enough for white text
/// to stay readable (about 4.5:1), and dims when it can't be used.
struct CleanButtonStyle: ButtonStyle {
    @Environment(\.isEnabled) private var isEnabled

    private static let green = Color(red: 0.12, green: 0.56, blue: 0.27)
    private static let pressed = Color(red: 0.09, green: 0.46, blue: 0.22)

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.system(size: 14, weight: .semibold))
            .foregroundStyle(.white)
            .padding(.horizontal, 18)
            .frame(height: 36)
            .background(configuration.isPressed ? Self.pressed : Self.green,
                        in: RoundedRectangle(cornerRadius: 10, style: .continuous))
            .opacity(isEnabled ? 1 : 0.4)
            .contentShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
            .animation(.easeOut(duration: 0.12), value: configuration.isPressed)
    }
}
