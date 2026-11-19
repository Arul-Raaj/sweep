import SwiftUI

/// Settings (⌘,). Just the weekly clean, which only ever touches Recommended items.
struct SettingsView: View {
    @Bindable var model: Model

    var body: some View {
        Form {
            Section {
                Toggle("Clean Recommended items every Monday",
                       isOn: Binding(get: { model.weekly }, set: { model.setWeekly($0) }))
            } footer: {
                Text("Runs at 11:00, or when your Mac next wakes. Rebuildable and Review items always wait for you.")
                    .foregroundStyle(.secondary)
            }
        }
        .formStyle(.grouped)
        .frame(width: 440)
        .onAppear { model.refreshWeekly() }
    }
}
