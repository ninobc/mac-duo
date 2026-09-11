import Foundation

/// Everything that shapes the look. Stored as one value so presets are a
/// single assignment and "custom" is any deviation from them.
public struct EffectSettings: Codable, Equatable, Sendable {

    /// The fold starts at this angle.
    public var startAngle: Double = 90
    /// Degrees of further closing to reach full strength.
    public var span: Double = 60
    /// Blur radius at the far edge at full strength, in points.
    public var blurRadius: Double = 135
    /// Blur at the hinge as a fraction of the far edge. 0 keeps the hinge sharp.
    public var blurFloor: Double = 0.0
    /// How dark the far edge goes, 0…1.
    public var dimming: Double = 1
    /// Height, as a fraction of the screen, where dimming starts to bite.
    public var dimStart: Double = 0.0
    /// Height where the dimming reaches full strength. Above it, at full fold,
    /// the picture is dark.
    public var dimReach: Double = 0.5
    /// Dimming at the hinge as a fraction of the far edge, so the whole
    /// picture sinks a little as it folds.
    public var dimHingeFloor: Double = 0.2
    /// Eye height above the screen centre, in screen heights.
    public var eyeHeight: Double = 0.0
    /// How much the picture stays fixed in the room. 1 is physically right.
    public var depth: Double = 1
    /// Eye distance in screen heights. Closer means stronger perspective.
    public var eyeDistance: Double = 6.0
    /// The travelling highlight on the frosted glass.
    public var sheen: Double = 0
    /// Fine grain that hides banding in the dark gradient.
    public var grain: Double = 0
    /// Keep the picture live under the fold instead of holding one frame.
    public var livePicture: Bool = true

    public init() {}

    /// Older saved settings lack the newer keys; they take the defaults.
    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        let d = EffectSettings()
        startAngle = try c.decodeIfPresent(Double.self, forKey: .startAngle) ?? d.startAngle
        span = try c.decodeIfPresent(Double.self, forKey: .span) ?? d.span
        blurRadius = try c.decodeIfPresent(Double.self, forKey: .blurRadius) ?? d.blurRadius
        blurFloor = try c.decodeIfPresent(Double.self, forKey: .blurFloor) ?? d.blurFloor
        dimming = try c.decodeIfPresent(Double.self, forKey: .dimming) ?? d.dimming
        dimStart = try c.decodeIfPresent(Double.self, forKey: .dimStart) ?? d.dimStart
        dimReach = try c.decodeIfPresent(Double.self, forKey: .dimReach) ?? d.dimReach
        dimHingeFloor = try c.decodeIfPresent(Double.self, forKey: .dimHingeFloor) ?? d.dimHingeFloor
        eyeHeight = try c.decodeIfPresent(Double.self, forKey: .eyeHeight) ?? d.eyeHeight
        depth = try c.decodeIfPresent(Double.self, forKey: .depth) ?? d.depth
        eyeDistance = try c.decodeIfPresent(Double.self, forKey: .eyeDistance) ?? d.eyeDistance
        sheen = try c.decodeIfPresent(Double.self, forKey: .sheen) ?? d.sheen
        grain = try c.decodeIfPresent(Double.self, forKey: .grain) ?? d.grain
        livePicture = try c.decodeIfPresent(Bool.self, forKey: .livePicture) ?? d.livePicture
    }

    public static let duo = EffectSettings()

    public static let soft: EffectSettings = {
        var s = EffectSettings()
        s.startAngle = 90
        s.span = 50
        s.blurRadius = 70
        s.dimming = 0.7
        s.dimReach = 0.75
        s.dimHingeFloor = 0.1
        s.depth = 0.8
        return s
    }()

    public static let cinematic: EffectSettings = {
        var s = EffectSettings()
        s.startAngle = 100
        s.span = 70
        s.blurRadius = 160
        s.dimming = 1
        s.dimReach = 0.45
        s.dimHingeFloor = 0.25
        s.depth = 1.2
        s.eyeDistance = 4.5
        return s
    }()
}

/// The named looks in the menu.
public enum EffectPreset: String, CaseIterable, Codable, Sendable {
    case duo, soft, cinematic

    public var title: String {
        switch self {
        case .duo: return "Duo"
        case .soft: return "Soft"
        case .cinematic: return "Cinematic"
        }
    }

    public var settings: EffectSettings {
        switch self {
        case .duo: return .duo
        case .soft: return .soft
        case .cinematic: return .cinematic
        }
    }

    /// The preset these settings equal, if any.
    public static func matching(_ settings: EffectSettings) -> EffectPreset? {
        allCases.first { $0.settings == settings }
    }
}
