import Foundation

/// Calibration seed model — 메인 앱에서 생성, 키보드 익스텐션에서 로드
/// App Group을 통해 양쪽이 공유
struct CalibrationSeedModel: Codable {

    // MARK: - Row Seeds

    struct RowSeed: Codable {
        var rowID: Int              // 0=top, 1=middle, 2=bottom
        var meanOffsetX: Float
        var meanOffsetY: Float
        var confidence: Float       // 0.0 ~ 1.0
        var recommendedPriorSampleCount: UInt16  // 권장 30~35
    }

    // MARK: - Global Seed

    struct GlobalSeed: Codable {
        var shiftX: Float
        var shiftY: Float
        var confidence: Float
    }

    // MARK: - Per-Slot Seed

    struct SlotSeed: Codable {
        var physicalSlotID: String  // 예: "row0_col3" 또는 key label
        var shiftX: Float
        var shiftY: Float
        var confidence: Float
        var sampleCount: UInt16
    }

    // MARK: - Metadata

    struct Metadata: Codable {
        var modelVersion: Int
        var createdAt: Date
        var layoutID: String        // 예: "english_letters", "korean_letters"
        var orientationClass: String // "portrait" / "landscape"
    }

    // MARK: - Data

    var rowSeeds: [RowSeed]
    var globalSeed: GlobalSeed?
    var slotSeeds: [SlotSeed]
    var metadata: Metadata

    // MARK: - App Group IO

    private static let storageKey = "calibration_seed_model_v1"

    static func load() -> CalibrationSeedModel? {
        guard let defaults = UserDefaults(suiteName: AppConstants.appGroupIdentifier),
              let data = defaults.data(forKey: storageKey),
              let model = try? JSONDecoder().decode(CalibrationSeedModel.self, from: data) else {
            return nil
        }
        return model
    }

    func save() {
        guard let defaults = UserDefaults(suiteName: AppConstants.appGroupIdentifier),
              let data = try? JSONEncoder().encode(self) else { return }
        defaults.set(data, forKey: Self.storageKey)
    }

    /// re-calibration reset 시 기존 모델 제거
    static func remove() {
        UserDefaults(suiteName: AppConstants.appGroupIdentifier)?.removeObject(forKey: storageKey)
    }
}
