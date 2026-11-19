import AppKit

/// Sound and haptics. Uses sounds that ship with macOS, so they add nothing to the app's size.
@MainActor
enum Feedback {
    private static let emptyTrash = NSSound(
        contentsOfFile: "/System/Library/Components/CoreAudio.component/Contents/SharedSupport/SystemSounds/finder/empty trash.aif",
        byReference: true) ?? NSSound(named: "Pop")

    /// The Finder "empty trash" sound plus a firm trackpad click.
    static func emptiedTrash() {
        if soundEffectsOn, let sound = emptyTrash {
            sound.stop()
            sound.play()
        }
        NSHapticFeedbackManager.defaultPerformer.perform(.levelChange, performanceTime: .now)
    }

    /// A light trackpad tick for checkboxes. No sound: it would get tiring.
    static func tick() {
        NSHapticFeedbackManager.defaultPerformer.perform(.alignment, performanceTime: .now)
    }

    /// Honours System Settings → Sound → "Play user interface sound effects".
    private static var soundEffectsOn: Bool {
        UserDefaults(suiteName: "com.apple.systemsound")?
            .object(forKey: "com.apple.sound.uiaudio.enabled") as? Bool ?? true
    }
}
