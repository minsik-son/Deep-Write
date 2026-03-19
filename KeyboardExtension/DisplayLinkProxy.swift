import UIKit

/// CADisplayLink 전용 프록시 — WeakProxy의 resolveInstanceMethod 문제를 우회.
/// ObjC 메시지 포워딩에 의존하지 않고 perform(_:with:)로 직접 호출.
final class DisplayLinkProxy: NSObject {
    weak var target: AnyObject?
    private let action: Selector

    init(target: AnyObject, action: Selector) {
        self.target = target
        self.action = action
        super.init()
    }

    /// CADisplayLink가 매 프레임 호출하는 메서드.
    /// target이 해제되면 displayLink를 자동 무효화하여 retain cycle 방지.
    @objc func proxyTick(_ displayLink: CADisplayLink) {
        guard let target = target else {
            displayLink.invalidate()
            return
        }
        _ = target.perform(action, with: displayLink)
    }
}
