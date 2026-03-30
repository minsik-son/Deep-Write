import Foundation

final class DarwinNotificationBridge {
    static let shared = DarwinNotificationBridge()

    typealias Handler = () -> Void

    private let lock = NSLock()
    private var handlers: [String: [UUID: Handler]] = [:]

    private init() {}

    func post(_ name: String) {
        let center = CFNotificationCenterGetDarwinNotifyCenter()
        CFNotificationCenterPostNotification(
            center,
            CFNotificationName(name as CFString),
            nil,
            nil,
            true
        )
    }

    @discardableResult
    func addObserver(name: String, handler: @escaping Handler) -> UUID {
        let token = UUID()
        let needsRegistration: Bool

        lock.lock()
        needsRegistration = handlers[name] == nil
        handlers[name, default: [:]][token] = handler
        lock.unlock()

        if needsRegistration {
            let center = CFNotificationCenterGetDarwinNotifyCenter()
            CFNotificationCenterAddObserver(
                center,
                Unmanaged.passUnretained(self).toOpaque(),
                Self.callback,
                name as CFString,
                nil,
                .deliverImmediately
            )
        }

        return token
    }

    func removeObserver(name: String, token: UUID) {
        var shouldUnregister = false

        lock.lock()
        handlers[name]?[token] = nil
        if handlers[name]?.isEmpty == true {
            handlers[name] = nil
            shouldUnregister = true
        }
        lock.unlock()

        if shouldUnregister {
            let center = CFNotificationCenterGetDarwinNotifyCenter()
            CFNotificationCenterRemoveObserver(
                center,
                Unmanaged.passUnretained(self).toOpaque(),
                CFNotificationName(name as CFString),
                nil
            )
        }
    }

    private static let callback: CFNotificationCallback = { _, observer, name, _, _ in
        guard let observer else { return }
        let bridge = Unmanaged<DarwinNotificationBridge>
            .fromOpaque(observer)
            .takeUnretainedValue()
        guard let raw = name?.rawValue as String? else { return }
        bridge.dispatch(raw)
    }

    private func dispatch(_ name: String) {
        lock.lock()
        let closures = handlers[name]?.values.map { $0 } ?? []
        lock.unlock()
        closures.forEach { $0() }
    }
}
