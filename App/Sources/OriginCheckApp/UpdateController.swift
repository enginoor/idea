import AppKit
import Sparkle

/// Owns the Sparkle auto-updater for OriginCheck.
///
/// Two deliberate design choices, inherited from the reference app:
///
/// 1. Implements `SPUStandardUserDriverDelegate` with
///    `supportsGentleScheduledUpdateReminders = true`. This is Sparkle's
///    documented requirement for background apps. Without it, Sparkle shows
///    a scary "Update Error!" modal whenever a background check fails (no
///    network, 404 on the feed). With it, background check errors are
///    silently ignored; only user-triggered checks ever show an error.
///
/// 2. `SUAutomaticallyUpdate` is `false` in Info.plist, so Sparkle never
///    installs an update without the user's explicit approval. The update
///    is downloaded and verified, then the user decides.
///
/// The updater reads `SUFeedURL` and `SUPublicEDKey` from the packaged
/// app's Info.plist. The feed is hosted in this repository (appcast.xml)
/// and every release artifact is signed with the Sparkle EdDSA key before
/// it is published.
@MainActor
final class UpdateController: NSObject {
    static let shared = UpdateController()

    /// Lazy so `self` is fully initialized before it is handed to Sparkle
    /// as the user-driver delegate. Accessing this property starts the
    /// updater (the first `start()` call triggers it).
    private lazy var controller: SPUStandardUpdaterController =
        SPUStandardUpdaterController(
            startingUpdater: true,
            updaterDelegate: nil,
            userDriverDelegate: self
        )

    var automaticallyChecksForUpdates: Bool {
        get { controller.updater.automaticallyChecksForUpdates }
        set { controller.updater.automaticallyChecksForUpdates = newValue }
    }

    /// Starts the updater. Called once at launch from the app scene so
    /// scheduled background checks run even if no window is ever opened.
    func start() {
        _ = controller
    }

    /// User-initiated check, from the menu and Settings. This is the one
    /// path that may show an error dialog, because the user asked.
    func checkForUpdates(_ sender: Any?) {
        controller.checkForUpdates(sender)
    }
}

// MARK: - SPUStandardUserDriverDelegate

// Sparkle 2.9's protocol is not yet annotated for Swift 6 isolation, so
// the conformance is @preconcurrency: isolation is checked at run time.
// Sparkle's standard user driver runs on the main thread, matching
// UpdateController's @MainActor isolation, so the calls are always legal.
extension UpdateController: @preconcurrency SPUStandardUserDriverDelegate {

    /// Opt into Sparkle's Gentle Reminders API. This single declaration is
    /// what stops the "Update Error!" modal from appearing on background or
    /// scheduled check failures. With it, background check errors are
    /// silently ignored; without it, they produce a scary modal dialog.
    var supportsGentleScheduledUpdateReminders: Bool { true }

    /// Called when a scheduled background check finds a real update.
    /// Returning `true` lets Sparkle show the "Update Available" alert at
    /// its own opportune moment instead of interrupting immediately.
    func standardUserDriverShouldHandleShowingScheduledUpdate(
        _ update: SUAppcastItem,
        andInImmediateFocus immediateFocus: Bool
    ) -> Bool {
        true
    }

    /// Suppress the "Version History" button in "You're up to date"
    /// alerts. The full changelog lives on GitHub, not in the app.
    func standardUserDriverShouldShowVersionHistory(
        for item: SUAppcastItem
    ) -> Bool {
        false
    }
}
