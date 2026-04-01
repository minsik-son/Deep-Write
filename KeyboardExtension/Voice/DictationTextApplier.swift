import UIKit

enum DictationApplyMode {
    case finalOnly
    case rollbackLive
}

final class DictationTextApplier {

    var mode: DictationApplyMode = .rollbackLive

    private var state = RollbackState()
    private var lastApplyTime: Date = .distantPast
    private var pendingPayload: DictationStatePayload?
    private var pendingTimer: Timer?

    weak var overlay: DictationOverlayView?

    // MARK: - Public API

    func reset(sessionId: String) {
        state = RollbackState()
        state.sessionId = sessionId
        lastApplyTime = .distantPast
        pendingPayload = nil
        pendingTimer?.invalidate()
        pendingTimer = nil
    }

    /// Clear: 현재 세션이 삽입한 text만 지운다
    func clearInsertedText(proxy: UITextDocumentProxy) {
        guard state.lastInsertedLength > 0 else {
            overlay?.updatePreviewOnly("")
            return
        }

        if !state.isContextBroken {
            rollbackDelete(count: state.lastInsertedLength, proxy: proxy)
        }

        state.lastInsertedText = ""
        state.lastInsertedLength = 0
        state.currentPartialText = ""
        state.isContextBroken = false
        overlay?.updatePreviewOnly("")
    }

    func applyPartial(_ payload: DictationStatePayload, proxy: UITextDocumentProxy) {
        guard mode == .rollbackLive else {
            // finalOnly mode: only update overlay preview
            overlay?.updatePreviewOnly(payload.partialText)
            return
        }

        guard payload.version > state.lastAppliedVersion else { return }

        let now = Date()
        let minInterval = Double(DictationConstants.Limits.extensionPartialThrottleMs) / 1000.0
        let elapsed = now.timeIntervalSince(lastApplyTime)
        if elapsed < minInterval {
            pendingPayload = payload
            schedulePendingApply(after: minInterval - elapsed, proxy: proxy)
            return
        }

        executePartialApply(payload, proxy: proxy)
    }

    func applyFinal(_ payload: DictationStatePayload, proxy: UITextDocumentProxy) {
        guard payload.version > state.lastAppliedVersion else { return }
        state.lastAppliedVersion = payload.version

        let finalText = payload.finalText ?? payload.partialText

        if mode == .finalOnly {
            // Direct insertion — no rollback needed
            proxy.insertText(finalText)
            cleanupRollbackState()
            return
        }

        // rollbackLive: clean up previous partial then insert final
        let currentTailRaw = proxy.documentContextBeforeInput ?? ""
        let currentTail = normalized(currentTailRaw, locale: payload.locale)
        let normalizedLast = normalized(state.lastInsertedText, locale: payload.locale)

        if !state.isContextBroken && currentTail.hasSuffix(normalizedLast) {
            rollbackDelete(count: state.lastInsertedLength, proxy: proxy)
            proxy.insertText(finalText)
            state.committedFinalText = finalText
            cleanupRollbackState()
            return
        }

        if state.isContextBroken && state.lastInsertedLength > 0 && currentTail.hasSuffix(normalizedLast) {
            rollbackDelete(count: state.lastInsertedLength, proxy: proxy)
            proxy.insertText(finalText)
            state.committedFinalText = finalText
            cleanupRollbackState()
            return
        }

        // Cannot rollback — show confirmation on overlay
        overlay?.updatePreviewOnly("⚠ Tap to insert: \(String(finalText.prefix(40)))...")
    }

    // MARK: - Private Implementation

    private func executePartialApply(_ payload: DictationStatePayload, proxy: UITextDocumentProxy) {
        lastApplyTime = Date()
        state.lastAppliedVersion = payload.version

        if state.isContextBroken {
            state.currentPartialText = payload.partialText
            overlay?.updatePreviewOnly(payload.partialText)
            return
        }

        let currentTailRaw = proxy.documentContextBeforeInput ?? ""
        let currentTail = normalized(currentTailRaw, locale: payload.locale)
        let normalizedLast = normalized(state.lastInsertedText, locale: payload.locale)

        if state.lastInsertedLength == 0 {
            proxy.insertText(payload.partialText)
            state.lastInsertedText = payload.partialText
            state.lastInsertedLength = payload.partialText.count
            state.currentPartialText = payload.partialText
            overlay?.updatePreviewOnly(payload.partialText)
            return
        }

        guard currentTail.hasSuffix(normalizedLast) else {
            state.isContextBroken = true
            state.currentPartialText = payload.partialText
            overlay?.updatePreviewOnly(payload.partialText)
            return
        }

        rollbackDelete(count: state.lastInsertedLength, proxy: proxy)
        proxy.insertText(payload.partialText)
        state.lastInsertedText = payload.partialText
        state.lastInsertedLength = payload.partialText.count
        state.currentPartialText = payload.partialText
        overlay?.updatePreviewOnly(payload.partialText)
    }

    private func schedulePendingApply(after interval: TimeInterval, proxy: UITextDocumentProxy) {
        pendingTimer?.invalidate()
        pendingTimer = Timer.scheduledTimer(withTimeInterval: interval, repeats: false) { [weak self] _ in
            guard let self = self, let payload = self.pendingPayload else { return }
            self.pendingPayload = nil
            self.executePartialApply(payload, proxy: proxy)
        }
    }

    // MARK: - Helpers

    private func normalized(_ text: String, locale: String) -> String {
        return text.precomposedStringWithCanonicalMapping
    }

    private func rollbackDelete(count: Int, proxy: UITextDocumentProxy) {
        for _ in 0..<count {
            proxy.deleteBackward()
        }
    }

    private func cleanupRollbackState() {
        state.lastInsertedText = ""
        state.lastInsertedLength = 0
        state.isContextBroken = false
        state.currentPartialText = ""
        pendingPayload = nil
        pendingTimer?.invalidate()
        pendingTimer = nil
    }
}

// MARK: - Rollback State

private struct RollbackState {
    var sessionId: String?
    var lastInsertedText: String = ""
    var lastInsertedLength: Int = 0
    var lastAppliedVersion: UInt64 = 0
    var baseContextSnapshot: String = ""
    var currentPartialText: String = ""
    var committedFinalText: String?
    var isContextBroken: Bool = false
}
