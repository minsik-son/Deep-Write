import Foundation

enum HistoryType: String, Codable {
    case translation
    case correction
    case clipboard
    case chatReply
}

struct HistoryItem: Codable, Identifiable {
    let id: UUID
    let type: HistoryType
    let originalText: String
    let resultText: String?
    let metadata: String?
    let createdAt: Date
}
