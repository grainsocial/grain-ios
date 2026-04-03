import Foundation

enum LabelAction: Comparable {
    case none
    case badge
    case warnMedia
    case warnContent
    case hide

    var severity: Int {
        switch self {
        case .none: 0
        case .badge: 1
        case .warnMedia: 2
        case .warnContent: 3
        case .hide: 4
        }
    }

    static func < (lhs: LabelAction, rhs: LabelAction) -> Bool {
        lhs.severity < rhs.severity
    }
}

struct LabelResolution {
    let action: LabelAction
    let label: String
    let name: String

    static let none = LabelResolution(action: .none, label: "", name: "")
}

/// Well-known ATProto label fallbacks (used when server definitions unavailable)
private let fallbackDefinitions: [String: (blurs: String, defaultSetting: String, name: String)] = [
    "porn": ("media", "warn", "Adult Content"),
    "sexual": ("media", "warn", "Sexual Content"),
    "nudity": ("media", "warn", "Nudity"),
    "nsfl": ("media", "hide", "NSFL"),
    "gore": ("media", "hide", "Graphic Violence"),
    "dmca-violation": ("content", "hide", "DMCA Violation"),
    "doxxing": ("content", "hide", "Doxxing"),
    "!hide": ("content", "hide", "Hidden"),
    "!warn": ("content", "warn", "Warning"),
]

/// Resolve the most restrictive label action for a set of labels.
func resolveLabels(_ labels: [ATLabel]?, definitions: [LabelDefinition]) -> LabelResolution {
    guard let labels, !labels.isEmpty else { return .none }

    var worst = LabelResolution.none

    for label in labels {
        guard let val = label.val, !val.isEmpty else { continue }

        let resolution: LabelResolution
        if let def = definitions.first(where: { $0.identifier == val }) {
            resolution = resolveFromDefinition(val: val, def: def)
        } else if let fallback = fallbackDefinitions[val] {
            resolution = resolveFromFallback(val: val, fallback: fallback)
        } else {
            // Unknown label — treat as badge warning
            resolution = LabelResolution(action: .badge, label: val, name: val)
        }

        if resolution.action > worst.action {
            worst = resolution
        }
    }

    return worst
}

private func resolveFromDefinition(val: String, def: LabelDefinition) -> LabelResolution {
    let blurs = def.blurs ?? "none"
    let setting = def.defaultSetting ?? "ignore"
    let name = def.displayName

    return resolveAction(val: val, name: name, blurs: blurs, setting: setting)
}

private func resolveFromFallback(val: String, fallback: (blurs: String, defaultSetting: String, name: String)) -> LabelResolution {
    return resolveAction(val: val, name: fallback.name, blurs: fallback.blurs, setting: fallback.defaultSetting)
}

private func resolveAction(val: String, name: String, blurs: String, setting: String) -> LabelResolution {
    let action: LabelAction
    switch (blurs, setting) {
    case (_, "hide") where blurs != "none":
        action = blurs == "media" ? .warnMedia : .hide
    case ("content", "warn"):
        action = .warnContent
    case ("media", "warn"):
        action = .warnMedia
    case ("none", "warn"):
        action = .badge
    default:
        action = .none
    }
    return LabelResolution(action: action, label: val, name: name)
}
