import Foundation

enum AppInfo {
    static let name = "Mac Duo"
    static let bundleID = Bundle.main.bundleIdentifier ?? "com.mac-duo.app"
    static let version = Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "0.0.0"
    static let build = Bundle.main.object(forInfoDictionaryKey: "CFBundleVersion") as? String ?? "0"
    static let website = URL(string: "https://mac-duo.com")!
    static let downloadPage = URL(string: "https://mac-duo.com/#install")!
    static let updateFeed = URL(string: "https://mac-duo.com/updates.json")!
    static let sourceCode = URL(string: "https://github.com/ninobc/mac-duo")!
    static let privacy = URL(string: "https://mac-duo.com/privacy")!
    static let author = "Nino Bouchedid"
    static let copyright = "© 2026 Nino Bouchedid"
}
