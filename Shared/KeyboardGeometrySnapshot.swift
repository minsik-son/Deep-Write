import Foundation
import CoreGraphics

/// 키보드 익스텐션에서 실제 key center screen 좌표를 저장하고,
/// 메인 앱 calibration mirror가 동일한 screen position에 배치할 수 있게 한다.
struct KeyboardGeometrySnapshot: Codable {

    struct KeyFrame: Codable {
        var key: String
        var row: Int
        var col: Int
        var centerXInScreen: CGFloat
        var centerYInScreen: CGFloat
        var width: CGFloat
        var height: CGFloat
        var physicalSlotID: String?
    }

    var version: Int = 1
    var createdAt: Date
    var screenWidth: CGFloat
    var screenHeight: CGFloat
    var inputViewOriginYInScreen: CGFloat
    var inputViewHeight: CGFloat
    var keyFrames: [KeyFrame]
    var showNumberRow: Bool
    var orientationClass: String
    var layoutID: String

    // MARK: - App Group IO

    private static let storageKey = "keyboard_geometry_snapshot_v1"

    static func load() -> KeyboardGeometrySnapshot? {
        guard let defaults = UserDefaults(suiteName: AppConstants.appGroupIdentifier),
              let data = defaults.data(forKey: storageKey),
              let snapshot = try? JSONDecoder().decode(KeyboardGeometrySnapshot.self, from: data) else {
            return nil
        }
        return snapshot
    }

    func save() {
        guard let defaults = UserDefaults(suiteName: AppConstants.appGroupIdentifier),
              let data = try? JSONEncoder().encode(self) else { return }
        defaults.set(data, forKey: Self.storageKey)
    }

    /// Snapshot이 현재 기기/orientation과 호환되는지 확인
    func isCompatible(screenWidth: CGFloat, screenHeight: CGFloat) -> Bool {
        return abs(self.screenWidth - screenWidth) < 1
            && abs(self.screenHeight - screenHeight) < 1
            && !keyFrames.isEmpty
    }
}
