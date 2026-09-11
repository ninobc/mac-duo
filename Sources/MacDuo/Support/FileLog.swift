import Foundation

/// A plain text log next to the system one, because `log show` is awkward
/// for people and unavailable in some shells. Lives at
/// ~/Library/Logs/Mac Duo/Mac Duo.log, capped at about a megabyte.
enum FileLog {
    static let url: URL = {
        let base = FileManager.default.urls(for: .libraryDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("Logs/Mac Duo", isDirectory: true)
        try? FileManager.default.createDirectory(at: base, withIntermediateDirectories: true)
        return base.appendingPathComponent("Mac Duo.log")
    }()

    private static let queue = DispatchQueue(label: "com.mac-duo.filelog", qos: .utility)
    private static let stamp: DateFormatter = {
        let f = DateFormatter()
        f.dateFormat = "yyyy-MM-dd HH:mm:ss.SSS"
        return f
    }()

    static func write(_ category: String, _ message: String) {
        let line = "\(stamp.string(from: Date())) [\(category)] \(message)\n"
        queue.async {
            guard let data = line.data(using: .utf8) else { return }
            if let handle = try? FileHandle(forWritingTo: url) {
                defer { try? handle.close() }
                if let size = try? handle.seekToEnd(), size > 1_000_000 {
                    try? handle.truncate(atOffset: 0)
                }
                try? handle.write(contentsOf: data)
            } else {
                try? data.write(to: url)
            }
        }
    }
}
