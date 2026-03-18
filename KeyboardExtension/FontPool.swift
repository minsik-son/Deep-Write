import UIKit

/// UIFont 인스턴스를 풀링하여 CoreText font descriptor 캐시 누적을 방지.
///
/// .systemFont(ofSize:) 를 매번 호출하면 CoreText가 내부 C++ font descriptor를
/// 프로세스 레벨 캐시에 누적. 동일한 (size, weight) 조합은 한 번만 생성하여 재사용.
///
/// 이 Phase에서는 파일 생성만 수행.
/// 기존 UIFont 호출 교체는 별도 Phase에서 진행.
enum FontPool {

    private static var cache: [String: UIFont] = [:]
    private static let lock = NSLock()

    /// systemFont 풀링
    static func systemFont(ofSize size: CGFloat, weight: UIFont.Weight = .regular) -> UIFont {
        let key = "sys_\(size)_\(weight.rawValue)"
        lock.lock()
        defer { lock.unlock() }

        if let cached = cache[key] {
            return cached
        }
        let font = UIFont.systemFont(ofSize: size, weight: weight)
        cache[key] = font
        return font
    }

    /// 메모리 경고 시 풀 정리
    static func clearIfNeeded() {
        lock.lock()
        defer { lock.unlock() }
        if cache.count > 30 {
            cache.removeAll()
        }
    }
}
