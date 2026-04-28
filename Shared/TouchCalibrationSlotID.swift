import Foundation

/// Producer (메인 앱)와 Consumer (익스텐션)가 동일한 slot naming contract를 공유
enum TouchCalibrationSlotID {

    /// physicalSlotID 생성 — row/col 기반
    /// 예: "row0_col3", "row1_col5"
    static func make(row: Int, col: Int) -> String {
        return "row\(row)_col\(col)"
    }

    /// Letters page 기본 레이아웃 메타데이터
    /// English: row0=10, row1=9, row2=7(letters only, shift/backspace 제외)
    /// Korean:  row0=10, row1=9, row2=7(letters only)
    struct LayoutMetadata {
        let layoutID: String          // "english_letters", "korean_letters"
        let rowKeyCounts: [Int]       // [10, 9, 7] 등
        let orientationClass: String  // "portrait" / "landscape"

        /// 전체 slot 수
        var totalSlots: Int { rowKeyCounts.reduce(0, +) }

        /// 모든 physicalSlotID 목록 생성
        func allSlotIDs() -> [String] {
            var ids: [String] = []
            for (row, count) in rowKeyCounts.enumerated() {
                for col in 0..<count {
                    ids.append(TouchCalibrationSlotID.make(row: row, col: col))
                }
            }
            return ids
        }
    }

    /// 영어 portrait 기본 레이아웃 (number row 미포함, letters page character keys only)
    static let englishPortrait = LayoutMetadata(
        layoutID: "english_letters",
        rowKeyCounts: [10, 9, 7],  // q-p, a-l, z-m
        orientationClass: "portrait"
    )

    /// 한국어 portrait 기본 레이아웃
    static let koreanPortrait = LayoutMetadata(
        layoutID: "korean_letters",
        rowKeyCounts: [10, 9, 7],  // ㅂ-ㅔ, ㅁ-ㅣ, ㅋ-ㅎ
        orientationClass: "portrait"
    )
}
