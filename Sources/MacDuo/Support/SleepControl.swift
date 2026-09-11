import Foundation

/// Keeps the Mac awake with the lid closed.
///
/// A closed lid forces sleep unless the system-wide `disablesleep` power
/// setting is on, and that needs administrator rights, so flipping it asks
/// for the password through the standard macOS prompt. Reading it needs no
/// rights. The display still turns off when the lid is shut; only the Mac
/// stays running.
enum SleepControl {

    /// The current system setting, from `pmset -g`.
    static func isSleepDisabled() -> Bool {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/pmset")
        process.arguments = ["-g"]
        let pipe = Pipe()
        process.standardOutput = pipe
        process.standardError = Pipe()
        do {
            try process.run()
            process.waitUntilExit()
        } catch {
            return false
        }
        let output = String(decoding: pipe.fileHandleForReading.readDataToEndOfFile(), as: UTF8.self)
        for line in output.split(separator: "\n") {
            let parts = line.split(whereSeparator: { $0 == " " || $0 == "\t" })
            if parts.first == "SleepDisabled", parts.count > 1 { return parts[1] == "1" }
        }
        return false
    }

    /// Changes the setting with administrator rights. Returns the setting
    /// as it stands afterwards, which is unchanged if the prompt was
    /// cancelled.
    static func setSleepDisabled(_ disabled: Bool) async -> Bool {
        await Task.detached(priority: .userInitiated) {
            let script = "do shell script \"/usr/bin/pmset -a disablesleep \(disabled ? 1 : 0)\" with administrator privileges"
            let process = Process()
            process.executableURL = URL(fileURLWithPath: "/usr/bin/osascript")
            process.arguments = ["-e", script]
            process.standardOutput = Pipe()
            let errors = Pipe()
            process.standardError = errors
            do {
                try process.run()
                process.waitUntilExit()
            } catch {
                FileLog.write("sleep", "osascript failed to launch: \(error)")
            }
            if process.terminationStatus != 0 {
                let text = String(decoding: errors.fileHandleForReading.readDataToEndOfFile(), as: UTF8.self)
                FileLog.write("sleep", "pmset disablesleep \(disabled ? 1 : 0) refused: \(text.trimmingCharacters(in: .whitespacesAndNewlines))")
            } else {
                FileLog.write("sleep", "pmset disablesleep \(disabled ? 1 : 0)")
            }
            return isSleepDisabled()
        }.value
    }
}
