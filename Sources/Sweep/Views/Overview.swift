import SwiftUI
import SweepCore

/// The first screen: how much space is free, three levels to pick from, one button.
struct Overview: View {
    @Bindable var model: Model

    var body: some View {
        ScrollView {
            VStack(spacing: 28) {
                Hero(disk: model.disk, cleanable: model.cleanableBytes, scanning: model.phase == .scanning)

                VStack(spacing: 0) {
                    ForEach(Rule.Level.allCases, id: \.self) { level in
                        LevelRow(model: model, level: level)
                        if level != Rule.Level.allCases.last {
                            Divider().padding(.leading, 72)
                        }
                    }
                }
                .background(Color(nsColor: .controlBackgroundColor), in: .rect(cornerRadius: 12))
                .overlay(RoundedRectangle(cornerRadius: 12).strokeBorder(.separator))
                .redacted(reason: model.phase == .scanning && model.findings.isEmpty ? .placeholder : [])
            }
            .frame(maxWidth: 560)
            .padding(.horizontal, 32)
            .padding(.vertical, 40)
            .frame(maxWidth: .infinity)
        }
        .navigationTitle(Paths.isDemo ? "Sweep (demo)" : "Sweep")
    }
}

private struct Hero: View {
    let disk: DiskSpace?
    let cleanable: Int64
    let scanning: Bool

    var body: some View {
        VStack(spacing: 8) {
            Text(disk.map { formatBytes($0.free) } ?? "–")
                .font(.system(size: 48, weight: .semibold, design: .rounded))
                .monospacedDigit()
                .contentTransition(.numericText())
            if let disk {
                Text("free of \(formatBytes(disk.total))")
                    .foregroundStyle(.secondary)
                ProgressView(value: Double(disk.total - disk.free), total: Double(max(disk.total, 1)))
                    .tint(disk.free < 15_000_000_000 ? .orange : .accentColor)
                    .frame(width: 260)
                    .padding(.vertical, 4)
            }
            Text(status)
                .font(.callout)
                .foregroundStyle(.secondary)
                .contentTransition(.numericText())
        }
        .accessibilityElement(children: .combine)
    }

    private var status: String {
        if scanning { return "Looking for things to clean…" }
        return cleanable > 0 ? "\(formatBytes(cleanable)) can be cleaned" : "Nothing to clean right now"
    }
}

private struct LevelRow: View {
    @Bindable var model: Model
    let level: Rule.Level

    private var group: [Finding] { model.findings(in: level) }
    private var total: Int64 { model.bytes(in: level) }

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            Toggle(level.title, isOn: Binding(get: { model.isOn(level) }, set: { model.set(level, on: $0) }))
                .toggleStyle(.checkbox)
                .labelsHidden()
                .tint(level.tint)
                .disabled(total == 0)
                .padding(.top, 9)

            // The rest of the row is one button that opens the level's items.
            Button {
                if let first = group.first { model.route = .rule(first.id) }
            } label: {
                HStack(alignment: .top, spacing: 12) {
                    LevelIcon(level: level)
                    details
                    Image(systemName: "chevron.right")
                        .font(.footnote.weight(.semibold))
                        .foregroundStyle(.tertiary)
                        .padding(.top, 10)
                        .opacity(group.isEmpty ? 0 : 1)
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .disabled(group.isEmpty)
            .accessibilityLabel("\(level.title), \(sizeText)")
            .accessibilityHint("Shows the \(level.title) items")
        }
        .padding(14)
        .opacity(group.isEmpty && model.phase == .ready ? 0.5 : 1)
    }

    private var details: some View {
        VStack(alignment: .leading, spacing: 3) {
            HStack(alignment: .firstTextBaseline) {
                Text(level.title).font(.headline)
                Spacer()
                Text(sizeText)
                    .monospacedDigit()
                    .foregroundStyle(.secondary)
                    .contentTransition(.numericText())
            }
            Text(level.summary)
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
            if !group.isEmpty {
                Text(group.map(\.rule.name).joined(separator: " · "))
                    .font(.caption)
                    .foregroundStyle(.tertiary)
                    .lineLimit(1)
            }
        }
    }

    private var sizeText: String {
        guard total > 0 else { return group.isEmpty ? "Nothing found" : "In use" }
        let chosen = model.selectedBytes(in: level)
        return chosen == 0 || chosen == total ? formatBytes(total) : "\(formatBytes(chosen)) of \(formatBytes(total))"
    }
}
