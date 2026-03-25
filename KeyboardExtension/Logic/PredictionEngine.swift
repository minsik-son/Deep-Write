import Foundation

final class PredictionEngine {
    private var trigrams: [String: [(String, Int)]] = [:]
    private var bigrams: [String: [(String, Int)]] = [:]
    private var unigrams: [(String, Int)] = []
    private var loadedLanguage: String?
    private var isLoading = false
    private let loadQueue = DispatchQueue(label: "com.translatorkeyboard.prediction.load",
                                          qos: .userInitiated)

    /// 비동기 모델 로딩. 완료 시 completion 호출 (메인 스레드).
    /// ⚠️ 반드시 메인 스레드에서 호출할 것 (isLoading thread safety)
    func loadModel(for language: String, completion: (() -> Void)? = nil) {
        assert(Thread.isMainThread, "loadModel must be called on main thread")
        guard language != loadedLanguage, !isLoading else {
            completion?()
            return
        }

        isLoading = true

        loadQueue.async { [weak self] in
            guard let self = self else { return }

            let fileName = "ngram_\(language)"
            guard let url = Bundle(for: type(of: self)).url(forResource: fileName, withExtension: "json"),
                  let data = try? Data(contentsOf: url),
                  let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
                DispatchQueue.main.async {
                    self.trigrams = [:]
                    self.bigrams = [:]
                    self.unigrams = []
                    self.loadedLanguage = nil
                    self.isLoading = false
                    completion?()
                }
                return
            }

            // 백그라운드에서 파싱
            var newTrigrams: [String: [(String, Int)]] = [:]
            var newBigrams: [String: [(String, Int)]] = [:]
            var newUnigrams: [(String, Int)] = []

            if let trigramData = json["trigrams"] as? [String: [[Any]]] {
                newTrigrams = trigramData.mapValues { entries in
                    entries.compactMap { entry in
                        guard entry.count >= 2,
                              let word = entry[0] as? String,
                              let freq = entry[1] as? Int else { return nil }
                        return (word, freq)
                    }
                }
            }

            if let bigramData = json["bigrams"] as? [String: [[Any]]] {
                newBigrams = bigramData.mapValues { entries in
                    entries.compactMap { entry in
                        guard entry.count >= 2,
                              let word = entry[0] as? String,
                              let freq = entry[1] as? Int else { return nil }
                        return (word, freq)
                    }
                }
            }

            if let unigramData = json["unigrams"] as? [[Any]] {
                newUnigrams = unigramData.compactMap { entry in
                    guard entry.count >= 2,
                          let word = entry[0] as? String,
                          let freq = entry[1] as? Int else { return nil }
                    return (word, freq)
                }
            }

            // 메인 스레드에서 데이터 교체
            DispatchQueue.main.async {
                self.trigrams = newTrigrams
                self.bigrams = newBigrams
                self.unigrams = newUnigrams
                self.loadedLanguage = language
                self.isLoading = false
                #if DEBUG
                var info = task_vm_info_data_t()
                var count = mach_msg_type_number_t(MemoryLayout<task_vm_info>.size / MemoryLayout<integer_t>.size)
                let result = withUnsafeMutablePointer(to: &info) {
                    $0.withMemoryRebound(to: integer_t.self, capacity: Int(count)) {
                        task_info(mach_task_self_, task_flavor_t(TASK_VM_INFO), $0, &count)
                    }
                }
                if result == KERN_SUCCESS {
                    let mb = Float(info.phys_footprint) / (1024 * 1024)
                    print("🔬 PredictionEngine loaded — trigrams:\(self.trigrams.count) bigrams:\(self.bigrams.count) unigrams:\(self.unigrams.count) — Memory: \(String(format: "%.2f", mb)) MB")
                }
                #endif
                completion?()
            }
        }
    }

    /// 모델이 로드되었는지 확인
    var isModelLoaded: Bool {
        return loadedLanguage != nil && !isLoading
    }

    func predict(context: [String], limit: Int = 3) -> [String] {
        var scored: [String: Double] = [:]

        let normalizedContext = context.map { $0.lowercased() }

        // Trigram lookup: last 2 words
        if normalizedContext.count >= 2 {
            let key = normalizedContext.suffix(2).joined(separator: " ")
            if let matches = trigrams[key] {
                for (word, freq) in matches {
                    scored[word, default: 0] += Double(freq) * 1.0
                }
            }
        }

        // Bigram fallback: last 1 word
        if let lastWord = normalizedContext.last {
            if let matches = bigrams[lastWord] {
                for (word, freq) in matches {
                    scored[word, default: 0] += Double(freq) * 0.4
                }
            }
        }

        // Unigram fallback
        for (word, freq) in unigrams {
            scored[word, default: 0] += Double(freq) * 0.16
        }

        let sorted = scored.sorted { $0.value > $1.value }
        return Array(sorted.prefix(limit).map { $0.key })
    }

    /// Phase 3: next character probability distribution from unigram data
    func nextCharacterProbabilities(prefix: String) -> [Character: Float] {
        guard !prefix.isEmpty, isModelLoaded else { return [:] }

        let lowerPrefix = prefix.lowercased()
        var charFreq: [Character: Int] = [:]
        var totalFreq: Int = 0

        for (word, freq) in unigrams {
            let lowerWord = word.lowercased()
            guard lowerWord.hasPrefix(lowerPrefix),
                  lowerWord.count > lowerPrefix.count else { continue }

            let nextIndex = lowerWord.index(lowerWord.startIndex, offsetBy: lowerPrefix.count)
            let nextChar = lowerWord[nextIndex]

            guard nextChar.isLetter && nextChar.isASCII else { continue }

            charFreq[nextChar, default: 0] += freq
            totalFreq += freq
        }

        guard totalFreq > 0 else { return [:] }

        var probs: [Character: Float] = [:]
        for (char, freq) in charFreq {
            probs[char] = Float(freq) / Float(totalFreq)
        }
        return probs
    }
}
