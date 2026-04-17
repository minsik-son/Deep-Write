import UIKit

final class AutocorrectEngine {
    private lazy var textChecker: UITextChecker = {
        #if DEBUG
        let _t = CACurrentMediaTime()
        #endif
        let tc = UITextChecker()
        #if DEBUG
        NSLog("[SuggestionInit] textChecker.create = %.2fms", (CACurrentMediaTime() - _t) * 1000)
        #endif
        return tc
    }()

    func textCheckerLanguage(for language: KeyboardLanguage) -> String {
        switch language {
        case .english: return "en_US"
        case .korean: return "ko"
        case .spanish: return "es"
        case .french: return "fr"
        case .german: return "de"
        case .italian: return "it"
        case .russian: return "ru"
        }
    }

    func suggestions(for word: String, language: KeyboardLanguage) -> [String] {
        guard !word.isEmpty else { return [] }
        let lang = textCheckerLanguage(for: language)
        let range = NSRange(location: 0, length: word.utf16.count)

        let misspelledRange = textChecker.rangeOfMisspelledWord(
            in: word, range: range, startingAt: 0, wrap: false, language: lang)

        if misspelledRange.location == NSNotFound {
            let completions = textChecker.completions(
                forPartialWordRange: range, in: word, language: lang) ?? []
            return Array(completions.prefix(3))
        }

        let guesses = textChecker.guesses(
            forWordRange: misspelledRange, in: word, language: lang) ?? []
        return Array(guesses.prefix(3))
    }
}
