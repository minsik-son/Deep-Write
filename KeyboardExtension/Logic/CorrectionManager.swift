import UIKit

protocol CorrectionManagerDelegate: AnyObject {
    func correctionManager(_ manager: CorrectionManager, didCorrect text: String, language: String)
    func correctionManager(_ manager: CorrectionManager, didFailWithError error: TranslationError)
    func correctionManagerDidStartCorrecting(_ manager: CorrectionManager)
}

class CorrectionManager {

    weak var delegate: CorrectionManagerDelegate?

    private let cache = TranslationCache.shared
    private var session: URLSession { SharedNetworkSession.shared }
    private var debounceWorkItem: DispatchWorkItem?
    private var lastCorrectedText: String = ""
    private var retryCount = 0
    private let maxRetries = 1
    private var currentGeneration: Int = 0

    private var languageCode: String = "ko"
    private var toneStyle: ToneStyle = .none

    func setLanguage(_ code: String) {
        self.languageCode = code
    }

    func setTone(_ tone: ToneStyle) {
        self.toneStyle = tone
    }

    func requestCorrection(text: String) {
        debounceWorkItem?.cancel()

        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty, trimmed != lastCorrectedText else { return }

        if let cached = cache.get(text: trimmed, source: "correct_\(toneStyle.rawValue)", target: languageCode) {
            currentGeneration += 1
            lastCorrectedText = trimmed
            delegate?.correctionManager(self, didCorrect: cached, language: languageCode)
            return
        }

        let workItem = DispatchWorkItem { [weak self] in
            self?.performCorrection(text: trimmed)
        }
        debounceWorkItem = workItem
        DispatchQueue.main.asyncAfter(deadline: .now() + FeatureGate.shared.debounceDuration, execute: workItem)
    }

    func cancelPending() {
        debounceWorkItem?.cancel()
        debounceWorkItem = nil
        currentGeneration += 1
    }

    func reset() {
        lastCorrectedText = ""
        cancelPending()
    }

    private func performCorrection(text: String) {
        delegate?.correctionManagerDidStartCorrecting(self)
        currentGeneration += 1
        retryCount = 0
        executeRequest(text: text, generation: currentGeneration)
    }

    private func executeRequest(text: String, generation: Int) {
        let urlString = AppConstants.API.baseURL + AppConstants.API.correctEndpoint
        guard let url = URL(string: urlString) else { return }

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")

        let deviceId = UIDevice.current.identifierForVendor?.uuidString ?? "unknown"
        let tier = SubscriptionStatus.shared.currentTier.rawValue

        let body: [String: Any] = [
            "text": text,
            "language": languageCode,
            "tone": toneStyle.rawValue,
            "tier": tier,
            "deviceId": deviceId,
            "model": FeatureGate.shared.apiModelName
        ]

        request.httpBody = try? JSONSerialization.data(withJSONObject: body)

        let task = session.dataTask(with: request) { [weak self] data, response, error in
            DispatchQueue.main.async {
                self?.handleResponse(text: text, generation: generation, data: data, response: response, error: error)
            }
        }
        task.resume()
    }

    private func handleResponse(text: String, generation: Int, data: Data?, response: URLResponse?, error: Error?) {
        // Discard stale responses — only process the latest generation
        guard generation == currentGeneration else { return }

        if let error = error {
            let nsError = error as NSError
            if nsError.code == NSURLErrorTimedOut {
                if retryCount < maxRetries {
                    retryCount += 1
                    executeRequest(text: text, generation: generation)
                    return
                }
                delegate?.correctionManager(self, didFailWithError: .timeout)
            } else if nsError.code == NSURLErrorNotConnectedToInternet {
                delegate?.correctionManager(self, didFailWithError: .offline)
            } else {
                if retryCount < maxRetries {
                    retryCount += 1
                    executeRequest(text: text, generation: generation)
                    return
                }
                delegate?.correctionManager(self, didFailWithError: .networkError(error))
            }
            return
        }

        guard let httpResponse = response as? HTTPURLResponse,
              let data = data else {
            delegate?.correctionManager(self, didFailWithError: .invalidResponse)
            return
        }

        if httpResponse.statusCode == 429 {
            if let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
               let retryAfter = json["retryAfter"] as? Int {
                delegate?.correctionManager(self, didFailWithError: .rateLimited(retryAfter))
            }
            return
        }

        guard httpResponse.statusCode == 200 else {
            let errorMsg = String(data: data, encoding: .utf8) ?? "Unknown error"
            delegate?.correctionManager(self, didFailWithError: .serverError(httpResponse.statusCode, errorMsg))
            return
        }

        guard let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let correctedText = json["correctedText"] as? String else {
            delegate?.correctionManager(self, didFailWithError: .invalidResponse)
            return
        }

        cache.set(text: text, source: "correct_\(toneStyle.rawValue)", target: languageCode, translatedText: correctedText)
        lastCorrectedText = text

        // Log to session (stats는 세션 종료 시 CompositionSessionManager에서 처리)
        CompositionSessionManager.shared.recordAPICall(sourceText: text, resultText: correctedText, mode: .correct)

        #if DEBUG
        var memInfo = task_vm_info_data_t()
        var memCount = mach_msg_type_number_t(MemoryLayout<task_vm_info>.size / MemoryLayout<integer_t>.size)
        let memResult = withUnsafeMutablePointer(to: &memInfo) {
            $0.withMemoryRebound(to: integer_t.self, capacity: Int(memCount)) {
                task_info(mach_task_self_, task_flavor_t(TASK_VM_INFO), $0, &memCount)
            }
        }
        if memResult == KERN_SUCCESS {
            let mb = Float(memInfo.phys_footprint) / (1024 * 1024)
            print("🔬 Correction response received — Memory: \(String(format: "%.2f", mb)) MB, cache: \(TranslationCache.shared.debugCacheInfo)")
        }
        #endif

        // 카운트는 세션 종료 시 CompositionSessionManager에서 1회만 기록
        delegate?.correctionManager(self, didCorrect: correctedText, language: languageCode)
    }
}
