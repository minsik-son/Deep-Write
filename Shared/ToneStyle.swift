import Foundation

enum ToneStyle: String, CaseIterable {
    case none = "none"
    case casual = "casual"
    case formal = "formal"
    case polished = "polished"
    case friendly = "friendly"
    // AI Writer exclusive tones (v2)
    case empathetic = "empathetic"
    case confident = "confident"
    case witty = "witty"
    case persuasive = "persuasive"
    case enthusiastic = "enthusiastic"
    case apologetic = "apologetic"
    case social = "social"
    case professional = "professional"

    var displayName: String {
        switch self {
        case .none: return L("tone.none")
        case .casual: return L("tone.casual")
        case .formal: return L("tone.formal")
        case .polished: return L("tone.polished")
        case .friendly: return L("tone.friendly")
        case .empathetic: return L("tone.empathetic")
        case .confident: return L("tone.confident")
        case .witty: return L("tone.witty")
        case .persuasive: return L("tone.persuasive")
        case .enthusiastic: return L("tone.enthusiastic")
        case .apologetic: return L("tone.apologetic")
        case .social: return L("tone.social")
        case .professional: return L("tone.professional")
        }
    }

    /// [v2-W2] Keyboard extension only uses original 5 tones (none + 4 classic)
    var isKeyboardTone: Bool {
        switch self {
        case .none, .casual, .formal, .polished, .friendly:
            return true
        default:
            return false
        }
    }

    /// Keyboard-safe subset
    static var keyboardCases: [ToneStyle] {
        return allCases.filter { $0.isKeyboardTone }
    }
}
