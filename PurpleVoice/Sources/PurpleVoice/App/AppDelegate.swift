import AppKit

final class AppDelegate: NSObject, NSApplicationDelegate {

    static let windowResetVersion = 1

    func applicationWillFinishLaunching(_ notification: Notification) {
        // CLI dispatch: if invoked with `clean` / `help` / `version`,
        // run the CLI flow and exit BEFORE SwiftUI brings up a window.
        // Hooked here (not at `static main`) because SwiftUI's
        // `WindowGroup` macro requires `@main` to stay on the App
        // struct itself — intercepting earlier broke the window
        // registration and the app launched with zero windows.
        let args = Array(CommandLine.arguments.dropFirst())
        if let first = args.first, Self.isCLICommand(first) {
            // Run the CLI on a background task and spin the main run
            // loop while it works — do NOT block the main thread on a
            // semaphore. `ClipProcessor` hops to `@MainActor` (e.g. to
            // stamp the clip's duration), and those hops are serviced by
            // the main run loop / `DispatchQueue.main`; a blocked main
            // thread deadlocks the `clean` pipeline. When the CLI
            // finishes it stops the run loop and we exit.
            Task.detached {
                await CLI.run(args: args)
                CFRunLoopStop(CFRunLoopGetMain())
            }
            CFRunLoopRun()
            exit(0)
        }
        WindowStateGuard.applyOnLaunch(
            appName: "PurpleVoice",
            resetVersion: Self.windowResetVersion
        )
    }

    func applicationDidFinishLaunching(_ notification: Notification) {
        // Belt-and-braces window activation. On multi-monitor setups,
        // SwiftUI's `WindowGroup` cascade can land the first window
        // on an inactive screen, with the parent app not yet
        // activated — leaving the user staring at the Dock icon
        // wondering where the window is. Forcing activation here
        // brings the window to whatever screen the user is on.
        NSApp.setActivationPolicy(.regular)
        NSApp.activate(ignoringOtherApps: true)
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        true
    }

    /// Documented CLI subcommands and standard help/version flags.
    /// Anything else (including Launch Services' `-NSDocumentRevisions…`
    /// flags passed when opening a file via Finder) falls through to
    /// the GUI.
    static func isCLICommand(_ arg: String) -> Bool {
        ["clean", "presets", "help", "version",
         "-h", "--help", "-v", "--version"].contains(arg)
    }
}
