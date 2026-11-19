import SwiftUI
import SweepCore

/// The window: levels and categories on the left, the overview or a category on the right.
struct ContentView: View {
    @Bindable var model: Model

    var body: some View {
        NavigationSplitView {
            Sidebar(model: model)
                .navigationSplitViewColumnWidth(min: 220, ideal: 240, max: 300)
        } detail: {
            detail
                .overlay(alignment: .bottom) { Banner(text: model.banner) }
        }
        .toolbar {
            ToolbarItem {
                Button {
                    Task { await model.scan() }
                } label: {
                    Label("Rescan", systemImage: "arrow.clockwise")
                }
                .help("Scan again")
                .keyboardShortcut("r")
                .disabled(model.phase != .ready)
            }
            // The overview has its own large Clean button; elsewhere it lives here.
            if model.focused != nil {
                ToolbarItem(placement: .primaryAction) {
                    CleanButton(model: model)
                }
            }
        }
        .confirmationDialog(
            "Clean \(formatBytes(model.selectedBytes))?",
            isPresented: $model.confirming
        ) {
            Button("Clean", role: .destructive) { Task { await model.clean() } }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text(model.selectionIncludesTrash
                 ? "Review items go to the Trash. Everything else is deleted. Each item is checked once more right before it's removed."
                 : "These are deleted, not moved to the Trash. Each item is checked once more right before it's removed.")
        }
        .task { await model.scan() }
    }

    @ViewBuilder private var detail: some View {
        if let finding = model.focused {
            CategoryView(model: model, finding: finding)
        } else {
            Overview(model: model)
        }
    }
}
