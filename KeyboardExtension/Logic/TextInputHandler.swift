import Foundation

protocol TextInputHandlerDelegate: AnyObject {
    func textInputHandler(_ handler: TextInputHandler, didUpdateBuffer text: String)
    func textInputHandler(_ handler: TextInputHandler, didUpdateComposing text: String)
}

protocol TextInputHandling: AnyObject {
    var delegate: TextInputHandlerDelegate? { get set }
    var buffer: String { get }
    var composingText: String { get }
    var fullText: String { get }
    var totalLength: Int { get }

    func handleKey(_ key: Character, isKorean: Bool)
    func handleBackspace()
    func handleSpace()
    func handleNewline()
    func clear()
    func commitComposing()
}

class TextInputHandler: TextInputHandling {

    weak var delegate: TextInputHandlerDelegate?

    private(set) var buffer: String = ""
    private(set) var composingText: String = ""
    private(set) var cursorIndex: Int = 0

    var maxNewlineCount: Int = 10
    var maxLength: Int = Int.max

    // Hangul composition state
    private var hangulState: HangulState = .empty

    enum HangulState {
        case empty
        case initial(Int)           // 초성만
        case initialVowel(Int, Int) // 초성 + 중성
        case complete(Int, Int, Int) // 초성 + 중성 + 종성
    }

    // Hangul constants
    private static let initialConsonants: [Character: Int] = [
        "ㄱ": 0, "ㄲ": 1, "ㄴ": 2, "ㄷ": 3, "ㄸ": 4, "ㄹ": 5,
        "ㅁ": 6, "ㅂ": 7, "ㅃ": 8, "ㅅ": 9, "ㅆ": 10, "ㅇ": 11,
        "ㅈ": 12, "ㅉ": 13, "ㅊ": 14, "ㅋ": 15, "ㅌ": 16, "ㅍ": 17, "ㅎ": 18
    ]

    private static let vowels: [Character: Int] = [
        "ㅏ": 0, "ㅐ": 1, "ㅑ": 2, "ㅒ": 3, "ㅓ": 4, "ㅔ": 5,
        "ㅕ": 6, "ㅖ": 7, "ㅗ": 8, "ㅘ": 9, "ㅙ": 10, "ㅚ": 11,
        "ㅛ": 12, "ㅜ": 13, "ㅝ": 14, "ㅞ": 15, "ㅟ": 16, "ㅠ": 17,
        "ㅡ": 18, "ㅢ": 19, "ㅣ": 20
    ]

    private static let finalConsonants: [Character: Int] = [
        "ㄱ": 1, "ㄲ": 2, "ㄳ": 3, "ㄴ": 4, "ㄵ": 5, "ㄶ": 6,
        "ㄷ": 7, "ㄹ": 8, "ㄺ": 9, "ㄻ": 10, "ㄼ": 11, "ㄽ": 12,
        "ㄾ": 13, "ㄿ": 14, "ㅀ": 15, "ㅁ": 16, "ㅂ": 17, "ㅄ": 18,
        "ㅅ": 19, "ㅆ": 20, "ㅇ": 21, "ㅈ": 22, "ㅊ": 23,
        "ㅋ": 24, "ㅌ": 25, "ㅍ": 26, "ㅎ": 27
    ]

    // Final consonant to initial consonant mapping (for when vowel follows)
    private static let finalToInitial: [Int: Int] = [
        1: 0,   // ㄱ
        2: 1,   // ㄲ
        4: 2,   // ㄴ
        7: 3,   // ㄷ
        8: 5,   // ㄹ
        16: 6,  // ㅁ
        17: 7,  // ㅂ
        19: 9,  // ㅅ
        20: 10, // ㅆ
        21: 11, // ㅇ
        22: 12, // ㅈ
        23: 14, // ㅊ
        24: 15, // ㅋ
        25: 16, // ㅌ
        26: 17, // ㅍ
        27: 18  // ㅎ
    ]

    // Compound final consonants: (first, second) -> compound index
    private static let compoundFinals: [String: (compound: Int, first: Int, second: Int)] = [
        "ㄱㅅ": (3, 1, 19),   // ㄳ
        "ㄴㅈ": (5, 4, 22),   // ㄵ
        "ㄴㅎ": (6, 4, 27),   // ㄶ
        "ㄹㄱ": (9, 8, 1),    // ㄺ
        "ㄹㅁ": (10, 8, 16),  // ㄻ
        "ㄹㅂ": (11, 8, 17),  // ㄼ
        "ㄹㅅ": (12, 8, 19),  // ㄽ
        "ㄹㅌ": (13, 8, 25),  // ㄾ
        "ㄹㅍ": (14, 8, 26),  // ㄿ
        "ㄹㅎ": (15, 8, 27),  // ㅀ
        "ㅂㅅ": (18, 17, 19), // ㅄ
    ]

    // Compound vowels
    private static let compoundVowels: [String: Int] = [
        "ㅗㅏ": 9,   // ㅘ
        "ㅗㅐ": 10,  // ㅙ
        "ㅗㅣ": 11,  // ㅚ
        "ㅜㅓ": 14,  // ㅝ
        "ㅜㅔ": 15,  // ㅞ
        "ㅜㅣ": 16,  // ㅟ
        "ㅡㅣ": 19,  // ㅢ
    ]

    // Reverse lookups
    private static let initialIndex: [Int: Character] = {
        var map = [Int: Character]()
        for (char, idx) in initialConsonants { map[idx] = char }
        return map
    }()

    private static let vowelIndex: [Int: Character] = {
        var map = [Int: Character]()
        for (char, idx) in vowels { map[idx] = char }
        return map
    }()

    private static let finalIndex: [Int: Character] = {
        var map = [Int: Character]()
        for (char, idx) in finalConsonants { map[idx] = char }
        return map
    }()

    var totalLength: Int {
        return buffer.count + (composingText.isEmpty ? 0 : 1)
    }

    func handleKey(_ key: Character, isKorean: Bool) {
        if isKorean {
            handleKoreanKey(key)
        } else {
            guard (buffer.count + (composingText.isEmpty ? 0 : 1) + 1) <= maxLength else { return }
            commitComposing()
            let idx = buffer.index(buffer.startIndex, offsetBy: min(cursorIndex, buffer.count))
            buffer.insert(key, at: idx)
            cursorIndex += 1
            delegate?.textInputHandler(self, didUpdateBuffer: buffer)
        }
    }

    func handleBackspace() {
        if !composingText.isEmpty {
            removeLastComposingUnit()
        } else if !buffer.isEmpty && cursorIndex > 0 {
            let idx = buffer.index(buffer.startIndex, offsetBy: cursorIndex - 1)
            buffer.remove(at: idx)
            cursorIndex -= 1
            delegate?.textInputHandler(self, didUpdateBuffer: buffer)
        }
    }

    func handleSpace() {
        guard (buffer.count + (composingText.isEmpty ? 0 : 1) + 1) <= maxLength else { return }
        commitComposing()
        let idx = buffer.index(buffer.startIndex, offsetBy: min(cursorIndex, buffer.count))
        buffer.insert(" ", at: idx)
        cursorIndex += 1
        delegate?.textInputHandler(self, didUpdateBuffer: buffer)
    }

    func handleNewline() {
        guard (buffer.count + (composingText.isEmpty ? 0 : 1) + 1) <= maxLength else { return }
        let lineCount = buffer.components(separatedBy: "\n").count
        guard lineCount < maxNewlineCount else { return }
        commitComposing()
        let idx = buffer.index(buffer.startIndex, offsetBy: min(cursorIndex, buffer.count))
        buffer.insert("\n", at: idx)
        cursorIndex += 1
        delegate?.textInputHandler(self, didUpdateBuffer: buffer)
    }

    func clear() {
        buffer = ""
        composingText = ""
        hangulState = .empty
        cursorIndex = 0
        delegate?.textInputHandler(self, didUpdateBuffer: buffer)
        delegate?.textInputHandler(self, didUpdateComposing: "")
    }

    var fullText: String {
        return composingText.isEmpty ? buffer : buffer + composingText
    }

    // MARK: - Korean Composition

    private func handleKoreanKey(_ key: Character) {
        let isConsonant = Self.initialConsonants[key] != nil
        let isVowel = Self.vowels[key] != nil

        guard isConsonant || isVowel else {
            commitComposing()
            insertCharIntoBuffer(key)
            delegate?.textInputHandler(self, didUpdateBuffer: buffer)
            return
        }

        switch hangulState {
        case .empty:
            if isConsonant {
                guard (buffer.count + 1) <= maxLength else { return }
                if let initialIdx = Self.initialConsonants[key] {
                    hangulState = .initial(initialIdx)
                    composingText = String(key)
                }
            } else if isVowel {
                guard (buffer.count + 1) <= maxLength else { return }
                commitComposing()
                insertCharIntoBuffer(key)
                delegate?.textInputHandler(self, didUpdateBuffer: buffer)
                return
            }

        case .initial(let initial):
            if isVowel {
                // 중성 추가 → 조합만 변경, 글자 수 변화 없음
                if let vowelIdx = Self.vowels[key] {
                    hangulState = .initialVowel(initial, vowelIdx)
                    composingText = composeSyllable(initial: initial, vowel: vowelIdx, final: 0)
                }
            } else {
                // Another consonant - commit current and start new → 글자 수 +1
                guard (buffer.count + 1 + 1) <= maxLength else { return }
                commitComposing()
                if let initialIdx = Self.initialConsonants[key] {
                    hangulState = .initial(initialIdx)
                    composingText = String(key)
                }
            }

        case .initialVowel(let initial, let vowel):
            if isVowel {
                // Try compound vowel
                if let vowelChar = Self.vowelIndex[vowel],
                   let compoundIdx = Self.compoundVowels[String(vowelChar) + String(key)] {
                    // 복합 모음 → 조합만 변경, 글자 수 변화 없음
                    hangulState = .initialVowel(initial, compoundIdx)
                    composingText = composeSyllable(initial: initial, vowel: compoundIdx, final: 0)
                } else {
                    // Can't compound - commit and start fresh → 글자 수 +1
                    guard (buffer.count + 1 + 1) <= maxLength else { return }
                    commitComposing()
                    insertCharIntoBuffer(key)
                    hangulState = .empty
                    composingText = ""
                    delegate?.textInputHandler(self, didUpdateBuffer: buffer)
                    return
                }
            } else if isConsonant {
                if let finalIdx = Self.finalConsonants[key] {
                    // 종성 추가 → 조합만 변경, 글자 수 변화 없음
                    hangulState = .complete(initial, vowel, finalIdx)
                    composingText = composeSyllable(initial: initial, vowel: vowel, final: finalIdx)
                } else {
                    // 종성이 될 수 없는 자음 → commit + new → 글자 수 +1
                    guard (buffer.count + 1 + 1) <= maxLength else { return }
                    commitComposing()
                    if let initialIdx = Self.initialConsonants[key] {
                        hangulState = .initial(initialIdx)
                        composingText = String(key)
                    }
                }
            }

        case .complete(let initial, let vowel, let final_):
            if isVowel {
                // Check if compound final - split it
                var splitFinal: (first: Int, secondInitial: Int)? = nil
                for (_, value) in Self.compoundFinals {
                    if value.compound == final_ {
                        if let newInitial = Self.finalToInitial[value.second] {
                            splitFinal = (value.first, newInitial)
                        }
                        break
                    }
                }

                if let split = splitFinal, let vowelIdx = Self.vowels[key] {
                    // 복합 종성 분리 → 글자 수 +1
                    guard (buffer.count + 1 + 1) <= maxLength else { return }
                    let syllable = composeSyllable(initial: initial, vowel: vowel, final: split.first)
                    insertIntoBuffer(String(syllable))

                    hangulState = .initialVowel(split.secondInitial, vowelIdx)
                    composingText = composeSyllable(initial: split.secondInitial, vowel: vowelIdx, final: 0)
                    delegate?.textInputHandler(self, didUpdateBuffer: buffer)
                } else if let newInitial = Self.finalToInitial[final_],
                          let vowelIdx = Self.vowels[key] {
                    // 단순 종성 → 다음 글자 초성으로 → 글자 수 +1
                    guard (buffer.count + 1 + 1) <= maxLength else { return }
                    let syllable = composeSyllable(initial: initial, vowel: vowel, final: 0)
                    insertIntoBuffer(String(syllable))

                    hangulState = .initialVowel(newInitial, vowelIdx)
                    composingText = composeSyllable(initial: newInitial, vowel: vowelIdx, final: 0)
                    delegate?.textInputHandler(self, didUpdateBuffer: buffer)
                } else {
                    guard (buffer.count + 1 + 1) <= maxLength else { return }
                    commitComposing()
                    insertCharIntoBuffer(key)
                    hangulState = .empty
                    composingText = ""
                    delegate?.textInputHandler(self, didUpdateBuffer: buffer)
                    return
                }
            } else if isConsonant {
                // Try compound final consonant
                if let finalChar = Self.finalIndex[final_] {
                    let compoundKey = String(finalChar) + String(key)
                    if let compound = Self.compoundFinals[compoundKey] {
                        // 복합 종성 → 조합만 변경, 글자 수 변화 없음
                        hangulState = .complete(initial, vowel, compound.compound)
                        composingText = composeSyllable(initial: initial, vowel: vowel, final: compound.compound)
                    } else {
                        // Can't compound - commit and start new → 글자 수 +1
                        guard (buffer.count + 1 + 1) <= maxLength else { return }
                        commitComposing()
                        if let initialIdx = Self.initialConsonants[key] {
                            hangulState = .initial(initialIdx)
                            composingText = String(key)
                        }
                    }
                } else {
                    guard (buffer.count + 1 + 1) <= maxLength else { return }
                    commitComposing()
                    if let initialIdx = Self.initialConsonants[key] {
                        hangulState = .initial(initialIdx)
                        composingText = String(key)
                    }
                }
            }
        }

        delegate?.textInputHandler(self, didUpdateComposing: composingText)
    }

    private func composeSyllable(initial: Int, vowel: Int, final: Int) -> String {
        let code = 0xAC00 + (initial * 21 + vowel) * 28 + final
        guard let scalar = Unicode.Scalar(code) else { return "" }
        return String(Character(scalar))
    }

    func commitComposing() {
        if !composingText.isEmpty {
            let idx = buffer.index(buffer.startIndex, offsetBy: min(cursorIndex, buffer.count))
            buffer.insert(contentsOf: composingText, at: idx)
            cursorIndex += composingText.count
            composingText = ""
            hangulState = .empty
            delegate?.textInputHandler(self, didUpdateBuffer: buffer)
            delegate?.textInputHandler(self, didUpdateComposing: "")
        }
    }

    func resetBuffer() {
        buffer = ""
    }

    func setInitialText(_ text: String) {
        buffer = text
        composingText = ""
        hangulState = .empty
        cursorIndex = text.count
    }

    /// v2: cursorIndex 위치에 텍스트 삽입 + index 증가
    private func insertIntoBuffer(_ text: String) {
        let idx = buffer.index(buffer.startIndex, offsetBy: min(cursorIndex, buffer.count))
        buffer.insert(contentsOf: text, at: idx)
        cursorIndex += text.count
    }

    /// v2: cursorIndex 위치에 단일 문자 삽입
    private func insertCharIntoBuffer(_ ch: Character) {
        let idx = buffer.index(buffer.startIndex, offsetBy: min(cursorIndex, buffer.count))
        buffer.insert(ch, at: idx)
        cursorIndex += 1
    }

    func moveCursor(to index: Int) {
        commitComposing()
        cursorIndex = max(0, min(index, buffer.count))
    }

    func moveCursorToEnd() {
        commitComposing()
        cursorIndex = buffer.count
    }

    private func removeLastComposingUnit() {
        switch hangulState {
        case .empty:
            break
        case .initial:
            hangulState = .empty
            composingText = ""
        case .initialVowel(let initial, _):
            hangulState = .initial(initial)
            if let char = Self.initialIndex[initial] {
                composingText = String(char)
            }
        case .complete(let initial, let vowel, let final_):
            // Check if compound final - decompose it
            for (_, value) in Self.compoundFinals {
                if value.compound == final_ {
                    hangulState = .complete(initial, vowel, value.first)
                    composingText = composeSyllable(initial: initial, vowel: vowel, final: value.first)
                    delegate?.textInputHandler(self, didUpdateComposing: composingText)
                    return
                }
            }
            // Simple final - just remove it
            hangulState = .initialVowel(initial, vowel)
            composingText = composeSyllable(initial: initial, vowel: vowel, final: 0)
        }
        delegate?.textInputHandler(self, didUpdateComposing: composingText)
    }
}
