import SwiftUI
import SweepCore

/// Navigation only: the overview, then each level's categories. Empty categories are hidden.
struct Sidebar: View {
    @Bindable var model: Model

    var body: some View {
        List(selection: $model.route) {
            Label("Overview", systemImage: "internaldrive")
                .tag(Model.Route.overview)

            ForEach(Rule.Level.allCases, id: \.self) { level in
                let group = model.findings(in: level)
                if !group.isEmpty {
                    Section(level.title) {
                        ForEach(group) { finding in
                            CategoryRow(finding: finding)
                                .tag(Model.Route.rule(finding.id))
                        }
                    }
                }
            }
        }
    }
}

private struct CategoryRow: View {
    let finding: Finding

    var body: some View {
        Label {
            HStack {
                Text(finding.rule.name)
                Spacer()
                if finding.note != nil {
                    Image(systemName: "lock.fill")
                        .foregroundStyle(.tertiary)
                        .help("Needs Full Disk Access")
                } else {
                    Text(finding.cleanable.isEmpty ? "In use" : formatBytes(finding.bytes))
                        .monospacedDigit()
                        .foregroundStyle(.secondary)
                        .contentTransition(.numericText())
                }
            }
        } icon: {
            // Coloured by level: green safe, blue rebuildable, orange to review.
            Image(systemName: finding.rule.symbol)
                .foregroundStyle(finding.rule.level.tint)
        }
    }
}
