import Foundation

/// CADisplayLink retain cycle 방지를 위한 weak proxy.
/// target이 해제된 후에도 크래시하지 않도록 안전장치 포함.
final class WeakProxy: NSObject {
    weak var target: AnyObject?

    init(target: AnyObject) {
        self.target = target
        super.init()
    }

    override func responds(to aSelector: Selector!) -> Bool {
        return target?.responds(to: aSelector) ?? false
    }

    override func forwardingTarget(for aSelector: Selector!) -> Any? {
        return target
    }

    /// target이 nil일 때 unrecognized selector 크래시 방지
    override class func resolveInstanceMethod(_ sel: Selector!) -> Bool {
        // 알 수 없는 selector에 대해 빈 구현 동적 추가
        let types = "v@:"  // void return, id self, SEL _cmd
        if let cTypes = types.cString(using: .ascii) {
            class_addMethod(self, sel, imp_implementationWithBlock({} as @convention(block) () -> Void), cTypes)
            return true
        }
        return super.resolveInstanceMethod(sel)
    }
}
