import SwiftUI
import SweepCore

/// One category: what it is, why it's safe, and every item with a checkbox.
struct CategoryView: View {
    @Bindable var model: Model
    let finding: Finding

    var body: some View {
        List {
            Section {
                Explainer(rule: finding.rule)
            }
            if let note = finding.note {
                Section {
                    Label(note, systemImage: "lock.fill").foregroundStyle(.secondary)
                }
            }
            if !finding.items.isEmpty {
                Section {
                    ForEach(finding.items) { item in
                        ItemRow(model: model, item: item, rule: finding.rule)
                    }
                } header: {
                    HStack {
                        Text(finding.items.count == 1 ? "1 item" : "\(finding.items.count) items")
                        Spacer()
                        if !finding.cleanable.isEmpty {
                            Button(model.isOn(finding) ? "Deselect All" : "Select All") {
                                model.set(finding, on: !model.isOn(finding))
                            }
                            .buttonStyle(.link)
                            .font(.caption)
                        }
                    }
                }
            }
        }
        .navigationTitle(finding.rule.name)
        .navigationSubtitle(finding.bytes > 0 ? formatBytes(finding.bytes) : "")
    }
}

private struct Explainer: View {
    let rule: Rule

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            LevelPill(level: rule.level)
            Text(rule.what)
                .fixedSize(horizontal: false, vertical: true)
            Fact(symbol: "checkmark.shield.fill", tint: .green,
                 title: rule.level == .review ? "Before you remove" : "Why it's safe", text: rule.whySafe)
            Fact(symbol: "arrow.uturn.backward.circle.fill", tint: .secondary,
                 title: "After cleaning", text: rule.after)
        }
        .padding(.vertical, 8)
    }
}

private struct Fact: View {
    let symbol: String
    let tint: Color
    let title: String
    let text: String

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 10) {
            Image(systemName: symbol).foregroundStyle(tint)
            VStack(alignment: .leading, spacing: 2) {
                Text(title).font(.subheadline.weight(.semibold))
                Text(text)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .accessibilityElement(children: .combine)
    }
}

private struct ItemRow: View {
    @Bindable var model: Model
    let item: Item
    let rule: Rule

    var body: some View {
        let label = ItemLabel.make(item, rule: rule)
        let selected = model.selected.contains(item.url)
        HStack(spacing: 10) {
            Toggle(label.title, isOn: Binding(get: { selected }, set: { _ in model.toggle(item) }))
                .toggleStyle(.checkbox)
                .labelsHidden()
                .disabled(item.blocked != nil)
            Image(nsImage: label.icon)
                .resizable()
                .frame(width: 24, height: 24)
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 2) {
                Text(label.title).lineLimit(1)
                Text(label.subtitle)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .truncationMode(.middle)
            }
            .help(item.targets.map { $0.path(percentEncoded: false) }.joined(separator: "\n"))
            Spacer(minLength: 12)
            VStack(alignment: .trailing, spacing: 2) {
                Text(formatBytes(item.bytes)).monospacedDigit()
                if let blocked = item.blocked {
                    Label(blocked, systemImage: "lock.fill")
                        .font(.caption)
                        .foregroundStyle(.orange)
                } else {
                    Text(label.age)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
            Button {
                model.reveal(item)
            } label: {
                Image(systemName: "magnifyingglass")
            }
            .buttonStyle(.borderless)
            .help("Show in Finder")
            .accessibilityLabel("Show \(label.title) in Finder")
        }
        .padding(.vertical, 3)
        .contentShape(Rectangle())
        .onTapGesture { model.toggle(item) }
        .opacity(selected || item.blocked != nil ? 1 : 0.6)
    }
}
