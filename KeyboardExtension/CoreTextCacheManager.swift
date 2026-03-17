import Foundation
import CoreGraphics
import ObjectiveC
import os

/// CoreText가 내부적으로 사용하는 NSCache 인스턴스를 탐지·추적하여
/// 이모지 글리프 캐시를 전략적으로 클리어하는 매니저.
///
/// Phase 4 v3 (SwiftKey 방식 적용):
/// - setObject:forKey: 와 setObject:forKey:cost: 양쪽 모두 swizzle
/// - activate()를 KeyboardViewController.init()에서 호출 (viewDidLoad보다 이전)
/// - Thread-local 재진입 가드로 이중 카운팅 방지 + 스레드 안전
/// - defer로 예외 시에도 플래그 복구 보장
/// - 블록 static 유지로 use-after-free 방지
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

    /// 원본 IMP 보관
    private static var originalSetObjectForKeyCostIMP: IMP?
    private static var originalSetObjectForKeyIMP: IMP?

    /// 블록 유지용 (imp_implementationWithBlock의 블록이 해제되지 않도록)
    private static var retainedBlockCost: Any?
    private static var retainedBlockNoKey: Any?

    /// 중복 swizzle 방지
    private static var isActivated = false

    /// Thread-local 재진입 키
    private static let reentrantKey = "com.translatorkeyboard.CoreTextCacheManager.isInsideSwizzle"

    /// [DEBUG] 인터셉트 카운터
    #if DEBUG
    private static var interceptCountCost: Int = 0
    private static var interceptCountNoCost: Int = 0
    private static var cgImageCountCost: Int = 0
    private static var cgImageCountNoCost: Int = 0
    #endif

    // MARK: - Activation (1회만 호출)

    /// ⚠️ KeyboardViewController.init()에서 호출할 것 (viewDidLoad보다 이전).
    /// Release 빌드에서도 동작.
    static func activate() {
        guard !isActivated else { return }
        isActivated = true

        guard let nsCacheClass = NSClassFromString("NSCache") else {
            #if DEBUG
            logger.error("⚠️ CoreTextCacheManager: NSCache 클래스를 찾을 수 없음")
            #endif
            return
        }

        // ─── Swizzle 1: setObject:forKey:cost: ───
        if let methodCost = class_getInstanceMethod(nsCacheClass, sel_registerName("setObject:forKey:cost:")) {
            originalSetObjectForKeyCostIMP = method_getImplementation(methodCost)

            let blockCost: @convention(block) (AnyObject, AnyObject, AnyObject, UInt) -> Void = {
                cacheObj, value, key, cost in

                // Thread-local 재진입 체크
                let alreadyInside = Thread.current.threadDictionary[CoreTextCacheManager.reentrantKey] as? Bool ?? false

                if !alreadyInside {
                    Thread.current.threadDictionary[CoreTextCacheManager.reentrantKey] = true
                }
                defer {
                    if !alreadyInside {
                        Thread.current.threadDictionary[CoreTextCacheManager.reentrantKey] = false
                    }
                }

                // 원본 호출
                typealias OrigFunc = @convention(c) (AnyObject, Selector, AnyObject, AnyObject, UInt) -> Void
                let sel = sel_registerName("setObject:forKey:cost:")
                if let imp = CoreTextCacheManager.originalSetObjectForKeyCostIMP {
                    let orig = unsafeBitCast(imp, to: OrigFunc.self)
                    orig(cacheObj, sel, value, key, cost)
                }

                // 재진입이 아닌 경우에만 탐지 로직
                if !alreadyInside {
                    #if DEBUG
                    CoreTextCacheManager.interceptCountCost += 1
                    #endif

                    if CFGetTypeID(value) == CGImage.typeID {
                        #if DEBUG
                        CoreTextCacheManager.cgImageCountCost += 1
                        #endif
                        if let cache = cacheObj as? NSCache<AnyObject, AnyObject> {
                            CoreTextCacheManager.shared.trackCache(cache, source: "cost")
                        }
                    }
                }
            }

            retainedBlockCost = blockCost
            method_setImplementation(methodCost, imp_implementationWithBlock(blockCost))
        }

        // ─── Swizzle 2: setObject:forKey: (SwiftKey 방식 핵심) ───
        if let methodNoKey = class_getInstanceMethod(nsCacheClass, sel_registerName("setObject:forKey:")) {
            originalSetObjectForKeyIMP = method_getImplementation(methodNoKey)

            let blockNoKey: @convention(block) (AnyObject, AnyObject, AnyObject) -> Void = {
                cacheObj, value, key in

                // Thread-local 재진입 가드 설정
                Thread.current.threadDictionary[CoreTextCacheManager.reentrantKey] = true
                defer {
                    Thread.current.threadDictionary[CoreTextCacheManager.reentrantKey] = false
                }

                // 원본 호출 (내부적으로 setObject:forKey:cost:를 호출할 수 있음)
                typealias OrigFunc = @convention(c) (AnyObject, Selector, AnyObject, AnyObject) -> Void
                let sel = sel_registerName("setObject:forKey:")
                if let imp = CoreTextCacheManager.originalSetObjectForKeyIMP {
                    let orig = unsafeBitCast(imp, to: OrigFunc.self)
                    orig(cacheObj, sel, value, key)
                }

                #if DEBUG
                CoreTextCacheManager.interceptCountNoCost += 1
                #endif

                // CGImage 탐지
                if CFGetTypeID(value) == CGImage.typeID {
                    #if DEBUG
                    CoreTextCacheManager.cgImageCountNoCost += 1
                    #endif
                    if let cache = cacheObj as? NSCache<AnyObject, AnyObject> {
                        CoreTextCacheManager.shared.trackCache(cache, source: "noKey")
                    }
                }
            }

            retainedBlockNoKey = blockNoKey
            method_setImplementation(methodNoKey, imp_implementationWithBlock(blockNoKey))
        }

        #if DEBUG
        logger.info("✅ CoreTextCacheManager Phase4v3: 듀얼 swizzle 활성화 완료")
        #endif
    }

    // MARK: - Cache Tracking

    private func trackCache(_ cache: NSCache<AnyObject, AnyObject>, source: String) {
        lock.lock()
        defer { lock.unlock() }
        if !trackedCaches.contains(cache) {
            trackedCaches.add(cache)
            #if DEBUG
            Self.logger.info("🔍 CoreTextCacheManager: 새 캐시 탐지 via \(source) (총 \(self.trackedCaches.count)개 추적 중)")
            #endif
        }
    }

    // MARK: - Cache Clearing

    /// 추적된 모든 CoreText 글리프 캐시를 클리어한다.
    func clearGlyphCaches() {
        lock.lock()
        let caches = trackedCaches.allObjects
        let cacheCount = caches.count
        lock.unlock()

        #if DEBUG
        let beforeMB = Self.currentPhysFootprint()
        #endif

        autoreleasepool {
            for cache in caches {
                cache.removeAllObjects()
            }
        }

        #if DEBUG
        let afterMB = Self.currentPhysFootprint()
        let deltaMB = afterMB - beforeMB
        Self.logger.info("🧹 CoreText glyph caches cleared: \(cacheCount) caches (with autoreleasepool)")
        Self.logger.info("🧹 clearGlyphCaches phys_footprint: \(beforeMB, format: .fixed(precision: 4)) → \(afterMB, format: .fixed(precision: 4)) MB (delta: \(deltaMB, format: .fixed(precision: 4)) MB)")
        #endif
    }

    /// 현재 추적 중인 캐시 개수
    var trackedCacheCount: Int {
        lock.lock()
        defer { lock.unlock() }
        return trackedCaches.count
    }

    // MARK: - Memory Measurement (DEBUG only)

    #if DEBUG
    private static func currentPhysFootprint() -> Double {
        var info = task_vm_info_data_t()
        var count = mach_msg_type_number_t(MemoryLayout<task_vm_info>.size / MemoryLayout<integer_t>.size)
        let result = withUnsafeMutablePointer(to: &info) {
            $0.withMemoryRebound(to: integer_t.self, capacity: Int(count)) {
                task_info(mach_task_self_, task_flavor_t(TASK_VM_INFO), $0, &count)
            }
        }
        guard result == KERN_SUCCESS else { return 0 }
        return Double(info.phys_footprint) / (1024 * 1024)
    }
    #endif

    // MARK: - Diagnostics (DEBUG)

    #if DEBUG
    /// 인터셉트 통계 로깅
    static func logInterceptStats() {
        logger.info("📊 [Swizzle Stats] setObject:forKey:cost: 호출 \(interceptCountCost)회, CGImage 탐지 \(cgImageCountCost)회")
        logger.info("📊 [Swizzle Stats] setObject:forKey: 호출 \(interceptCountNoCost)회, CGImage 탐지 \(cgImageCountNoCost)회")
        logger.info("📊 [Swizzle Stats] 추적 중인 캐시: \(shared.trackedCacheCount)개")
    }

    /// 인터셉트 카운터 리셋
    static func resetInterceptCounters() {
        interceptCountCost = 0
        interceptCountNoCost = 0
        cgImageCountCost = 0
        cgImageCountNoCost = 0
    }

    /// 추적된 캐시 상세 정보
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
