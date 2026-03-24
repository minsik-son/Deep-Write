import Foundation

struct AccentMap {
    static func accents(for language: KeyboardLanguage) -> [String: [String]] {
        switch language {
        case .english: return englishAccents
        case .spanish: return spanishAccents
        case .french: return frenchAccents
        case .german: return germanAccents
        case .italian: return italianAccents
        default: return [:]
        }
    }

    private static let englishAccents: [String: [String]] = [
        "a": ["à", "á", "â", "ä", "æ", "ã", "å"],
        "e": ["è", "é", "ê", "ë"],
        "i": ["ì", "í", "î", "ï"],
        "o": ["ò", "ó", "ô", "ö", "œ", "ø", "õ"],
        "u": ["ù", "ú", "û", "ü"],
        "y": ["ÿ"],
        "c": ["ç"],
        "n": ["ñ"],
        "s": ["ß"],
        "l": ["ł"],

        "A": ["À", "Á", "Â", "Ä", "Æ", "Ã", "Å"],
        "E": ["È", "É", "Ê", "Ë"],
        "I": ["Ì", "Í", "Î", "Ï"],
        "O": ["Ò", "Ó", "Ô", "Ö", "Œ", "Ø", "Õ"],
        "U": ["Ù", "Ú", "Û", "Ü"],
        "Y": ["Ÿ"],
        "C": ["Ç"],
        "N": ["Ñ"],
        "S": ["ẞ"],
        "L": ["Ł"]
    ]

    private static let spanishAccents: [String: [String]] = [
        "a": ["á", "à", "â", "ä", "ã"], "A": ["Á", "À", "Â", "Ä", "Ã"],
        "e": ["é", "è", "ê", "ë"],       "E": ["É", "È", "Ê", "Ë"],
        "i": ["í", "ì", "î", "ï"],       "I": ["Í", "Ì", "Î", "Ï"],
        "o": ["ó", "ò", "ô", "ö", "õ"], "O": ["Ó", "Ò", "Ô", "Ö", "Õ"],
        "u": ["ú", "ù", "û", "ü"],       "U": ["Ú", "Ù", "Û", "Ü"],
        "n": ["ñ"],                       "N": ["Ñ"],
        "?": ["¿"],                       "!": ["¡"],
    ]

    private static let frenchAccents: [String: [String]] = [
        "a": ["à", "â", "æ", "ä"],       "A": ["À", "Â", "Æ", "Ä"],
        "e": ["é", "è", "ê", "ë", "œ"],  "E": ["É", "È", "Ê", "Ë", "Œ"],
        "i": ["î", "ï"],                  "I": ["Î", "Ï"],
        "o": ["ô", "ö"],                  "O": ["Ô", "Ö"],
        "u": ["ù", "û", "ü"],             "U": ["Ù", "Û", "Ü"],
        "c": ["ç"],                        "C": ["Ç"],
        "y": ["ÿ"],                        "Y": ["Ÿ"],
    ]

    private static let germanAccents: [String: [String]] = [
        "a": ["ä", "à", "â"],             "A": ["Ä", "À", "Â"],
        "o": ["ö", "ò", "ô"],             "O": ["Ö", "Ò", "Ô"],
        "u": ["ü", "ù", "û"],             "U": ["Ü", "Ù", "Û"],
        "s": ["ß"],                        "S": ["ẞ"],
    ]

    private static let italianAccents: [String: [String]] = [
        "a": ["à", "á", "â"],             "A": ["À", "Á", "Â"],
        "e": ["è", "é", "ê"],             "E": ["È", "É", "Ê"],
        "i": ["ì", "í", "î"],             "I": ["Ì", "Í", "Î"],
        "o": ["ò", "ó", "ô"],             "O": ["Ò", "Ó", "Ô"],
        "u": ["ù", "ú", "û"],             "U": ["Ù", "Ú", "Û"],
    ]
}
