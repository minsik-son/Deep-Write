import UIKit

protocol TranslationManagerDelegate: AnyObject {
    func translationManager(_ manager: TranslationManager, didTranslate text: String, from source: String, to target: String)
    func translationManager(_ manager: TranslationManager, didFailWithError error: TranslationError)
    func translationManagerDidStartTranslating(_ manager: TranslationManager)
}

enum TranslationError: Error {
    case networkError(Error)
    case serverError(Int, String)
    case rateLimited(Int)
    case offline
    case timeout
    case invalidResponse
}

class TranslationManager {

    weak var delegate: TranslationManagerDelegate?

    private let cache = TranslationCache.shared
    private var session: URLSession { SharedNetworkSession.shared }
    private var debounceWorkItem: DispatchWorkItem?
    private var lastTranslatedText: String = ""
    private var retryCount = 0
    private let maxRetries = 1
    private var currentGeneration: Int = 0

    private var sourceLang: String = "ko"
    private var targetLang: String = "en"

    func setLanguages(source: String, target: String) {
        self.sourceLang = source
        self.targetLang = target
    }

    func requestTranslation(text: String) {
        debounceWorkItem?.cancel()

        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty, trimmed != lastTranslatedText else { return }

        // Check cache first (instant, no debounce needed)
        if let cached = cache.get(text: trimmed, source: sourceLang, target: targetLang) {
            currentGeneration += 1
            lastTranslatedText = trimmed
            delegate?.translationManager(self, didTranslate: cached, from: sourceLang, to: targetLang)
            return
        }

        let workItem = DispatchWorkItem { [weak self] in
            self?.performTranslation(text: trimmed)
        }
        debounceWorkItem = workItem
        DispatchQueue.main.asyncAfter(deadline: .now() + FeatureGate.shared.debounceDuration, execute: workItem)
    }

    func cancelPending() {
        debounceWorkItem?.cancel()
        debounceWorkItem = nil
        currentGeneration += 1
    }

    private func performTranslation(text: String) {
        delegate?.translationManagerDidStartTranslating(self)
        currentGeneration += 1
        retryCount = 0
        executeRequest(text: text, generation: currentGeneration)
    }

    private func executeRequest(text: String, generation: Int) {
        let urlString = AppConstants.API.baseURL + AppConstants.API.translateEndpoint
        guard let url = URL(string: urlString) else { return }

        let requestId = String(UUID().uuidString.prefix(8))
        let networkStartedAt = CFAbsoluteTimeGetCurrent()

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue(requestId, forHTTPHeaderField: "X-OneBoard-Request-ID")

        let deviceId = UIDevice.current.identifierForVendor?.uuidString ?? "unknown"
        let tier = SubscriptionStatus.shared.currentTier.rawValue

        let body: [String: Any] = [
            "text": text,
            "sourceLang": sourceLang,
            "targetLang": targetLang,
            "tier": tier,
            "deviceId": deviceId,
            "model": FeatureGate.shared.apiModelName,
            "requestId": requestId
        ]

        request.httpBody = try? JSONSerialization.data(withJSONObject: body)

        let charCount = text.count
        let src = sourceLang
        let tgt = targetLang
        let model = FeatureGate.shared.apiModelName
        let retry = retryCount

        let task = session.dataTask(with: request) { [weak self] data, response, error in
            let responseAt = CFAbsoluteTimeGetCurrent()
            let networkMs = Int((responseAt - networkStartedAt) * 1000)
            let statusCode = (response as? HTTPURLResponse)?.statusCode ?? 0
            let serverProvider = (response as? HTTPURLResponse)?.value(forHTTPHeaderField: "X-OneBoard-AI-Provider")
            let serverTimingMs = (response as? HTTPURLResponse)?.value(forHTTPHeaderField: "X-OneBoard-Server-Timing-Ms")

            #if DEBUG
            let stale = generation != self?.currentGeneration
            NSLog("[AI_LATENCY_CLIENT] requestId=%@ mode=translate cacheHit=false charCount=%d sourceLang=%@ targetLang=%@ tier=%@ requestedModel=%@ networkMs=%d statusCode=%d retryAttempt=%d stale=%d serverProvider=%@ serverTimingMs=%@",
                  requestId, charCount, src, tgt, tier, model, networkMs, statusCode, retry,
                  stale ? 1 : 0, serverProvider ?? "-", serverTimingMs ?? "-")
            #endif

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
                delegate?.translationManager(self, didFailWithError: .timeout)
            } else if nsError.code == NSURLErrorNotConnectedToInternet {
                delegate?.translationManager(self, didFailWithError: .offline)
            } else {
                if retryCount < maxRetries {
                    retryCount += 1
                    executeRequest(text: text, generation: generation)
                    return
                }
                delegate?.translationManager(self, didFailWithError: .networkError(error))
            }
            return
        }

        guard let httpResponse = response as? HTTPURLResponse else {
            delegate?.translationManager(self, didFailWithError: .invalidResponse)
            return
        }

        guard let data = data else {
            delegate?.translationManager(self, didFailWithError: .invalidResponse)
            return
        }

        if httpResponse.statusCode == 429 {
            let bodyRetryAfter: Int? = {
                guard let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else { return nil }
                return json["retryAfter"] as? Int
            }()
            let headerRetryAfter = Int(httpResponse.value(forHTTPHeaderField: "Retry-After") ?? "")
            let retryAfter = bodyRetryAfter ?? headerRetryAfter ?? 60
            delegate?.translationManager(self, didFailWithError: .rateLimited(retryAfter))
            return
        }

        guard httpResponse.statusCode == 200 else {
            let errorMsg = String(data: data, encoding: .utf8) ?? "Unknown error"
            delegate?.translationManager(self, didFailWithError: .serverError(httpResponse.statusCode, errorMsg))
            return
        }

        guard let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let translatedText = json["translatedText"] as? String else {
            delegate?.translationManager(self, didFailWithError: .invalidResponse)
            return
        }

        let normalized = translatedText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !normalized.isEmpty else {
            delegate?.translationManager(self, didFailWithError: .invalidResponse)
            return
        }

        cache.set(text: text, source: sourceLang, target: targetLang, translatedText: normalized)
        lastTranslatedText = text

        // Log to session (stats는 세션 종료 시 CompositionSessionManager에서 처리)
        CompositionSessionManager.shared.recordAPICall(sourceText: text, resultText: normalized, mode: .translate)

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
            print("🔬 Translation response received — Memory: \(String(format: "%.2f", mb)) MB, cache: \(TranslationCache.shared.debugCacheInfo)")
        }
        #endif

        // 카운트는 세션 종료 시 CompositionSessionManager에서 1회만 기록
        delegate?.translationManager(self, didTranslate: normalized, from: sourceLang, to: targetLang)
    }
}
