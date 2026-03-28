import Foundation

struct DailyUsageData: Codable {
    var lastResetDate: Date
    var correctionCount: Int
    var translationCount: Int
    var bonusCorrection: Int
    var bonusTranslation: Int
    var rewardedAdCorrection: Int
    var rewardedAdTranslation: Int
    var composeCount: Int
    var bonusCompose: Int
    var rewardedAdCompose: Int
    var chatReplyCount: Int
    var bonusChatReply: Int
    var rewardedAdChatReply: Int

    static let empty = DailyUsageData(
        lastResetDate: Date(),
        correctionCount: 0,
        translationCount: 0,
        bonusCorrection: 0,
        bonusTranslation: 0,
        rewardedAdCorrection: 0,
        rewardedAdTranslation: 0,
        composeCount: 0,
        bonusCompose: 0,
        rewardedAdCompose: 0,
        chatReplyCount: 0,
        bonusChatReply: 0,
        rewardedAdChatReply: 0
    )

    init(lastResetDate: Date, correctionCount: Int, translationCount: Int, bonusCorrection: Int, bonusTranslation: Int, rewardedAdCorrection: Int, rewardedAdTranslation: Int, composeCount: Int = 0, bonusCompose: Int = 0, rewardedAdCompose: Int = 0, chatReplyCount: Int = 0, bonusChatReply: Int = 0, rewardedAdChatReply: Int = 0) {
        self.lastResetDate = lastResetDate
        self.correctionCount = correctionCount
        self.translationCount = translationCount
        self.bonusCorrection = bonusCorrection
        self.bonusTranslation = bonusTranslation
        self.rewardedAdCorrection = rewardedAdCorrection
        self.rewardedAdTranslation = rewardedAdTranslation
        self.composeCount = composeCount
        self.bonusCompose = bonusCompose
        self.rewardedAdCompose = rewardedAdCompose
        self.chatReplyCount = chatReplyCount
        self.bonusChatReply = bonusChatReply
        self.rewardedAdChatReply = rewardedAdChatReply
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        lastResetDate = try container.decode(Date.self, forKey: .lastResetDate)
        correctionCount = try container.decode(Int.self, forKey: .correctionCount)
        translationCount = try container.decode(Int.self, forKey: .translationCount)
        bonusCorrection = try container.decode(Int.self, forKey: .bonusCorrection)
        bonusTranslation = try container.decode(Int.self, forKey: .bonusTranslation)
        rewardedAdCorrection = try container.decode(Int.self, forKey: .rewardedAdCorrection)
        rewardedAdTranslation = try container.decode(Int.self, forKey: .rewardedAdTranslation)
        // 새 필드 — 기존 데이터에 없으면 0
        composeCount = try container.decodeIfPresent(Int.self, forKey: .composeCount) ?? 0
        bonusCompose = try container.decodeIfPresent(Int.self, forKey: .bonusCompose) ?? 0
        rewardedAdCompose = try container.decodeIfPresent(Int.self, forKey: .rewardedAdCompose) ?? 0
        chatReplyCount = try container.decodeIfPresent(Int.self, forKey: .chatReplyCount) ?? 0
        bonusChatReply = try container.decodeIfPresent(Int.self, forKey: .bonusChatReply) ?? 0
        rewardedAdChatReply = try container.decodeIfPresent(Int.self, forKey: .rewardedAdChatReply) ?? 0
    }
}
