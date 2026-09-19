import AppKit
import Foundation

/// A self-report of the things that decide whether MechKeys can hear the
/// keyboard. Printed by `MechKeys --diagnose`.
///
/// Every value here is read from inside the running app, because that is the
/// only place the answers are true: TCC decides per process, by code
/// signature, and nothing outside the process can see what it was told.
public enum Diagnostics {

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
        lines.append("")

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
