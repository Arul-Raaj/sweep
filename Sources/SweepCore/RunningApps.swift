import AppKit

/// Matches an app-data folder name ("Claude", "com.microsoft.teams2") to a running app.
enum RunningApps {
    /// The running app's name if one owns `folder`, else nil.
    static func matching(folder: String) -> String? {
        let key = folder.lowercased()
        for app in NSWorkspace.shared.runningApplications {
            let id = app.bundleIdentifier?.lowercased() ?? ""
            let names = [
                app.localizedName,
                app.bundleURL?.deletingPathExtension().lastPathComponent,
                app.executableURL?.lastPathComponent,
            ].compactMap { $0?.lowercased() }

            let sameName = names.contains(key)
            // Folder named after the bundle id, or a helper of it ("com.polar.browser.host").
            let sameID = !id.isEmpty && (key == id || key.hasPrefix(id + "."))
            if sameName || sameID {
                return app.localizedName ?? folder
            }
        }
        return nil
    }
}
