import AppKit
import Foundation

/// A self-report of the things that decide whether MechKeys can hear the
/// keyboard. Printed by `MechKeys --diagnose`.
///
/// Every value here is read from inside the running app, because that is the
/// only place the answers are true: TCC decides per process, by code
/// signature, and nothing outside the process can see what it was told.
///
/// With one large caveat, which this report has to say out loud. TCC answers
/// for the **responsible process**, not always the asking one, and a binary
/// exec'd from a shell is the terminal's responsibility rather than its own.
/// So `MechKeys --diagnose` typed into a terminal reports whether *the
/// terminal* has Accessibility — and cheerfully concludes "no access" about
/// an app that is working perfectly. See `launchedByLaunchd`.
public enum Diagnostics {

    /// Whether this process was started by the system rather than by a shell.
    ///
    /// A GUI launch is re-parented to launchd, so `getppid() == 1`. Anything
    /// else means something launched us and TCC is very likely answering
    /// about that something instead.
    static var launchedByLaunchd: Bool { getppid() == 1 }

    public static func report() -> String {
        let bundle = Bundle.main
        var lines: [String] = ["MechKeys diagnostics", String(repeating: "=", count: 20), ""]

        lines.append("bundle path:       \(bundle.bundlePath)")
        lines.append("bundle identifier: \(bundle.bundleIdentifier ?? "none")")
        lines.append(
            "version:           \(bundle.infoDictionary?["CFBundleShortVersionString"] as? String ?? "?")"
        )
        lines.append("process id:        \(ProcessInfo.processInfo.processIdentifier)")
        lines.append("")

        // The two answers that matter, and the whole point is that they can
        // disagree with each other.
        let trusted = PermissionManager.currentStatus()
        let canTap = KeyboardMonitor.canCreateTap()
        lines.append("AXIsProcessTrusted:   \(trusted)")
        lines.append("can create event tap: \(canTap)")
        lines.append("launched by launchd:  \(launchedByLaunchd)")
        lines.append("")

        // Said before the verdict, because it decides whether the verdict
        // means anything at all.
        if !launchedByLaunchd && !canTap {
            lines.append(
                """
                WARNING: this copy was started from a shell, not by macOS, so the two \
                answers above are probably not about MechKeys. Accessibility is granted \
                to the *responsible* process, and for a binary run from a terminal that \
                is the terminal. Expect "no access" here even when the app in your menu \
                bar is working.

                To diagnose the real thing: open MechKeys normally and look at Keyboard \
                Access in the popover, or grant your terminal Accessibility too if you \
                want this command to answer for itself.
                """)
            lines.append("")
        }

        switch (trusted, canTap) {
        case (true, true):
            lines.append("VERDICT: access is granted and working.")
        case (false, true):
            lines.append(
                """
                VERDICT: working, despite the trust call saying otherwise. macOS has \
                cached a stale answer for this process; MechKeys uses the tap test, \
                so it will listen normally.
                """)
        case (true, false):
            lines.append(
                """
                VERDICT: trusted but cannot create a tap. Something else is holding \
                the tap, or the session is restricted.
                """)
        case (false, false) where !launchedByLaunchd:
            lines.append(
                """
                VERDICT: no access *for this process*, which given the warning above \
                says nothing either way about the app itself.
                """)
        case (false, false):
            lines.append(
                """
                VERDICT: no access. If MechKeys is already switched on in System \
                Settings, the entry there belongs to a different build: the grant is \
                keyed to the code signature, and an ad-hoc signature changes on every \
                rebuild. Remove MechKeys from the list, add this bundle, relaunch.
                """)
        }

        lines.append("")
        lines.append("code signature")
        lines.append(String(repeating: "-", count: 14))
        lines.append(signatureDescription(for: bundle.bundlePath))
        return lines.joined(separator: "\n")
    }

    /// Shells out to `codesign`, because the identity TCC keys on is the one
    /// `codesign` reports, not anything the process can introspect directly.
    private static func signatureDescription(for path: String) -> String {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/codesign")
        process.arguments = ["-dvv", path]
        let pipe = Pipe()
        process.standardError = pipe
        process.standardOutput = pipe

        do {
            try process.run()
            let data = pipe.fileHandleForReading.readDataToEndOfFile()
            process.waitUntilExit()
            let text = String(decoding: data, as: UTF8.self)
            let interesting = text.split(separator: "\n").filter {
                $0.hasPrefix("Identifier") || $0.hasPrefix("Signature")
                    || $0.hasPrefix("Authority") || $0.hasPrefix("TeamIdentifier")
                    || $0.hasPrefix("CDHash")
            }
            return interesting.isEmpty ? text : interesting.joined(separator: "\n")
        } catch {
            return "could not run codesign: \(error.localizedDescription)"
        }
    }
}
