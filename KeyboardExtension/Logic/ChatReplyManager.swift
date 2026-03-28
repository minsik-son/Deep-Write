import Foundation
import UIKit

protocol ChatReplyManagerDelegate: AnyObject {
    func chatReplyManager(_ manager: ChatReplyManager, didGenerate replies: [String])
    func chatReplyManager(_ manager: ChatReplyManager, didFailWith error: String)
}

final class ChatReplyManager {

    weak var delegate: ChatReplyManagerDelegate?

    private var currentTask: URLSessionDataTask?
    private var generationCounter: Int = 0
    private let maxRetries = 1
    private var retryCount = 0

    private var deviceId: String {
        return UIDevice.current.identifierForVendor?.uuidString ?? "unknown"
    }

    // MARK: - Public

    func generate(request: ChatReplyRequest) {
        cancelPending()
        retryCount = 0
        generationCounter += 1

        if let cached = ChatReplyCache.shared.get(
            context: request.context,
            tone: request.tone,
            direction: request.direction
        ) {
            let gen = generationCounter
            DispatchQueue.main.async { [weak self] in
                guard let self = self, gen == self.generationCounter else { return }
                self.delegate?.chatReplyManager(self, didGenerate: cached)
            }
            return
        }

        executeRequest(request: request, generation: generationCounter)
    }

    func cancelPending() {
        currentTask?.cancel()
        currentTask = nil
    }

    func clearCache() {
        cancelPending()
        generationCounter = 0
        retryCount = 0
    }

    // MARK: - Private

    private func executeRequest(request: ChatReplyRequest, generation: Int) {
        guard let urlRequest = buildRequest(request) else {
            delegate?.chatReplyManager(self, didFailWith: L("chatreply.error.invalid_request"))
            return
        }

        currentTask = SharedNetworkSession.shared.dataTask(with: urlRequest) { [weak self] data, response, error in
            DispatchQueue.main.async {
                guard let self = self else { return }
                guard generation == self.generationCounter else { return }

                if let error = error {
                    let nsError = error as NSError
                    if nsError.code == NSURLErrorCancelled { return }

                    if nsError.code == NSURLErrorTimedOut || nsError.code == NSURLErrorNotConnectedToInternet {
                        if self.retryCount < self.maxRetries {
                            self.retryCount += 1
                            self.executeRequest(request: request, generation: generation)
                            return
                        }
                    }

                    let errorMsg = nsError.code == NSURLErrorTimedOut ?
                        L("chatreply.error.timeout") :
                        nsError.code == NSURLErrorNotConnectedToInternet ?
                        L("chatreply.error.no_internet") :
                        L("chatreply.error.network")
                    self.delegate?.chatReplyManager(self, didFailWith: errorMsg)
                    return
                }

                guard let data = data else {
                    self.delegate?.chatReplyManager(self, didFailWith: L("chatreply.error.empty"))
                    return
                }

                guard data.count < 50_000 else {
                    self.delegate?.chatReplyManager(self, didFailWith: L("chatreply.error.too_large"))
                    return
                }

                if let httpResponse = response as? HTTPURLResponse {
                    if httpResponse.statusCode == 429 {
                        self.delegate?.chatReplyManager(self, didFailWith: L("chatreply.error.rate_limit"))
                        return
                    }
                    guard (200...299).contains(httpResponse.statusCode) else {
                        self.delegate?.chatReplyManager(self, didFailWith: L("chatreply.error.server"))
                        return
                    }
                }

                do {
                    let decoded = try JSONDecoder().decode(ChatReplyResponse.self, from: data)
                    let replies = decoded.replies.prefix(3).map { String($0.prefix(500)) }
                    if replies.isEmpty {
                        self.delegate?.chatReplyManager(self, didFailWith: L("chatreply.error.no_replies"))
                    } else {
                        ChatReplyCache.shared.set(
                            context: request.context,
                            tone: request.tone,
                            direction: request.direction,
                            replies: Array(replies)
                        )
                        self.delegate?.chatReplyManager(self, didGenerate: Array(replies))
                    }
                } catch {
                    self.delegate?.chatReplyManager(self, didFailWith: L("chatreply.error.parse"))
                }
            }
        }
        currentTask?.resume()
    }

    private func buildRequest(_ request: ChatReplyRequest) -> URLRequest? {
        guard let url = URL(string: AppConstants.API.baseURL + "/api/chat-reply/generate") else { return nil }

        var urlRequest = URLRequest(url: url)
        urlRequest.httpMethod = "POST"
        urlRequest.setValue("application/json", forHTTPHeaderField: "Content-Type")

        let body: [String: Any] = [
            "context": request.context,
            "tone": request.tone,
            "direction": request.direction,
            "language": request.language,
            "count": 3,
            "deviceId": deviceId
        ]

        urlRequest.httpBody = try? JSONSerialization.data(withJSONObject: body)
        return urlRequest
    }
}

struct ChatReplyResponse: Codable {
    let replies: [String]
}
