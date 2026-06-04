import AppKit
import ObjectiveC.runtime

/// Captures the *reason* string of any Objective-C exception AppKit reports
/// from its event / display cycle.
///
/// Why this exists: the SwiftUI "state mutation during layout" crash
/// (`-[NSWindow _postWindowNeedsUpdateConstraints]` throwing during a
/// CoreAnimation transaction commit) lands in the crash report with **no
/// PurpleIRC frames on the stack** — only SwiftUI / AppKit internals — and
/// the `.ips` carries no `exceptionReason`. So the crash report tells us the
/// *class* of fault but not the trigger. AppKit, however, funnels every
/// exception it catches through `-[NSApplication reportException:]` *with the
/// reason attached*, before deciding whether to terminate. We hook that (and
/// the uncaught-exception handler as a backstop) and write
/// name + reason + callstack to a plaintext breadcrumb so the next occurrence
/// is self-diagnosing.
///
/// This is diagnostics only: we log, then defer to AppKit's original
/// behaviour (which may still terminate). No control flow is changed.
enum ExceptionLogger {

    /// Plaintext, *unencrypted* breadcrumb. The reason string for a layout
    /// exception is AppKit constraint text — no user secrets — and writing
    /// it must not depend on the keystore/DEK being unlocked at crash time.
    static var breadcrumbURL: URL? {
        FileManager.default
            .urls(for: .applicationSupportDirectory, in: .userDomainMask).first?
            .appendingPathComponent("PurpleIRC", isDirectory: true)
            .appendingPathComponent("last-exception.log")
    }

    static func install() {
        swizzleReportException()
        NSSetUncaughtExceptionHandler { exc in
            ExceptionLogger.record(exc, source: "uncaught")
        }
    }

    static func record(_ exc: NSException, source: String) {
        let stack = exc.callStackSymbols.joined(separator: "\n")
        let userInfo = exc.userInfo.map { String(describing: $0) } ?? "<nil>"
        let msg = """
        ==== PurpleIRC exception (\(source)) @ \(Date()) ====
        name:   \(exc.name.rawValue)
        reason: \(exc.reason ?? "<nil>")
        userInfo: \(userInfo)
        callstack:
        \(stack)
        ======================================================

        """
        NSLog("PurpleIRC uncaught exception (%@): %@ — %@", source,
              exc.name.rawValue, exc.reason ?? "<nil>")

        guard let url = breadcrumbURL,
              let data = msg.data(using: .utf8) else { return }
        let fm = FileManager.default
        try? fm.createDirectory(at: url.deletingLastPathComponent(),
                                withIntermediateDirectories: true)
        if let fh = try? FileHandle(forWritingTo: url) {
            defer { try? fh.close() }
            try? fh.seekToEnd()
            try? fh.write(contentsOf: data)
        } else {
            try? data.write(to: url, options: .atomic)
        }
    }

    /// Wrap `-[NSApplication reportException:]` so every exception AppKit
    /// catches in its run loop (the display-cycle ones included) is recorded
    /// before the original handler runs.
    private static func swizzleReportException() {
        let cls: AnyClass = NSApplication.self
        let sel = #selector(NSApplication.reportException(_:))
        guard let method = class_getInstanceMethod(cls, sel) else { return }
        typealias Fn = @convention(c) (AnyObject, Selector, NSException) -> Void
        let originalFn = unsafeBitCast(method_getImplementation(method), to: Fn.self)
        let block: @convention(block) (AnyObject, NSException) -> Void = { obj, exc in
            ExceptionLogger.record(exc, source: "reportException")
            originalFn(obj, sel, exc)
        }
        method_setImplementation(method, imp_implementationWithBlock(block))
    }
}
