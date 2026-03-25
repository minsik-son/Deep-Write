import Foundation

final class SuggestionManager {
    private let autocorrectEngine = AutocorrectEngine()
    private let predictionEngine = PredictionEngine()

    /// Phase 3: KeyboardLayoutView에서 PredictionEngine 접근용 getter
    var predictionEngineRef: PredictionEngine { return predictionEngine }

    /// debounce 타이머 참조
    private var suggestionDebounceTimer: Timer?

    deinit {
        suggestionDebounceTimer?.invalidate()
    }

    enum SuggestionMode {
        case autocorrect
        case prediction
        case none
    }

    struct SuggestionResult {
        let mode: SuggestionMode
        let suggestions: [String]
    }

    func getSuggestions(
        context: String?,
        currentWord: String?,
        isComposing: Bool,
        language: KeyboardLanguage,
        onPrediction: (([String]) -> Void)? = nil
    ) -> SuggestionResult {
        // Korean composing → no suggestions
        if isComposing {
            return SuggestionResult(mode: .none, suggestions: [])
        }

        // Currently typing a word → autocorrect (동기, 빠름)
        if let word = currentWord, !word.isEmpty {
            let suggestions = autocorrectEngine.suggestions(for: word, language: language)
            if suggestions.isEmpty {
                return SuggestionResult(mode: .none, suggestions: [])
            }
            return SuggestionResult(mode: .autocorrect, suggestions: suggestions)
        }

        // No current word (after space) → prediction (비동기)
        let langCode = language.rawValue

        // 모델이 이미 로드되어 있으면 즉시 반환
        if predictionEngine.isModelLoaded {
            let words = extractContextWords(from: context)
            guard !words.isEmpty else {
                return SuggestionResult(mode: .none, suggestions: [])
            }
            let predictions = predictionEngine.predict(context: words)
            if predictions.isEmpty {
                return SuggestionResult(mode: .none, suggestions: [])
            }
            return SuggestionResult(mode: .prediction, suggestions: predictions)
        }

        // 모델 미로드 → 비동기 로딩 시작, 빈 결과 즉시 반환
        predictionEngine.loadModel(for: langCode) { [weak self] in
            guard let self = self else { return }
            let words = self.extractContextWords(from: context)
            guard !words.isEmpty else { return }
            let predictions = self.predictionEngine.predict(context: words)
            if !predictions.isEmpty {
                onPrediction?(predictions)
            }
        }
        return SuggestionResult(mode: .none, suggestions: [])
    }

    /// Debounce 기반 비동기 제안 (메인 스레드에서 실행, UITextChecker thread-safety 보장)
    /// 연속 타이핑 시 마지막 입력만 처리하여 메인 스레드 부담 최소화
    func getSuggestionsAsync(
        context: String?,
        currentWord: String?,
        isComposing: Bool,
        language: KeyboardLanguage,
        completion: @escaping (SuggestionResult) -> Void
    ) {
        // 이전 타이머 취소 (연속 타이핑 시 이전 요청 무시)
        suggestionDebounceTimer?.invalidate()

        // Korean composing → 즉시 none 반환 (debounce 불필요)
        if isComposing {
            completion(SuggestionResult(mode: .none, suggestions: []))
            return
        }

        // 현재 단어 없음 → prediction 로직 (기존 동기 방식 유지)
        guard let word = currentWord, !word.isEmpty else {
            let result = getSuggestions(
                context: context,
                currentWord: currentWord,
                isComposing: isComposing,
                language: language,
                onPrediction: { predictions in
                    completion(SuggestionResult(mode: .prediction, suggestions: predictions))
                }
            )
            completion(result)
            return
        }

        // 단어 입력 중 → debounce 80ms 후 autocorrect 실행
        suggestionDebounceTimer = Timer.scheduledTimer(withTimeInterval: 0.08, repeats: false) { [weak self] _ in
            guard let self = self else { return }
            let suggestions = self.autocorrectEngine.suggestions(for: word, language: language)
            if suggestions.isEmpty {
                completion(SuggestionResult(mode: .none, suggestions: []))
            } else {
                completion(SuggestionResult(mode: .autocorrect, suggestions: suggestions))
            }
        }
    }

    private func extractContextWords(from context: String?) -> [String] {
        guard let context = context else { return [] }
        let words = context.components(separatedBy: CharacterSet.whitespacesAndNewlines)
            .filter { !$0.isEmpty }
        return Array(words.suffix(2))
    }
}
