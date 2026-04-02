import UIKit
import SwiftUI
import os.log

enum KeyboardMode {
    case defaultMode
    case translationMode
    case correctionMode
    case phraseInputMode
    case quickNoteMode
    case chatReplyMode
}

enum QuickNoteSubState {
    case list
    case reading(QuickNote)
    case editing(QuickNote?)
}

class KeyboardViewController: UIInputViewController {

    private var currentMode: KeyboardMode = .defaultMode

    // MARK: - Debug Logger
    private let kbLogger = Logger(subsystem: "com.translatorkeyboard.keyboard", category: "SettingsLink")
    private static let staticLogger = Logger(subsystem: "com.translatorkeyboard.keyboard", category: "SettingsLink")

    // MARK: - UI Components

    private lazy var toolbarView = ToolbarView()
    /// 프로세스 수명 동안 유지되는 단일 UIHostingController (SwiftUI 런타임 누적 방지)
    private static var sharedSettingsHC: UIHostingController<SettingsLinkView>?
    /// 현재 VC에서 사용 중인 참조 (weak — static이 소유권 보유)
    private weak var settingsLinkHostingController: UIHostingController<SettingsLinkView>?
    /// re-parent 시 이전 constraint를 명시적으로 정리하기 위한 참조
    private var settingsHCConstraints: [NSLayoutConstraint] = []
    private lazy var translationLanguageBar = TranslationLanguageBar()
    private lazy var translationInputView = TranslationInputView()
    private lazy var correctionLanguageBar = CorrectionLanguageBar()
    private lazy var correctionInputView = TranslationInputView()
    private lazy var keyboardLayoutView = KeyboardLayoutView()
    private var emojiKeyboardView: EmojiKeyboardView?
    private var languagePickerView: LanguagePickerView?
    private var savedPhrasesView: SavedPhrasesView?
    private var clipboardHistoryView: ClipboardHistoryView?
    private lazy var phraseInputHeaderView = PhraseInputHeaderView()
    private lazy var phraseInputView = TranslationInputView()
    private var isEmojiMode = false
    private var clipboardCheckTimer: Timer?
    private var lastKnownClipboardChangeCount: Int = 0

    // MARK: - QuickNote (CC-2: Optional + Lazy)
    private var quickNoteListView: QuickNoteListView?
    private var quickNoteReadView: QuickNoteReadView?
    private var quickNoteEditView: QuickNoteEditView?
    private var quickNoteTextInputHandler: TextInputHandler?
    private var quickNoteSubState: QuickNoteSubState = .list
    private var editingNote: QuickNote?
    private var quickNoteTopConstraint: NSLayoutConstraint?

    // MARK: - Calculator
    private var calculatorView: CalculatorView?
    private var modeBeforeCalculator: KeyboardMode?

    // MARK: - Chat Reply Generator
    private var chatReplyView: ChatReplyGeneratorView?
    private var chatReplyManager: ChatReplyManager?
    private var isShowingChatReply: Bool = false
    private var chatReplyExpandedHeight: CGFloat = 0

    // MARK: - Dictation
    private var dictationCoordinator: DictationSessionCoordinator?
    private var dictationOverlay: DictationOverlayView?
    private var dictationTextApplier: DictationTextApplier?
    private var isShowingDictation: Bool = false

    // MARK: - Logic Managers

    private let defaultTextInputHandler = TextInputHandler()
    private let modeTextInputHandler = TextInputHandler()
    private var defaultModeComposingLength: Int = 0
    private lazy var textProxyManager = TextProxyManager(textDocumentProxy: textDocumentProxy)
    private let translationManager = TranslationManager()
    private let correctionManager = CorrectionManager()
    private let sessionManager = SessionManager.shared
    private lazy var suggestionManager = SuggestionManager()

    // MARK: - Deferred View Setup Flags

    private var isTranslationViewsSetUp = false
    private var isCorrectionViewsSetUp = false
    private var isPhraseViewsSetUp = false

    // MARK: - Constraints

    private var heightConstraint: NSLayoutConstraint?
    private var keyboardTopToToolbarConstraint: NSLayoutConstraint?
    private var keyboardTopToTranslationConstraint: NSLayoutConstraint?
    private var keyboardTopToCorrectionConstraint: NSLayoutConstraint?
    private var translationInputHeightConstraint: NSLayoutConstraint?
    private var correctionInputHeightConstraint: NSLayoutConstraint?
    private var phraseInputHeightConstraint: NSLayoutConstraint?
    private var keyboardTopToPhraseInputConstraint: NSLayoutConstraint?
    private var keyboardLayoutHeightConstraint: NSLayoutConstraint?
    private var correctionInputTopConstraint: NSLayoutConstraint?
    private let hapticFeedback = UIImpactFeedbackGenerator(style: .medium)

    // Status message (floating toast)
    private var statusMessageTimer: DispatchWorkItem?
    private lazy var toastLabel: UILabel = {
        let label = UILabel()
        label.font = .systemFont(ofSize: 13, weight: .medium)
        label.textColor = .white
        label.textAlignment = .center
        label.backgroundColor = UIColor.black.withAlphaComponent(0.8)
        label.layer.cornerRadius = 8
        label.clipsToBounds = true
        label.numberOfLines = 1
        label.translatesAutoresizingMaskIntoConstraints = false
        label.isHidden = true
        label.isUserInteractionEnabled = false
        return label
    }()

    // MARK: - Cached Settings (UserDefaults I/O 최소화)
    /// viewDidLoad에서 1회 로드, viewWillAppear에서 갱신. 이후 메모리 캐시 사용.
    private var cachedIsAutocorrectEnabled: Bool = false
    private var cachedAutoCapitalize: Bool = true

    private var isAutocorrectEnabled: Bool {
        cachedIsAutocorrectEnabled
    }

    /// stale 결과 무시용 토큰
    private var pendingSuggestionToken: UUID?

    // Suggestion dismiss state
    private var isSuggestionDismissedForCurrentWord = false
    private var hasUserTypedSinceAppeared = false

    // Language state
    private var sourceLanguageCode: String = "ko"
    private var targetLanguageCode: String = "en"
    private var correctionLanguageCode: String = "ko"
    private var isLanguagePickerVisible = false

    // Tone state
    private var currentToneStyle: ToneStyle = .none
    private var tonePickerView: TonePickerView?
    private var isTonePickerVisible = false
    private var tonePickerHeightConstraint: NSLayoutConstraint?

    // MARK: - Layout Constants

    private struct Heights {
        static let toolbar: CGFloat = 40
        static let translationLanguageBar: CGFloat = 44
        static let translationInput: CGFloat = 44
        static let topPadding: CGFloat = 8
    }

    private func keyAreaHeight(for page: KeyboardPage? = nil) -> CGFloat {
        let effectivePage = page ?? keyboardLayoutView.currentPage

        let defaults = UserDefaults(suiteName: AppConstants.appGroupIdentifier)
        let showNumberRow = defaults?.object(forKey: AppConstants.UserDefaultsKeys.showNumberRow) == nil
            ? true
            : (defaults?.bool(forKey: AppConstants.UserDefaultsKeys.showNumberRow) ?? true)

        switch effectivePage {
        case .letters:
            return showNumberRow ? 270 : 222
        case .symbols1, .symbols2:
            return 270  // number row always visible in symbols
        }
    }

    // MARK: - Lifecycle

    override init(nibName nibNameOrNil: String?, bundle nibBundleOrNil: Bundle?) {
        super.init(nibName: nibNameOrNil, bundle: nibBundleOrNil)
        CoreTextCacheManager.activate()  // Phase 4: viewDidLoad보다 이전에 활성화
    }

    required init?(coder: NSCoder) {
        super.init(coder: coder)
        CoreTextCacheManager.activate()
    }

    deinit {
        #if DEBUG
        let deinitMemory = Self.measurePhysFootprint()
        kbLogger.warning("💀 KeyboardViewController DEINIT — pid=\(ProcessInfo.processInfo.processIdentifier) [cycle \(Self.lifecycleCount)]")
        kbLogger.warning("💀 children.count at deinit = \(self.children.count)")
        kbLogger.warning("💀 Memory at DEINIT: \(deinitMemory, format: .fixed(precision: 2)) MB (phys_footprint)")
        #endif

        // NotificationCenter 정리 (스레드 무관 — iOS 9+ 안전)
        NotificationCenter.default.removeObserver(self)

        // UIHostingController는 static으로 프로세스 수명 동안 유지
        // deinit에서 파괴하지 않음 — 다음 VC가 re-parent하여 재사용
        if let hc = settingsLinkHostingController, hc.parent === self {
            NSLayoutConstraint.deactivate(settingsHCConstraints)
            settingsHCConstraints = []
            hc.willMove(toParent: nil)
            hc.view.removeFromSuperview()
            hc.removeFromParent()
        }

        #if DEBUG
        let afterCleanup = Self.measurePhysFootprint()
        kbLogger.warning("💀 Memory after DEINIT cleanup: \(afterCleanup, format: .fixed(precision: 2)) MB (delta: \(afterCleanup - deinitMemory, format: .fixed(precision: 2)) MB)")

        // malloc pressure relief — DEINIT에서도 한번 더 시도
        Self.testMallocPressureRelief()
        Self.logMallocZoneStats()

        let finalMemory = Self.measurePhysFootprint()
        kbLogger.warning("💀 DEINIT final (pressure_relief 후): \(finalMemory, format: .fixed(precision: 2)) MB")
        Self.diagnoseMemoryBreakdown()

        // 다음 사이클 viewDidLoad에서 비교할 수 있도록 저장
        Self.lastDeinitMemory = finalMemory
        CoreTextCacheManager.logInterceptStats()
        #endif
    }

    override func viewDidLoad() {
        super.viewDidLoad()
        NSLog("══════════════════════════════════════")
        NSLog("═══  Keyboard Loaded  ═══")
        NSLog("══════════════════════════════════════")
        // CoreTextCacheManager.activate()는 init()으로 이동됨 (Phase 4)
        #if DEBUG
        CoreTextCacheManager.resetInterceptCounters()
        kbLogger.info("📊 [Phase4] Swizzle 인터셉트 카운터 리셋")
        kbLogger.info("📌 viewDidLoad START — pid=\(ProcessInfo.processInfo.processIdentifier)")
        kbLogger.info("📌 Memory at viewDidLoad: \(self.currentMemoryMB(), format: .fixed(precision: 2)) MB")
        kbLogger.info("📌 Memory comparison — phys_footprint: \(self.currentMemoryMB(), format: .fixed(precision: 2)) MB, resident_size: \(self.currentResidentMB(), format: .fixed(precision: 2)) MB")
        kbLogger.info("📌 self address = \(String(describing: Unmanaged.passUnretained(self).toOpaque()))")
        #endif

        HistoryManager.shared.migrateClipboardHistoryIfNeeded()
        setupUI()
        setupDelegates()
        setupCallbacks()
        setupSettingsLink()
        loadCachedSettings()
        switchMode(to: .defaultMode)
        restoreState()

        // Phase 2: load touch learning data
        keyboardLayoutView.loadTouchLearningData()
        // Phase 3: connect PredictionEngine
        keyboardLayoutView.predictionEngine = suggestionManager.predictionEngineRef

        // 저전력 모드 변경 감지
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(powerStateDidChange),
            name: .NSProcessInfoPowerStateDidChange,
            object: nil
        )

        #if DEBUG
        Self.lifecycleCount += 1
        let currentMem = self.currentMemoryMB()
        kbLogger.info("📌 viewDidLoad END — Memory: \(currentMem, format: .fixed(precision: 2)) MB [cycle \(Self.lifecycleCount)]")
        Self.logMallocZoneStats()
        kbLogger.info("📌 os_proc_available_memory: \(os_proc_available_memory() / 1024 / 1024) MB")
        Self.diagnoseMemoryBreakdown()

        // 이전 사이클 DEINIT과 비교 — asyncAfter 대체
        if Self.lastDeinitMemory > 0 {
            let delta = currentMem - Self.lastDeinitMemory
            kbLogger.info("📌 [CROSS-CYCLE] 이전 DEINIT: \(Self.lastDeinitMemory, format: .fixed(precision: 2)) MB → 현재 viewDidLoad: \(currentMem, format: .fixed(precision: 2)) MB (delta: \(delta, format: .fixed(precision: 2)) MB)")
            kbLogger.info("📌 [CROSS-CYCLE] delta > 0이면 DEINIT~viewDidLoad 사이 시스템이 메모리를 회수하지 못한 것")
        }
        #endif
    }

    override func didReceiveMemoryWarning() {
        super.didReceiveMemoryWarning()
        #if DEBUG
        kbLogger.warning("⚠️ didReceiveMemoryWarning! Memory: \(self.currentMemoryMB(), format: .fixed(precision: 2)) MB")
        #endif

        // Dictation: memory warning시 현재 상태 보존하며 종료
        if isShowingDictation {
            dictationCoordinator?.forceFinalizePreservingCurrentState()
            dismissDictation()
        }

        // Static 캐시 일괄 해제
        ThemePatternRenderer.clearCache()
        MatrixRainView.clearCharacterImageCache()

        // 계산기가 열려있으면 메모리 확보를 위해 정리 후 defaultMode 복귀
        if let calc = calculatorView {
            calc.removeFromSuperview()
            calculatorView = nil
            modeBeforeCalculator = nil
            switchMode(to: .defaultMode)
        }

        // Chat Reply Generator 메모리 확보
        if chatReplyView != nil {
            chatReplyManager?.cancelPending()
            chatReplyManager?.clearCache()
            chatReplyManager = nil
            chatReplyView?.prepareForDismiss()
            chatReplyView?.removeFromSuperview()
            chatReplyView = nil
            isShowingChatReply = false
            modeTextInputHandler.clear()
            keyboardLayoutView.isHidden = false
            toolbarView.isHidden = false
            switchMode(to: .defaultMode)
        }

        ChatReplyCache.shared.clear()

        #if DEBUG
        kbLogger.warning("⚠️ After cache clear — Memory: \(self.currentMemoryMB(), format: .fixed(precision: 2)) MB")
        #endif
    }

    @objc private func powerStateDidChange() {
        keyboardLayoutView.handlePowerStateChange()
    }

    override func viewWillAppear(_ animated: Bool) {
        super.viewWillAppear(animated)
        #if DEBUG
        kbLogger.info("📌 viewWillAppear — pid=\(ProcessInfo.processInfo.processIdentifier), Memory: \(self.currentMemoryMB(), format: .fixed(precision: 2)) MB")
        kbLogger.info("📌 settingsLinkHostingController isNil=\(self.settingsLinkHostingController == nil), container.subviews=\(self.toolbarView.settingsLinkContainer.subviews.count)")
        #endif

        // ════════════════════════════════════════════
        // 조기 해제 복원 — 같은 인스턴스 재사용 시 (알림센터, 앱 스위처 등)
        // viewWillDisappear에서 정리한 리소스를 필요 시 재생성
        // ════════════════════════════════════════════

        // UIHostingController 복원 (nil이면 setupSettingsLink가 재생성)
        if settingsLinkHostingController == nil {
            setupSettingsLink()
        }

        // ── 즉시 필요한 것만 동기 실행 ──
        textProxyManager.updateProxy(textDocumentProxy)
        setupHeightConstraint()
        loadCachedSettings()
        toolbarView.rebuildToolbarIfNeeded()

        // Phase 7: 키보드 오픈 시 테마 + 애니메이션 확실히 초기화
        // viewDidLoad/switchMode(.defaultMode)에서는 호출되지 않으므로
        // 여기서 호출하여 customTheme 설정 + 애니메이션 뷰 생성 + buildKeyboard 보장
        updateKeyboardAppearance()

        // ── 나머지는 다음 런루프에서 실행 (키보드 UI 먼저 표시) ──
        DispatchQueue.main.async { [weak self] in
            guard let self = self else { return }
            LocalizationManager.shared.reload()
            self.reloadLocalizedStrings()
            self.loadNumberRowSetting()
            self.loadPeriodKeySetting()
            self.loadKeyPreviewSetting()
            self.loadLatinAlternativesSetting()
            self.loadKeyboardLanguageSetting()
            self.updateReturnKeyAppearance()
            self.checkAutoCapitalize()
        }

        hasUserTypedSinceAppeared = false
        toolbarView.hideSuggestions()

        // Delay pasteboard access until the user explicitly opens clipboard history.
        // This avoids the system paste permission prompt racing with the keyboard's
        // initial presentation during onboarding verification and similar first-open flows.
        stopClipboardMonitoring()

        AppGroupManager.shared.set(self.hasFullAccess, forKey: AppConstants.UserDefaultsKeys.keyboardFullAccessEnabled)
    }

    override func viewDidAppear(_ animated: Bool) {
        super.viewDidAppear(animated)
        checkMemorySafetyNet()  // Phase 5: 메모리 안전망

        // Dictation session recovery: 메인앱에서 돌아왔을 때 active session 복구
        if !isShowingDictation {
            tryRecoverDictationSession()
        }
    }

    override func viewWillDisappear(_ animated: Bool) {
        super.viewWillDisappear(animated)

        #if DEBUG
        kbLogger.info("📌 viewWillDisappear START — Memory: \(self.currentMemoryMB(), format: .fixed(precision: 2)) MB")
        kbLogger.info("📌 self address = \(String(describing: Unmanaged.passUnretained(self).toOpaque()))")
        kbLogger.info("📌 children.count = \(self.children.count)")
        #endif

        stopClipboardMonitoring()

        // Dictation: 키보드 dismiss 시 UI만 정리
        // handoff dismiss와 실제 종료를 구분 — stop 커맨드를 보내지 않음
        // 메인앱 세션은 유지되며, viewDidAppear에서 tryRecoverDictationSession()이 복구
        if isShowingDictation {
            dismissDictation()
        }

        // 계산기 정리
        if let calc = calculatorView {
            calc.removeFromSuperview()
            calculatorView = nil
            modeBeforeCalculator = nil
        }

        // Chat Reply Generator 정리
        if currentMode == .chatReplyMode {
            chatReplyManager?.cancelPending()
            chatReplyManager?.clearCache()
            chatReplyManager = nil
            chatReplyView?.prepareForDismiss()
            chatReplyView?.removeFromSuperview()
            chatReplyView = nil
            isShowingChatReply = false
        }

        // CC-4: QuickNote 자동 저장 (기존 로직 유지)
        if currentMode == .quickNoteMode {
            autoSaveIfNeeded()
        }
        CompositionSessionManager.shared.endSession(reason: .keyboardHidden)

        // Phase 2: save touch learning data
        keyboardLayoutView.saveTouchLearningData()

        // ════════════════════════════════════════════
        // 조기 해제 (Early Teardown) — 단계별 메모리 측정
        // ════════════════════════════════════════════

        #if DEBUG
        let mem0 = currentMemoryMB()
        #endif

        // 1) UIHostingController — static 재사용이므로 detach만 (파괴하지 않음)
        if let hc = settingsLinkHostingController {
            NSLayoutConstraint.deactivate(settingsHCConstraints)
            settingsHCConstraints = []
            hc.willMove(toParent: nil)
            hc.view.removeFromSuperview()
            hc.removeFromParent()
            // settingsLinkHostingController는 weak이므로 nil 할당 불필요
            // Self.sharedSettingsHC는 유지 — 다음 사이클에서 재사용
        }

        #if DEBUG
        let mem1 = currentMemoryMB()
        kbLogger.info("🔬 [1] UIHostingController 정리 후 — Memory: \(mem1, format: .fixed(precision: 2)) MB (delta: \(mem1 - mem0, format: .fixed(precision: 2)) MB)")
        #endif

        // 2) KeyboardLayoutView 애니메이션 + CADisplayLink 정리
        keyboardLayoutView.prepareForDismiss()

        #if DEBUG
        let mem2 = currentMemoryMB()
        kbLogger.info("🔬 [2] prepareForDismiss 후 — Memory: \(mem2, format: .fixed(precision: 2)) MB (delta: \(mem2 - mem1, format: .fixed(precision: 2)) MB)")
        #endif

        // 3) Static 캐시 강제 해제
        #if DEBUG
        kbLogger.info("🔬 [3] 캐시 상태 — TranslationCache: \(TranslationCache.shared.debugCacheInfo)")
        #endif
        ThemePatternRenderer.clearCache()
        MatrixRainView.clearCharacterImageCache()

        #if DEBUG
        let mem3 = currentMemoryMB()
        kbLogger.info("🔬 [3] Static 캐시 해제 후 — Memory: \(mem3, format: .fixed(precision: 2)) MB (delta: \(mem3 - mem2, format: .fixed(precision: 2)) MB)")
        #endif

        // 4) Optional views 해제
        #if DEBUG
        kbLogger.info("🔬 [4] Optional views 상태 — emoji:\(self.emojiKeyboardView != nil) clipboard:\(self.clipboardHistoryView != nil) savedPhrases:\(self.savedPhrasesView != nil) langPicker:\(self.languagePickerView != nil) calculator:\(self.calculatorView != nil)")
        #endif

        if let ev = emojiKeyboardView {
            ev.prepareForDismiss()  // CoreText 글리프 캐시 클리어
            ev.removeFromSuperview()
            emojiKeyboardView = nil
        }
        if let cv = clipboardHistoryView {
            cv.removeFromSuperview()
            clipboardHistoryView = nil
        }
        if let sv = savedPhrasesView {
            sv.removeFromSuperview()
            savedPhrasesView = nil
        }
        if let lp = languagePickerView {
            lp.removeFromSuperview()
            languagePickerView = nil
        }

        #if DEBUG
        let mem4 = currentMemoryMB()
        kbLogger.info("🔬 [4] Optional views 해제 후 — Memory: \(mem4, format: .fixed(precision: 2)) MB (delta: \(mem4 - mem3, format: .fixed(precision: 2)) MB)")
        #endif

        // 5) QuickNote views 해제
        #if DEBUG
        kbLogger.info("🔬 [5] QuickNote views 상태 — list:\(self.quickNoteListView != nil) read:\(self.quickNoteReadView != nil) edit:\(self.quickNoteEditView != nil)")
        #endif

        if let qnl = quickNoteListView {
            qnl.removeFromSuperview()
            quickNoteListView = nil
        }
        if let qnr = quickNoteReadView {
            qnr.removeFromSuperview()
            quickNoteReadView = nil
        }
        if let qne = quickNoteEditView {
            qne.removeFromSuperview()
            quickNoteEditView = nil
        }

        #if DEBUG
        let mem5 = currentMemoryMB()
        kbLogger.info("🔬 [5] QuickNote views 해제 후 — Memory: \(mem5, format: .fixed(precision: 2)) MB (delta: \(mem5 - mem4, format: .fixed(precision: 2)) MB)")
        kbLogger.info("📌 viewWillDisappear END — Memory: \(mem5, format: .fixed(precision: 2)) MB (총 delta: \(mem5 - mem0, format: .fixed(precision: 2)) MB) [cycle \(Self.lifecycleCount)]")
        Self.logMallocZoneStats()
        Self.diagnoseMemoryBreakdown()
        CoreTextCacheManager.logInterceptStats()
        #endif

        // ═══ 시스템 캐시 cleanup + malloc pressure relief — Release에서도 실행 ═══
        triggerSystemCacheCleanup()
        malloc_zone_pressure_relief(nil, 0)

        #if DEBUG
        let memAfterRelief = currentMemoryMB()
        kbLogger.info("🔬 [malloc_pressure_relief] viewWillDisappear 후 → \(memAfterRelief, format: .fixed(precision: 2)) MB")
        kbLogger.info("📌 os_proc_available_memory: \(os_proc_available_memory() / 1024 / 1024) MB")
        #endif

        // ═══ Graceful Restart — Phase 6 ═══
        // 메모리 누적이 임계치를 넘으면 프로세스를 깨끗하게 종료.
        // 키보드가 닫히는 시점이므로 유저 입력 손실 없음.
        // 다음 키보드 열기 시 iOS가 fresh 프로세스를 생성하여 baseline ~13MB로 리셋.
        // 애니메이션, 모든 기능이 처음부터 완벽하게 동작.
        let finalMemoryForRestart = currentMemoryMB()
        if finalMemoryForRestart > Self.memoryGracefulExitMB {
            #if DEBUG
            kbLogger.warning("🔄 [GracefulRestart] phys_footprint: \(finalMemoryForRestart, format: .fixed(precision: 1)) MB > \(Self.memoryGracefulExitMB, format: .fixed(precision: 1)) MB — 프로세스 리스타트")
            #endif
            exit(0)
        }
    }

    private func reloadLocalizedStrings() {
        if isTranslationViewsSetUp {
            translationInputView.setPlaceholder(L("translation.placeholder"))
        }
        if isCorrectionViewsSetUp {
            correctionInputView.setPlaceholder(L("correction.placeholder"))
        }
        if isPhraseViewsSetUp {
            phraseInputView.setPlaceholder(L("phrase.placeholder"))
            phraseInputHeaderView.reloadLocalizedStrings()
        }
        updateLanguageLabels()
        if currentMode == .correctionMode {
            correctionLanguageBar.updateToneName(currentToneStyle.displayName)
        }
    }

    private func loadNumberRowSetting() {
        let defaults = UserDefaults(suiteName: AppConstants.appGroupIdentifier)
        let show = defaults?.object(forKey: AppConstants.UserDefaultsKeys.showNumberRow) == nil ? true : (defaults?.bool(forKey: AppConstants.UserDefaultsKeys.showNumberRow) ?? true)
        keyboardLayoutView.showNumberRow = show
        keyboardLayoutHeightConstraint?.constant = keyAreaHeight()
    }

    private func loadPeriodKeySetting() {
        let defaults = UserDefaults(suiteName: AppConstants.appGroupIdentifier)
        let show = defaults?.object(forKey: AppConstants.UserDefaultsKeys.showPeriodKey) == nil
            ? true
            : (defaults?.bool(forKey: AppConstants.UserDefaultsKeys.showPeriodKey) ?? true)
        keyboardLayoutView.showPeriodKey = show
    }

    private func loadKeyPreviewSetting() {
        let defaults = UserDefaults(suiteName: AppConstants.appGroupIdentifier)
        let enabled = defaults?.object(forKey: AppConstants.UserDefaultsKeys.keyTapPreview) == nil
            ? true
            : (defaults?.bool(forKey: AppConstants.UserDefaultsKeys.keyTapPreview) ?? true)
        keyboardLayoutView.isKeyTapPreviewEnabled = enabled
    }

    private func loadLatinAlternativesSetting() {
        let defaults = UserDefaults(suiteName: AppConstants.appGroupIdentifier)
        let enabled = defaults?.object(forKey: AppConstants.UserDefaultsKeys.latinAlternatives) == nil
            ? true
            : (defaults?.bool(forKey: AppConstants.UserDefaultsKeys.latinAlternatives) ?? true)
        keyboardLayoutView.isLatinAlternativesEnabled = enabled
    }

    private func loadKeyboardLanguageSetting() {
        let code = AppGroupManager.shared.string(forKey: AppConstants.UserDefaultsKeys.primaryKeyboardLanguage) ?? "ko"
        let lang = KeyboardLanguage(rawValue: code) ?? .korean
        keyboardLayoutView.pairedLanguage = lang
        let current = keyboardLayoutView.getCurrentLanguage()
        if current != .english && current != lang {
            keyboardLayoutView.setLanguage(lang)
        }
    }

    override func textDidChange(_ textInput: UITextInput?) {
        super.textDidChange(textInput)
        updateKeyboardAppearance()
        updateReturnKeyAppearance()

        // 교정/번역 모드: 호스트 앱 텍스트 필드가 비워지면 입력창 초기화
        if textProxyManager.hasPendingText {
            let contextEmpty = (textDocumentProxy.documentContextBeforeInput ?? "").isEmpty
                            && (textDocumentProxy.documentContextAfterInput ?? "").isEmpty
            if contextEmpty {
                if currentMode == .correctionMode {
                    modeTextInputHandler.clear()
                    correctionInputView.clear()
                    correctionManager.reset()
                    textProxyManager.reset()
                    correctionInputHeightConstraint?.constant = Heights.translationInput
                    updateHeight(for: .correctionMode, animated: true)
                } else if currentMode == .translationMode {
                    modeTextInputHandler.clear()
                    translationInputView.clear()
                    translationManager.cancelPending()
                    textProxyManager.reset()
                    translationInputHeightConstraint?.constant = Heights.translationInput
                    updateHeight(for: .translationMode, animated: true)
                }
            }
        }

        // CRITICAL: Reset Korean composition state when text context changes
        // (e.g., after sending a message, the text field is cleared by the app)
        // Without this, leftover composing characters contaminate the next input.
        if currentMode == .defaultMode || currentMode == .correctionMode || currentMode == .phraseInputMode {
            defaultTextInputHandler.clear()
            defaultModeComposingLength = 0
            isSuggestionDismissedForCurrentWord = false
        }

        checkAutoCapitalize()
        updateSuggestions()
    }

    // MARK: - Height

    private func setupHeightConstraint() {
        guard heightConstraint == nil, let inputView = self.inputView else { return }
        // DO NOT set translatesAutoresizingMaskIntoConstraints = false on inputView
        // iOS system manages the keyboard extension's inputView width via autoresizing masks
        let totalDefault = Heights.topPadding + Heights.toolbar + keyAreaHeight()
        heightConstraint = inputView.heightAnchor.constraint(equalToConstant: totalDefault)
        heightConstraint?.priority = .defaultHigh
        heightConstraint?.isActive = true
    }

    private func updateHeight(for mode: KeyboardMode, animated: Bool = true) {
        let keyArea = keyAreaHeight()
        keyboardLayoutHeightConstraint?.constant = keyArea
        let newHeight: CGFloat
        switch mode {
        case .defaultMode:
            newHeight = Heights.topPadding + Heights.toolbar + keyArea
        case .translationMode:
            let inputH = translationInputHeightConstraint?.constant ?? Heights.translationInput
            newHeight = Heights.topPadding + Heights.translationLanguageBar + inputH + keyArea
        case .correctionMode:
            let inputH = correctionInputHeightConstraint?.constant ?? Heights.translationInput
            let toneH = tonePickerHeightConstraint?.constant ?? 0
            newHeight = Heights.topPadding + Heights.translationLanguageBar + toneH + inputH + keyArea
        case .phraseInputMode:
            let inputH = phraseInputHeightConstraint?.constant ?? Heights.translationInput
            newHeight = Heights.topPadding + Heights.translationLanguageBar + inputH + keyArea
        case .quickNoteMode:
            switch quickNoteSubState {
            case .list:
                newHeight = Heights.topPadding + Heights.toolbar + keyArea
            case .reading:
                newHeight = Heights.topPadding + Heights.toolbar + keyArea
            case .editing:
                let editH = quickNoteEditView?.idealHeight() ?? 130
                newHeight = Heights.topPadding + editH + keyArea
            }
        case .chatReplyMode:
            if chatReplyExpandedHeight > 0 {
                // Results 상태: 키보드 숨기고 콘텐츠에 맞게 확장
                let maxH = UIScreen.main.bounds.height * 0.55
                let defaultH = Heights.topPadding + Heights.toolbar + keyArea
                let expandedH = chatReplyExpandedHeight + Heights.topPadding + 8
                // 짧은 답장이어도 기본 높이 이하로 줄어들지 않도록 (Patch #1)
                newHeight = min(max(expandedH, defaultH), maxH)
            } else {
                // Setup/Loading 상태: 기본 키보드 높이
                newHeight = Heights.topPadding + Heights.toolbar + keyArea
            }
        }

        heightConstraint?.constant = newHeight

        if animated {
            UIView.animate(withDuration: 0.15) {
                self.inputView?.superview?.layoutIfNeeded()
            }
        }
    }

    private func updateInputHeight(_ newHeight: CGFloat, isTranslation: Bool) {
        if isTranslation {
            translationInputHeightConstraint?.constant = newHeight
        } else {
            correctionInputHeightConstraint?.constant = newHeight
        }
        updateHeight(for: currentMode, animated: true)
    }

    // MARK: - Book Animation

    private func animateBookOpen(_ views: [UIView]) {
        inputView?.layoutIfNeeded()
        for v in views {
            v.alpha = 0
            var t = CATransform3DIdentity
            t.m34 = -1.0 / 500
            t = CATransform3DRotate(t, -CGFloat.pi * 0.45, 1, 0, 0)
            v.layer.transform = t
        }
        UIView.animate(withDuration: 0.4, delay: 0, usingSpringWithDamping: 0.82, initialSpringVelocity: 0.3, options: []) {
            for v in views {
                v.alpha = 1
                v.layer.transform = CATransform3DIdentity
            }
        }
    }

    private func animateBookClose(_ views: [UIView], completion: @escaping () -> Void) {
        UIView.animate(withDuration: 0.25, delay: 0, options: .curveEaseIn) {
            for v in views {
                v.alpha = 0
                var t = CATransform3DIdentity
                t.m34 = -1.0 / 500
                t = CATransform3DRotate(t, -CGFloat.pi * 0.45, 1, 0, 0)
                v.layer.transform = t
            }
        } completion: { _ in
            for v in views {
                v.layer.transform = CATransform3DIdentity
                v.alpha = 1
            }
            completion()
        }
    }

    // MARK: - Cached Settings

    /// ⚠️ 반드시 setupUI() 이후에 호출할 것 (keyboardLayoutView 접근 필요)
    private func loadCachedSettings() {
        let defaults = UserDefaults(suiteName: AppConstants.appGroupIdentifier)

        // Autocorrect
        if let obj = defaults?.object(forKey: AppConstants.UserDefaultsKeys.autoComplete) {
            cachedIsAutocorrectEnabled = (obj as? Bool) ?? false
        }

        // AutoCapitalize
        cachedAutoCapitalize = defaults?.bool(forKey: AppConstants.UserDefaultsKeys.autoCapitalize) ?? true

        // Haptic — KeyboardLayoutView에 전달
        if let hapticObj = defaults?.object(forKey: AppConstants.UserDefaultsKeys.hapticFeedback) {
            keyboardLayoutView.cachedHapticEnabled = (hapticObj as? Bool) ?? true
        } else {
            keyboardLayoutView.cachedHapticEnabled = true
        }
    }

    // MARK: - Setup UI

    private func setupUI() {
        guard let inputView = self.inputView else {
            return
        }
        inputView.backgroundColor = .clear
        inputView.layer.cornerRadius = 20
        inputView.layer.maskedCorners = [.layerMinXMinYCorner, .layerMaxXMinYCorner]
        inputView.clipsToBounds = true

        // Only add always-needed views: toolbar + keyboard layout
        // Translation, correction, phrase views are deferred to first mode entry
        [toolbarView, keyboardLayoutView].forEach {
            $0.translatesAutoresizingMaskIntoConstraints = false
            inputView.addSubview($0)
        }

        NSLayoutConstraint.activate([
            // Toolbar — pinned to top with padding
            toolbarView.topAnchor.constraint(equalTo: inputView.topAnchor, constant: Heights.topPadding),
            toolbarView.leadingAnchor.constraint(equalTo: inputView.leadingAnchor),
            toolbarView.trailingAnchor.constraint(equalTo: inputView.trailingAnchor),
            toolbarView.heightAnchor.constraint(equalToConstant: Heights.toolbar),

            // Keyboard Layout
            keyboardLayoutView.leadingAnchor.constraint(equalTo: inputView.leadingAnchor),
            keyboardLayoutView.trailingAnchor.constraint(equalTo: inputView.trailingAnchor),
            keyboardLayoutView.bottomAnchor.constraint(equalTo: inputView.bottomAnchor),
        ])

        // Fixed height for keyboard layout — prevents stretching when system popup expands inputView
        keyboardLayoutHeightConstraint = keyboardLayoutView.heightAnchor.constraint(equalToConstant: keyAreaHeight())
        keyboardLayoutHeightConstraint?.isActive = true

        // Default: keyboard top = toolbar bottom
        keyboardTopToToolbarConstraint = keyboardLayoutView.topAnchor.constraint(equalTo: toolbarView.bottomAnchor)
        keyboardTopToToolbarConstraint?.priority = .defaultHigh
        keyboardTopToToolbarConstraint?.isActive = true

        // Toast — floating on top of everything
        inputView.addSubview(toastLabel)
        NSLayoutConstraint.activate([
            toastLabel.centerXAnchor.constraint(equalTo: inputView.centerXAnchor),
            toastLabel.topAnchor.constraint(equalTo: inputView.topAnchor, constant: 6),
            toastLabel.leadingAnchor.constraint(greaterThanOrEqualTo: inputView.leadingAnchor, constant: 24),
            toastLabel.trailingAnchor.constraint(lessThanOrEqualTo: inputView.trailingAnchor, constant: -24),
            toastLabel.heightAnchor.constraint(equalToConstant: 32),
        ])
    }

    // MARK: - Deferred View Setup

    private func setupTranslationViewsIfNeeded() {
        guard !isTranslationViewsSetUp, let inputView = self.inputView else { return }
        #if DEBUG
        let memBefore = currentMemoryMB()
        kbLogger.info("🔬 setupTranslationViews START — Memory: \(memBefore, format: .fixed(precision: 2)) MB")
        #endif
        isTranslationViewsSetUp = true

        [translationLanguageBar, translationInputView].forEach {
            $0.translatesAutoresizingMaskIntoConstraints = false
            inputView.addSubview($0)
        }
        translationLanguageBar.isHidden = true
        translationInputView.isHidden = true

        NSLayoutConstraint.activate([
            translationLanguageBar.topAnchor.constraint(equalTo: inputView.topAnchor, constant: Heights.topPadding),
            translationLanguageBar.leadingAnchor.constraint(equalTo: inputView.leadingAnchor),
            translationLanguageBar.trailingAnchor.constraint(equalTo: inputView.trailingAnchor),
            translationLanguageBar.heightAnchor.constraint(equalToConstant: Heights.translationLanguageBar),

            translationInputView.topAnchor.constraint(equalTo: translationLanguageBar.bottomAnchor),
            translationInputView.leadingAnchor.constraint(equalTo: inputView.leadingAnchor),
            translationInputView.trailingAnchor.constraint(equalTo: inputView.trailingAnchor),
        ])

        translationInputHeightConstraint = translationInputView.heightAnchor.constraint(equalToConstant: Heights.translationInput)
        translationInputHeightConstraint?.isActive = true

        keyboardTopToTranslationConstraint = keyboardLayoutView.topAnchor.constraint(equalTo: translationInputView.bottomAnchor)
        keyboardTopToTranslationConstraint?.priority = .defaultHigh

        setupTranslationCallbacks()
        updateLanguageLabels()

        // 생성 직후 테마 적용
        let theme = loadTheme()
        let isDark = textDocumentProxy.keyboardAppearance == .dark
        translationLanguageBar.applyTheme(theme)
        translationLanguageBar.updateAppearance(isDark: isDark)
        translationInputView.applyTheme(theme)
        translationInputView.updateAppearance(isDark: isDark)
        #if DEBUG
        let memAfter = currentMemoryMB()
        kbLogger.info("🔬 setupTranslationViews END — Memory: \(memAfter, format: .fixed(precision: 2)) MB (delta: \(memAfter - memBefore, format: .fixed(precision: 2)) MB)")
        #endif
    }

    private func setupCorrectionViewsIfNeeded() {
        guard !isCorrectionViewsSetUp, let inputView = self.inputView else { return }
        #if DEBUG
        let memBefore = currentMemoryMB()
        kbLogger.info("🔬 setupCorrectionViews START — Memory: \(memBefore, format: .fixed(precision: 2)) MB")
        #endif
        isCorrectionViewsSetUp = true

        [correctionLanguageBar, correctionInputView].forEach {
            $0.translatesAutoresizingMaskIntoConstraints = false
            inputView.addSubview($0)
        }
        correctionLanguageBar.isHidden = true
        correctionInputView.isHidden = true

        NSLayoutConstraint.activate([
            correctionLanguageBar.topAnchor.constraint(equalTo: inputView.topAnchor, constant: Heights.topPadding),
            correctionLanguageBar.leadingAnchor.constraint(equalTo: inputView.leadingAnchor),
            correctionLanguageBar.trailingAnchor.constraint(equalTo: inputView.trailingAnchor),
            correctionLanguageBar.heightAnchor.constraint(equalToConstant: Heights.translationLanguageBar),

            correctionInputView.leadingAnchor.constraint(equalTo: inputView.leadingAnchor),
            correctionInputView.trailingAnchor.constraint(equalTo: inputView.trailingAnchor),
        ])

        correctionInputTopConstraint = correctionInputView.topAnchor.constraint(equalTo: correctionLanguageBar.bottomAnchor)
        correctionInputTopConstraint?.isActive = true

        correctionInputHeightConstraint = correctionInputView.heightAnchor.constraint(equalToConstant: Heights.translationInput)
        correctionInputHeightConstraint?.isActive = true

        keyboardTopToCorrectionConstraint = keyboardLayoutView.topAnchor.constraint(equalTo: correctionInputView.bottomAnchor)
        keyboardTopToCorrectionConstraint?.priority = .defaultHigh

        setupCorrectionCallbacks()

        // 생성 직후 테마 적용
        let theme = loadTheme()
        let isDark = textDocumentProxy.keyboardAppearance == .dark
        correctionLanguageBar.applyTheme(theme)
        correctionLanguageBar.updateAppearance(isDark: isDark)
        correctionInputView.applyTheme(theme)
        correctionInputView.updateAppearance(isDark: isDark)
        #if DEBUG
        let memAfter = currentMemoryMB()
        kbLogger.info("🔬 setupCorrectionViews END — Memory: \(memAfter, format: .fixed(precision: 2)) MB (delta: \(memAfter - memBefore, format: .fixed(precision: 2)) MB)")
        #endif
    }

    private func setupPhraseViewsIfNeeded() {
        guard !isPhraseViewsSetUp, let inputView = self.inputView else { return }
        #if DEBUG
        let memBefore = currentMemoryMB()
        kbLogger.info("🔬 setupPhraseViews START — Memory: \(memBefore, format: .fixed(precision: 2)) MB")
        #endif
        isPhraseViewsSetUp = true

        [phraseInputHeaderView, phraseInputView].forEach {
            $0.translatesAutoresizingMaskIntoConstraints = false
            inputView.addSubview($0)
        }
        phraseInputHeaderView.isHidden = true
        phraseInputView.isHidden = true

        NSLayoutConstraint.activate([
            phraseInputHeaderView.topAnchor.constraint(equalTo: inputView.topAnchor, constant: Heights.topPadding),
            phraseInputHeaderView.leadingAnchor.constraint(equalTo: inputView.leadingAnchor),
            phraseInputHeaderView.trailingAnchor.constraint(equalTo: inputView.trailingAnchor),
            phraseInputHeaderView.heightAnchor.constraint(equalToConstant: Heights.translationLanguageBar),

            phraseInputView.topAnchor.constraint(equalTo: phraseInputHeaderView.bottomAnchor),
            phraseInputView.leadingAnchor.constraint(equalTo: inputView.leadingAnchor),
            phraseInputView.trailingAnchor.constraint(equalTo: inputView.trailingAnchor),
        ])

        phraseInputHeightConstraint = phraseInputView.heightAnchor.constraint(equalToConstant: Heights.translationInput)
        phraseInputHeightConstraint?.isActive = true

        keyboardTopToPhraseInputConstraint = keyboardLayoutView.topAnchor.constraint(equalTo: phraseInputView.bottomAnchor)
        keyboardTopToPhraseInputConstraint?.priority = .defaultHigh

        setupPhraseCallbacks()
        #if DEBUG
        let memAfter = currentMemoryMB()
        kbLogger.info("🔬 setupPhraseViews END — Memory: \(memAfter, format: .fixed(precision: 2)) MB (delta: \(memAfter - memBefore, format: .fixed(precision: 2)) MB)")
        #endif
    }

    // MARK: - Deferred Callbacks

    private func setupTranslationCallbacks() {
        translationInputView.onClearText = { [weak self] in
            guard let self = self else { return }
            self.modeTextInputHandler.clear()
            self.translationManager.cancelPending()
        }
        translationInputView.onHeightChanged = { [weak self] newHeight in
            self?.updateInputHeight(newHeight, isTranslation: true)
        }
        translationLanguageBar.onSourceTap = { [weak self] in
            self?.showLanguagePicker(initialTab: .source)
        }
        translationLanguageBar.onTargetTap = { [weak self] in
            self?.showLanguagePicker(initialTab: .target)
        }
        translationLanguageBar.onSwapTap = { [weak self] in
            self?.swapLanguages()
        }
        translationLanguageBar.onCloseTap = { [weak self] in
            self?.exitTranslationMode()
        }
    }

    private func setupCorrectionCallbacks() {
        correctionInputView.setPlaceholder(L("correction.placeholder"))
        correctionInputView.onClearText = { [weak self] in
            guard let self = self else { return }
            self.modeTextInputHandler.clear()
            self.correctionManager.reset()
        }
        correctionInputView.onHeightChanged = { [weak self] newHeight in
            self?.updateInputHeight(newHeight, isTranslation: false)
        }
        correctionLanguageBar.onLanguageTap = { [weak self] in
            self?.showCorrectionLanguagePicker()
        }
        correctionLanguageBar.onToneTap = { [weak self] in
            self?.toggleTonePicker()
        }
        correctionLanguageBar.onCloseTap = { [weak self] in
            self?.exitCorrectionMode()
        }
    }

    private func setupPhraseCallbacks() {
        phraseInputHeaderView.onCancel = { [weak self] in
            self?.exitPhraseInputMode()
        }
        phraseInputHeaderView.onSave = { [weak self] in
            self?.saveNewPhrase()
        }
        phraseInputView.setPlaceholder(L("phrase.placeholder"))
        phraseInputView.onHeightChanged = { [weak self] newHeight in
            self?.phraseInputHeightConstraint?.constant = newHeight
            self?.updateHeight(for: .phraseInputMode, animated: true)
        }
    }

    // MARK: - Delegates

    private func setupDelegates() {
        modeTextInputHandler.delegate = self
        translationManager.delegate = self
        correctionManager.delegate = self
    }

    // MARK: - Callbacks

    private func setupCallbacks() {
        // Toolbar — default mode only
        toolbarView.onTranslateToggle = { [weak self] in
            self?.hideContextMenu()
            self?.hideStatusPopup()
            self?.toggleTranslationMode()
        }
        toolbarView.onEmojiKeyboardToggle = { [weak self] in
            self?.hideContextMenu()
            self?.hideStatusPopup()
            self?.toggleEmojiKeyboard()
        }
        toolbarView.onCorrectionToggle = { [weak self] in
            self?.hideContextMenu()
            self?.hideStatusPopup()
            self?.toggleCorrectionMode()
        }
        toolbarView.onSavedPhrasesTap = { [weak self] in
            self?.hideContextMenu()
            self?.hideStatusPopup()
            self?.showSavedPhrases()
        }
        toolbarView.onClipboardTap = { [weak self] in
            self?.hideContextMenu()
            self?.hideStatusPopup()
            self?.toggleClipboardHistory()
        }
        toolbarView.onQuickNoteTap = { [weak self] in
            self?.hideContextMenu()
            self?.hideStatusPopup()
            self?.toggleQuickNoteMode()
        }
        toolbarView.onCalculatorTap = { [weak self] in
            self?.hideContextMenu()
            self?.hideStatusPopup()
            self?.showCalculator()
        }
        toolbarView.onChatReplyGeneratorTap = { [weak self] in
            self?.hideContextMenu()
            self?.hideStatusPopup()
            self?.showChatReplyGenerator()
        }
        toolbarView.onDictationTap = { [weak self] in
            self?.hideContextMenu()
            self?.hideStatusPopup()
            self?.startDictation()
        }
        // onLogoTap, onLogoLongPress 제거 — + 버튼은 SwiftUI Link가 직접 처리
        toolbarView.onSuggestionTap = { [weak self] suggestion in
            self?.applySuggestion(suggestion)
        }
        toolbarView.onSuggestionDismiss = { [weak self] in
            self?.dismissSuggestions()
        }

        // Keyboard layout — always present
        keyboardLayoutView.onKeyTap = { [weak self] key in
            self?.handleKeyTap(key)
        }
        keyboardLayoutView.onHeightChangeNeeded = { [weak self] in
            guard let self = self else { return }
            let newHeight = self.keyAreaHeight()
            guard let constraint = self.keyboardLayoutHeightConstraint,
                  constraint.constant != newHeight else { return }
            constraint.constant = newHeight
            self.updateHeight(for: self.currentMode, animated: true)
        }
        keyboardLayoutView.onLanguageChanged = { [weak self] lang in
            self?.commitDefaultComposing()
            AppGroupManager.shared.set(lang.rawValue, forKey: AppConstants.UserDefaultsKeys.keyboardLayout)
        }
        keyboardLayoutView.onCursorMove = { [weak self] horizontal, vertical in
            self?.handleCursorMove(horizontal: horizontal, vertical: vertical)
        }
        keyboardLayoutView.onTrackpadModeChanged = { [weak self] active in
            if active {
                // Commit any in-progress Korean composition before moving cursor
                self?.commitDefaultComposing()
            }
        }

    }

    // MARK: - State Restoration

    private func restoreState() {
        if let sourceLang = AppGroupManager.shared.string(forKey: AppConstants.UserDefaultsKeys.sourceLanguage) {
            sourceLanguageCode = sourceLang
        }
        if let targetLang = AppGroupManager.shared.string(forKey: AppConstants.UserDefaultsKeys.targetLanguage) {
            targetLanguageCode = targetLang
        }
        correctionLanguageCode = sourceLanguageCode
        translationManager.setLanguages(source: sourceLanguageCode, target: targetLanguageCode)
        updateLanguageLabels()

        // Restore keyboard language from keyboardLayout key (supports both old "korean"/"english" and new rawValue format)
        if let savedLang = AppGroupManager.shared.string(forKey: AppConstants.UserDefaultsKeys.keyboardLayout) {
            let lang: KeyboardLanguage
            if let parsed = KeyboardLanguage(rawValue: savedLang) {
                lang = parsed
            } else if savedLang == "korean" {
                lang = .korean
            } else {
                lang = .english
            }
            keyboardLayoutView.setLanguage(lang)
        }
    }

    // MARK: - SwiftUI Settings Link

    private func setupSettingsLink() {
        #if DEBUG
        kbLogger.info("🔗 setupSettingsLink START — sharedHC isNil=\(Self.sharedSettingsHC == nil), localRef isNil=\(self.settingsLinkHostingController == nil)")
        kbLogger.info("🔗 container.subviews.count BEFORE = \(self.toolbarView.settingsLinkContainer.subviews.count)")
        #endif

        // ── static 인스턴스가 없으면 최초 1회 생성 ──
        if Self.sharedSettingsHC == nil {
            let hc = UIHostingController(rootView: SettingsLinkView())
            hc.view.translatesAutoresizingMaskIntoConstraints = false
            hc.view.backgroundColor = .clear
            Self.sharedSettingsHC = hc
            #if DEBUG
            kbLogger.info("🔗 UIHostingController 최초 생성 (프로세스 수명 동안 재사용)")
            #endif
        }

        guard let hc = Self.sharedSettingsHC else { return }

        // ── 이전 VC에서 detach (re-parent 준비) ──
        if hc.parent != nil {
            hc.willMove(toParent: nil)
            hc.view.removeFromSuperview()
            hc.removeFromParent()
        }

        // ── 현재 VC에 attach ──
        addChild(hc)
        hc.view.translatesAutoresizingMaskIntoConstraints = false
        toolbarView.settingsLinkContainer.addSubview(hc.view)
        hc.didMove(toParent: self)

        // 컨테이너에 꽉 채움 — constraint를 변수에 보관하여 re-parent 시 명시적 정리 가능
        let constraints = [
            hc.view.topAnchor.constraint(equalTo: toolbarView.settingsLinkContainer.topAnchor),
            hc.view.bottomAnchor.constraint(equalTo: toolbarView.settingsLinkContainer.bottomAnchor),
            hc.view.leadingAnchor.constraint(equalTo: toolbarView.settingsLinkContainer.leadingAnchor),
            hc.view.trailingAnchor.constraint(equalTo: toolbarView.settingsLinkContainer.trailingAnchor),
        ]
        NSLayoutConstraint.activate(constraints)
        self.settingsHCConstraints = constraints

        // weak 참조 보관
        self.settingsLinkHostingController = hc

        #if DEBUG
        kbLogger.info("🔗 setupSettingsLink END — container.subviews.count AFTER = \(self.toolbarView.settingsLinkContainer.subviews.count)")
        kbLogger.info("🔗 Memory after setupSettingsLink: \(self.currentMemoryMB(), format: .fixed(precision: 2)) MB")
        kbLogger.info("🔗 children.count = \(self.children.count)")
        #endif
    }

    // MARK: - System Cache Cleanup

    /// 시스템 프레임워크(CoreText, CoreAnimation, UIKit)의 내부 캐시를
    /// 메모리 경고 notification을 통해 자체 purge하도록 유도.
    /// CoreText의 NSCache는 이 notification에 반응하여 글리프 캐시를 해제한다.
    /// 시스템 프레임워크 캐시를 직접 정리.
    /// Release 빌드에서도 동작해야 하므로 #if DEBUG 밖에 위치.
    ///
    /// Phase 6 v2: didReceiveMemoryWarningNotification post 제거.
    /// 이유:
    /// 1. 모든 테스트에서 메모리 회수 효과 = 0.0000 MB (무효)
    /// 2. KeyboardLayoutView.handleMemoryWarning()가 이 notification에 반응하여
    ///    isMemoryConstrained=true + 모든 애니메이션 뷰 제거하는 치명적 부작용 발생
    /// 3. 키보드 dismiss 후 asyncAfter 미실행으로 isMemoryConstrained가 영구 true
    /// 4. 결과: 애니메이션이 처음부터 작동하지 않는 버그
    private func triggerSystemCacheCleanup() {
        // 1) 추적된 CoreText 캐시 직접 클리어
        CoreTextCacheManager.shared.clearGlyphCaches()

        // 2) URL 캐시 정리
        URLCache.shared.removeAllCachedResponses()

        // 3) hidden 뷰의 CALayer backing store 해제
        for subview in view.subviews where subview.isHidden || subview.alpha == 0 {
            subview.layer.contents = nil
        }
    }

    // MARK: - Memory Safety Net (Phase 5)

    /// 메모리 안전망 — phys_footprint 기반
    ///
    /// Phase 6: CRITICAL 단계를 제거하고 Graceful Restart로 대체.
    /// 애니메이션 캐시, CALayer backing store 등을 건드리지 않는다.
    /// 고메모리 상태에서 cleanup은 delta=0으로 무효하므로, exit(0)으로 프로세스 리스타트가 유일한 해법.
    private func checkMemorySafetyNet() {
        let currentMB = currentMemoryMB()

        if currentMB > Self.memoryEmergencyExitMB {
            // ═══ EMERGENCY EXIT ═══
            // viewDidAppear에서 호출됨 — 키보드가 막 열렸는데 이미 위험 수준.
            // 이 상태에서는 어떤 cleanup도 효과 없음 (delta=0 확인됨).
            // 유저 입력은 이미 text field에 commit된 상태이므로 손실 없음.
            #if DEBUG
            kbLogger.error("🚨 [SafetyNet] EMERGENCY EXIT — phys_footprint: \(currentMB, format: .fixed(precision: 1)) MB > \(Self.memoryEmergencyExitMB, format: .fixed(precision: 1)) MB, 프로세스 리스타트")
            #endif
            exit(0)

        } else if currentMB > Self.memoryWarningThresholdMB {
            // ═══ WARNING: 소프트 캐시만 정리 ═══
            // CoreText 글리프 캐시, FontPool, URLCache만 정리.
            // ⚠️ 애니메이션 캐시(MatrixRain, Stardust), sublayer.contents,
            //    이모지 뷰 등은 절대 건드리지 않는다.
            CoreTextCacheManager.shared.clearGlyphCaches()
            FontPool.clearIfNeeded()
            URLCache.shared.removeAllCachedResponses()

            #if DEBUG
            kbLogger.warning("⚠️ [SafetyNet] WARNING — phys_footprint: \(currentMB, format: .fixed(precision: 1)) MB, 소프트 캐시 정리")
            #endif
        }
    }

    // MARK: - Memory Measurement

    /// Jetsam이 실제로 보는 phys_footprint (MB)
    /// Phase 6: Release에서도 SafetyNet이 사용하므로 #if DEBUG 밖에 위치.
    private func currentMemoryMB() -> Double {
        var info = task_vm_info_data_t()
        var count = mach_msg_type_number_t(MemoryLayout<task_vm_info>.size / MemoryLayout<integer_t>.size)
        let result = withUnsafeMutablePointer(to: &info) {
            $0.withMemoryRebound(to: integer_t.self, capacity: Int(count)) {
                task_info(mach_task_self_, task_flavor_t(TASK_VM_INFO), $0, &count)
            }
        }
        if result == KERN_SUCCESS {
            return Double(info.phys_footprint) / (1024 * 1024)
        }
        return 0
    }

    #if DEBUG
    /// resident_size (비교용, 기존 측정값)
    private func currentResidentMB() -> Double {
        var info = mach_task_basic_info()
        var count = mach_msg_type_number_t(MemoryLayout<mach_task_basic_info>.size / MemoryLayout<integer_t>.size)
        let result = withUnsafeMutablePointer(to: &info) {
            $0.withMemoryRebound(to: integer_t.self, capacity: Int(count)) {
                task_info(mach_task_self_, task_flavor_t(MACH_TASK_BASIC_INFO), $0, &count)
            }
        }
        if result == KERN_SUCCESS {
            return Double(info.resident_size) / (1024 * 1024)
        }
        return 0
    }

    /// 메모리 안전망 임계치 (phys_footprint MB 기준)
    ///
    /// 설계 근거:
    /// - 22MB WARNING: 이모지 피크 후 소프트 캐시 정리. 애니메이션은 절대 안 건드림.
    /// - 40MB GRACEFUL: 기본 테마 ~54사이클, 애니메이션 테마 ~29사이클 후 도달.
    ///   키보드 닫는 시점(viewWillDisappear)에서만 exit(0) 호출.
    ///   유저 입장에서 다음 키보드 열기 시 fresh 프로세스로 13MB baseline 시작.
    /// - 55MB EMERGENCY: viewWillDisappear 없이 메모리가 폭증한 극단적 상황.
    ///   viewDidAppear에서 즉시 exit(0). (실제 발생 확률 매우 낮음)
    private static let memoryWarningThresholdMB: Double = 22.0     // WARNING: 소프트 캐시만 정리
    private static let memoryGracefulExitMB: Double = 40.0         // GRACEFUL: 키보드 닫을 때 exit(0)
    private static let memoryEmergencyExitMB: Double = 55.0        // EMERGENCY: 즉시 exit(0)

    /// 사이클 간 메모리 추적용 static 변수
    private static var lastDeinitMemory: Double = 0
    private static var lifecycleCount: Int = 0

    /// deinit에서 사용 가능한 static 메모리 측정 (self 접근 불필요)
    private static func measurePhysFootprint() -> Double {
        var info = task_vm_info_data_t()
        var count = mach_msg_type_number_t(MemoryLayout<task_vm_info>.size / MemoryLayout<integer_t>.size)
        let result = withUnsafeMutablePointer(to: &info) {
            $0.withMemoryRebound(to: integer_t.self, capacity: Int(count)) {
                task_info(mach_task_self_, task_flavor_t(TASK_VM_INFO), $0, &count)
            }
        }
        if result == KERN_SUCCESS {
            return Double(info.phys_footprint) / (1024 * 1024)
        }
        return 0
    }

    /// malloc zone 통계 — 할당 중인 메모리 vs 실제 사용 중인 메모리
    private static func logMallocZoneStats() {
        if let zone = malloc_default_zone() {
            var stats = malloc_statistics_t()
            malloc_zone_statistics(zone, &stats)
            let allocatedMB = Double(stats.size_allocated) / (1024 * 1024)
            let inUseMB = Double(stats.size_in_use) / (1024 * 1024)
            let freeMB = allocatedMB - inUseMB
            staticLogger.info("🔬 [malloc] default zone — allocated: \(allocatedMB, format: .fixed(precision: 2)) MB, in_use: \(inUseMB, format: .fixed(precision: 2)) MB, free_in_zone: \(freeMB, format: .fixed(precision: 2)) MB")
        }
    }

    /// malloc에게 미사용 메모리를 OS에 반환하도록 요청하고 효과를 측정
    private static func testMallocPressureRelief() {
        let before = measurePhysFootprint()
        let released = malloc_zone_pressure_relief(nil, 0)
        let after = measurePhysFootprint()
        staticLogger.info("🔬 [malloc_pressure_relief] before: \(before, format: .fixed(precision: 2)) MB → after: \(after, format: .fixed(precision: 2)) MB (delta: \(after - before, format: .fixed(precision: 2)) MB, bytes_released: \(released))")
    }

    /// [DEBUG] VM 메모리 상세 분석 — iOS에서 사용 가능한 필드만 사용
    private static func diagnoseMemoryBreakdown() {
        var info = task_vm_info_data_t()
        var count = mach_msg_type_number_t(MemoryLayout<task_vm_info>.size / MemoryLayout<integer_t>.size)
        let result = withUnsafeMutablePointer(to: &info) {
            $0.withMemoryRebound(to: integer_t.self, capacity: Int(count)) {
                task_info(mach_task_self_, task_flavor_t(TASK_VM_INFO), $0, &count)
            }
        }
        guard result == KERN_SUCCESS else {
            staticLogger.error("📊 [vm_info] task_info 호출 실패")
            return
        }

        let physFP = Double(info.phys_footprint) / (1024 * 1024)
        let internalMem = Double(info.`internal`) / (1024 * 1024)
        let compressed = Double(info.compressed) / (1024 * 1024)
        let resident = Double(info.resident_size) / (1024 * 1024)
        let virtual = Double(info.virtual_size) / (1024 * 1024)

        staticLogger.info("📊 [vm_info] phys_footprint: \(physFP, format: .fixed(precision: 2)) MB")
        staticLogger.info("📊 [vm_info]   internal (dirty): \(internalMem, format: .fixed(precision: 2)) MB")
        staticLogger.info("📊 [vm_info]   compressed: \(compressed, format: .fixed(precision: 2)) MB")
        staticLogger.info("📊 [vm_info]   resident_size: \(resident, format: .fixed(precision: 2)) MB")
        staticLogger.info("📊 [vm_info]   virtual_size: \(virtual, format: .fixed(precision: 2)) MB")
        staticLogger.info("📊 [vm_info]   non-malloc dirty (internal - phys): \(internalMem - physFP, format: .fixed(precision: 2)) MB")
    }
    #endif

    // MARK: - Mode Switching

    func switchMode(to mode: KeyboardMode) {
        let previousMode = currentMode

        // 계산기가 열려있으면 먼저 닫기 (모드 전환 충돌 방지)
        if let calc = calculatorView {
            calc.removeFromSuperview()
            calculatorView = nil
            modeBeforeCalculator = nil
        }

        // chatReplyMode 이탈 시 전체 정리
        if previousMode == .chatReplyMode && mode != .chatReplyMode {
            chatReplyManager?.cancelPending()
            chatReplyManager?.clearCache()
            chatReplyManager = nil
            chatReplyView?.prepareForDismiss()
            chatReplyView?.removeFromSuperview()
            chatReplyView = nil
            isShowingChatReply = false
            chatReplyExpandedHeight = 0
            modeTextInputHandler.clear()
            keyboardLayoutView.isHidden = false
            toolbarView.isHidden = false
        }

        // QuickNote 모드 이탈 시 전체 정리
        if previousMode == .quickNoteMode && mode != .quickNoteMode {
            autoSaveIfNeeded()
            quickNoteReadView?.removeFromSuperview()
            quickNoteReadView = nil
            quickNoteListView?.removeFromSuperview()
            quickNoteListView = nil
            quickNoteEditView?.removeFromSuperview()
            quickNoteEditView = nil
            quickNoteTextInputHandler = nil
            quickNoteSubState = .list
            editingNote = nil
        }

        currentMode = mode
        hideEmojiKeyboard()

        // Phase 3: disable context probability in non-default modes
        keyboardLayoutView.isDefaultMode = (mode == .defaultMode)

        // Deactivate all keyboard top constraints first
        keyboardTopToToolbarConstraint?.isActive = false
        keyboardTopToTranslationConstraint?.isActive = false
        keyboardTopToCorrectionConstraint?.isActive = false
        keyboardTopToPhraseInputConstraint?.isActive = false
        quickNoteTopConstraint?.isActive = false

        switch mode {
        case .defaultMode:
            toolbarView.isHidden = false
            keyboardLayoutView.isHidden = false
            if isTranslationViewsSetUp {
                translationLanguageBar.isHidden = true
                translationInputView.isHidden = true
            }
            if isCorrectionViewsSetUp {
                correctionLanguageBar.isHidden = true
                correctionInputView.isHidden = true
            }
            if isPhraseViewsSetUp {
                phraseInputHeaderView.isHidden = true
                phraseInputView.isHidden = true
            }
            // CC-2: QuickNote 뷰 메모리 반환 (보험용)
            quickNoteTextInputHandler = nil
            quickNoteReadView?.removeFromSuperview()
            quickNoteReadView = nil
            quickNoteListView?.removeFromSuperview()
            quickNoteListView = nil
            quickNoteEditView?.removeFromSuperview()
            quickNoteEditView = nil
            quickNoteSubState = .list
            editingNote = nil
            translationManager.cancelPending()
            textProxyManager.reset()
            keyboardTopToToolbarConstraint?.isActive = true

        case .translationMode:
            toolbarView.isHidden = true
            translationLanguageBar.isHidden = false
            translationInputView.isHidden = false
            if isCorrectionViewsSetUp {
                correctionLanguageBar.isHidden = true
                correctionInputView.isHidden = true
            }
            if isPhraseViewsSetUp {
                phraseInputHeaderView.isHidden = true
                phraseInputView.isHidden = true
            }
            modeTextInputHandler.clear()
            translationInputView.clear()
            toolbarView.hideSuggestions()
            keyboardTopToTranslationConstraint?.isActive = true
            updateKeyboardAppearance()

        case .correctionMode:
            toolbarView.isHidden = true
            if isTranslationViewsSetUp {
                translationLanguageBar.isHidden = true
                translationInputView.isHidden = true
            }
            correctionLanguageBar.isHidden = false
            correctionInputView.isHidden = false
            if isPhraseViewsSetUp {
                phraseInputHeaderView.isHidden = true
                phraseInputView.isHidden = true
            }
            modeTextInputHandler.clear()
            correctionInputView.clear()
            correctionManager.reset()
            textProxyManager.reset()
            toolbarView.hideSuggestions()
            keyboardTopToCorrectionConstraint?.isActive = true
            updateKeyboardAppearance()

        case .phraseInputMode:
            toolbarView.isHidden = true
            if isTranslationViewsSetUp {
                translationLanguageBar.isHidden = true
                translationInputView.isHidden = true
            }
            if isCorrectionViewsSetUp {
                correctionLanguageBar.isHidden = true
                correctionInputView.isHidden = true
            }
            phraseInputHeaderView.isHidden = false
            phraseInputView.isHidden = false
            modeTextInputHandler.clear()
            phraseInputView.clear()
            toolbarView.hideSuggestions()
            keyboardTopToPhraseInputConstraint?.isActive = true

        case .quickNoteMode:
            toolbarView.isHidden = true
            if isTranslationViewsSetUp {
                translationLanguageBar.isHidden = true
                translationInputView.isHidden = true
            }
            if isCorrectionViewsSetUp {
                correctionLanguageBar.isHidden = true
                correctionInputView.isHidden = true
            }
            if isPhraseViewsSetUp {
                phraseInputHeaderView.isHidden = true
                phraseInputView.isHidden = true
            }
            toolbarView.hideSuggestions()
            showQuickNoteList()

        case .chatReplyMode:
            if isTranslationViewsSetUp {
                translationLanguageBar.isHidden = true
                translationInputView.isHidden = true
            }
            if isCorrectionViewsSetUp {
                correctionLanguageBar.isHidden = true
                correctionInputView.isHidden = true
            }
            if isPhraseViewsSetUp {
                phraseInputHeaderView.isHidden = true
                phraseInputView.isHidden = true
            }
            modeTextInputHandler.clear()
            toolbarView.hideSuggestions()
            keyboardTopToToolbarConstraint?.isActive = true
        }

        updateHeight(for: mode)
        updateReturnKeyForCurrentMode()
    }

    private func toggleTranslationMode() {
        switch currentMode {
        case .defaultMode:
            enterTranslationMode()
        case .translationMode:
            exitTranslationMode()
        case .correctionMode, .phraseInputMode, .quickNoteMode, .chatReplyMode:
            break
        }
    }

    private func enterTranslationMode() {
        commitDefaultComposing()

        guard hasFullAccess() else {
            showStatusMessage(L("keyboard.error.full_access"))
            return
        }

        guard CompositionSessionManager.shared.canStartSession(mode: .translate) else {
            showDailyLimitReached(mode: .translate)
            return
        }
        CompositionSessionManager.shared.startSession(mode: .translate)
        setupTranslationViewsIfNeeded()
        switchMode(to: .translationMode)
        animateBookOpen([translationLanguageBar, translationInputView])
    }

    private func exitTranslationMode() {
        modeTextInputHandler.commitComposing()
        translationManager.cancelPending()
        CompositionSessionManager.shared.endSession(reason: .modeExit)
        textProxyManager.reset()
        defaultTextInputHandler.clear()
        defaultModeComposingLength = 0
        translationInputHeightConstraint?.constant = Heights.translationInput
        hideLanguagePicker()
        animateBookClose([translationLanguageBar, translationInputView]) { [weak self] in
            self?.switchMode(to: .defaultMode)
        }
    }

    // MARK: - Correction Mode

    private func toggleCorrectionMode() {
        switch currentMode {
        case .defaultMode:
            enterCorrectionMode()
        case .correctionMode:
            exitCorrectionMode()
        case .translationMode, .phraseInputMode, .quickNoteMode, .chatReplyMode:
            break
        }
    }

    private func enterCorrectionMode() {
        commitDefaultComposing()

        guard hasFullAccess() else {
            showStatusMessage(L("keyboard.error.full_access"))
            return
        }

        guard CompositionSessionManager.shared.canStartSession(mode: .correct) else {
            showDailyLimitReached(mode: .correct)
            return
        }
        CompositionSessionManager.shared.startSession(mode: .correct)
        setupCorrectionViewsIfNeeded()

        let langName = languageDisplayName(for: correctionLanguageCode)
        correctionLanguageBar.updateLanguageName(langName)
        correctionManager.setLanguage(correctionLanguageCode)
        if let savedTone = AppGroupManager.shared.string(forKey: AppConstants.UserDefaultsKeys.toneStyle),
           let tone = ToneStyle(rawValue: savedTone) {
            currentToneStyle = tone
        } else {
            currentToneStyle = .none
        }
        correctionLanguageBar.updateToneName(currentToneStyle.displayName)
        correctionManager.setTone(currentToneStyle)
        switchMode(to: .correctionMode)
        animateBookOpen([correctionLanguageBar, correctionInputView])
    }

    private func exitCorrectionMode() {
        modeTextInputHandler.commitComposing()
        modeTextInputHandler.clear()
        correctionManager.cancelPending()
        correctionManager.reset()
        CompositionSessionManager.shared.endSession(reason: .modeExit)
        textProxyManager.reset()
        defaultTextInputHandler.clear()
        defaultModeComposingLength = 0
        correctionInputHeightConstraint?.constant = Heights.translationInput
        hideTonePicker()
        hideLanguagePicker()
        animateBookClose([correctionLanguageBar, correctionInputView]) { [weak self] in
            self?.switchMode(to: .defaultMode)
        }
    }

    // MARK: - Saved Phrases

    private func showSavedPhrases() {
        #if DEBUG
        let memBefore = currentMemoryMB()
        kbLogger.info("🔬 showSavedPhrases START — Memory: \(memBefore, format: .fixed(precision: 2)) MB")
        #endif
        if savedPhrasesView == nil {
            guard let inputView = self.inputView else { return }
            let sv = SavedPhrasesView()
            sv.translatesAutoresizingMaskIntoConstraints = false
            sv.isHidden = true
            sv.onPhraseSelected = { [weak self] phrase in
                self?.insertPhrase(phrase)
            }
            sv.onAddPhrase = { [weak self] in
                self?.enterPhraseInputMode()
            }
            sv.onDismiss = { [weak self] in
                self?.hideSavedPhrases()
            }
            inputView.addSubview(sv)
            NSLayoutConstraint.activate([
                sv.topAnchor.constraint(equalTo: inputView.topAnchor),
                sv.leadingAnchor.constraint(equalTo: inputView.leadingAnchor),
                sv.trailingAnchor.constraint(equalTo: inputView.trailingAnchor),
                sv.bottomAnchor.constraint(equalTo: inputView.bottomAnchor),
            ])
            savedPhrasesView = sv

            // ★ 생성 직후 현재 테마 적용
            let theme = loadTheme()
            let isDarkMode = textDocumentProxy.keyboardAppearance == .dark
            sv.applyTheme(theme)
            sv.updateAppearance(isDark: isDarkMode)
        }
        savedPhrasesView?.reloadData()
        savedPhrasesView?.isHidden = false
        savedPhrasesView?.alpha = 0
        if let sv = savedPhrasesView {
            inputView?.bringSubviewToFront(sv)
        }
        UIView.animate(withDuration: 0.2) {
            self.savedPhrasesView?.alpha = 1
        }
        #if DEBUG
        let memAfter = currentMemoryMB()
        kbLogger.info("🔬 showSavedPhrases END — Memory: \(memAfter, format: .fixed(precision: 2)) MB (delta: \(memAfter - memBefore, format: .fixed(precision: 2)) MB)")
        #endif
    }

    private func hideSavedPhrases() {
        UIView.animate(withDuration: 0.15, animations: {
            self.savedPhrasesView?.alpha = 0
        }) { _ in
            self.savedPhrasesView?.isHidden = true
        }
    }

    // MARK: - Clipboard History

    private func toggleClipboardHistory() {
        if clipboardHistoryView?.isHidden ?? true {
            showClipboardHistory()
        } else {
            hideClipboardHistory()
        }
    }

    private func showClipboardHistory() {
        guard hasFullAccess() else {
            showStatusMessage(L("keyboard.error.full_access"))
            return
        }
        #if DEBUG
        let memBefore = currentMemoryMB()
        kbLogger.info("🔬 showClipboard START — Memory: \(memBefore, format: .fixed(precision: 2)) MB")
        #endif
        if clipboardHistoryView == nil {
            guard let inputView = self.inputView else { return }
            let cv = ClipboardHistoryView()
            cv.translatesAutoresizingMaskIntoConstraints = false
            cv.isHidden = true
            cv.onItemSelected = { [weak self] text in
                self?.textDocumentProxy.insertText(text)
                self?.hideClipboardHistory()
            }
            cv.onDismiss = { [weak self] in
                self?.hideClipboardHistory()
            }
            inputView.addSubview(cv)
            NSLayoutConstraint.activate([
                cv.topAnchor.constraint(equalTo: inputView.topAnchor),
                cv.leadingAnchor.constraint(equalTo: inputView.leadingAnchor),
                cv.trailingAnchor.constraint(equalTo: inputView.trailingAnchor),
                cv.bottomAnchor.constraint(equalTo: inputView.bottomAnchor),
            ])
            clipboardHistoryView = cv

            // ★ 생성 직후 현재 테마 적용
            let theme = loadTheme()
            let isDarkMode = textDocumentProxy.keyboardAppearance == .dark
            cv.applyTheme(theme)
            cv.updateAppearance(isDark: isDarkMode)
        }
        syncClipboardForVisibleHistory()
        startClipboardMonitoring()
        clipboardHistoryView?.reloadData()
        clipboardHistoryView?.isHidden = false
        clipboardHistoryView?.alpha = 0
        if let cv = clipboardHistoryView {
            inputView?.bringSubviewToFront(cv)
        }
        inputView?.bringSubviewToFront(toastLabel)
        UIView.animate(withDuration: 0.2) {
            self.clipboardHistoryView?.alpha = 1
        }
        #if DEBUG
        let memAfter = currentMemoryMB()
        kbLogger.info("🔬 showClipboard END — Memory: \(memAfter, format: .fixed(precision: 2)) MB (delta: \(memAfter - memBefore, format: .fixed(precision: 2)) MB)")
        #endif
    }

    private func hideClipboardHistory() {
        stopClipboardMonitoring()
        UIView.animate(withDuration: 0.15, animations: {
            self.clipboardHistoryView?.alpha = 0
        }) { _ in
            self.clipboardHistoryView?.isHidden = true
        }
    }

    // MARK: - Clipboard Monitoring

    private func startClipboardMonitoring() {
        guard hasFullAccess() else { return }
        lastKnownClipboardChangeCount = UIPasteboard.general.changeCount
        clipboardCheckTimer?.invalidate()
        clipboardCheckTimer = Timer.scheduledTimer(withTimeInterval: 2.0, repeats: true) { [weak self] _ in
            guard let self = self else { return }
            let currentCount = UIPasteboard.general.changeCount
            if currentCount != self.lastKnownClipboardChangeCount {
                self.lastKnownClipboardChangeCount = currentCount
                self.checkClipboardForNewContent()

                if let clipboardView = self.clipboardHistoryView,
                   !clipboardView.isHidden {
                    if let tableView = clipboardView.subviews.compactMap({ $0 as? UITableView }).first,
                       !tableView.isDragging, !tableView.isDecelerating {
                        clipboardView.reloadData()
                    } else {
                        DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) { [weak self] in
                            guard let self = self,
                                  let cv = self.clipboardHistoryView,
                                  !cv.isHidden else { return }
                            cv.reloadData()
                        }
                    }
                }
            }
        }
    }

    private func stopClipboardMonitoring() {
        clipboardCheckTimer?.invalidate()
        clipboardCheckTimer = nil
    }

    private func syncClipboardForVisibleHistory() {
        guard hasFullAccess() else { return }
        lastKnownClipboardChangeCount = UIPasteboard.general.changeCount
        checkClipboardForNewContent()
    }

    private func checkClipboardForNewContent() {
        guard hasFullAccess() else { return }
        guard UIPasteboard.general.hasStrings else { return }
        guard let text = UIPasteboard.general.string else { return }
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }

        // 중복 체크 — HistoryManager 기반
        let existing = HistoryManager.shared.loadItems(ofType: .clipboard)
        if existing.first?.originalText == trimmed { return }

        // 단일 소스에만 저장
        HistoryManager.shared.addItem(
            type: .clipboard,
            original: trimmed,
            result: nil,
            metadata: nil
        )
    }

    private func insertPhrase(_ phrase: String) {
        textDocumentProxy.insertText(phrase)
        hideSavedPhrases()
    }

    private func enterPhraseInputMode() {
        hideSavedPhrases()
        setupPhraseViewsIfNeeded()
        phraseInputHeightConstraint?.constant = Heights.translationInput
        switchMode(to: .phraseInputMode)
    }

    private func exitPhraseInputMode() {
        modeTextInputHandler.commitComposing()
        modeTextInputHandler.clear()
        phraseInputHeightConstraint?.constant = Heights.translationInput
        switchMode(to: .defaultMode)
        showSavedPhrases()
    }

    private func saveNewPhrase() {
        let text = modeTextInputHandler.fullText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else {
            exitPhraseInputMode()
            return
        }
        SavedPhrasesManager.shared.addPhrase(text)
        modeTextInputHandler.commitComposing()
        modeTextInputHandler.clear()
        phraseInputHeightConstraint?.constant = Heights.translationInput
        switchMode(to: .defaultMode)
        showSavedPhrases()
    }

    private func handlePhraseInputModeKey(_ key: String) {
        switch key {
        case KeyboardLayoutView.backKey:
            modeTextInputHandler.handleBackspace()

        case KeyboardLayoutView.returnKey:
            modeTextInputHandler.commitComposing()

        case " ":
            modeTextInputHandler.handleSpace()

        default:
            if modeTextInputHandler.totalLength >= AppConstants.Limits.maxCharacters {
                hapticFeedback.impactOccurred()
                return
            }

            let isKorean = isKoreanJamo(key)
            if let char = key.first {
                modeTextInputHandler.handleKey(char, isKorean: isKorean)
            }
        }
    }

    private func toggleTonePicker() {
        if isTonePickerVisible {
            hideTonePicker()
        } else {
            showTonePicker()
        }
    }

    private func ensureTonePickerView() {
        guard tonePickerView == nil, let inputView = self.inputView else { return }
        let tp = TonePickerView()
        tp.translatesAutoresizingMaskIntoConstraints = false
        tp.isHidden = true
        tp.onToneSelected = { [weak self] tone in
            self?.currentToneStyle = tone
            AppGroupManager.shared.set(tone.rawValue, forKey: AppConstants.UserDefaultsKeys.toneStyle)
            self?.correctionLanguageBar.updateToneName(tone.displayName)
            self?.correctionManager.setTone(tone)
            self?.hideTonePicker()
            if let text = self?.modeTextInputHandler.fullText, !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                self?.correctionManager.reset()
                self?.correctionManager.requestCorrection(text: text)
            }
        }
        inputView.addSubview(tp)

        // Re-anchor correctionInputView: was pinned to correctionLanguageBar, now pin to tonePicker
        correctionInputTopConstraint?.isActive = false
        NSLayoutConstraint.activate([
            tp.topAnchor.constraint(equalTo: correctionLanguageBar.bottomAnchor),
            tp.leadingAnchor.constraint(equalTo: inputView.leadingAnchor),
            tp.trailingAnchor.constraint(equalTo: inputView.trailingAnchor),
        ])
        correctionInputTopConstraint = correctionInputView.topAnchor.constraint(equalTo: tp.bottomAnchor)
        correctionInputTopConstraint?.isActive = true

        tonePickerHeightConstraint = tp.heightAnchor.constraint(equalToConstant: 0)
        tonePickerHeightConstraint?.isActive = true

        tonePickerView = tp
    }

    private func showTonePicker() {
        ensureTonePickerView()
        isTonePickerVisible = true
        tonePickerView?.selectTone(currentToneStyle)
        tonePickerHeightConstraint?.constant = 38
        tonePickerView?.show()
        updateHeight(for: .correctionMode, animated: true)
    }

    private func hideTonePicker() {
        guard isTonePickerVisible else { return }
        isTonePickerVisible = false
        tonePickerView?.hide()
        tonePickerHeightConstraint?.constant = 0
        updateHeight(for: .correctionMode, animated: true)
    }

    private func showCorrectionLanguagePicker() {
        guard !isLanguagePickerVisible else {
            hideLanguagePicker()
            return
        }
        ensureLanguagePickerView()
        isLanguagePickerVisible = true
        languagePickerView?.configureSingleLanguage(code: correctionLanguageCode, title: L("keyboard.correction_language"))
        languagePickerView?.isHidden = false
        languagePickerView?.alpha = 0
        UIView.animate(withDuration: 0.2) {
            self.languagePickerView?.alpha = 1
        }
    }

    // MARK: - Emoji Keyboard

    private func toggleEmojiKeyboard() {
        if isEmojiMode { hideEmojiKeyboard() } else { showEmojiKeyboard() }
    }

    private func showEmojiKeyboard() {
        #if DEBUG
        let memBefore = currentMemoryMB()
        kbLogger.info("🔬 showEmojiKeyboard START — Memory: \(memBefore, format: .fixed(precision: 2)) MB")
        #endif
        if emojiKeyboardView == nil {
            guard let inputView = self.inputView else { return }
            let emoji = EmojiKeyboardView()
            emoji.translatesAutoresizingMaskIntoConstraints = false
            emoji.onEmojiSelected = { [weak self] emojiStr in
                guard let self = self else { return }
                if emojiStr == KeyboardLayoutView.backKey {
                    self.textDocumentProxy.deleteBackward()
                } else {
                    self.textDocumentProxy.insertText(emojiStr)
                }
            }
            emoji.onBackToKeyboard = { [weak self] in
                self?.hideEmojiKeyboard()
            }
            inputView.addSubview(emoji)
            NSLayoutConstraint.activate([
                emoji.leadingAnchor.constraint(equalTo: inputView.leadingAnchor),
                emoji.trailingAnchor.constraint(equalTo: inputView.trailingAnchor),
                emoji.bottomAnchor.constraint(equalTo: inputView.bottomAnchor),
                emoji.topAnchor.constraint(equalTo: toolbarView.bottomAnchor),
            ])
            emojiKeyboardView = emoji
        }
        isEmojiMode = true
        keyboardLayoutView.isHidden = true
        emojiKeyboardView?.isHidden = false
        #if DEBUG
        let memAfter = currentMemoryMB()
        kbLogger.info("🔬 showEmojiKeyboard END — Memory: \(memAfter, format: .fixed(precision: 2)) MB (delta: \(memAfter - memBefore, format: .fixed(precision: 2)) MB)")
        kbLogger.info("🔬 CoreText tracked caches: \(CoreTextCacheManager.shared.trackedCacheCount)")
        #endif

        // Phase 6: 이모지 열기 시 메모리 안전망 체크
        checkMemorySafetyNet()
    }

    private func hideEmojiKeyboard() {
        // Phase 8: 이모지 모드가 아니면 즉시 리턴 (중복 호출 방지)
        // switchMode()가 매번 무조건 호출하므로, guard 없으면 매 모드 전환마다
        // triggerSystemCacheCleanup + checkMemorySafetyNet이 불필요하게 실행됨
        guard isEmojiMode else { return }

        isEmojiMode = false

        #if DEBUG
        let beforeClear = currentMemoryMB()
        let cacheCountBefore = CoreTextCacheManager.shared.trackedCacheCount
        let cacheObjectsBefore = CoreTextCacheManager.shared.totalCachedObjectCount
        #endif

        // Phase 8: 이모지 뷰 완전 파괴 (isHidden 대신 nil)
        // viewWillDisappear와 동일한 teardown 패턴 적용
        // 이모지 뷰의 CALayer backing store + UIView 계층 메모리 즉시 회수
        emojiKeyboardView?.prepareForDismiss()
        emojiKeyboardView?.removeFromSuperview()
        emojiKeyboardView = nil

        keyboardLayoutView.isHidden = false

        // 시스템 프레임워크 캐시 purge (CoreText 글리프, CALayer backing store 등)
        triggerSystemCacheCleanup()

        // Phase 6: 이모지 닫기 시 메모리 안전망 체크
        checkMemorySafetyNet()

        #if DEBUG
        let afterClear = currentMemoryMB()
        kbLogger.info("🧹 hideEmojiKeyboard — 시스템 캐시 cleanup 효과:")
        kbLogger.info("🧹   before: \(beforeClear, format: .fixed(precision: 2)) MB → after: \(afterClear, format: .fixed(precision: 2)) MB (delta: \(afterClear - beforeClear, format: .fixed(precision: 2)) MB)")
        kbLogger.info("🧹   tracked caches: \(cacheCountBefore), cached objects before clear: \(cacheObjectsBefore)")
        Self.logMallocZoneStats()
        #endif
    }

    private func hasFullAccess() -> Bool {
        if #available(iOSApplicationExtension 11.0, *) {
            return self.hasFullAccess
        }
        return false
    }

    // MARK: - Language Picker

    private func ensureLanguagePickerView() {
        guard languagePickerView == nil, let inputView = self.inputView else { return }
        let picker = LanguagePickerView()
        picker.translatesAutoresizingMaskIntoConstraints = false
        picker.isHidden = true
        picker.onLanguageSelected = { [weak self] tab, language in
            self?.handleLanguageSelection(tab: tab, language: language)
        }
        picker.onDismiss = { [weak self] in
            self?.hideLanguagePicker()
        }
        inputView.addSubview(picker)
        NSLayoutConstraint.activate([
            picker.topAnchor.constraint(equalTo: inputView.topAnchor),
            picker.leadingAnchor.constraint(equalTo: inputView.leadingAnchor),
            picker.trailingAnchor.constraint(equalTo: inputView.trailingAnchor),
            picker.bottomAnchor.constraint(equalTo: inputView.bottomAnchor),
        ])
        languagePickerView = picker
    }

    private func showLanguagePicker(initialTab: LanguagePickerView.Tab = .source) {
        guard !isLanguagePickerVisible else {
            hideLanguagePicker()
            return
        }
        ensureLanguagePickerView()
        isLanguagePickerVisible = true
        languagePickerView?.configure(
            sourceCode: sourceLanguageCode,
            targetCode: targetLanguageCode,
            initialTab: initialTab
        )
        languagePickerView?.isHidden = false
        languagePickerView?.alpha = 0
        UIView.animate(withDuration: 0.2) {
            self.languagePickerView?.alpha = 1
        }
    }

    private func hideLanguagePicker() {
        guard isLanguagePickerVisible else { return }
        isLanguagePickerVisible = false
        UIView.animate(withDuration: 0.15, animations: {
            self.languagePickerView?.alpha = 0
        }) { _ in
            self.languagePickerView?.isHidden = true
        }
    }

    private func handleLanguageSelection(tab: LanguagePickerView.Tab, language: LanguageItem) {
        if currentMode == .correctionMode {
            correctionLanguageCode = language.code
            correctionLanguageBar.updateLanguageName(language.displayName)
            correctionManager.setLanguage(language.code)
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) { [weak self] in
                self?.hideLanguagePicker()
            }
            return
        }

        switch tab {
        case .source:
            if language.code == targetLanguageCode {
                targetLanguageCode = sourceLanguageCode
                AppGroupManager.shared.set(targetLanguageCode, forKey: AppConstants.UserDefaultsKeys.targetLanguage)
            }
            sourceLanguageCode = language.code
            AppGroupManager.shared.set(language.code, forKey: AppConstants.UserDefaultsKeys.sourceLanguage)
        case .target:
            if language.code == sourceLanguageCode {
                sourceLanguageCode = targetLanguageCode
                AppGroupManager.shared.set(sourceLanguageCode, forKey: AppConstants.UserDefaultsKeys.sourceLanguage)
            }
            targetLanguageCode = language.code
            AppGroupManager.shared.set(language.code, forKey: AppConstants.UserDefaultsKeys.targetLanguage)
        }

        translationManager.setLanguages(source: sourceLanguageCode, target: targetLanguageCode)
        updateLanguageLabels()

        DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) { [weak self] in
            self?.hideLanguagePicker()
        }
    }

    private func swapLanguages() {
        let temp = sourceLanguageCode
        sourceLanguageCode = targetLanguageCode
        targetLanguageCode = temp

        AppGroupManager.shared.set(sourceLanguageCode, forKey: AppConstants.UserDefaultsKeys.sourceLanguage)
        AppGroupManager.shared.set(targetLanguageCode, forKey: AppConstants.UserDefaultsKeys.targetLanguage)
        translationManager.setLanguages(source: sourceLanguageCode, target: targetLanguageCode)
        updateLanguageLabels()
    }

    private func updateLanguageLabels() {
        guard isTranslationViewsSetUp else { return }
        let sourceName = languageDisplayName(for: sourceLanguageCode)
        let targetName = languageDisplayName(for: targetLanguageCode)
        translationLanguageBar.updateLanguageNames(source: sourceName, target: targetName)
    }

    private func languageDisplayName(for code: String) -> String {
        return LanguagePickerView.supportedLanguages.first(where: { $0.code == code })?.displayName ?? code
    }

    // MARK: - Key Handling

    private func handleKeyTap(_ key: String) {
        hasUserTypedSinceAppeared = true
        switch currentMode {
        case .defaultMode:
            handleDefaultModeKey(key)
        case .translationMode:
            handleTranslationModeKey(key)
        case .correctionMode:
            handleCorrectionModeKey(key)
        case .phraseInputMode:
            handlePhraseInputModeKey(key)
        case .quickNoteMode:
            handleQuickNoteModeKey(key)
        case .chatReplyMode:
            handleChatReplyModeKey(key)
        }
    }

    private func handleDefaultModeKey(_ key: String) {
        switch key {
        case KeyboardLayoutView.backKey:
            if !defaultTextInputHandler.composingText.isEmpty {
                textDocumentProxy.deleteBackward()
                defaultModeComposingLength = 0
                defaultTextInputHandler.handleBackspace()
                if !defaultTextInputHandler.composingText.isEmpty {
                    textDocumentProxy.insertText(defaultTextInputHandler.composingText)
                    defaultModeComposingLength = 1
                }
            } else {
                textDocumentProxy.deleteBackward()
            }
            keyboardLayoutView.currentTypingPrefix = currentTypingWord() ?? ""

        case KeyboardLayoutView.returnKey:
            if currentTypingWord() != nil {
                StatsManager.shared.incrementWordsTyped()
            }
            commitDefaultComposing()
            textDocumentProxy.insertText("\n")
            keyboardLayoutView.currentTypingPrefix = ""
            isSuggestionDismissedForCurrentWord = false

        case " ":
            if currentTypingWord() != nil {
                StatsManager.shared.incrementWordsTyped()
            }
            commitDefaultComposing()
            textDocumentProxy.insertText(" ")
            keyboardLayoutView.currentTypingPrefix = ""

        default:
            isSuggestionDismissedForCurrentWord = false
            let isKorean = isKoreanJamo(key)
            if isKorean, let char = key.first {
                if defaultModeComposingLength > 0 {
                    textDocumentProxy.deleteBackward()
                    defaultModeComposingLength = 0
                }

                let oldBufferCount = defaultTextInputHandler.buffer.count
                defaultTextInputHandler.handleKey(char, isKorean: true)

                let newBufferCount = defaultTextInputHandler.buffer.count
                if newBufferCount > oldBufferCount {
                    let committedChars = String(defaultTextInputHandler.buffer.suffix(newBufferCount - oldBufferCount))
                    textDocumentProxy.insertText(committedChars)
                    defaultTextInputHandler.resetBuffer()
                }

                if !defaultTextInputHandler.composingText.isEmpty {
                    textDocumentProxy.insertText(defaultTextInputHandler.composingText)
                    defaultModeComposingLength = 1
                }
            } else {
                commitDefaultComposing()
                textDocumentProxy.insertText(key)
            }
            keyboardLayoutView.currentTypingPrefix = currentTypingWord() ?? ""
        }

        checkAutoCapitalize()
        updateSuggestions()
    }

    private func commitDefaultComposing() {
        if defaultModeComposingLength > 0 {
            defaultTextInputHandler.commitComposing()
            defaultTextInputHandler.resetBuffer()
            defaultModeComposingLength = 0
        }
    }

    private func handleTranslationModeKey(_ key: String) {
        switch key {
        case KeyboardLayoutView.backKey:
            modeTextInputHandler.handleBackspace()

        case KeyboardLayoutView.returnKey:
            modeTextInputHandler.handleNewline()

        case " ":
            modeTextInputHandler.handleSpace()

        default:
            if modeTextInputHandler.totalLength >= AppConstants.Limits.maxCharacters {
                hapticFeedback.impactOccurred()
                showStatusMessage(String(format: L("keyboard.error.max_chars"), AppConstants.Limits.maxCharacters))
                return
            }

            let isKorean = isKoreanJamo(key)
            if let char = key.first {
                modeTextInputHandler.handleKey(char, isKorean: isKorean)
            }
        }
    }

    private func handleCorrectionModeKey(_ key: String) {
        switch key {
        case KeyboardLayoutView.backKey:
            modeTextInputHandler.handleBackspace()

        case KeyboardLayoutView.returnKey:
            modeTextInputHandler.handleNewline()

        case " ":
            modeTextInputHandler.handleSpace()

        default:
            if modeTextInputHandler.totalLength >= AppConstants.Limits.maxCharacters {
                hapticFeedback.impactOccurred()
                return
            }

            let isKorean = isKoreanJamo(key)
            if let char = key.first {
                modeTextInputHandler.handleKey(char, isKorean: isKorean)
            }
        }
    }

    private func isKoreanJamo(_ key: String) -> Bool {
        guard let scalar = key.unicodeScalars.first else { return false }
        return (0x3131...0x3163).contains(scalar.value)
    }

    // MARK: - Trackpad Cursor Movement

    private func handleCursorMove(horizontal: Int, vertical: Int) {
        if horizontal != 0 {
            textDocumentProxy.adjustTextPosition(byCharacterOffset: horizontal)
        }
        if vertical != 0 {
            if vertical < 0 {
                moveUp()
            } else {
                moveDown()
            }
        }
    }

    /// Estimate visual line width based on screen width and current language.
    private var estimatedCharsPerLine: Int {
        let screenWidth = UIScreen.main.bounds.width
        let textWidth = screenWidth * 0.85  // ~85% of screen for typical text view margins
        let lang = keyboardLayoutView.getCurrentLanguage()
        let avgCharWidth: CGFloat
        switch lang {
        case .korean: avgCharWidth = 17
        case .russian: avgCharWidth = 12
        default: avgCharWidth = 9
        }
        return max(10, Int(textWidth / avgCharWidth))
    }

    /// Move cursor up one line.
    /// Uses actual \n positions when available, falls back to estimated offset for soft-wrapped text.
    private func moveUp() {
        guard let before = textDocumentProxy.documentContextBeforeInput, !before.isEmpty else { return }

        // Find the last newline before cursor — that's the start of current line
        guard let currentLineStart = before.lastIndex(of: "\n") else {
            // No \n found — soft-wrapped text, use estimated offset
            textDocumentProxy.adjustTextPosition(byCharacterOffset: -estimatedCharsPerLine)
            return
        }

        let currentColumn = before.distance(from: before.index(after: currentLineStart), to: before.endIndex)

        // Find the previous line
        let textBeforeCurrentLine = before[before.startIndex..<currentLineStart]
        let prevLineStart: String.Index
        if let prevNewline = textBeforeCurrentLine.lastIndex(of: "\n") {
            prevLineStart = textBeforeCurrentLine.index(after: prevNewline)
        } else {
            prevLineStart = textBeforeCurrentLine.startIndex
        }

        let prevLineLength = before.distance(from: prevLineStart, to: currentLineStart)
        let targetColumn = min(currentColumn, prevLineLength)

        // Move back: current column chars + newline char + remaining chars in prev line
        let offset = -(currentColumn + 1 + (prevLineLength - targetColumn))
        textDocumentProxy.adjustTextPosition(byCharacterOffset: offset)
    }

    /// Move cursor down one line.
    /// Uses actual \n positions when available, falls back to estimated offset for soft-wrapped text.
    private func moveDown() {
        let after = textDocumentProxy.documentContextAfterInput ?? ""

        // Try \n-based accurate movement
        guard !after.isEmpty, let currentLineEnd = after.firstIndex(of: "\n") else {
            // No context, empty, or no \n — use estimated offset
            textDocumentProxy.adjustTextPosition(byCharacterOffset: estimatedCharsPerLine)
            return
        }

        // Calculate current column position
        let before = textDocumentProxy.documentContextBeforeInput ?? ""
        let currentColumn: Int
        if let lastNewline = before.lastIndex(of: "\n") {
            currentColumn = before.distance(from: before.index(after: lastNewline), to: before.endIndex)
        } else {
            currentColumn = before.count
        }

        // Find the next line's length
        let nextLineStart = after.index(after: currentLineEnd)
        let nextLineEnd: String.Index
        if let nextNewline = after[nextLineStart...].firstIndex(of: "\n") {
            nextLineEnd = nextNewline
        } else {
            nextLineEnd = after.endIndex
        }

        let nextLineLength = after.distance(from: nextLineStart, to: nextLineEnd)
        let targetColumn = min(currentColumn, nextLineLength)

        // Offset = chars remaining on current line + 1 (newline) + targetColumn
        let charsToCurrentLineEnd = after.distance(from: after.startIndex, to: currentLineEnd)
        let offset = charsToCurrentLineEnd + 1 + targetColumn
        textDocumentProxy.adjustTextPosition(byCharacterOffset: offset)
    }

    // MARK: - Status Messages

    private func showStatusMessage(_ message: String) {
        statusMessageTimer?.cancel()

        // Floating toast — visible in all modes
        toastLabel.text = "  \(message)  "
        toastLabel.isHidden = false
        toastLabel.alpha = 0
        inputView?.bringSubviewToFront(toastLabel)

        UIView.animate(withDuration: 0.2) {
            self.toastLabel.alpha = 1
        }

        let workItem = DispatchWorkItem { [weak self] in
            UIView.animate(withDuration: 0.3, animations: {
                self?.toastLabel.alpha = 0
            }) { _ in
                self?.toastLabel.isHidden = true
            }
        }
        statusMessageTimer = workItem
        DispatchQueue.main.asyncAfter(deadline: .now() + 2.5, execute: workItem)
    }

    /// showStatusMessage의 convenience wrapper (chatReply에서 사용)
    private func showToast(_ message: String) {
        showStatusMessage(message)
    }

    // MARK: - Autocorrect Suggestions

    private func currentTypingWord() -> String? {
        guard let context = textDocumentProxy.documentContextBeforeInput else { return nil }
        let components = context.components(separatedBy: CharacterSet.whitespacesAndNewlines)
        return components.last?.isEmpty == false ? components.last : nil
    }

    private func dismissSuggestions() {
        isSuggestionDismissedForCurrentWord = true
        toolbarView.hideSuggestions()
    }

    private func updateSuggestions() {
        guard currentMode == .defaultMode, isAutocorrectEnabled, hasUserTypedSinceAppeared else {
            toolbarView.hideSuggestions(); return
        }
        guard !isSuggestionDismissedForCurrentWord else { return }

        // Only show suggestions when actively typing a word (not after space/enter/empty)
        guard let word = currentTypingWord(), !word.isEmpty else {
            toolbarView.hideSuggestions(); return
        }

        let token = UUID()
        pendingSuggestionToken = token
        let currentLang = keyboardLayoutView.getCurrentLanguage()

        // Context는 메인에서 읽기 (UIKit 필수)
        let context = textDocumentProxy.documentContextBeforeInput
        let isComposing = !defaultTextInputHandler.composingText.isEmpty

        // debounce 비동기로 제안 계산 (메인 스레드, UITextChecker safe)
        suggestionManager.getSuggestionsAsync(
            context: context,
            currentWord: word,
            isComposing: isComposing,
            language: currentLang
        ) { [weak self] result in
            guard let self = self else { return }
            // 이미 새로운 요청이 들어왔으면 이전 결과 무시
            guard self.pendingSuggestionToken == token else { return }

            switch result.mode {
            case .none: self.toolbarView.hideSuggestions()
            case .autocorrect, .prediction: self.toolbarView.showSuggestions(result.suggestions)
            }
        }
    }

    private func applySuggestion(_ suggestion: String) {
        let word = currentTypingWord()
        if let word = word, !word.isEmpty {
            commitDefaultComposing()
            for _ in 0..<word.count { textDocumentProxy.deleteBackward() }
        }
        textDocumentProxy.insertText(suggestion + " ")
        toolbarView.hideSuggestions()
        checkAutoCapitalize()
        DispatchQueue.main.async { [weak self] in
            self?.updateSuggestions()
        }
    }

    // MARK: - Return Key

    private func updateReturnKeyAppearance() {
        let returnType = textDocumentProxy.returnKeyType ?? .default

        switch returnType {
        case .go:
            keyboardLayoutView.returnKeyDisplayName = L("keyboard.return.go")
            keyboardLayoutView.returnKeyIsBlue = true
        case .search:
            keyboardLayoutView.returnKeyDisplayName = L("keyboard.return.search")
            keyboardLayoutView.returnKeyIsBlue = true
        case .send:
            keyboardLayoutView.returnKeyDisplayName = L("keyboard.return.send")
            keyboardLayoutView.returnKeyIsBlue = true
        case .done:
            keyboardLayoutView.returnKeyDisplayName = L("keyboard.return.done")
            keyboardLayoutView.returnKeyIsBlue = true
        case .next:
            keyboardLayoutView.returnKeyDisplayName = L("keyboard.return.next")
            keyboardLayoutView.returnKeyIsBlue = true
        case .join:
            keyboardLayoutView.returnKeyDisplayName = L("keyboard.return.join")
            keyboardLayoutView.returnKeyIsBlue = true
        case .route:
            keyboardLayoutView.returnKeyDisplayName = L("keyboard.return.route")
            keyboardLayoutView.returnKeyIsBlue = true
        case .emergencyCall:
            keyboardLayoutView.returnKeyDisplayName = L("keyboard.return.emergency")
            keyboardLayoutView.returnKeyIsBlue = true
        case .continue:
            keyboardLayoutView.returnKeyDisplayName = L("keyboard.return.continue")
            keyboardLayoutView.returnKeyIsBlue = true
        default:
            // .default — used in text editors, messaging body, notes → newline
            keyboardLayoutView.returnKeyDisplayName = L("keyboard.return.newline")
            keyboardLayoutView.returnKeyIsBlue = false
        }
    }

    // MARK: - Open Containing App

    @objc protocol URLOpener {
        @objc(openURL:options:completionHandler:)
        func open(_ url: URL, options: [String: Any], completionHandler: ((Bool) -> Void)?)
    }

    private func openContainingApp(path: String = "settings") {
        guard let url = URL(string: "translatorkeyboard://\(path)") else { return }
        var responder: UIResponder? = self
        while let r = responder {
            if let opener = r as? URLOpener {
                opener.open(url, options: [:], completionHandler: nil)
                return
            }
            responder = r.next
        }
    }

    private func showDailyLimitReached(mode: CompositionSession.SessionMode) {
        let modeText = mode == .correct ? L("home.stat.corrections") : L("home.stat.translations")
        let rewardMode: RewardMode = mode == .correct ? .correction : .translation
        let remaining = CompositionSessionManager.shared.remainingSessions(for: mode)

        if remaining <= 0 {
            // 토스트 메시지에 광고/업그레이드 안내 포함
            let message: String
            if DailyUsageManager.shared.canWatchRewardedAd(for: rewardMode) {
                message = String(format: L("session_limit.watch_ad"), modeText)
            } else {
                message = String(format: L("session_limit.upgrade"), modeText)
            }
            showStatusMessage(message)

            // 메인 앱의 페이월 또는 리워드 광고 화면으로 이동
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) { [weak self] in
                if DailyUsageManager.shared.canWatchRewardedAd(for: rewardMode) {
                    self?.openContainingApp(path: "reward-ad?mode=\(rewardMode.rawValue)")
                } else {
                    self?.openContainingApp(path: "paywall")
                }
            }
        } else {
            showStatusMessage(L("session_limit.title"))
        }
    }

    // MARK: - Auto Capitalize

    private func checkAutoCapitalize() {
        guard cachedAutoCapitalize else { return }
        // Caps Lock active — skip auto-capitalize logic
        guard !keyboardLayoutView.isCapsLocked else { return }
        guard currentMode == .defaultMode || currentMode == .quickNoteMode else { return }

        let lang = keyboardLayoutView.getCurrentLanguage()
        guard lang == .english || lang == .spanish || lang == .french || lang == .german || lang == .italian else { return }

        let shouldCapitalize: Bool

        if currentMode == .quickNoteMode {
            guard let handler = quickNoteTextInputHandler else { return }
            let text = handler.fullText

            if text.isEmpty {
                shouldCapitalize = true
            } else if text.hasSuffix(". ") || text.hasSuffix("? ") || text.hasSuffix("! ") || text.hasSuffix("\n") {
                shouldCapitalize = true
            } else {
                shouldCapitalize = false
            }
        } else {
            let context = textDocumentProxy.documentContextBeforeInput
            if context == nil || context?.isEmpty == true {
                shouldCapitalize = true
            } else if let text = context,
                      text.hasSuffix(". ") || text.hasSuffix("? ") || text.hasSuffix("! ") || text.hasSuffix("\n") {
                shouldCapitalize = true
            } else {
                shouldCapitalize = false
            }
        }

        if shouldCapitalize {
            keyboardLayoutView.setShifted(true)
        } else {
            keyboardLayoutView.setShifted(false)
        }
    }

    // MARK: - Appearance

    private func loadTheme() -> KeyboardTheme? {
        guard let theme = KeyboardTheme.currentTheme() else { return nil }
        if theme.isPremium && !SubscriptionStatus.shared.isPro {
            AppGroupManager.shared.set("default", forKey: AppConstants.UserDefaultsKeys.keyboardTheme)
            return nil
        }
        return theme
    }

    private func updateKeyboardAppearance() {
        let isDark = textDocumentProxy.keyboardAppearance == .dark
        let theme = loadTheme()

        // 시스템 둥근 배경을 덮기 위해 inputView 배경색 설정
        if let theme = theme {
            inputView?.backgroundColor = theme.keyboardBackground
        } else if isDark {
            inputView?.backgroundColor = UIColor(white: 0.12, alpha: 1)
        } else {
            inputView?.backgroundColor = UIColor(red: 0.82, green: 0.84, blue: 0.86, alpha: 1)
        }

        keyboardLayoutView.applyTheme(theme)
        keyboardLayoutView.updateAppearance(isDark: isDark)
        toolbarView.applyTheme(theme)
        toolbarView.updateAppearance(isDark: isDark)
        emojiKeyboardView?.updateAppearance(isDark: isDark)
        if isTranslationViewsSetUp {
            translationLanguageBar.applyTheme(theme)
            translationLanguageBar.updateAppearance(isDark: isDark)
            translationInputView.applyTheme(theme)
            translationInputView.updateAppearance(isDark: isDark)
        }
        if isCorrectionViewsSetUp {
            correctionLanguageBar.applyTheme(theme)
            correctionLanguageBar.updateAppearance(isDark: isDark)
            correctionInputView.applyTheme(theme)
            correctionInputView.updateAppearance(isDark: isDark)
        }
        tonePickerView?.applyTheme(theme)
        tonePickerView?.updateAppearance(isDark: isDark)
        savedPhrasesView?.applyTheme(theme)
        savedPhrasesView?.updateAppearance(isDark: isDark)
        clipboardHistoryView?.applyTheme(theme)
        clipboardHistoryView?.updateAppearance(isDark: isDark)

        // settingsLink 아이콘 색상 업데이트
        if let hc = settingsLinkHostingController {
            let textColor: UIColor
            if let theme = theme {
                textColor = theme.keyTextColor
            } else {
                textColor = isDark ? .white : .label
            }
            hc.rootView = SettingsLinkView(tintColor: textColor)
        }
        if isPhraseViewsSetUp {
            phraseInputHeaderView.applyTheme(theme)
            phraseInputHeaderView.updateAppearance(isDark: isDark)
            phraseInputView.applyTheme(theme)
            phraseInputView.updateAppearance(isDark: isDark)
        }
        quickNoteListView?.applyTheme(theme)
        quickNoteListView?.updateAppearance(isDark: isDark)
        quickNoteReadView?.applyTheme(theme)
        quickNoteReadView?.updateAppearance(isDark: isDark)
        quickNoteEditView?.applyTheme(theme)
        quickNoteEditView?.updateAppearance(isDark: isDark)
        calculatorView?.applyTheme(theme)
        calculatorView?.updateAppearance(isDark: isDark)
        chatReplyView?.applyTheme(theme)
        chatReplyView?.updateAppearance(isDark: isDark)
    }

    // MARK: - Status Popup (Proposal 02)

    private var statusPopupView: StatusPopupView?

    private func showStatusPopup() {
        hideContextMenu()
        guard statusPopupView == nil else {
            hideStatusPopup()
            return
        }
        guard let inputView = self.inputView else { return }

        let popup = StatusPopupView()
        popup.translatesAutoresizingMaskIntoConstraints = false
        inputView.addSubview(popup)
        NSLayoutConstraint.activate([
            popup.topAnchor.constraint(equalTo: toolbarView.bottomAnchor),
            popup.leadingAnchor.constraint(equalTo: inputView.leadingAnchor),
            popup.trailingAnchor.constraint(equalTo: inputView.trailingAnchor),
            popup.bottomAnchor.constraint(equalTo: inputView.bottomAnchor),
        ])

        // Populate data
        let corrUsed = DailyUsageManager.shared.correctionCount
        let corrRemain = DailyUsageManager.shared.remainingCorrections
        let corrTotal = corrUsed + corrRemain
        let transUsed = DailyUsageManager.shared.translationCount
        let transRemain = DailyUsageManager.shared.remainingTranslations
        let transTotal = transUsed + transRemain
        let tier = SubscriptionStatus.shared.currentTier
        let planName: String
        switch tier {
        case .free: planName = "Free"
        case .pro: planName = "Pro"
        case .premium: planName = "Premium"
        }
        popup.update(corrUsed: corrUsed, corrTotal: corrTotal,
                     transUsed: transUsed, transTotal: transTotal,
                     planName: planName, isPro: tier != .free)

        popup.onUpgradeTap = { [weak self] in
            self?.hideStatusPopup()
            self?.openContainingApp(path: "paywall")
        }
        popup.onDismiss = { [weak self] in
            self?.hideStatusPopup()
        }

        popup.alpha = 0
        UIView.animate(withDuration: 0.2) {
            popup.alpha = 1
        }

        statusPopupView = popup
        inputView.bringSubviewToFront(toastLabel)
    }

    private func hideStatusPopup() {
        guard let popup = statusPopupView else { return }
        UIView.animate(withDuration: 0.15, animations: {
            popup.alpha = 0
        }) { _ in
            popup.removeFromSuperview()
        }
        statusPopupView = nil
    }

    // MARK: - Context Menu (Proposal 02)

    private var contextMenuView: ContextMenuView?

    private func showContextMenu() {
        hideStatusPopup()
        guard contextMenuView == nil else {
            hideContextMenu()
            return
        }
        guard let inputView = self.inputView else { return }

        let menu = ContextMenuView()
        menu.translatesAutoresizingMaskIntoConstraints = false
        inputView.addSubview(menu)
        NSLayoutConstraint.activate([
            menu.topAnchor.constraint(equalTo: toolbarView.bottomAnchor),
            menu.leadingAnchor.constraint(equalTo: inputView.leadingAnchor),
            menu.trailingAnchor.constraint(equalTo: inputView.trailingAnchor),
            menu.bottomAnchor.constraint(equalTo: inputView.bottomAnchor),
        ])

        menu.onSettingsTap = { [weak self] in
            self?.hideContextMenu()
            self?.openContainingApp(path: "settings")
        }
        menu.onHelpTap = { [weak self] in
            self?.hideContextMenu()
            self?.openContainingApp(path: "help")
        }
        menu.onDismiss = { [weak self] in
            self?.hideContextMenu()
        }

        menu.alpha = 0
        UIView.animate(withDuration: 0.2) {
            menu.alpha = 1
        }

        contextMenuView = menu
        inputView.bringSubviewToFront(toastLabel)
    }

    private func hideContextMenu() {
        guard let menu = contextMenuView else { return }
        UIView.animate(withDuration: 0.15, animations: {
            menu.alpha = 0
        }) { _ in
            menu.removeFromSuperview()
        }
        contextMenuView = nil
    }

    // MARK: - Return Key Mode Update (Proposal 03)

    private func updateReturnKeyForCurrentMode() {
        let hasText: Bool
        switch currentMode {
        case .translationMode:
            hasText = !modeTextInputHandler.fullText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            keyboardLayoutView.updateReturnKey(mode: .translationMode, hasText: hasText)
        case .correctionMode:
            hasText = !modeTextInputHandler.fullText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            keyboardLayoutView.updateReturnKey(mode: .correctionMode, hasText: hasText)
        case .defaultMode, .phraseInputMode, .quickNoteMode, .chatReplyMode:
            keyboardLayoutView.clearReturnKeyOverride()
        }
    }
}


// MARK: - TextInputHandlerDelegate

extension KeyboardViewController: TextInputHandlerDelegate {
    func textInputHandler(_ handler: TextInputHandler, didUpdateBuffer text: String) {
        let displayText = handler.fullText
        switch currentMode {
        case .correctionMode:
            correctionInputView.setDisplayText(displayText)
            correctionManager.requestCorrection(text: displayText)
        case .phraseInputMode:
            phraseInputView.setDisplayText(displayText)
        case .translationMode:
            translationInputView.setDisplayText(displayText)
            translationManager.requestTranslation(text: displayText)
        case .quickNoteMode:
            if handler === quickNoteTextInputHandler, case .editing = quickNoteSubState {
                quickNoteEditView?.setDisplayText(displayText)
                quickNoteEditView?.updateCharCount(displayText.count)
            }
        case .chatReplyMode:
            break
        case .defaultMode:
            break
        }
        updateReturnKeyForCurrentMode()
    }

    func textInputHandler(_ handler: TextInputHandler, didUpdateComposing text: String) {
        let displayText = handler.fullText
        switch currentMode {
        case .correctionMode:
            correctionInputView.setDisplayText(displayText)
            correctionManager.requestCorrection(text: displayText)
        case .phraseInputMode:
            phraseInputView.setDisplayText(displayText)
        case .translationMode:
            translationInputView.setDisplayText(displayText)
            translationManager.requestTranslation(text: displayText)
        case .quickNoteMode:
            if handler === quickNoteTextInputHandler, case .editing = quickNoteSubState {
                quickNoteEditView?.setDisplayText(displayText)
                quickNoteEditView?.updateCharCount(displayText.count)
            }
        case .chatReplyMode:
            break
        case .defaultMode:
            break
        }
        updateReturnKeyForCurrentMode()
    }
}

// MARK: - ChatReplyManagerDelegate

extension KeyboardViewController: ChatReplyManagerDelegate {
    func chatReplyManager(_ manager: ChatReplyManager, didGenerate replies: [String]) {
        guard let view = chatReplyView else { return }
        guard view.superview != nil else { return }
        view.displayReplies(replies)

        let tone = ChatReplyGeneratorView.toneAPIValues[safe: view.selectedToneIndex] ?? "Friendly"
        let joinedReplies = replies.joined(separator: "\n---\n")
        HistoryManager.shared.addItem(
            type: .chatReply,
            original: view.contextMessage,
            result: joinedReplies,
            metadata: tone
        )

        DailyUsageManager.shared.recordChatReply()
    }

    func chatReplyManager(_ manager: ChatReplyManager, didFailWith error: String) {
        guard let view = chatReplyView else { return }
        view.showError(error)
    }
}

// MARK: - CorrectionManagerDelegate

extension KeyboardViewController: CorrectionManagerDelegate {
    func correctionManager(_ manager: CorrectionManager, didCorrect text: String, language: String) {
        textProxyManager.updateProxy(textDocumentProxy)
        textProxyManager.replaceText(with: text)
    }

    func correctionManager(_ manager: CorrectionManager, didFailWithError error: TranslationError) {
        switch error {
        case .timeout:
            showStatusMessage(L("keyboard.error.timeout"))
        case .offline:
            showStatusMessage(L("keyboard.error.offline"))
        case .rateLimited:
            showStatusMessage(L("keyboard.error.rate_limited"))
        case .networkError, .serverError, .invalidResponse:
            showStatusMessage(L("keyboard.error.correct_failed"))
        }
    }

    // 오타교정 진행 로그
    func correctionManagerDidStartCorrecting(_ manager: CorrectionManager) {
        // showStatusMessage(L("keyboard.status.correcting"))
    }
}

// MARK: - TranslationManagerDelegate

extension KeyboardViewController: TranslationManagerDelegate {
    func translationManager(_ manager: TranslationManager, didTranslate text: String, from source: String, to target: String) {
        textProxyManager.updateProxy(textDocumentProxy)
        textProxyManager.replaceText(with: text)
    }

    func translationManager(_ manager: TranslationManager, didFailWithError error: TranslationError) {
        switch error {
        case .timeout:
            showStatusMessage(L("keyboard.error.timeout"))
        case .offline:
            showStatusMessage(L("keyboard.error.offline"))
        case .rateLimited:
            showStatusMessage(L("keyboard.error.rate_limited"))
        case .networkError, .serverError, .invalidResponse:
            showStatusMessage(L("keyboard.error.translate_failed"))
        }
    }

    // 번역 진행 로그
    func translationManagerDidStartTranslating(_ manager: TranslationManager) {
        // showStatusMessage(L("keyboard.status.translating"))
    }
}

// MARK: - QuickNote Mode

extension KeyboardViewController {

    private func toggleQuickNoteMode() {
        if currentMode == .quickNoteMode {
            autoSaveIfNeeded()
            switchMode(to: .defaultMode)
        } else {
            switchMode(to: .quickNoteMode)
        }
    }

    // MARK: - Dictation

    private func startDictation() {
        guard !isShowingDictation else { return }

        // Secure field / phone pad guard
        if textDocumentProxy.isSecureTextEntry == true { return }
        if let keyboardType = textDocumentProxy.keyboardType {
            switch keyboardType {
            case .phonePad, .namePhonePad:
                return
            default:
                break
            }
        }

        let coordinator = DictationSessionCoordinator()
        coordinator.delegate = self
        coordinator.openURLHandler = { [weak self] url in
            self?.openURL(url)
        }

        let overlay = DictationOverlayView()
        overlay.delegate = self
        overlay.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(overlay)

        NSLayoutConstraint.activate([
            overlay.topAnchor.constraint(equalTo: view.topAnchor),
            overlay.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            overlay.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            overlay.bottomAnchor.constraint(equalTo: view.bottomAnchor),
        ])

        let applier = DictationTextApplier()
        applier.mode = .rollbackLive
        applier.overlay = overlay

        let locale = AppGroupManager.shared.string(forKey: DictationConstants.DefaultsKeys.dictationPreferredLocale) ?? "en-US"
        overlay.updateLocale(locale)

        dictationCoordinator = coordinator
        dictationOverlay = overlay
        dictationTextApplier = applier
        isShowingDictation = true

        keyboardLayoutView.isHidden = true
        toolbarView.isHidden = true

        applier.reset(sessionId: coordinator.sessionId)
        let started = coordinator.startDictation(locale: locale, proxy: textDocumentProxy)
        if !started {
            dismissDictation()
        }
    }

    /// viewDidAppear에서 호출 — active dictation session이 있으면 overlay 자동 복구
    private func tryRecoverDictationSession() {
        let coordinator = DictationSessionCoordinator()
        guard coordinator.tryRecoverSession() else { return }

        coordinator.delegate = self
        coordinator.openURLHandler = { [weak self] url in
            self?.openURL(url)
        }

        let overlay = DictationOverlayView()
        overlay.delegate = self
        overlay.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(overlay)

        NSLayoutConstraint.activate([
            overlay.topAnchor.constraint(equalTo: view.topAnchor),
            overlay.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            overlay.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            overlay.bottomAnchor.constraint(equalTo: view.bottomAnchor),
        ])

        let applier = DictationTextApplier()
        applier.mode = .rollbackLive
        applier.overlay = overlay
        applier.reset(sessionId: coordinator.sessionId)

        overlay.updateLocale(coordinator.locale)

        // Phase별 정확한 UI 세팅
        switch coordinator.state {
        case .paused:
            overlay.setPausedState()
        case .waitingForAck:
            overlay.updateStatus("Connecting...")
        default:
            overlay.setRecordingState()
        }

        dictationCoordinator = coordinator
        dictationOverlay = overlay
        dictationTextApplier = applier
        isShowingDictation = true

        keyboardLayoutView.isHidden = true
        toolbarView.isHidden = true
    }

    private func dismissDictation() {
        dictationCoordinator?.cleanup()
        dictationCoordinator = nil
        dictationOverlay?.removeFromSuperview()
        dictationOverlay = nil
        dictationTextApplier = nil
        isShowingDictation = false
        keyboardLayoutView.isHidden = false
        toolbarView.isHidden = false
    }

    private func openURL(_ url: URL) {
        var responder: UIResponder? = self
        while let r = responder {
            if let application = r as? UIApplication {
                application.open(url, options: [:], completionHandler: nil)
                return
            }
            responder = r.next
        }
    }

    // MARK: - Chat Reply Generator

    private func showChatReplyGenerator() {
        guard !isShowingChatReply else { return }

        guard hasFullAccess() else {
            showStatusMessage(L("keyboard.error.full_access"))
            return
        }

        guard UIPasteboard.general.hasStrings,
              let clipText = UIPasteboard.general.string,
              !clipText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            showToast(L("chatreply.copy_first"))
            return
        }

        closeCalculator()
        hideEmojiKeyboard()
        hideClipboardHistory()
        hideSavedPhrases()

        isShowingChatReply = true

        #if DEBUG
        let memBefore = currentMemoryMB()
        kbLogger.info("[ChatReply] SHOW start: \(String(format: "%.2f", memBefore))MB")
        #endif

        let view = ChatReplyGeneratorView()
        view.translatesAutoresizingMaskIntoConstraints = false

        view.onClose = { [weak self] in
            self?.closeChatReplyGenerator()
        }
        view.onInsert = { [weak self] text in
            self?.textDocumentProxy.insertText(text)
            self?.closeChatReplyGenerator()
        }
        view.onRequestGenerate = { [weak self] request in
            self?.triggerChatReplyGeneration(request: request)
        }
        view.onRequestRegenerate = { [weak self] in
            self?.regenerateChatReply()
        }
        view.onCopy = { [weak self] _ in
            self?.showToast(L("chatreply.copied"))
        }
        view.onToneChanged = { [weak self] in
            self?.modeTextInputHandler.commitComposing()
        }
        view.onRequestHeightUpdate = { [weak self] neededHeight in
            guard let self = self else { return }
            if neededHeight <= 0 {
                // 기본 높이로 복귀 (setup 상태)
                self.chatReplyExpandedHeight = 0
                self.keyboardLayoutView.isHidden = false
                self.toolbarView.isHidden = false
            } else {
                // Results 상태: 키보드 숨기고 확장
                self.chatReplyExpandedHeight = neededHeight
                self.keyboardLayoutView.isHidden = true
            }
            self.updateHeight(for: .chatReplyMode, animated: true)
        }
        view.onBack = { [weak self] in
            guard let self = self else { return }
            self.chatReplyView?.showSubState(.setup)
        }

        let manager = ChatReplyManager()
        manager.delegate = self
        chatReplyManager = manager

        view.setContext(clipText)

        let disclosureKey = "chatReplyAIDisclosureSeen"
        if !(AppGroupManager.shared.bool(forKey: disclosureKey)) {
            showToast(L("chatreply.ai_first_use_notice"))
            AppGroupManager.shared.set(true, forKey: disclosureKey)
        }

        switchMode(to: .chatReplyMode)

        guard let inputView = inputView else {
            isShowingChatReply = false
            return
        }

        inputView.addSubview(view)

        NSLayoutConstraint.activate([
            view.leadingAnchor.constraint(equalTo: inputView.leadingAnchor),
            view.trailingAnchor.constraint(equalTo: inputView.trailingAnchor),
            view.topAnchor.constraint(equalTo: inputView.topAnchor),
            view.bottomAnchor.constraint(equalTo: inputView.bottomAnchor),
        ])

        chatReplyView = view

        // Calculator 패턴: 키보드+툴바 숨기고 전체 영역 커버
        keyboardLayoutView.isHidden = true
        toolbarView.isHidden = true
        inputView.bringSubviewToFront(view)
        inputView.bringSubviewToFront(toastLabel)

        if let theme = loadTheme() {
            view.applyTheme(theme)
        }
        let isDarkMode = textDocumentProxy.keyboardAppearance == .dark
        view.updateAppearance(isDark: isDarkMode)

        view.alpha = 0
        UIView.animate(withDuration: 0.2) { view.alpha = 1 }

        checkMemorySafetyNet()

        #if DEBUG
        let memAfter = currentMemoryMB()
        kbLogger.info("[ChatReply] SHOW end: \(String(format: "%.2f", memAfter))MB (delta: +\(String(format: "%.2f", memAfter - memBefore))MB)")
        #endif
    }

    private func closeChatReplyGenerator() {
        guard let view = chatReplyView else { return }

        #if DEBUG
        let memBefore = currentMemoryMB()
        kbLogger.info("[ChatReply] CLOSE start: \(String(format: "%.2f", memBefore))MB")
        #endif

        chatReplyManager?.cancelPending()
        chatReplyManager?.clearCache()
        chatReplyManager = nil

        view.prepareForDismiss()
        view.removeFromSuperview()
        chatReplyView = nil

        modeTextInputHandler.clear()

        isShowingChatReply = false

        keyboardLayoutView.isHidden = false
        toolbarView.isHidden = false

        switchMode(to: .defaultMode)

        triggerSystemCacheCleanup()
        checkMemorySafetyNet()

        #if DEBUG
        let memAfter = currentMemoryMB()
        kbLogger.info("[ChatReply] CLOSE end: \(String(format: "%.2f", memAfter))MB (delta: \(String(format: "%.2f", memAfter - memBefore))MB)")
        #endif
    }

    private func handleChatReplyModeKey(_ key: String) {
        // v3.1: Direction 입력 제거 — 키보드 숨김 상태에서 호출되지 않음
        return
    }

    private func triggerChatReplyGeneration(request: ChatReplyRequest) {
        guard let view = chatReplyView else { return }

        modeTextInputHandler.commitComposing()

        let language = detectLanguage(request.context)
        let finalRequest = ChatReplyRequest(
            context: request.context,
            tone: request.tone,
            direction: "",
            language: language
        )

        view.showSubState(.loading)

        chatReplyManager?.generate(request: finalRequest)
    }

    private func regenerateChatReply() {
        guard let view = chatReplyView else { return }

        let tone = ChatReplyGeneratorView.toneAPIValues[safe: view.selectedToneIndex] ?? "Friendly"
        let request = ChatReplyRequest(
            context: view.contextMessage,
            tone: tone,
            direction: "",
            language: detectLanguage(view.contextMessage)
        )

        view.showSubState(.loading)
        chatReplyManager?.generate(request: request, skipCache: true)
    }

    private func detectLanguage(_ text: String) -> String {
        for scalar in text.unicodeScalars {
            if (0xAC00...0xD7AF).contains(scalar.value) ||
               (0x1100...0x11FF).contains(scalar.value) {
                return "ko"
            }
            if (0x3040...0x309F).contains(scalar.value) ||
               (0x30A0...0x30FF).contains(scalar.value) {
                return "ja"
            }
            if (0x4E00...0x9FFF).contains(scalar.value) {
                return "zh"
            }
        }
        return "en"
    }

    // MARK: - Calculator

    private func showCalculator() {
        guard let inputView = self.inputView else { return }

        #if DEBUG
        let memBefore = currentMemoryMB()
        kbLogger.info("🔬 showCalculator START — Memory: \(memBefore, format: .fixed(precision: 2)) MB")
        #endif

        modeBeforeCalculator = currentMode

        calculatorView?.removeFromSuperview()
        calculatorView = nil

        keyboardLayoutView.prepareForDismiss()

        let calc = CalculatorView()
        calc.translatesAutoresizingMaskIntoConstraints = false

        calc.onClose = { [weak self] in
            self?.closeCalculator()
        }
        calc.onInsert = { [weak self] text in
            self?.textDocumentProxy.insertText(text)
        }

        inputView.addSubview(calc)
        calculatorView = calc

        NSLayoutConstraint.activate([
            calc.topAnchor.constraint(equalTo: inputView.topAnchor),
            calc.leadingAnchor.constraint(equalTo: inputView.leadingAnchor),
            calc.trailingAnchor.constraint(equalTo: inputView.trailingAnchor),
            calc.bottomAnchor.constraint(equalTo: inputView.bottomAnchor),
        ])

        toolbarView.isHidden = true
        keyboardLayoutView.isHidden = true

        let isDark = textDocumentProxy.keyboardAppearance == .dark
        let theme = loadTheme()
        calc.applyTheme(theme)
        calc.updateAppearance(isDark: isDark)

        calc.alpha = 0
        UIView.animate(withDuration: 0.2) {
            calc.alpha = 1
        }

        inputView.bringSubviewToFront(toastLabel)

        #if DEBUG
        let memAfter = currentMemoryMB()
        kbLogger.info("🔬 showCalculator END — Memory: \(memAfter, format: .fixed(precision: 2)) MB (delta: \(memAfter - memBefore, format: .fixed(precision: 2)) MB)")
        #endif

        checkMemorySafetyNet()
    }

    private func closeCalculator() {
        guard let calc = calculatorView else { return }

        #if DEBUG
        let memBefore = currentMemoryMB()
        kbLogger.info("🔬 closeCalculator START — Memory: \(memBefore, format: .fixed(precision: 2)) MB")
        #endif

        calc.removeFromSuperview()
        calculatorView = nil

        if let previousMode = modeBeforeCalculator {
            modeBeforeCalculator = nil
            switchMode(to: previousMode)
        } else {
            toolbarView.isHidden = false
            keyboardLayoutView.isHidden = false
        }

        // updateKeyboardAppearance 제거 — switchMode가 이미 필요한 뷰 복원 수행
        // 테마는 계산기 사용 중 변경 불가하므로 재적용 불필요
        // 애니메이션 재시작은 keyboardLayoutView.isHidden = false 시 자동

        #if DEBUG
        let memAfter = currentMemoryMB()
        kbLogger.info("🔬 closeCalculator END — Memory: \(memAfter, format: .fixed(precision: 2)) MB (delta: \(memAfter - memBefore, format: .fixed(precision: 2)) MB)")
        #endif
    }

    private func showQuickNoteList() {
        guard let inputView = self.inputView else { return }
        #if DEBUG
        let memBefore = currentMemoryMB()
        kbLogger.info("🔬 showQuickNoteList START — Memory: \(memBefore, format: .fixed(precision: 2)) MB")
        #endif

        // CC-2: 편집/읽기 뷰가 있으면 제거
        quickNoteEditView?.removeFromSuperview()
        quickNoteEditView = nil
        quickNoteReadView?.removeFromSuperview()
        quickNoteReadView = nil
        quickNoteTextInputHandler = nil
        editingNote = nil
        quickNoteSubState = .list

        // 리스트 뷰 생성
        let listView = QuickNoteListView()
        listView.translatesAutoresizingMaskIntoConstraints = false
        inputView.addSubview(listView)
        quickNoteListView = listView

        // 키보드 숨기고 리스트가 전체 영역 사용
        keyboardLayoutView.isHidden = true

        NSLayoutConstraint.activate([
            listView.topAnchor.constraint(equalTo: inputView.topAnchor, constant: Heights.topPadding),
            listView.leadingAnchor.constraint(equalTo: inputView.leadingAnchor),
            listView.trailingAnchor.constraint(equalTo: inputView.trailingAnchor),
            listView.bottomAnchor.constraint(equalTo: inputView.bottomAnchor),
        ])

        setupQuickNoteListCallbacks()
        applyQuickNoteTheme()
        listView.reloadNotes()

        inputView.bringSubviewToFront(toastLabel)
        #if DEBUG
        let memAfter = currentMemoryMB()
        kbLogger.info("🔬 showQuickNoteList END — Memory: \(memAfter, format: .fixed(precision: 2)) MB (delta: \(memAfter - memBefore, format: .fixed(precision: 2)) MB)")
        #endif
    }

    private func setupQuickNoteListCallbacks() {
        // CC-3: [weak self]
        quickNoteListView?.onNoteTap = { [weak self] note in
            self?.enterQuickNoteRead(note: note)
        }
        quickNoteListView?.onNewNote = { [weak self] in
            self?.enterQuickNoteEdit(note: nil)
        }
        quickNoteListView?.onDeleteNote = { [weak self] noteId in
            QuickNoteManager.shared.deleteNote(id: noteId)
            self?.quickNoteListView?.reloadNotes()
        }
        quickNoteListView?.onClose = { [weak self] in
            self?.toggleQuickNoteMode()
        }
    }

    private func enterQuickNoteRead(note: QuickNote) {
        guard let inputView = self.inputView else { return }
        #if DEBUG
        let memBefore = currentMemoryMB()
        kbLogger.info("🔬 showQuickNoteRead START — Memory: \(memBefore, format: .fixed(precision: 2)) MB")
        #endif

        quickNoteSubState = .reading(note)

        // 리스트 뷰 제거
        quickNoteListView?.removeFromSuperview()
        quickNoteListView = nil

        // 읽기 뷰 생성
        let readView = QuickNoteReadView()
        readView.translatesAutoresizingMaskIntoConstraints = false
        readView.configure(with: note)
        inputView.addSubview(readView)
        quickNoteReadView = readView

        setupQuickNoteReadCallbacks(readView, note: note)

        // 키보드 숨김 상태 유지
        keyboardLayoutView.isHidden = true

        NSLayoutConstraint.activate([
            readView.topAnchor.constraint(equalTo: inputView.topAnchor, constant: Heights.topPadding),
            readView.leadingAnchor.constraint(equalTo: inputView.leadingAnchor),
            readView.trailingAnchor.constraint(equalTo: inputView.trailingAnchor),
            readView.bottomAnchor.constraint(equalTo: inputView.bottomAnchor),
        ])

        applyQuickNoteTheme()
        inputView.bringSubviewToFront(toastLabel)
        #if DEBUG
        let memAfter = currentMemoryMB()
        kbLogger.info("🔬 showQuickNoteRead END — Memory: \(memAfter, format: .fixed(precision: 2)) MB (delta: \(memAfter - memBefore, format: .fixed(precision: 2)) MB)")
        #endif
    }

    private func setupQuickNoteReadCallbacks(_ readView: QuickNoteReadView, note: QuickNote) {
        readView.onBack = { [weak self] in
            self?.returnToQuickNoteList()
        }
        readView.onEdit = { [weak self] note in
            self?.transitionFromReadToEdit(note: note)
        }
        readView.onPaste = { [weak self] content in
            self?.textDocumentProxy.insertText(content)
        }
        readView.onCopy = { [weak self] content in
            guard let self = self else { return }
            if self.hasFullAccess() {
                UIPasteboard.general.string = content
                self.showStatusMessage(L("quicknote.copied"))
            } else {
                self.showStatusMessage(L("keyboard.error.full_access"))
            }
        }
    }

    private func transitionFromReadToEdit(note: QuickNote) {
        quickNoteReadView?.removeFromSuperview()
        quickNoteReadView = nil
        enterQuickNoteEdit(note: note)
    }

    private func enterQuickNoteEdit(note: QuickNote?) {
        guard let inputView = self.inputView else { return }
        #if DEBUG
        let memBefore = currentMemoryMB()
        kbLogger.info("🔬 showQuickNoteEdit START — Memory: \(memBefore, format: .fixed(precision: 2)) MB")
        #endif

        // READ 뷰가 남아있으면 제거
        quickNoteReadView?.removeFromSuperview()
        quickNoteReadView = nil

        editingNote = note
        quickNoteSubState = .editing(note)

        // CC-2: 리스트 뷰 제거
        quickNoteListView?.removeFromSuperview()
        quickNoteListView = nil

        // TextInputHandler 초기화
        quickNoteTextInputHandler = TextInputHandler()
        quickNoteTextInputHandler?.delegate = self
        quickNoteTextInputHandler?.maxNewlineCount = 50
        quickNoteTextInputHandler?.maxLength = AppConstants.Limits.quickNoteMaxLength
        if let existingText = note?.content {
            quickNoteTextInputHandler?.setInitialText(existingText)
        }

        // 편집 뷰 생성 — 키보드 아래에 삽입하여 터치 이벤트 간섭 방지
        let editView = QuickNoteEditView()
        editView.translatesAutoresizingMaskIntoConstraints = false
        inputView.insertSubview(editView, belowSubview: keyboardLayoutView)
        quickNoteEditView = editView

        // 키보드 표시
        keyboardLayoutView.isHidden = false

        quickNoteTopConstraint = keyboardLayoutView.topAnchor.constraint(equalTo: editView.bottomAnchor)
        quickNoteTopConstraint?.priority = .defaultHigh
        quickNoteTopConstraint?.isActive = true

        NSLayoutConstraint.activate([
            editView.topAnchor.constraint(equalTo: inputView.topAnchor, constant: Heights.topPadding),
            editView.leadingAnchor.constraint(equalTo: inputView.leadingAnchor),
            editView.trailingAnchor.constraint(equalTo: inputView.trailingAnchor),
        ])

        setupQuickNoteEditCallbacks()
        editView.configure(with: note)
        applyQuickNoteTheme()

        editView.onHeightChanged = { [weak self] _ in
            self?.updateHeight(for: .quickNoteMode, animated: true)
        }

        updateHeight(for: .quickNoteMode, animated: true)
        inputView.bringSubviewToFront(toastLabel)
        checkAutoCapitalize()
        #if DEBUG
        let memAfter = currentMemoryMB()
        kbLogger.info("🔬 showQuickNoteEdit END — Memory: \(memAfter, format: .fixed(precision: 2)) MB (delta: \(memAfter - memBefore, format: .fixed(precision: 2)) MB)")
        #endif
    }

    private func setupQuickNoteEditCallbacks() {
        // CC-3: [weak self] — onSave 제거 (autoSaveIfNeeded에서 일원화)
        quickNoteEditView?.onClearText = { [weak self] in
            self?.quickNoteTextInputHandler?.clear()
        }
        quickNoteEditView?.onPaste = { [weak self] content in
            self?.textDocumentProxy.insertText(content)
        }
        quickNoteEditView?.onCopy = { [weak self] content in
            // CC-5: Full Access 체크
            guard let self = self else { return }
            if self.hasFullAccess() {
                UIPasteboard.general.string = content
                self.showStatusMessage(L("quicknote.copied"))
            } else {
                self.showStatusMessage(L("keyboard.error.full_access"))
            }
        }
        quickNoteEditView?.onClose = { [weak self] in
            self?.autoSaveIfNeeded()
            self?.returnToQuickNoteList()
        }
    }

    private func returnToQuickNoteList() {
        editingNote = nil
        quickNoteSubState = .list

        // CC-2: 뷰 메모리 반환
        quickNoteTopConstraint?.isActive = false
        quickNoteTopConstraint = nil
        quickNoteReadView?.removeFromSuperview()
        quickNoteReadView = nil
        quickNoteEditView?.removeFromSuperview()
        quickNoteEditView = nil
        quickNoteTextInputHandler = nil

        showQuickNoteList()
        updateHeight(for: .quickNoteMode, animated: true)
    }

    // CC-4: 자동 저장
    private func autoSaveIfNeeded() {
        guard case .editing = quickNoteSubState,
              let handler = quickNoteTextInputHandler else { return }

        handler.commitComposing()

        let content = handler.fullText
        guard !content.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return }

        if let existingNote = editingNote {
            QuickNoteManager.shared.updateNote(id: existingNote.id, content: content)
        } else {
            QuickNoteManager.shared.addNote(content)
            editingNote = nil
        }
    }

    private func applyQuickNoteTheme() {
        let isDark = traitCollection.userInterfaceStyle == .dark
        let theme = loadTheme()

        quickNoteListView?.applyTheme(theme)
        quickNoteListView?.updateAppearance(isDark: isDark)
        quickNoteReadView?.applyTheme(theme)
        quickNoteReadView?.updateAppearance(isDark: isDark)
        quickNoteEditView?.applyTheme(theme)
        quickNoteEditView?.updateAppearance(isDark: isDark)
    }

    func handleQuickNoteModeKey(_ key: String) {
        guard case .editing = quickNoteSubState else { return }
        guard let handler = quickNoteTextInputHandler else { return }

        switch key {
        case KeyboardLayoutView.backKey:
            handler.handleBackspace()
        case KeyboardLayoutView.returnKey:
            handler.handleNewline()
        case " ":
            handler.handleSpace()
        default:
            let isKorean = isKoreanJamo(key)
            if let char = key.first {
                handler.handleKey(char, isKorean: isKorean)
            }
        }

        checkAutoCapitalize()
    }
}

// MARK: - SwiftUI Settings Link

struct SettingsLinkView: View {
    var tintColor: UIColor = .label

    var body: some View {
        Link(destination: URL(string: "translatorkeyboard://settings")!) {
            Image("icon_toolbar_settings")
                .renderingMode(.template)
                .resizable()
                .aspectRatio(contentMode: .fit)
                .frame(width: 20, height: 20)
                .foregroundColor(Color(tintColor))
                .frame(width: 36, height: 34)
                .contentShape(Rectangle())
        }
    }
}

// MARK: - DictationSessionCoordinatorDelegate

extension KeyboardViewController: DictationSessionCoordinatorDelegate {

    func dictationCoordinator(_ coordinator: DictationSessionCoordinator, didChangeState state: KeyboardDictationState) {
        DispatchQueue.main.async { [weak self] in
            guard let self = self else { return }
            switch state {
            case .active:
                self.dictationOverlay?.setRecordingState()
            case .paused:
                self.dictationOverlay?.setPausedState()
            case .error(let message):
                self.dictationOverlay?.setErrorState(message)
            case .idle:
                self.dismissDictation()
            default:
                break
            }
        }
    }

    func dictationCoordinator(_ coordinator: DictationSessionCoordinator, didReceivePartial text: String) {
        DispatchQueue.main.async { [weak self] in
            guard let self = self, let applier = self.dictationTextApplier else { return }
            let payload = DictationStatePayload(
                sessionId: coordinator.sessionId,
                phase: .recording,
                locale: coordinator.locale,
                partialText: text,
                finalText: nil,
                errorMessage: nil,
                errorCode: nil,
                audioLevel: nil,
                version: UInt64(Date().timeIntervalSince1970 * 1000),
                updatedAt: Date()
            )
            applier.applyPartial(payload, proxy: self.textDocumentProxy)
        }
    }

    func dictationCoordinator(_ coordinator: DictationSessionCoordinator, didReceiveFinal text: String) {
        DispatchQueue.main.async { [weak self] in
            guard let self = self, let applier = self.dictationTextApplier else { return }
            let payload = DictationStatePayload(
                sessionId: coordinator.sessionId,
                phase: .completed,
                locale: coordinator.locale,
                partialText: text,
                finalText: text,
                errorMessage: nil,
                errorCode: nil,
                audioLevel: nil,
                version: UInt64(Date().timeIntervalSince1970 * 1000),
                updatedAt: Date()
            )
            applier.applyFinal(payload, proxy: self.textDocumentProxy)
            self.dismissDictation()
        }
    }

    func dictationCoordinatorDidCancel(_ coordinator: DictationSessionCoordinator) {
        DispatchQueue.main.async { [weak self] in
            self?.dismissDictation()
        }
    }
}

// MARK: - DictationOverlayViewDelegate

extension KeyboardViewController: DictationOverlayViewDelegate {

    func dictationOverlayDidTapBack() {
        // Back = same as X: stop recognition, keep text
        dictationOverlayDidTapStop()
    }

    func dictationOverlayDidTapPause() {
        dictationCoordinator?.sendPause()
    }

    func dictationOverlayDidTapResume() {
        dictationCoordinator?.sendResume()
    }

    func dictationOverlayDidTapCancel() {
        guard let coordinator = dictationCoordinator else { return }
        coordinator.forceShutdown(reason: "user_cancel")
        dismissDictation()
    }

    func dictationOverlayDidTapClear() {
        dictationCoordinator?.sendClear()
        dictationTextApplier?.clearInsertedText(proxy: textDocumentProxy)
    }

    /// X = stop recognition, keep inserted text, force shutdown with kill signal
    func dictationOverlayDidTapStop() {
        guard let coordinator = dictationCoordinator else {
            dismissDictation()
            return
        }

        coordinator.forceShutdown(reason: "user_stop")
        dismissDictation()
    }
}
