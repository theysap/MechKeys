import OSLog

/// Subsystem-wide loggers.
///
/// Everything the app reports goes through `os.Logger`, so diagnostics can be
/// collected with `log stream --predicate 'subsystem == "com.mechkeys.app"'`
/// without MechKeys writing any files of its own.
///
/// Nothing logged here ever contains a keycode or a character. The keyboard
/// path logs lifecycle events only.
enum AppLog {
    private static let subsystem = "com.mechkeys.app"

    static let app = Logger(subsystem: subsystem, category: "app")
    static let audio = Logger(subsystem: subsystem, category: "audio")
    static let keyboard = Logger(subsystem: subsystem, category: "keyboard")
    static let library = Logger(subsystem: subsystem, category: "library")
    static let settings = Logger(subsystem: subsystem, category: "settings")
}
