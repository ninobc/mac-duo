import Foundation
import os

/// Read with:
///
///     log show --last 10m --predicate 'subsystem == "com.mac-duo.app"' --info
enum Log {
    static let subsystem = "com.mac-duo.app"
    static let lid = Logger(subsystem: subsystem, category: "lid")
    static let fold = Logger(subsystem: subsystem, category: "fold")
    static let render = Logger(subsystem: subsystem, category: "render")
    static let capture = Logger(subsystem: subsystem, category: "capture")
    static let app = Logger(subsystem: subsystem, category: "app")
}
