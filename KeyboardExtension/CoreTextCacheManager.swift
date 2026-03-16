import Foundation
import CoreGraphics
import ObjectiveC
import os

/// CoreText가 내부적으로 사용하는 NSCache 인스턴스를 탐지·추적하여
/// 이모지 글리프 캐시를 전략적으로 클리어하는 매니저.
///
/// CoreText는 이모지를 렌더링할 때 각 글리프를 CGImage로 래스터라이즈하여
/// NSCache에 저장한다 (~65KB/글리프). 이 캐시는 didReceiveMemoryWarning에서도
/// 자동 퇴거되지 않으므로, 수동으로 removeAllObjects()를 호출해야 한다.
///
/// 동작 원리:
/// 1. NSCache.setObject(_:forKey:cost:)를 swizzle
/// 2. 저장되는 값이 CGImage인 NSCache 인스턴스를 CoreText 캐시로 판단
/// 3. 해당 인스턴스를 weak reference로 추적
/// 4. clearGlyphCaches() 호출 시 추적된 모든 캐시에 removeAllObjects()
final class CoreTextCacheManager {

    static let shared = CoreTextCacheManager()
    #if DEBUG
    private static let logger = Logger(subsystem: "com.translatorkeyboard.keyboard", category: "CoreTextCache")
    #endif
    private init() {}

    // MARK: - Properties

    /// CoreText 글리프 캐시로 탐지된 NSCache 인스턴스들 (weak 참조)
    private let trackedCaches = NSHashTable<NSCache<AnyObject, AnyObject>>.weakObjects()
    private let lock = NSLock()

    /// 원본 IMP 보관 (swizzle 전 구현체)
    private static var originalIMP: IMP?

    /// 중복 swizzle 방지 플래그
    private static var isActivated = false

    // MARK: - Activation (1회만 호출)

    /// 키보드 최초 로드 시 1회 호출. NSCache swizzling을 설정한다.
    /// viewDidLoad에서 호출할 것. 중복 호출 안전 (guard로 보호).
    ///
    /// ⚠️ 이 메서드는 #if DEBUG가 아님 — Release 빌드에서도 동작해야 한다.
    static func activate() {
        guard !isActivated else { return }
        isActivated = true

        // NSCache의 setObject:forKey:cost: 메서드를 swizzle
        // (setObject:forKey: 는 내부적으로 cost:0 으로 이 메서드를 호출)
        guard let nsCacheClass = NSClassFromString("NSCache"),
              let method = class_getInstanceMethod(nsCacheClass, sel_registerName("setObject:forKey:cost:"))
        else {
            #if DEBUG
            print("⚠️ CoreTextCacheManager: NSCache swizzle 대상 메서드를 찾을 수 없음")
            #endif
            return
        }

        // 원본 IMP 보존
        originalIMP = method_getImplementation(method)

        // 새 구현: 원본 호출 + CoreText 캐시 탐지
        // ⚠️ cost 파라미터는 NSUInteger → Swift에서 UInt (Int가 아님)
        let newBlock: @convention(block) (AnyObject, AnyObject, AnyObject, UInt) -> Void = {
            cacheObj, value, key, cost in

            // 원본 메서드 호출 (swizzle 전 구현체)
            typealias OriginalFunc = @convention(c) (AnyObject, Selector, AnyObject, AnyObject, UInt) -> Void
            let selector = sel_registerName("setObject:forKey:cost:")
            if let origIMP = CoreTextCacheManager.originalIMP {
                let original = unsafeBitCast(origIMP, to: OriginalFunc.self)
                original(cacheObj, selector, value, key, cost)
            }

            // CoreText 글리프 캐시 탐지: 값이 CGImage인 NSCache를 추적
            // CoreText는 글리프를 CGImage로 래스터라이즈하여 NSCache에 저장
            // 우리 앱의 ThemePatternRenderer는 UIImage를 저장하므로 오탐 없음
            if CFGetTypeID(value) == CGImage.typeID {
                if let cache = cacheObj as? NSCache<AnyObject, AnyObject> {
                    CoreTextCacheManager.shared.trackCache(cache)
                }
            }
        }

        let newIMP = imp_implementationWithBlock(newBlock)
        method_setImplementation(method, newIMP)

        #if DEBUG
        print("✅ CoreTextCacheManager: NSCache swizzle 활성화 완료")
        #endif
    }

    // MARK: - Cache Tracking

    /// CoreText 글리프 캐시로 판단된 NSCache를 등록
    private func trackCache(_ cache: NSCache<AnyObject, AnyObject>) {
        lock.lock()
        defer { lock.unlock() }
        // 이미 추적 중이면 스킵 (NSHashTable.contains는 O(1))
        if !trackedCaches.contains(cache) {
            trackedCaches.add(cache)
            #if DEBUG
            print("🔍 CoreTextCacheManager: 새 CoreText 캐시 탐지 (총 \(trackedCaches.count)개 추적 중)")
            #endif
        }
    }

    // MARK: - Cache Clearing

    /// 추적된 모든 CoreText 글리프 캐시를 클리어한다.
    /// 이모지 카테고리 전환, 이모지 뷰 dismiss, viewWillDisappear 시 호출.
    func clearGlyphCaches() {
        lock.lock()
        let caches = trackedCaches.allObjects
        lock.unlock()

        #if DEBUG
        let beforeCount = caches.count
        #endif

        // autoreleasepool로 감싸서 removeAllObjects 과정에서 생성되는
        // autorelease 임시 객체가 즉시 해제되도록 강제
        autoreleasepool {
            for cache in caches {
                cache.removeAllObjects()
            }
        }

        #if DEBUG
        Self.logger.info("🧹 CoreText glyph caches cleared: \(beforeCount) caches (with autoreleasepool)")
        #endif
    }

    /// 현재 추적 중인 캐시 개수 (디버그용)
    var trackedCacheCount: Int {
        lock.lock()
        defer { lock.unlock() }
        return trackedCaches.count
    }

    #if DEBUG
    /// 추적된 모든 CoreText 캐시에 들어있는 총 객체 수 추정
    /// NSCache는 직접적인 count API가 없으므로, countLimit을 확인하고
    /// 실제로는 removeAllObjects 전후 메모리 비교로 효과를 측정해야 함.
    /// 이 프로퍼티는 추적된 캐시의 countLimit 정보를 반환.
    var totalCachedObjectCount: String {
        lock.lock()
        let caches = trackedCaches.allObjects
        lock.unlock()
        var info: [String] = []
        for (i, cache) in caches.enumerated() {
            info.append("cache\(i): countLimit=\(cache.countLimit), totalCostLimit=\(cache.totalCostLimit)")
        }
        return info.isEmpty ? "no tracked caches" : info.joined(separator: ", ")
    }
    #endif
}
