import UIKit
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

    #if DEBUG
    /// 프로세스 내 가장 이른 코드 실행 시점 (static initializer)
    static let firstCodeEntryTime: CFAbsoluteTime = {
        let t = CFAbsoluteTimeGetCurrent()
        NSLog("[ActivationTrace] firstCodeEntry = %.4f", t)
        return t
    }()
    #endif

    #if DEBUG
    /// Unique build marker — used by `strings <KeyboardExtension binary>` to
    /// verify the device is actually running v3 reusable-surface code, not a
    /// stale build (the previous prompt cycle observed log strings missing in
    /// device logs even when source contained them). Logged once in `init`
    /// so the literal is retained in the binary.
    static let memorySurfaceBuildMarker = "ReusableKeyboardSurface_v3"
    #endif

    private var currentMode: KeyboardMode = .defaultMode

    // MARK: - Debug Logger
    private let kbLogger = Logger(subsystem: "com.translatorkeyboard.keyboard", category: "SettingsLink")
    private static let staticLogger = Logger(subsystem: "com.translatorkeyboard.keyboard", category: "SettingsLink")

    // MARK: - Active Instance Gating

    /// 현재 화면에 표시 중인 유일한 active instance (weak — 누수 방지)
    private static weak var activeVisibleController: KeyboardViewController?

    /// self가 현재 active instance인지 확인
    private var isActiveInstance: Bool {
        Self.activeVisibleController === self
    }

    /// Safe early activation: window + size ready 시점에서 active 승격
    /// viewDidAppear보다 먼저 active를 잡아 초기 consumeDeferred가 실행되게 한다
    private func promoteToActiveIfFirstVisibleCandidate(source: String) {
        // 이미 active가 있으면 skip (다른 인스턴스가 선점한 경우)
        guard Self.activeVisibleController == nil else {
            #if DEBUG
            NSLog("[InstanceGate] earlyActivate skipped source=%@ reason=alreadyHasActive self=%@", source, String(describing: Unmanaged.passUnretained(self).toOpaque()))
            #endif
            return
        }
        // 최소 visible 조건: window + non-zero bounds
        guard view.window != nil, keyboardLayoutView.bounds.width > 0 else {
            #if DEBUG
            NSLog("[InstanceGate] earlyActivate skipped source=%@ reason=notReady self=%@", source, String(describing: Unmanaged.passUnretained(self).toOpaque()))
            #endif
            return
        }

        // ── 승격: explicit handoff ──
        #if DEBUG
        let _eaDelta = (CFAbsoluteTimeGetCurrent() - Self.firstCodeEntryTime) * 1000
        NSLog("[InstanceGate] earlyActivate source=%@ self=%@ deltaSinceFirstCode=%.2fms", source, String(describing: Unmanaged.passUnretained(self).toOpaque()), _eaDelta)
        #endif
        Self.activeVisibleController = self
        keyboardLayoutView.isOwnedByActiveController = true
    }

    // MARK: - UI Components

    // ════════════════════════════════════════════
    // Reusable keyboard surface (v3) — process-local sharing of the base
    // toolbar + keyboardLayoutView across `KeyboardViewController` lifecycles.
    // Per-instance views (translation/correction/phrase/emoji/clipboard/etc.)
    // are still instance-local and lazy.
    //
    // The previous per-cycle UI graph churn was the dominant source of the
    // `viewDidLoad.end` baseline drift; reusing the same UIKit object graph
    // across cycles stops that allocation churn at the source.
    // ════════════════════════════════════════════

    /// Shared keyboard surface across the keyboard extension process.
    /// Allocated lazily on first access; only destroyed by
    /// `destroySharedKeyboardSurfaceIfHidden` while hidden + above the high
    /// memory threshold.
    private static var sharedKeyboardSurface: ReusableKeyboardSurface?

    /// Number of `ReusableKeyboardSurface` instances created (monotonic).
    /// Should usually be `1` in a healthy 30-cycle run.
    private static var sharedSurfaceCreateCount: Int = 0

    /// Read-through to the shared surface's toolbar view.
    private var toolbarView: ToolbarView { acquireKeyboardSurface().toolbarView }

    /// Read-through to the shared surface's keyboard layout view.
    private var keyboardLayoutView: KeyboardLayoutView { acquireKeyboardSurface().keyboardLayoutView }

    private lazy var translationLanguageBar = TranslationLanguageBar()
    private lazy var translationInputView = TranslationInputView()
    private lazy var correctionLanguageBar = CorrectionLanguageBar()
    private lazy var correctionInputView = TranslationInputView()
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

    // MARK: - Unit Converter
    private var unitConverterView: UnitConverterView?
    private var modeBeforeUnitConverter: KeyboardMode?

    // MARK: - Date/Time Insert
    private var dateTimeMenuView: UIView?

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

    // MARK: - No-Exit Memory Stabilization

    private enum MemoryPressureState: String {
        case normal
        case softPressure
        case invisiblePressure
        case stabilizationPending
        case survival
    }

    private var memoryPressureState: MemoryPressureState = .normal
    private var shouldDeepCleanOnDisappear = false
    private var needsLazyRecreationOnNextAppear = false

    /// Guard: heavy `viewWillDisappear` cleanup runs at most once per visible session.
    /// Reset in `viewWillAppear` (re-entering visibility). The system sometimes calls
    /// `viewWillDisappear` more than once for the same visible session during
    /// host-app transitions (notification center, app switcher), and the heavy
    /// teardown then races with the next instance's `viewDidLoad` and contributes
    /// to the baseline drift.
    private var didRunDismissCleanupForCurrentVisibility = false

    /// Guard: KLV/Toolbar callbacks have been nilled after dismiss. `viewWillAppear`
    /// re-installs them via `setupCallbacks()` when this is true so reused
    /// controller instances remain functional.
    private var didNilCallbacksAfterDismiss = false

    /// Track whether this controller currently owns the shared surface
    /// attachment. Used by `viewWillDisappear` to gate detach against owner
    /// race conditions.
    private var didAttachSharedSurface = false
    private var lastMemoryPressureTransitionAt: CFTimeInterval = 0
    private var stableLowMemoryObservationCount = 0
    private var idleMemoryCleanupWorkItem: DispatchWorkItem?
    private var lastHeavyFeatureEvent: String?
    private var lastHeavyFeatureAt: CFTimeInterval = 0

    // Language state
    private var sourceLanguageCode: String = "ko"
    private var targetLanguageCode: String = "en"
    private var correctionLanguageCode: String = "ko"
    private var isLanguagePickerVisible = false

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
        BlackboxAnomalyLogger.shared.record("init(nibName) self=\(Unmanaged.passUnretained(self).toOpaque())")
        #if DEBUG
        _ = Self.firstCodeEntryTime // static initializer 강제 트리거
        let delta = (CFAbsoluteTimeGetCurrent() - Self.firstCodeEntryTime) * 1000
        NSLog("[ActivationTrace] init(nibName) self=%@ deltaSinceFirstCode=%.2fms marker=%@", String(describing: Unmanaged.passUnretained(self).toOpaque()), delta, Self.memorySurfaceBuildMarker)
        #endif
    }

    required init?(coder: NSCoder) {
        super.init(coder: coder)
        CoreTextCacheManager.activate()
        BlackboxAnomalyLogger.shared.record("init(coder) self=\(Unmanaged.passUnretained(self).toOpaque())")
        #if DEBUG
        _ = Self.firstCodeEntryTime
        let delta = (CFAbsoluteTimeGetCurrent() - Self.firstCodeEntryTime) * 1000
        NSLog("[ActivationTrace] init(coder) self=%@ deltaSinceFirstCode=%.2fms", String(describing: Unmanaged.passUnretained(self).toOpaque()), delta)
        #endif
    }

    deinit {
        #if DEBUG
        let deinitMemory = Self.measurePhysFootprint()
        debugLogMemoryAttribution(event: "deinit", phase: "start", extra: "children=\(children.count)")
        kbLogger.warning("💀 KeyboardViewController DEINIT — pid=\(ProcessInfo.processInfo.processIdentifier) [cycle \(Self.lifecycleCount)]")
        kbLogger.warning("💀 children.count at deinit = \(self.children.count)")
        kbLogger.warning("💀 Memory at DEINIT: \(deinitMemory, format: .fixed(precision: 2)) MB (phys_footprint)")
        #endif

        // Active instance 정리
        if Self.activeVisibleController === self {
            Self.activeVisibleController = nil
        }

        // NotificationCenter 정리 (스레드 무관 — iOS 9+ 안전)
        NotificationCenter.default.removeObserver(self)
        idleMemoryCleanupWorkItem?.cancel()
        idleMemoryCleanupWorkItem = nil

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
        debugLogMemoryAttribution(event: "deinit", phase: "end")
        #endif
    }

    override func loadView() {
        #if DEBUG
        let _lvStart = CFAbsoluteTimeGetCurrent()
        let _lvDelta = (_lvStart - Self.firstCodeEntryTime) * 1000
        NSLog("[ActivationTrace] loadView START self=%@ deltaSinceFirstCode=%.2fms", String(describing: Unmanaged.passUnretained(self).toOpaque()), _lvDelta)
        #endif
        super.loadView()
        #if DEBUG
        let _lvEnd = CFAbsoluteTimeGetCurrent()
        NSLog("[ActivationTrace] loadView END delta=%.2fms deltaSinceFirstCode=%.2fms", (_lvEnd - _lvStart) * 1000, (_lvEnd - Self.firstCodeEntryTime) * 1000)
        #endif
    }

    override func viewDidLoad() {
        super.viewDidLoad()
        BlackboxAnomalyLogger.shared.record("viewDidLoad START self=\(Unmanaged.passUnretained(self).toOpaque())")
        #if DEBUG
        NSLog("══════════════════════════════════════")
        NSLog("═══  Keyboard Loaded  ═══")
        NSLog("══════════════════════════════════════")
        let _vdlDelta = (CFAbsoluteTimeGetCurrent() - Self.firstCodeEntryTime) * 1000
        NSLog("[ActivationTrace] viewDidLoad START self=%@ deltaSinceFirstCode=%.2fms cycle=%d", String(describing: Unmanaged.passUnretained(self).toOpaque()), _vdlDelta, Self.lifecycleCount + 1)
        #endif
        // CoreTextCacheManager.activate()는 init()으로 이동됨 (Phase 4)
        #if DEBUG
        CoreTextCacheManager.resetInterceptCounters()
        kbLogger.info("📊 [Phase4] Swizzle 인터셉트 카운터 리셋")
        kbLogger.info("📌 viewDidLoad START — pid=\(ProcessInfo.processInfo.processIdentifier)")
        kbLogger.info("📌 Memory at viewDidLoad: \(self.currentMemoryMB(), format: .fixed(precision: 2)) MB")
        kbLogger.info("📌 Memory comparison — phys_footprint: \(self.currentMemoryMB(), format: .fixed(precision: 2)) MB, resident_size: \(self.currentResidentMB(), format: .fixed(precision: 2)) MB")
        kbLogger.info("📌 self address = \(String(describing: Unmanaged.passUnretained(self).toOpaque()))")
        #endif

        #if DEBUG
        debugLogMemoryAttribution(event: "viewDidLoad", phase: "start")
        let _cs0 = CACurrentMediaTime()
        #endif
        HistoryManager.shared.migrateClipboardHistoryIfNeeded()
        #if DEBUG
        let _cs1 = CACurrentMediaTime()
        debugLogMemoryAttribution(event: "setupUI", phase: "start")
        #endif
        setupUI()
        setupHeightConstraint()  // 조기 설치 — host-side layout pass 최소화
        #if DEBUG
        let _cs2 = CACurrentMediaTime()
        debugLogMemoryAttribution(event: "setupUI", phase: "end")
        #endif
        setupDelegates()
        #if DEBUG
        let _cs3 = CACurrentMediaTime()
        #endif
        setupCallbacks()
        #if DEBUG
        let _cs4 = CACurrentMediaTime()
        let _cs5 = _cs4
        #endif
        loadCachedSettings()
        // Final-state 필수 값을 첫 build 이전에 확정 — late async rebuild 제거 목적
        // 이 설정들은 가벼운 UserDefaults read이므로 viewDidLoad 비용 증가 미미
        loadNumberRowSetting()
        loadPeriodKeySetting()
        loadKeyboardLanguageSetting()
        #if DEBUG
        let _cs6 = CACurrentMediaTime()
        debugLogMemoryAttribution(event: "switchModeInitial", phase: "start")
        #endif
        switchMode(to: .defaultMode)
        #if DEBUG
        let _cs7 = CACurrentMediaTime()
        debugLogMemoryAttribution(event: "switchModeInitial", phase: "end")
        #endif
        restoreState()
        #if DEBUG
        let _cs8 = CACurrentMediaTime()
        debugLogMemoryAttribution(event: "loadTouchLearningData", phase: "start")
        #endif

        // Phase 2: load touch learning data
        keyboardLayoutView.loadTouchLearningData()
        #if DEBUG
        let _cs9 = CACurrentMediaTime()
        debugLogMemoryAttribution(event: "loadTouchLearningData", phase: "end")
        #endif
        // Phase 3: suggestion subsystem — deferred to first frame to avoid blocking keyboard usability
        // keyboardLayoutView.predictionEngine will be nil until prewarm completes;
        // KeyboardLayoutView handles nil predictionEngine gracefully (returns empty probabilities).
        #if DEBUG
        let _cs10 = CACurrentMediaTime()
        NSLog("[ColdStart][viewDidLoad] migrateClipboardHistoryIfNeeded = %.2fms", (_cs1 - _cs0) * 1000)
        NSLog("[ColdStart][viewDidLoad] setupUI = %.2fms", (_cs2 - _cs1) * 1000)
        NSLog("[ColdStart][viewDidLoad] setupDelegates = %.2fms", (_cs3 - _cs2) * 1000)
        NSLog("[ColdStart][viewDidLoad] setupCallbacks = %.2fms", (_cs4 - _cs3) * 1000)
        NSLog("[ColdStart][viewDidLoad] loadCachedSettings = %.2fms", (_cs6 - _cs5) * 1000)
        NSLog("[ColdStart][viewDidLoad] switchMode = %.2fms", (_cs7 - _cs6) * 1000)
        NSLog("[ColdStart][viewDidLoad] restoreState = %.2fms", (_cs8 - _cs7) * 1000)
        NSLog("[ColdStart][viewDidLoad] loadTouchLearningData = %.2fms", (_cs9 - _cs8) * 1000)
        NSLog("[ColdStart][viewDidLoad] total = %.2fms (suggestion deferred), Memory: %.2f MB", (_cs10 - _cs0) * 1000, self.currentMemoryMB())
        NSLog("[ActivationTrace] viewDidLoad END self=%@ deltaSinceFirstCode=%.2fms", String(describing: Unmanaged.passUnretained(self).toOpaque()), (CFAbsoluteTimeGetCurrent() - Self.firstCodeEntryTime) * 1000)
        #endif

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
        debugLogMemoryAttribution(event: "viewDidLoad", phase: "end")

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
        let currentMB = currentMemoryMB()
        #if DEBUG
        debugLogMemoryAttribution(event: "didReceiveMemoryWarning", phase: "start")
        debugPublicMemoryLog(String(format: "[MemoryStabilization] didReceiveMemoryWarning memory=%.2fMB state=%@", currentMB, memoryPressureState.rawValue))
        #endif

        if currentMB >= Self.memorySurvivalEnterMB || memoryPressureState == .survival {
            enterSurvivalMode(currentMB: currentMB, source: "system.warning")
        } else {
            enterInvisiblePressure(currentMB: currentMB, source: "system.warning")
        }

        #if DEBUG
        debugPublicMemoryLog(String(format: "[MemoryStabilization] didReceiveMemoryWarning after=%.2fMB state=%@", currentMemoryMB(), memoryPressureState.rawValue))
        debugLogMemoryAttribution(event: "didReceiveMemoryWarning", phase: "end")
        #endif
    }

    @objc private func powerStateDidChange() {
        keyboardLayoutView.handlePowerStateChange()
    }

    override func viewWillAppear(_ animated: Bool) {
        super.viewWillAppear(animated)
        BlackboxAnomalyLogger.shared.record("viewWillAppear self=\(Unmanaged.passUnretained(self).toOpaque())")
        #if DEBUG
        NSLog("[ActivationTrace] viewWillAppear START self=%@ deltaSinceFirstCode=%.2fms", String(describing: Unmanaged.passUnretained(self).toOpaque()), (CFAbsoluteTimeGetCurrent() - Self.firstCodeEntryTime) * 1000)
        kbLogger.info("📌 viewWillAppear — pid=\(ProcessInfo.processInfo.processIdentifier), Memory: \(self.currentMemoryMB(), format: .fixed(precision: 2)) MB")
        kbLogger.info("📌 settingsLinkContainer.subviews=\(self.toolbarView.settingsLinkContainer.subviews.count)")
        debugLogMemoryAttribution(event: "viewWillAppear", phase: "start")
        #endif

        // Allow heavy dismiss cleanup to run once per upcoming visible session.
        didRunDismissCleanupForCurrentVisibility = false

        // If a previous dismiss nilled callbacks (Phase B teardown), re-install
        // them so a reused controller instance is functional on this appearance.
        if didNilCallbacksAfterDismiss {
            setupCallbacks()
            didNilCallbacksAfterDismiss = false
            #if DEBUG
            debugLogMemoryAttribution(event: "viewWillAppear", phase: "callbacksReinstalled")
            #endif
        }

        applyKeyboardInterfaceStyleOverride()
        if needsLazyRecreationOnNextAppear {
            keyboardLayoutView.enterInvisibleMemoryPressureMode()
            #if DEBUG
            debugPublicMemoryLog("[MemoryStabilization] next appear uses lazy recreation; heavy effects deferred")
            #endif
        }

        // ════════════════════════════════════════════
        // 조기 해제 복원 — 같은 인스턴스 재사용 시 (알림센터, 앱 스위처 등)
        // viewWillDisappear에서 정리한 리소스를 필요 시 재생성
        // ════════════════════════════════════════════

        // ── 즉시 필요한 것만 동기 실행 (startup batch로 build churn 억제) ──
        #if DEBUG
        let _wa0 = CACurrentMediaTime()
        #endif
        textProxyManager.updateProxy(textDocumentProxy)
        #if DEBUG
        let _wa1 = CACurrentMediaTime()
        #endif
        setupHeightConstraint()
        #if DEBUG
        let _wa2 = CACurrentMediaTime()
        #endif
        keyboardLayoutView.beginStartupBatch()
        loadCachedSettings()
        #if DEBUG
        let _wa3 = CACurrentMediaTime()
        #endif
        toolbarView.rebuildToolbarIfNeeded()
        #if DEBUG
        let _wa4 = CACurrentMediaTime()
        #endif

        // 새 calibration seed가 있으면 reload (기존 online data 보존)
        keyboardLayoutView.reloadCalibrationSeedIfNeeded()
        #if DEBUG
        let _wa5 = CACurrentMediaTime()
        #endif

        // Phase 7: 키보드 오픈 시 테마 + 애니메이션 확실히 초기화
        // rebuildKeyboard: false — batch commit에서 1회만 rebuild
        #if DEBUG
        debugLogMemoryAttribution(event: "updateKeyboardAppearance", phase: "start", extra: "caller=viewWillAppear.sync")
        #endif
        updateKeyboardAppearance(rebuildKeyboard: false, caller: "viewWillAppear.sync")
        keyboardLayoutView.endStartupBatch(reason: "startup.sync.commit")
        #if DEBUG
        debugLogMemoryAttribution(event: "updateKeyboardAppearance", phase: "end", extra: "caller=viewWillAppear.sync")
        let _wa6 = CACurrentMediaTime()
        NSLog("[ColdStart][viewWillAppear][sync] updateProxy = %.2fms", (_wa1 - _wa0) * 1000)
        NSLog("[ColdStart][viewWillAppear][sync] setupHeightConstraint = %.2fms", (_wa2 - _wa1) * 1000)
        NSLog("[ColdStart][viewWillAppear][sync] loadCachedSettings = %.2fms", (_wa3 - _wa2) * 1000)
        NSLog("[ColdStart][viewWillAppear][sync] rebuildToolbarIfNeeded = %.2fms", (_wa4 - _wa3) * 1000)
        NSLog("[ColdStart][viewWillAppear][sync] calibration+misc = %.2fms", (_wa5 - _wa4) * 1000)
        NSLog("[ColdStart][viewWillAppear][sync] updateKeyboardAppearance = %.2fms", (_wa6 - _wa5) * 1000)
        NSLog("[ColdStart][viewWillAppear][sync] total = %.2fms, containerSubviews=%d", (_wa6 - _wa0) * 1000, self.toolbarView.settingsLinkContainer.subviews.count)
        #endif

        // ── 나머지는 다음 런루프에서 실행 (키보드 UI 먼저 표시) ──
        DispatchQueue.main.async { [weak self] in
            guard let self = self else { return }
            #if DEBUG
            let _aa0 = CACurrentMediaTime()
            #endif
            self.keyboardLayoutView.beginStartupBatch()
            LocalizationManager.shared.reload()
            self.reloadLocalizedStrings()
            #if DEBUG
            let _aa1 = CACurrentMediaTime()
            #endif
            self.loadNumberRowSetting()
            #if DEBUG
            let _aa2 = CACurrentMediaTime()
            #endif
            self.loadPeriodKeySetting()
            #if DEBUG
            let _aa3 = CACurrentMediaTime()
            #endif
            self.loadKeyPreviewSetting()
            self.loadLatinAlternativesSetting()
            #if DEBUG
            let _aa4 = CACurrentMediaTime()
            #endif
            self.loadKeyboardLanguageSetting()
            #if DEBUG
            let _aa5 = CACurrentMediaTime()
            #endif
            self.updateReturnKeyAppearance()
            self.checkAutoCapitalize()
            self.keyboardLayoutView.endStartupBatch(reason: "startup.async.commit")
            #if DEBUG
            let _aa6 = CACurrentMediaTime()
            NSLog("[ColdStart][viewWillAppear][async] localization = %.2fms", (_aa1 - _aa0) * 1000)
            NSLog("[ColdStart][viewWillAppear][async] loadNumberRowSetting = %.2fms", (_aa2 - _aa1) * 1000)
            NSLog("[ColdStart][viewWillAppear][async] loadPeriodKeySetting = %.2fms", (_aa3 - _aa2) * 1000)
            NSLog("[ColdStart][viewWillAppear][async] keyPreview+latinAlt = %.2fms", (_aa4 - _aa3) * 1000)
            NSLog("[ColdStart][viewWillAppear][async] loadKeyboardLanguageSetting = %.2fms", (_aa5 - _aa4) * 1000)
            NSLog("[ColdStart][viewWillAppear][async] returnKey+autoCap = %.2fms", (_aa6 - _aa5) * 1000)
            NSLog("[ColdStart][viewWillAppear][async] total = %.2fms, Memory: %.2f MB", (_aa6 - _aa0) * 1000, self.currentMemoryMB())
            #endif
        }

        hasUserTypedSinceAppeared = false
        toolbarView.hideSuggestions()

        // Delay pasteboard access until the user explicitly opens clipboard history.
        // This avoids the system paste permission prompt racing with the keyboard's
        // initial presentation during onboarding verification and similar first-open flows.
        stopClipboardMonitoring()

        AppGroupManager.shared.set(self.hasFullAccess, forKey: AppConstants.UserDefaultsKeys.keyboardFullAccessEnabled)
        if needsLazyRecreationOnNextAppear {
            scheduleLazyRecreationProbe()
        }
        #if DEBUG
        debugLogMemoryAttribution(event: "viewWillAppear", phase: "end")
        #endif
    }

    override func viewDidAppear(_ animated: Bool) {
        super.viewDidAppear(animated)

        // ── Active instance 최종 확정 (idempotent — early activation 이후에도 안전) ──
        if let oldActive = Self.activeVisibleController, oldActive !== self {
            oldActive.keyboardLayoutView.isOwnedByActiveController = false
            #if DEBUG
            NSLog("[InstanceGate] handoff old=%@ new=%@ source=viewDidAppear", String(describing: Unmanaged.passUnretained(oldActive).toOpaque()), String(describing: Unmanaged.passUnretained(self).toOpaque()))
            #endif
        }
        Self.activeVisibleController = self
        keyboardLayoutView.isOwnedByActiveController = true

        // ── Winner self-heal: blank keyboard shell 방지 ──
        // 다른 VC가 build를 완료했지만 이 VC가 winner로 표시된 경우,
        // 키가 비어 있으면 즉시 1회 rebuild로 self-heal
        var needsSelfHeal = keyboardLayoutView.allKeyButtons.isEmpty || keyboardLayoutView.keyboardContainer.subviews.isEmpty
        #if DEBUG
        // ── Fault injection: DEBUG 전용 강제 self-heal 트리거 ──
        let debugForceKey = "debug_force_blank_keyboard_takeover_once"
        let debugDefaults = UserDefaults(suiteName: AppConstants.appGroupIdentifier)
        if debugDefaults?.bool(forKey: debugForceKey) == true {
            NSLog("[OwnershipTakeoverTest] armed=true")
            NSLog("[OwnershipTakeoverTest] trigger self-heal injection")
            needsSelfHeal = true
            debugDefaults?.set(false, forKey: debugForceKey)
            NSLog("[OwnershipTakeoverTest] autoReset=true")
        }
        #endif
        if needsSelfHeal {
            #if DEBUG
            NSLog("[OwnershipTakeover] self-heal needed self=%@ buttons=%d containerSubs=%d bounds=%@ pendingDeferred=%d",
                  String(describing: Unmanaged.passUnretained(self).toOpaque()),
                  keyboardLayoutView.allKeyButtons.count,
                  keyboardLayoutView.keyboardContainer.subviews.count,
                  String(describing: keyboardLayoutView.bounds),
                  keyboardLayoutView.pendingBuildUntilSizedForDiagnostics ? 1 : 0)
            #endif
            BlackboxAnomalyLogger.shared.record("ownershipTakeover.selfHeal buttons=\(keyboardLayoutView.allKeyButtons.count) containerSubs=\(keyboardLayoutView.keyboardContainer.subviews.count)")
            keyboardLayoutView.setNeedsLayout()
            keyboardLayoutView.requestBuildKeyboard(reason: "viewDidAppear.ownershipTakeover")
        }

        BlackboxAnomalyLogger.shared.record("viewDidAppear active=true self=\(Unmanaged.passUnretained(self).toOpaque()) buttons=\(keyboardLayoutView.allKeyButtons.count)")
        #if DEBUG
        NSLog("[ActivationTrace] viewDidAppear self=%@ deltaSinceFirstCode=%.2fms", String(describing: Unmanaged.passUnretained(self).toOpaque()), (CFAbsoluteTimeGetCurrent() - Self.firstCodeEntryTime) * 1000)
        NSLog("[InstanceGate] didAppear active=true self=%@", String(describing: Unmanaged.passUnretained(self).toOpaque()))

        // First frame presented candidate — CATransaction completion으로 첫 frame commit 추정
        CATransaction.begin()
        CATransaction.setCompletionBlock {
            let _ffp = (CFAbsoluteTimeGetCurrent() - Self.firstCodeEntryTime) * 1000
            NSLog("[ActivationTrace] firstFramePresentedCandidate deltaSinceFirstCode=%.2fms", _ffp)
        }
        CATransaction.commit()
        #endif

        // ── Blank keyboard anomaly 체크 (첫 frame 직후) ──
        DispatchQueue.main.async { [weak self] in
            guard let self = self else { return }
            BlackboxAnomalyLogger.shared.record("anomalyCheck buttons=\(self.keyboardLayoutView.allKeyButtons.count) containerSubs=\(self.keyboardLayoutView.keyboardContainer.subviews.count) toolbarHidden=\(self.toolbarView.isHidden) klvHidden=\(self.keyboardLayoutView.isHidden) mode=\(self.currentMode)")
            BlackboxAnomalyLogger.shared.checkAndFlushIfAnomaly(
                allKeyButtonsCount: self.keyboardLayoutView.allKeyButtons.count,
                containerSubviewsCount: self.keyboardLayoutView.keyboardContainer.subviews.count,
                toolbarHidden: self.toolbarView.isHidden,
                keyboardLayoutHidden: self.keyboardLayoutView.isHidden,
                snapshot: [
                    "self": String(describing: Unmanaged.passUnretained(self).toOpaque()),
                    "mode": String(describing: self.currentMode),
                    "page": String(describing: self.keyboardLayoutView.currentPage),
                    "language": String(describing: self.keyboardLayoutView.getCurrentLanguage()),
                    "pairedLanguage": String(describing: self.keyboardLayoutView.pairedLanguage),
                    "additionalLangs": String(self.keyboardLayoutView.additionalLanguagesEnabled),
                    "allKeyButtons": String(self.keyboardLayoutView.allKeyButtons.count),
                    "containerSubviews": String(self.keyboardLayoutView.keyboardContainer.subviews.count),
                    "bounds": String(describing: self.keyboardLayoutView.bounds),
                    "toolbarHidden": String(self.toolbarView.isHidden),
                    "klvHidden": String(self.keyboardLayoutView.isHidden),
                    "isActiveInstance": String(self.isActiveInstance),
                ]
            )
        }

        checkMemorySafetyNet()  // Phase 5: 메모리 안전망

        // ── Keyboard geometry snapshot 저장 (calibration mirror용) ──
        saveKeyboardGeometrySnapshotIfNeeded()

        // Dictation session recovery: 메인앱에서 돌아왔을 때 active session 복구
        if !isShowingDictation {
            tryRecoverDictationSession()
        }

        // ── Suggestion subsystem prewarm (first-frame 이후, active instance만) ──
        guard isActiveInstance else {
            #if DEBUG
            NSLog("[InstanceGate] prewarm skipped inactive self=%@", String(describing: Unmanaged.passUnretained(self).toOpaque()))
            #endif
            return
        }
        if keyboardLayoutView.predictionEngine == nil {
            #if DEBUG
            let _spStart = CACurrentMediaTime()
            NSLog("[SuggestionInit] prewarm START active=true self=%@", String(describing: Unmanaged.passUnretained(self).toOpaque()))
            debugLogMemoryAttribution(event: "suggestionPrewarm", phase: "start")
            #endif
            let engine = suggestionManager.predictionEngineRef
            keyboardLayoutView.predictionEngine = engine
            #if DEBUG
            NSLog("[SuggestionInit] prewarm END = %.2fms", (CACurrentMediaTime() - _spStart) * 1000)
            debugLogMemoryAttribution(event: "suggestionPrewarm", phase: "end")
            #endif
        }
    }

    override func viewWillDisappear(_ animated: Bool) {
        super.viewWillDisappear(animated)

        // ── Active instance 해제 ──
        if Self.activeVisibleController === self {
            Self.activeVisibleController = nil
            keyboardLayoutView.isOwnedByActiveController = false
            #if DEBUG
            NSLog("[InstanceGate] willDisappear activeCleared=true self=%@", String(describing: Unmanaged.passUnretained(self).toOpaque()))
            #endif
        }

        #if DEBUG
        kbLogger.info("📌 viewWillDisappear START — Memory: \(self.currentMemoryMB(), format: .fixed(precision: 2)) MB")
        kbLogger.info("📌 self address = \(String(describing: Unmanaged.passUnretained(self).toOpaque()))")
        kbLogger.info("📌 children.count = \(self.children.count)")
        #endif

        // ════════════════════════════════════════════
        // Idempotent guard — `viewWillDisappear` may be called multiple times
        // for the same visible session (notification center, app switcher).
        // Heavy teardown should only run once per visible session.
        // ════════════════════════════════════════════
        let isDuplicateDismiss = didRunDismissCleanupForCurrentVisibility
        if isDuplicateDismiss {
            #if DEBUG
            debugLogMemoryAttribution(event: "viewWillDisappear", phase: "duplicateSkip")
            #endif
            // Still allow lightweight bookkeeping every time.
            // saveTouchLearningData() is also re-run here so any newly-observed
            // touch samples between the first and second dismiss are persisted.
            keyboardLayoutView.saveTouchLearningData()
            return
        }
        didRunDismissCleanupForCurrentVisibility = true

        let dismissStartMemory = currentMemoryMB()
        transitionMemoryPressureIfNeeded(
            currentMB: dismissStartMemory,
            source: "viewWillDisappear.start",
            allowRecovery: false
        )
        #if DEBUG
        debugLogMemoryAttribution(event: "viewWillDisappear", phase: "start", extra: "stage=afterTransition")
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

        // 단위 변환기 정리
        if let converter = unitConverterView {
            converter.removeFromSuperview()
            unitConverterView = nil
            modeBeforeUnitConverter = nil
        }

        // 날짜/시간 메뉴 정리
        hideDateTimeMenu()

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

        let cleanupStart = CACurrentMediaTime()

        #if DEBUG
        let mem0 = currentMemoryMB()
        let mem1 = mem0
        #endif

        // 1) KeyboardLayoutView 애니메이션 + CADisplayLink 정리
        keyboardLayoutView.performDeepMemoryCleanupForDismiss()

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
        StardustView.clearSparkImageCache()

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
        debugLogMemoryAttribution(event: "viewWillDisappear", phase: "end")
        #endif

        // ════════════════════════════════════════════
        // Phase B: sever closed-keyboard references.
        // After visibility ends, nil callbacks that retain controller/view graph
        // so the next instance's lifecycle does not race with retained closures
        // from this one. Re-installed by `setupCallbacks()` on next viewWillAppear.
        //
        // Hard constraints honored:
        //   - textDocumentProxy / composing / dictation / user text NOT touched.
        //   - Heavy animation views already torn down above; we do not change
        //     visible UX, only nil closures and idempotently clear toolbar
        //     callbacks.
        // ════════════════════════════════════════════
        keyboardLayoutView.onKeyTap = nil
        keyboardLayoutView.onLanguageChanged = nil
        keyboardLayoutView.onCursorMove = nil
        keyboardLayoutView.onTrackpadModeChanged = nil
        keyboardLayoutView.onHeightChangeNeeded = nil
        keyboardLayoutView.onFirstVisibleCandidate = nil

        toolbarView.onTranslateToggle = nil
        toolbarView.onCorrectionToggle = nil
        toolbarView.onEmojiKeyboardToggle = nil
        toolbarView.onSavedPhrasesTap = nil
        toolbarView.onClipboardTap = nil
        toolbarView.onQuickNoteTap = nil
        toolbarView.onSuggestionTap = nil
        toolbarView.onSuggestionDismiss = nil
        toolbarView.onCalculatorTap = nil
        toolbarView.onChatReplyGeneratorTap = nil
        toolbarView.onDictationTap = nil
        toolbarView.onCursorLeftTap = nil
        toolbarView.onCursorRightTap = nil
        toolbarView.onDeleteWordTap = nil
        toolbarView.onUndoTap = nil
        toolbarView.onRedoTap = nil
        toolbarView.onSelectAllTap = nil
        toolbarView.onCopyTap = nil
        toolbarView.onPasteTap = nil
        toolbarView.onCutTap = nil
        toolbarView.onCaseTransformTap = nil
        toolbarView.onDateTimeInsertTap = nil
        toolbarView.onDateTimeInsertLongPress = nil
        toolbarView.onDismissKeyboardTap = nil
        toolbarView.onUnitConverterTap = nil
        toolbarView.onSettingsTap = nil

        // Also let the toolbar release transient suggestion chips / overlays.
        toolbarView.prepareForControllerRelease()

        didNilCallbacksAfterDismiss = true
        #if DEBUG
        debugLogMemoryAttribution(event: "viewWillDisappear", phase: "callbacksNilled")
        #endif

        // ════════════════════════════════════════════
        // v3: detach the shared keyboard surface from this controller's
        // inputView. Strict owner gate inside — a stale `viewWillDisappear`
        // from a previous controller that no longer owns the surface will
        // skip detach so it cannot remove the new controller's live UI.
        //
        // We do NOT destroy the surface here; reuse is the whole point.
        // Hidden-only destroy below evaluates whether memory pressure
        // warrants tearing the surface down.
        // ════════════════════════════════════════════
        detachKeyboardSurfaceIfOwned()

        // ═══ 시스템 캐시 cleanup + malloc pressure relief — Release에서도 실행 ═══
        triggerSystemCacheCleanup()
        malloc_zone_pressure_relief(nil, 0)

        // Hidden-only destroy after pressure relief: only fires if surface
        // is no longer attached, has no owner, and current memory is above
        // the high-watermark threshold (recommended >= 38MB).
        Self.destroySharedKeyboardSurfaceIfHidden(
            reason: "viewWillDisappear",
            currentMB: currentMemoryMB()
        )

        #if DEBUG
        let memAfterRelief = currentMemoryMB()
        kbLogger.info("🔬 [malloc_pressure_relief] viewWillDisappear 후 → \(memAfterRelief, format: .fixed(precision: 2)) MB")
        kbLogger.info("📌 os_proc_available_memory: \(os_proc_available_memory() / 1024 / 1024) MB")
        debugLogMemoryAttribution(event: "viewWillDisappear", phase: "afterPressureRelief")
        #endif

        let finalMemoryAfterCleanup = currentMemoryMB()
        evaluateMemoryRecoveryIfEligible(currentMB: finalMemoryAfterCleanup, source: "viewWillDisappear")
        if finalMemoryAfterCleanup >= Self.memoryStabilizationExitMB || shouldDeepCleanOnDisappear {
            shouldDeepCleanOnDisappear = finalMemoryAfterCleanup >= Self.memoryInvisiblePressureExitMB
            needsLazyRecreationOnNextAppear = finalMemoryAfterCleanup >= Self.memoryStabilizationExitMB
            #if DEBUG
            debugPublicMemoryLog(String(
                format: "[MemoryStabilization] no direct termination after dismiss cleanup; memory=%.1fMB state=%@ lazyNextAppear=%d",
                finalMemoryAfterCleanup,
                memoryPressureState.rawValue,
                needsLazyRecreationOnNextAppear ? 1 : 0))
            #endif
        }

        #if DEBUG
        debugLogDismissSummary(physStart: dismissStartMemory, physEnd: finalMemoryAfterCleanup)
        let cleanupDurationMs = (CACurrentMediaTime() - cleanupStart) * 1000
        if cleanupDurationMs > 50 {
            debugPublicMemoryLog(String(format: "[MemoryStabilization] dismiss cleanup exceeded budget: %.1fms", cleanupDurationMs))
        } else {
            debugPublicMemoryLog(String(format: "[MemoryStabilization] dismiss cleanup duration=%.1fms", cleanupDurationMs))
        }
        #endif
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
        // v2: additional languages toggle 로딩
        let enabled = AppGroupManager.shared.bool(forKey: "additional_keyboard_language_enabled")
        keyboardLayoutView.additionalLanguagesEnabled = enabled

        let code = AppGroupManager.shared.string(forKey: AppConstants.UserDefaultsKeys.primaryKeyboardLanguage)
        let lang: KeyboardLanguage
        if enabled, let code = code, let saved = KeyboardLanguage(rawValue: code) {
            lang = saved
        } else {
            lang = .english
        }
        keyboardLayoutView.pairedLanguage = lang
        let current = keyboardLayoutView.getCurrentLanguage()
        if current != .english && current != lang {
            keyboardLayoutView.setLanguage(lang)
        }
    }

    override func textDidChange(_ textInput: UITextInput?) {
        super.textDidChange(textInput)
        // 트랙패드 모드 중에는 appearance update 억제 — blank visual이 깨지지 않게
        // 트랙패드 종료 시 buildKeyboard()에서 전체 복원됨
        guard !keyboardLayoutView.isTrackpadModeActive else { return }
        // textDidChange는 텍스트 컨텍스트만 변경 — 키보드 구조(버튼/행)는 불변
        // 외형(다크모드/테마)만 갱신하고 full rebuild는 생략
        updateKeyboardAppearance(rebuildKeyboard: false, caller: "textDidChange")
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
        heightConstraint?.priority = UILayoutPriority(999)  // .required - 1: host encapsulated layout과 충돌 방지하면서 우선 반영
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
            newHeight = Heights.topPadding + Heights.translationLanguageBar + inputH + keyArea
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

        // v3: attach shared surface (toolbar + KLV). This force-detaches any
        // stale attachment from a previous controller's inputView, then adds
        // the shared views as subviews of this controller's inputView. Per-
        // attachment constraints are activated below and stored on the
        // surface so detach can deactivate them cleanly.
        attachKeyboardSurfaceToCurrentInputView(inputView)

        // Build per-attachment constraints. These are the only constraints
        // that anchor the shared (reused) views to this controller's
        // inputView; they MUST be deactivated on detach so they don't pin
        // the shared views to a dead inputView.
        let surfaceToolbarTop = toolbarView.topAnchor.constraint(equalTo: inputView.topAnchor, constant: Heights.topPadding)
        let surfaceToolbarLeading = toolbarView.leadingAnchor.constraint(equalTo: inputView.leadingAnchor)
        let surfaceToolbarTrailing = toolbarView.trailingAnchor.constraint(equalTo: inputView.trailingAnchor)
        let surfaceToolbarHeight = toolbarView.heightAnchor.constraint(equalToConstant: Heights.toolbar)

        let surfaceKLVLeading = keyboardLayoutView.leadingAnchor.constraint(equalTo: inputView.leadingAnchor)
        let surfaceKLVTrailing = keyboardLayoutView.trailingAnchor.constraint(equalTo: inputView.trailingAnchor)
        let surfaceKLVBottom = keyboardLayoutView.bottomAnchor.constraint(equalTo: inputView.bottomAnchor)

        // Fixed height for keyboard layout — prevents stretching when system popup expands inputView
        keyboardLayoutHeightConstraint = keyboardLayoutView.heightAnchor.constraint(equalToConstant: keyAreaHeight())

        // Default: keyboard top = toolbar bottom
        keyboardTopToToolbarConstraint = keyboardLayoutView.topAnchor.constraint(equalTo: toolbarView.bottomAnchor)
        keyboardTopToToolbarConstraint?.priority = .defaultHigh

        // Activate all per-attachment constraints together so the layout
        // engine sees a consistent set in one pass.
        activateBaseSurfaceConstraints([
            surfaceToolbarTop,
            surfaceToolbarLeading,
            surfaceToolbarTrailing,
            surfaceToolbarHeight,
            surfaceKLVLeading,
            surfaceKLVTrailing,
            surfaceKLVBottom,
            keyboardLayoutHeightConstraint!,
            keyboardTopToToolbarConstraint!,
        ])

        // Toast — floating on top of everything
        // centerX/leading/trailing priority를 낮춰 width-0 startup 시 constraint conflict 방지
        inputView.addSubview(toastLabel)
        let toastCenterX = toastLabel.centerXAnchor.constraint(equalTo: inputView.centerXAnchor)
        toastCenterX.priority = .defaultHigh
        let toastLeading = toastLabel.leadingAnchor.constraint(greaterThanOrEqualTo: inputView.leadingAnchor, constant: 24)
        toastLeading.priority = .defaultHigh
        let toastTrailing = toastLabel.trailingAnchor.constraint(lessThanOrEqualTo: inputView.trailingAnchor, constant: -24)
        toastTrailing.priority = .defaultHigh
        NSLayoutConstraint.activate([
            toastCenterX,
            toastLabel.topAnchor.constraint(equalTo: inputView.topAnchor, constant: 6),
            toastLeading,
            toastTrailing,
            toastLabel.heightAnchor.constraint(equalToConstant: 32),
        ])
    }

    // MARK: - Deferred View Setup

    private func setupTranslationViewsIfNeeded() {
        guard !isTranslationViewsSetUp, let inputView = self.inputView else { return }
        #if DEBUG
        let memBefore = currentMemoryMB()
        debugLogMemoryAttribution(event: "setupTranslationViews", phase: "start")
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
        let isDark = resolvedKeyboardIsDark()
        translationLanguageBar.applyTheme(theme)
        translationLanguageBar.updateAppearance(isDark: isDark)
        translationInputView.applyTheme(theme)
        translationInputView.updateAppearance(isDark: isDark)
        #if DEBUG
        let memAfter = currentMemoryMB()
        kbLogger.info("🔬 setupTranslationViews END — Memory: \(memAfter, format: .fixed(precision: 2)) MB (delta: \(memAfter - memBefore, format: .fixed(precision: 2)) MB)")
        debugLogMemoryAttribution(event: "setupTranslationViews", phase: "end")
        #endif
    }

    private func setupCorrectionViewsIfNeeded() {
        guard !isCorrectionViewsSetUp, let inputView = self.inputView else { return }
        #if DEBUG
        let memBefore = currentMemoryMB()
        debugLogMemoryAttribution(event: "setupCorrectionViews", phase: "start")
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
        let isDark = resolvedKeyboardIsDark()
        correctionLanguageBar.applyTheme(theme)
        correctionLanguageBar.updateAppearance(isDark: isDark)
        correctionInputView.applyTheme(theme)
        correctionInputView.updateAppearance(isDark: isDark)
        #if DEBUG
        let memAfter = currentMemoryMB()
        kbLogger.info("🔬 setupCorrectionViews END — Memory: \(memAfter, format: .fixed(precision: 2)) MB (delta: \(memAfter - memBefore, format: .fixed(precision: 2)) MB)")
        debugLogMemoryAttribution(event: "setupCorrectionViews", phase: "end")
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
        // 툴바 내부 커서 — 탭해서 커서 위치 이동 (QuickNote 패턴 복제)
        translationInputView.isCaretTapEnabled = true
        translationInputView.onCaretTap = { [weak self] index in
            guard let self = self else { return }
            self.modeTextInputHandler.moveCursor(to: index)
            self.translationInputView.setCursorIndex(self.modeTextInputHandler.cursorIndex)
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
        // 툴바 내부 커서 — 탭해서 커서 위치 이동 (QuickNote 패턴 복제)
        correctionInputView.isCaretTapEnabled = true
        correctionInputView.onCaretTap = { [weak self] index in
            guard let self = self else { return }
            self.modeTextInputHandler.moveCursor(to: index)
            self.correctionInputView.setCursorIndex(self.modeTextInputHandler.cursorIndex)
        }
        correctionLanguageBar.onLanguageTap = { [weak self] in
            self?.showCorrectionLanguagePicker()
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
            self?.toggleTranslationMode()
        }
        toolbarView.onEmojiKeyboardToggle = { [weak self] in
            self?.hideContextMenu()
            self?.toggleEmojiKeyboard()
        }
        toolbarView.onCorrectionToggle = { [weak self] in
            self?.hideContextMenu()
            self?.toggleCorrectionMode()
        }
        toolbarView.onSavedPhrasesTap = { [weak self] in
            self?.hideContextMenu()
            self?.showSavedPhrases()
        }
        toolbarView.onClipboardTap = { [weak self] in
            self?.hideContextMenu()
            self?.toggleClipboardHistory()
        }
        toolbarView.onQuickNoteTap = { [weak self] in
            self?.hideContextMenu()
            self?.toggleQuickNoteMode()
        }
        toolbarView.onCalculatorTap = { [weak self] in
            self?.hideContextMenu()
            self?.showCalculator()
        }
        toolbarView.onChatReplyGeneratorTap = { [weak self] in
            self?.hideContextMenu()
            self?.showChatReplyGenerator()
        }
        toolbarView.onDictationTap = { [weak self] in
            self?.hideContextMenu()
            self?.startDictation()
        }
        toolbarView.onSettingsTap = { [weak self] in
            self?.openContainingApp(path: "settings")
        }
        toolbarView.onSuggestionTap = { [weak self] suggestion in
            self?.applySuggestion(suggestion)
        }
        toolbarView.onSuggestionDismiss = { [weak self] in
            self?.dismissSuggestions()
        }

        // Productivity editing tools — host text only
        toolbarView.onCursorLeftTap = { [weak self] in
            self?.hideContextMenu()
            self?.handleToolbarCursorLeft()
        }
        toolbarView.onCursorRightTap = { [weak self] in
            self?.hideContextMenu()
            self?.handleToolbarCursorRight()
        }
        toolbarView.onDeleteWordTap = { [weak self] in
            self?.hideContextMenu()
            self?.handleToolbarDeleteWord()
        }
        toolbarView.onUndoTap = { [weak self] in
            self?.hideContextMenu()
            self?.handleToolbarUndo()
        }
        toolbarView.onRedoTap = { [weak self] in
            self?.hideContextMenu()
            self?.handleToolbarRedo()
        }
        toolbarView.onSelectAllTap = { [weak self] in
            self?.hideContextMenu()
            self?.handleToolbarSelectAll()
        }
        toolbarView.onCopyTap = { [weak self] in
            self?.hideContextMenu()
            self?.handleToolbarCopy()
        }
        toolbarView.onPasteTap = { [weak self] in
            self?.hideContextMenu()
            self?.handleToolbarPaste()
        }
        toolbarView.onCutTap = { [weak self] in
            self?.hideContextMenu()
            self?.handleToolbarCut()
        }
        toolbarView.onCaseTransformTap = { [weak self] in
            self?.hideContextMenu()
            self?.handleToolbarCaseTransform()
        }

        // New features
        toolbarView.onDateTimeInsertTap = { [weak self] in
            self?.hideContextMenu()
            self?.handleDateTimeInsert()
        }
        toolbarView.onDateTimeInsertLongPress = { [weak self] in
            self?.hideContextMenu()
            self?.showDateTimeMenu()
        }
        toolbarView.onDismissKeyboardTap = { [weak self] in
            self?.dismissKeyboard()
        }
        toolbarView.onUnitConverterTap = { [weak self] in
            self?.hideContextMenu()
            self?.showUnitConverter()
        }

        // Keyboard layout — always present
        keyboardLayoutView.onFirstVisibleCandidate = { [weak self] in
            self?.promoteToActiveIfFirstVisibleCandidate(source: "KLV.firstVisibleCandidate")
        }
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

    // MARK: - Settings (UIKit callback — SwiftUI removed)

    // MARK: - System Cache Cleanup

    /// 시스템 프레임워크 캐시를 직접 정리한다.
    /// Release 빌드에서도 동작해야 하므로 #if DEBUG 밖에 위치한다.
    /// didReceiveMemoryWarningNotification을 직접 post하지 않는다.
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

    private func recordHeavyFeatureEvent(_ event: String) {
        lastHeavyFeatureEvent = event
        lastHeavyFeatureAt = CACurrentMediaTime()
    }

    #if DEBUG
    private struct DebugMallocSnapshot {
        let allocatedMB: Double
        let inUseMB: Double
        let freeMB: Double
    }

    private static var highVisibleBaselineCount = 0
    private static var highDeinitBaselineCount = 0
    private static var lastVisibleBaselineCycle = -1
    private static var lastDeinitBaselineCycle = -1
    private static var lastVisibleDriftLogCycle = -1
    private static var lastDeinitDriftLogCycle = -1
    private static var lastMallocDriftLogCycle = -1

    private static func debugMallocSnapshot() -> DebugMallocSnapshot {
        guard let zone = malloc_default_zone() else {
            return DebugMallocSnapshot(allocatedMB: 0, inUseMB: 0, freeMB: 0)
        }
        var stats = malloc_statistics_t()
        malloc_zone_statistics(zone, &stats)
        let allocatedMB = Double(stats.size_allocated) / (1024 * 1024)
        let inUseMB = Double(stats.size_in_use) / (1024 * 1024)
        return DebugMallocSnapshot(
            allocatedMB: allocatedMB,
            inUseMB: inUseMB,
            freeMB: allocatedMB - inUseMB
        )
    }

    private func debugCurrentThemeId() -> String {
        KeyboardTheme.currentTheme()?.id ?? "default"
    }

    private func debugOptionalViewFlags() -> String {
        [
            "emoji=\(emojiKeyboardView == nil ? 0 : 1)",
            "clipboard=\(clipboardHistoryView == nil ? 0 : 1)",
            "savedPhrases=\(savedPhrasesView == nil ? 0 : 1)",
            "languagePicker=\(languagePickerView == nil ? 0 : 1)",
            "calculator=\(calculatorView == nil ? 0 : 1)",
            "unitConverter=\(unitConverterView == nil ? 0 : 1)",
            "quickNoteList=\(quickNoteListView == nil ? 0 : 1)",
            "quickNoteRead=\(quickNoteReadView == nil ? 0 : 1)",
            "quickNoteEdit=\(quickNoteEditView == nil ? 0 : 1)",
            "chatReply=\(chatReplyView == nil ? 0 : 1)"
        ].joined(separator: " ")
    }

    private func debugAnimationViewFlags() -> String {
        // With the reusable shared surface, KLV is created lazily on first
        // surface access. Avoid forcing creation here just to log a flag set;
        // if the surface doesn't exist yet, report all-zero so the log line
        // remains attribution-safe.
        guard Self.sharedKeyboardSurface != nil else {
            return [
                "animMatrix=0",
                "animMercury=0",
                "animStardust=0",
                "animSnowfall=0",
                "animSnowfallSoft=0",
                "animCherry=0"
            ].joined(separator: " ")
        }
        return keyboardLayoutView.memoryAttributionAnimationFlags()
    }

    private func debugCheckBaselineDrift(
        event: String,
        phase: String,
        physMB: Double,
        malloc: DebugMallocSnapshot
    ) {
        let location = "\(event).\(phase)"
        let cycle = Self.lifecycleCount

        if (event == "viewDidLoad" || event == "viewWillAppear"),
           (phase == "start" || phase == "end") {
            if physMB >= 30 {
                if Self.lastVisibleBaselineCycle != cycle {
                    Self.lastVisibleBaselineCycle = cycle
                    Self.highVisibleBaselineCount += 1
                }
            } else if Self.lastVisibleBaselineCycle != cycle {
                Self.highVisibleBaselineCount = 0
            }

            if Self.highVisibleBaselineCount >= 3,
               Self.lastVisibleDriftLogCycle != cycle {
                Self.lastVisibleDriftLogCycle = cycle
                debugPublicMemoryLog(String(
                    format: "[MEM_BASELINE_DRIFT] cycle=%d location=%@ phys=%.2f allocated=%.2f inUse=%.2f free=%.2f suspect=visibleBaseline",
                    cycle, location, physMB, malloc.allocatedMB, malloc.inUseMB, malloc.freeMB))
            }
        }

        if event == "deinit",
           phase == "end",
           Self.lastDeinitBaselineCycle != cycle {
            Self.lastDeinitBaselineCycle = cycle
            if physMB >= 30 {
                Self.highDeinitBaselineCount += 1
            } else {
                Self.highDeinitBaselineCount = 0
            }

            if Self.highDeinitBaselineCount >= 3,
               Self.lastDeinitDriftLogCycle != cycle {
                Self.lastDeinitDriftLogCycle = cycle
                debugPublicMemoryLog(String(
                    format: "[MEM_BASELINE_DRIFT] cycle=%d location=%@ phys=%.2f allocated=%.2f inUse=%.2f free=%.2f suspect=deinitBaseline",
                    cycle, location, physMB, malloc.allocatedMB, malloc.inUseMB, malloc.freeMB))
            }
        }

        if malloc.allocatedMB >= 48,
           malloc.freeMB >= 18,
           Self.lastMallocDriftLogCycle != cycle {
            Self.lastMallocDriftLogCycle = cycle
            debugPublicMemoryLog(String(
                format: "[MEM_BASELINE_DRIFT] cycle=%d location=%@ phys=%.2f allocated=%.2f inUse=%.2f free=%.2f suspect=heapArenaOrRetainedCache",
                cycle, location, physMB, malloc.allocatedMB, malloc.inUseMB, malloc.freeMB))
        }
    }

    private static let memoryDebugLog = OSLog(
        subsystem: "com.translatorkeyboard.keyboard",
        category: "MemoryDebug"
    )

    private func debugPublicMemoryLog(_ message: String) {
        os_log("%{public}@", log: Self.memoryDebugLog, type: .debug, message)
    }

    /// Compact stable identity for this controller instance — DEBUG attribution only.
    /// Used to disambiguate overlapping lifecycle events between successive
    /// `KeyboardViewController` instances during open/close cycles.
    private var debugInstanceIdHex: String {
        "id=\(String(describing: Unmanaged.passUnretained(self).toOpaque()))"
    }
    #endif

    // ════════════════════════════════════════════
    // MARK: - Reusable Keyboard Surface (v3)
    // (Intentionally outside `#if DEBUG` — surface attach/detach is the core
    //  Release behavior; only log lines inside the helpers are DEBUG-gated.)
    // ════════════════════════════════════════════

    /// Process-local holder for the base keyboard surface (`ToolbarView` +
    /// `KeyboardLayoutView`). Shared across `KeyboardViewController`
    /// instances; the *only* objects intentionally retained across the
    /// extension lifecycle.
    private final class ReusableKeyboardSurface {
        let toolbarView: ToolbarView
        let keyboardLayoutView: KeyboardLayoutView
        /// Weak so a controller dropping out of the active set cannot pin the
        /// surface to a stale instance.
        weak var owner: KeyboardViewController?
        /// True between `attachKeyboardSurfaceToCurrentInputView` and
        /// `detachKeyboardSurfaceIfOwned`. Used to gate hidden-only destroy.
        var isAttached: Bool = false
        /// Monotonic — only useful for DEBUG attribution. Incremented on each
        /// attach so adjacent log lines can be correlated.
        var generation: Int = 0
        /// Constraints belonging to the *current* attachment between the
        /// shared views and the current controller's `inputView`. Deactivated
        /// on detach and on force-detach (next controller stealing
        /// attachment). Never persisted across attachments.
        var attachConstraints: [NSLayoutConstraint] = []

        init() {
            toolbarView = ToolbarView()
            keyboardLayoutView = KeyboardLayoutView()
        }
    }

    private func acquireKeyboardSurface() -> ReusableKeyboardSurface {
        if let existing = Self.sharedKeyboardSurface {
            #if DEBUG
            debugPublicMemoryLog(String(
                format: "[MEM_ATTR] event=surface.reuse t=%.3f cycle=%d %@ surfaceGen=%d surfaceId=%@ toolbarId=%@ klvId=%@",
                CACurrentMediaTime(),
                Self.lifecycleCount,
                debugInstanceIdHex,
                existing.generation,
                String(describing: ObjectIdentifier(existing)),
                String(describing: Unmanaged.passUnretained(existing.toolbarView).toOpaque()),
                String(describing: Unmanaged.passUnretained(existing.keyboardLayoutView).toOpaque())
            ))
            #endif
            return existing
        }
        let created = ReusableKeyboardSurface()
        Self.sharedSurfaceCreateCount += 1
        Self.sharedKeyboardSurface = created
        #if DEBUG
        debugPublicMemoryLog(String(
            format: "[MEM_ATTR] event=surface.create t=%.3f cycle=%d %@ createCount=%d surfaceId=%@ toolbarId=%@ klvId=%@ marker=%@",
            CACurrentMediaTime(),
            Self.lifecycleCount,
            debugInstanceIdHex,
            Self.sharedSurfaceCreateCount,
            String(describing: ObjectIdentifier(created)),
            String(describing: Unmanaged.passUnretained(created.toolbarView).toOpaque()),
            String(describing: Unmanaged.passUnretained(created.keyboardLayoutView).toOpaque()),
            Self.memorySurfaceBuildMarker
        ))
        #endif
        return created
    }

    /// Attach the shared surface to this controller's `inputView`.
    /// Idempotent for this controller — calling twice without an intervening
    /// detach is a no-op.
    ///
    /// If the surface is currently attached to another controller's input
    /// view (lifecycle overlap), force-detach: deactivate its constraints,
    /// remove from the old superview, clear that controller's attachment
    /// flag. The old controller's `viewWillDisappear` will then see
    /// `owner !== self` and skip its detach, which is the desired race
    /// guard from plan §Important Implementation Warning.
    private func attachKeyboardSurfaceToCurrentInputView(_ inputView: UIView) {
        let surface = acquireKeyboardSurface()

        // Idempotent: already attached to this controller's inputView.
        if surface.owner === self,
           surface.isAttached,
           surface.toolbarView.superview === inputView,
           surface.keyboardLayoutView.superview === inputView {
            #if DEBUG
            debugPublicMemoryLog(String(
                format: "[MEM_ATTR] event=surface.attach phase=alreadyAttached %@ surfaceGen=%d",
                debugInstanceIdHex,
                surface.generation
            ))
            #endif
            didAttachSharedSurface = true
            return
        }

        // Force-detach from previous attachment if any.
        if surface.isAttached || surface.toolbarView.superview != nil || surface.keyboardLayoutView.superview != nil {
            #if DEBUG
            let oldOwnerId: String
            if let oldOwner = surface.owner {
                oldOwnerId = String(describing: Unmanaged.passUnretained(oldOwner).toOpaque())
            } else {
                oldOwnerId = "nil"
            }
            debugPublicMemoryLog(String(
                format: "[MEM_ATTR] event=surface.attach phase=forceDetachPrevious %@ oldOwner=%@ surfaceGen=%d",
                debugInstanceIdHex,
                oldOwnerId,
                surface.generation
            ))
            #endif
            // Deactivate previous attachment constraints.
            NSLayoutConstraint.deactivate(surface.attachConstraints)
            surface.attachConstraints.removeAll()
            // Detach old previous owner's flag so its `viewWillDisappear`
            // will see no ownership and skip detach.
            surface.owner?.didAttachSharedSurface = false
            // Remove from any old superview. Safe to call when superview is nil.
            surface.toolbarView.removeFromSuperview()
            surface.keyboardLayoutView.removeFromSuperview()
            surface.owner = nil
            surface.isAttached = false
        }

        // Take ownership and attach to current input view.
        surface.generation += 1
        surface.owner = self
        [surface.toolbarView, surface.keyboardLayoutView].forEach {
            $0.translatesAutoresizingMaskIntoConstraints = false
            inputView.addSubview($0)
        }
        surface.isAttached = true
        didAttachSharedSurface = true

        // Minimal state reset to keep KLV consistent with this new controller:
        // - clear stale prediction engine so `viewDidAppear` re-assigns it
        //   from the current controller's `suggestionManager`.
        // - any caps lock / shift / page session leak between host fields is
        //   small surface area and existing `viewWillAppear` flow rebuilds
        //   keyboard appearance for the new context.
        surface.keyboardLayoutView.predictionEngine = nil

        #if DEBUG
        debugPublicMemoryLog(String(
            format: "[MEM_ATTR] event=surface.attach phase=attached %@ surfaceGen=%d createCount=%d",
            debugInstanceIdHex,
            surface.generation,
            Self.sharedSurfaceCreateCount
        ))
        #endif
    }

    /// Activate the per-attachment constraints stored on the shared surface.
    /// Called from `setupUI` after `attachKeyboardSurfaceToCurrentInputView`.
    private func activateBaseSurfaceConstraints(_ constraints: [NSLayoutConstraint]) {
        guard let surface = Self.sharedKeyboardSurface else { return }
        surface.attachConstraints = constraints
        NSLayoutConstraint.activate(constraints)
    }

    /// Detach the shared surface from this controller's `inputView`.
    /// Strict owner gate: a stale `viewWillDisappear` from a previous
    /// controller must NOT detach the new controller's live surface.
    private func detachKeyboardSurfaceIfOwned() {
        guard let surface = Self.sharedKeyboardSurface else { return }
        guard surface.owner === self else {
            #if DEBUG
            debugPublicMemoryLog(String(
                format: "[MEM_ATTR] event=surface.detach phase=skipStaleOwner %@ surfaceGen=%d",
                debugInstanceIdHex,
                surface.generation
            ))
            #endif
            return
        }
        guard didAttachSharedSurface else {
            #if DEBUG
            debugPublicMemoryLog(String(
                format: "[MEM_ATTR] event=surface.detach phase=skipNotAttached %@",
                debugInstanceIdHex
            ))
            #endif
            return
        }

        // Deactivate per-attachment constraints first (must happen before
        // removeFromSuperview so old inputView's layout pass doesn't fight
        // a deactivated constraint set against the new attachment).
        NSLayoutConstraint.deactivate(surface.attachConstraints)
        surface.attachConstraints.removeAll()

        surface.toolbarView.removeFromSuperview()
        surface.keyboardLayoutView.removeFromSuperview()
        surface.isAttached = false
        surface.owner = nil
        didAttachSharedSurface = false

        #if DEBUG
        debugPublicMemoryLog(String(
            format: "[MEM_ATTR] event=surface.detach phase=detached %@ surfaceGen=%d",
            debugInstanceIdHex,
            surface.generation
        ))
        #endif
    }

    /// Hidden-only destroy. Reusable surface is meant to live for the
    /// extension's lifetime; only release it when memory pressure is high
    /// AND we are not currently visible. Called from `viewWillDisappear`
    /// after detach and pressure-relief.
    private static func destroySharedKeyboardSurfaceIfHidden(reason: String, currentMB: Double) {
        guard let surface = sharedKeyboardSurface else { return }
        // Must not destroy while attached / owned / visible.
        guard !surface.isAttached, surface.owner == nil else {
            #if DEBUG
            os_log(
                "%{public}@",
                log: memoryDebugLog,
                type: .debug,
                "[MEM_ATTR] event=surface.destroy phase=skipAttached reason=\(reason) attached=\(surface.isAttached) hasOwner=\(surface.owner != nil)"
            )
            #endif
            return
        }
        // High-memory threshold gate.
        let threshold: Double = 38.0
        guard currentMB >= threshold else {
            #if DEBUG
            os_log(
                "%{public}@",
                log: memoryDebugLog,
                type: .debug,
                "[MEM_ATTR] event=surface.destroy phase=skipBelowThreshold reason=\(reason) currentMB=\(String(format: "%.2f", currentMB)) threshold=\(threshold)"
            )
            #endif
            return
        }

        // Tear down KLV resources fully before dropping the strong ref.
        surface.keyboardLayoutView.prepareForDismiss()
        surface.toolbarView.prepareForControllerRelease()
        // Drop superview links if any survived a misordered detach.
        surface.toolbarView.removeFromSuperview()
        surface.keyboardLayoutView.removeFromSuperview()

        sharedKeyboardSurface = nil
        malloc_zone_pressure_relief(nil, 0)

        #if DEBUG
        os_log(
            "%{public}@",
            log: memoryDebugLog,
            type: .debug,
            "[MEM_ATTR] event=surface.destroy phase=destroyed reason=\(reason) currentMB=\(String(format: "%.2f", currentMB))"
        )
        #endif
    }

    #if DEBUG
    private func debugLogMemoryAttribution(event: String, phase: String, extra: String = "") {
        let physMB = currentMemoryMB()
        let malloc = Self.debugMallocSnapshot()
        let cycle = Self.lifecycleCount
        let themeId = debugCurrentThemeId()
        let optionals = debugOptionalViewFlags()
        let animations = debugAnimationViewFlags()
        // Always tag with the controller instance id so memory attribution can
        // be matched across overlapping open/close cycles (the previous instance
        // and the next instance can coexist briefly during keyboard handoff).
        let identity = debugInstanceIdHex
        let suffix = extra.isEmpty ? "" : " \(extra)"

        let line = String(
            format: "[MEM_ATTR] event=%@ phase=%@ t=%.3f cycle=%d mode=%@ theme=%@ state=%@ phys=%.2f allocated=%.2f inUse=%.2f free=%.2f %@ %@ %@%@",
            event,
            phase,
            CACurrentMediaTime(),
            cycle,
            String(describing: currentMode),
            themeId,
            memoryPressureState.rawValue,
            physMB,
            malloc.allocatedMB,
            malloc.inUseMB,
            malloc.freeMB,
            identity,
            optionals,
            animations,
            suffix)
        debugPublicMemoryLog(line)

        debugCheckBaselineDrift(event: event, phase: phase, physMB: physMB, malloc: malloc)
    }

    private func debugLogDismissSummary(physStart: Double, physEnd: Double) {
        let age: Double
        if lastHeavyFeatureAt > 0 {
            age = CACurrentMediaTime() - lastHeavyFeatureAt
        } else {
            age = -1
        }
        let lastHeavy = lastHeavyFeatureEvent ?? "none"
        let malloc = Self.debugMallocSnapshot()
        let optionals = debugOptionalViewFlags()
        let animations = debugAnimationViewFlags()
        let line = String(
            format: "[MEM_ATTR] event=dismissSummary phase=summary t=%.3f cycle=%d mode=%@ theme=%@ state=%@ physStart=%.2f physEnd=%.2f delta=%.2f allocated=%.2f inUse=%.2f free=%.2f %@ %@ lastHeavy=%@ age=%.2f",
            CACurrentMediaTime(),
            Self.lifecycleCount,
            String(describing: currentMode),
            debugCurrentThemeId(),
            memoryPressureState.rawValue,
            physStart,
            physEnd,
            physEnd - physStart,
            malloc.allocatedMB,
            malloc.inUseMB,
            malloc.freeMB,
            optionals,
            animations,
            lastHeavy,
            age)
        debugPublicMemoryLog(line)
    }
    #endif

    // MARK: - No-Exit Memory Stabilization

    private var isAtLeastInvisibleMemoryPressure: Bool {
        switch memoryPressureState {
        case .normal, .softPressure:
            return false
        case .invisiblePressure, .stabilizationPending, .survival:
            return true
        }
    }

    private func setMemoryPressureState(_ newState: MemoryPressureState, currentMB: Double, source: String) {
        guard memoryPressureState != newState else { return }
        let oldState = memoryPressureState
        memoryPressureState = newState
        lastMemoryPressureTransitionAt = CACurrentMediaTime()
        stableLowMemoryObservationCount = 0
        #if DEBUG
        debugPublicMemoryLog(String(
            format: "[MemoryStabilization] state %@ -> %@ source=%@ memory=%.1fMB",
            oldState.rawValue,
            newState.rawValue,
            source,
            currentMB))
        #endif
    }

    private func performSoftMemoryCleanup(source: String) {
        #if DEBUG
        debugLogMemoryAttribution(event: "performSoftMemoryCleanup", phase: "start", extra: "source=\(source)")
        let before = currentMemoryMB()
        let start = CACurrentMediaTime()
        #endif

        CoreTextCacheManager.shared.clearGlyphCaches()
        FontPool.clearIfNeeded()
        URLCache.shared.removeAllCachedResponses()
        keyboardLayoutView.performVisiblePreservingCleanup()
        releaseHiddenLayerBackingStores(in: view)
        malloc_zone_pressure_relief(nil, 0)

        #if DEBUG
        let after = currentMemoryMB()
        let duration = (CACurrentMediaTime() - start) * 1000
        debugPublicMemoryLog(String(
            format: "[MemoryStabilization] soft cleanup source=%@ %.1fMB -> %.1fMB duration=%.1fms",
            source,
            before,
            after,
            duration))
        debugLogMemoryAttribution(event: "performSoftMemoryCleanup", phase: "end", extra: String(format: "source=%@ duration=%.1f", source, duration))
        #endif
    }

    private func releaseHiddenLayerBackingStores(in root: UIView) {
        for subview in root.subviews {
            if subview.isHidden || subview.alpha == 0 {
                subview.layer.contents = nil
                subview.layer.sublayers?.forEach { $0.contents = nil }
            }
            releaseHiddenLayerBackingStores(in: subview)
        }
    }

    private func releaseHiddenOptionalViewsForPressure() {
        #if DEBUG
        debugLogMemoryAttribution(event: "releaseHiddenOptionalViewsForPressure", phase: "start")
        #endif
        if let ev = emojiKeyboardView, ev.isHidden {
            ev.prepareForDismiss()
            ev.removeFromSuperview()
            emojiKeyboardView = nil
            isEmojiMode = false
        }
        if let cv = clipboardHistoryView, cv.isHidden || cv.alpha == 0 {
            cv.removeFromSuperview()
            clipboardHistoryView = nil
            stopClipboardMonitoring()
        }
        if let sv = savedPhrasesView, sv.isHidden || sv.alpha == 0 {
            sv.removeFromSuperview()
            savedPhrasesView = nil
        }
        if !isLanguagePickerVisible, let lp = languagePickerView {
            lp.removeFromSuperview()
            languagePickerView = nil
        }
        if currentMode != .quickNoteMode {
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
        if !isShowingChatReply, let view = chatReplyView {
            view.prepareForDismiss()
            view.removeFromSuperview()
            chatReplyView = nil
            chatReplyManager?.cancelPending()
            chatReplyManager?.clearCache()
            chatReplyManager = nil
            chatReplyExpandedHeight = 0
        }
        if let calc = calculatorView, calc.isHidden || calc.alpha == 0 {
            calc.removeFromSuperview()
            calculatorView = nil
            modeBeforeCalculator = nil
        }
        if let converter = unitConverterView, converter.isHidden || converter.alpha == 0 {
            converter.removeFromSuperview()
            unitConverterView = nil
            modeBeforeUnitConverter = nil
        }
        if let menu = dateTimeMenuView, menu.isHidden || menu.alpha == 0 {
            menu.removeFromSuperview()
            dateTimeMenuView = nil
        }
        ChatReplyCache.shared.clear()
        #if DEBUG
        debugLogMemoryAttribution(event: "releaseHiddenOptionalViewsForPressure", phase: "end")
        #endif
    }

    private func enterSoftPressure(currentMB: Double, source: String) {
        setMemoryPressureState(.softPressure, currentMB: currentMB, source: source)
        performSoftMemoryCleanup(source: source)
    }

    private func enterInvisiblePressure(currentMB: Double, source: String) {
        setMemoryPressureState(.invisiblePressure, currentMB: currentMB, source: source)
        shouldDeepCleanOnDisappear = true
        keyboardLayoutView.enterInvisibleMemoryPressureMode()
        performSoftMemoryCleanup(source: source)
        releaseHiddenOptionalViewsForPressure()
    }

    private func enterStabilizationPending(currentMB: Double, source: String) {
        setMemoryPressureState(.stabilizationPending, currentMB: currentMB, source: source)
        shouldDeepCleanOnDisappear = true
        needsLazyRecreationOnNextAppear = true
        keyboardLayoutView.enterInvisibleMemoryPressureMode()
        performSoftMemoryCleanup(source: source)
        releaseHiddenOptionalViewsForPressure()
    }

    private func enterSurvivalMode(currentMB: Double, source: String) {
        setMemoryPressureState(.survival, currentMB: currentMB, source: source)
        shouldDeepCleanOnDisappear = true
        needsLazyRecreationOnNextAppear = true
        keyboardLayoutView.enterSurvivalModePreservingBaseTheme()
        performSoftMemoryCleanup(source: source)
        releaseHiddenOptionalViewsForPressure()
    }

    private func performCurrentStateMaintenance(currentMB: Double, source: String) {
        switch memoryPressureState {
        case .normal:
            break
        case .softPressure:
            performSoftMemoryCleanup(source: source)
        case .invisiblePressure:
            keyboardLayoutView.enterInvisibleMemoryPressureMode()
            performSoftMemoryCleanup(source: source)
            releaseHiddenOptionalViewsForPressure()
        case .stabilizationPending:
            needsLazyRecreationOnNextAppear = true
            keyboardLayoutView.enterInvisibleMemoryPressureMode()
            performSoftMemoryCleanup(source: source)
            releaseHiddenOptionalViewsForPressure()
        case .survival:
            keyboardLayoutView.enterSurvivalModePreservingBaseTheme()
            performSoftMemoryCleanup(source: source)
            releaseHiddenOptionalViewsForPressure()
        }
    }

    private func transitionMemoryPressureIfNeeded(currentMB: Double, source: String, allowRecovery: Bool) {
        if memoryPressureState == .survival,
           currentMB > Self.memorySurvivalExitMB {
            performCurrentStateMaintenance(currentMB: currentMB, source: source)
            return
        }

        if currentMB >= Self.memorySurvivalEnterMB {
            enterSurvivalMode(currentMB: currentMB, source: source)
            return
        }

        if currentMB >= Self.memoryStabilizationEnterMB {
            if memoryPressureState == .stabilizationPending {
                performCurrentStateMaintenance(currentMB: currentMB, source: source)
            } else {
                enterStabilizationPending(currentMB: currentMB, source: source)
            }
            return
        }

        switch memoryPressureState {
        case .stabilizationPending where currentMB > Self.memoryStabilizationExitMB:
            performCurrentStateMaintenance(currentMB: currentMB, source: source)
            return
        case .invisiblePressure where currentMB > Self.memoryInvisiblePressureExitMB:
            performCurrentStateMaintenance(currentMB: currentMB, source: source)
            return
        default:
            break
        }

        if !allowRecovery, isAtLeastInvisibleMemoryPressure {
            performCurrentStateMaintenance(currentMB: currentMB, source: source)
            return
        }

        let now = CACurrentMediaTime()
        if now - lastMemoryPressureTransitionAt < Self.memoryStateTransitionCooldown {
            performCurrentStateMaintenance(currentMB: currentMB, source: source)
            return
        }

        if currentMB >= Self.memoryStabilizationEnterMB {
            enterStabilizationPending(currentMB: currentMB, source: source)
        } else if currentMB >= Self.memoryInvisiblePressureEnterMB {
            enterInvisiblePressure(currentMB: currentMB, source: source)
        } else if currentMB >= Self.memorySoftPressureEnterMB {
            enterSoftPressure(currentMB: currentMB, source: source)
        } else if allowRecovery {
            evaluateMemoryRecoveryIfEligible(currentMB: currentMB, source: source)
        }
    }

    private func evaluateMemoryRecoveryIfEligible(currentMB: Double, source: String) {
        let targetExitMB: Double
        switch memoryPressureState {
        case .normal:
            stableLowMemoryObservationCount = 0
            return
        case .softPressure:
            targetExitMB = Self.memorySoftPressureEnterMB
        case .invisiblePressure:
            targetExitMB = Self.memoryInvisiblePressureExitMB
        case .stabilizationPending:
            targetExitMB = Self.memoryStabilizationExitMB
        case .survival:
            targetExitMB = Self.memorySurvivalExitMB
        }

        guard currentMB <= targetExitMB else {
            stableLowMemoryObservationCount = 0
            return
        }

        stableLowMemoryObservationCount += 1
        guard stableLowMemoryObservationCount >= 2 else {
            #if DEBUG
            debugPublicMemoryLog(String(
                format: "[MemoryStabilization] low memory observation %d/2 source=%@ memory=%.1fMB",
                stableLowMemoryObservationCount,
                source,
                currentMB))
            #endif
            return
        }

        let nextState: MemoryPressureState
        if currentMB >= Self.memoryStabilizationExitMB {
            nextState = .stabilizationPending
        } else if currentMB >= Self.memoryInvisiblePressureExitMB {
            nextState = .invisiblePressure
        } else if currentMB >= Self.memorySoftPressureEnterMB {
            nextState = .softPressure
        } else {
            nextState = .normal
        }

        setMemoryPressureState(nextState, currentMB: currentMB, source: "\(source).recovery")
        stableLowMemoryObservationCount = 0
        shouldDeepCleanOnDisappear = nextState != .normal && nextState != .softPressure
        needsLazyRecreationOnNextAppear = nextState == .stabilizationPending || nextState == .survival

        if nextState == .normal || nextState == .softPressure {
            keyboardLayoutView.exitMemoryPressureMode()
        } else {
            keyboardLayoutView.enterInvisibleMemoryPressureMode()
        }
    }

    private func prepareForUserRequestedHeavyAllocation(source: String) {
        recordHeavyFeatureEvent(source)
        let currentMB = currentMemoryMB()
        if isAtLeastInvisibleMemoryPressure || currentMB >= Self.memoryInvisiblePressureEnterMB {
            performSoftMemoryCleanup(source: "preHeavy.\(source)")
            releaseHiddenOptionalViewsForPressure()
        }
        transitionMemoryPressureIfNeeded(currentMB: currentMemoryMB(), source: "preHeavy.\(source)", allowRecovery: false)
    }

    private func scheduleIdleMemoryCleanupIfNeeded() {
        guard isAtLeastInvisibleMemoryPressure else { return }
        idleMemoryCleanupWorkItem?.cancel()
        let work = DispatchWorkItem { [weak self] in
            guard let self = self, self.isAtLeastInvisibleMemoryPressure else { return }
            self.performSoftMemoryCleanup(source: "idle")
            self.evaluateMemoryRecoveryIfEligible(currentMB: self.currentMemoryMB(), source: "idle")
        }
        idleMemoryCleanupWorkItem = work
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.2, execute: work)
    }

    private func scheduleLazyRecreationProbe(after delay: TimeInterval = 0.35) {
        DispatchQueue.main.asyncAfter(deadline: .now() + delay) { [weak self] in
            self?.handleLazyRecreationProbe()
        }
    }

    private func handleLazyRecreationProbe() {
        guard needsLazyRecreationOnNextAppear || isAtLeastInvisibleMemoryPressure else { return }
        let currentMB = currentMemoryMB()
        transitionMemoryPressureIfNeeded(currentMB: currentMB, source: "lazyRecreationProbe", allowRecovery: true)

        if needsLazyRecreationOnNextAppear, currentMB <= Self.memoryStabilizationExitMB {
            if stableLowMemoryObservationCount < 2 {
                scheduleLazyRecreationProbe(after: 0.35)
            }
        } else if currentMB > Self.memoryStabilizationExitMB {
            #if DEBUG
            debugPublicMemoryLog(String(format: "[MemoryStabilization] heavy effects remain deferred this visible session memory=%.1fMB", currentMB))
            #endif
        }
    }

    // MARK: - Geometry Snapshot

    private static var lastGeometrySnapshotSignature: String?

    private func saveKeyboardGeometrySnapshotIfNeeded() {
        guard keyboardLayoutView.bounds.width > 0,
              !keyboardLayoutView.allKeyButtons.isEmpty,
              view.window != nil else { return }

        // Only save for English letters page
        guard keyboardLayoutView.currentPage == .letters else { return }
        guard keyboardLayoutView.getCurrentLanguage() == .english else { return }

        let screenBounds = UIScreen.main.bounds
        let inputFrameInScreen = view.convert(view.bounds, to: nil)

        // Signature-based dedupe
        let signature = "\(Int(screenBounds.width))x\(Int(screenBounds.height))_\(Int(inputFrameInScreen.origin.y))_\(Int(inputFrameInScreen.height))_\(Int(keyboardLayoutView.bounds.width))x\(Int(keyboardLayoutView.bounds.height))_nr\(keyboardLayoutView.showNumberRow)_pd\(keyboardLayoutView.showPeriodKey)_al\(keyboardLayoutView.additionalLanguagesEnabled)_\(keyboardLayoutView.pairedLanguage)"
        guard signature != Self.lastGeometrySnapshotSignature else { return }
        Self.lastGeometrySnapshotSignature = signature

        var keyFrames: [KeyboardGeometrySnapshot.KeyFrame] = []
        // Group buttons by row for col assignment
        var rowBuckets: [Int: [(key: String, centerX: CGFloat, centerY: CGFloat, width: CGFloat, height: CGFloat)]] = [:]

        for button in keyboardLayoutView.allKeyButtons {
            guard let key = button.accessibilityLabel, !key.isEmpty else { continue }
            guard let sv = button.superview else { continue }
            let frameInKLV = sv.convert(button.frame, to: keyboardLayoutView)
            let centerInScreen = keyboardLayoutView.convert(
                CGPoint(x: frameInKLV.midX, y: frameInKLV.midY), to: nil
            )
            let rowIdx = keyboardLayoutView.rowIndexForKeyCenter(frameInKLV.midY)
            rowBuckets[rowIdx, default: []].append((key, centerInScreen.x, centerInScreen.y, frameInKLV.width, frameInKLV.height))
        }

        for (rowIdx, bucket) in rowBuckets {
            let sorted = bucket.sorted { $0.centerX < $1.centerX }
            for (col, item) in sorted.enumerated() {
                keyFrames.append(.init(
                    key: item.key,
                    row: rowIdx,
                    col: col,
                    centerXInScreen: item.centerX,
                    centerYInScreen: item.centerY,
                    width: item.width,
                    height: item.height,
                    physicalSlotID: nil
                ))
            }
        }

        let klvFrameInInputView = keyboardLayoutView.frame

        let snapshot = KeyboardGeometrySnapshot(
            createdAt: Date(),
            screenWidth: screenBounds.width,
            screenHeight: screenBounds.height,
            inputViewOriginYInScreen: inputFrameInScreen.origin.y,
            inputViewHeight: inputFrameInScreen.height,
            keyFrames: keyFrames,
            showNumberRow: keyboardLayoutView.showNumberRow,
            orientationClass: "portrait",
            layoutID: "english_letters",
            keyboardLayoutOriginYInInputView: klvFrameInInputView.origin.y,
            keyboardLayoutHeight: klvFrameInInputView.height,
            toolbarHeight: 40,
            topPadding: 8,
            showPeriodKey: keyboardLayoutView.showPeriodKey,
            hasAdditionalLanguage: keyboardLayoutView.hasAdditionalLanguage,
            languageCode: "english",
            pairedLanguageCode: String(describing: keyboardLayoutView.pairedLanguage)
        )
        snapshot.save()
    }

    private func checkMemorySafetyNet() {
        #if DEBUG
        debugLogMemoryAttribution(event: "checkMemorySafetyNet", phase: "start")
        #endif
        let currentMB = currentMemoryMB()
        transitionMemoryPressureIfNeeded(currentMB: currentMB, source: "safetyNet", allowRecovery: false)
        #if DEBUG
        debugLogMemoryAttribution(event: "checkMemorySafetyNet", phase: "end")
        #endif
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

    /// No-exit memory stabilization thresholds (phys_footprint MB 기준).
    private static let memorySoftPressureEnterMB: Double = 22.0
    private static let memoryInvisiblePressureEnterMB: Double = 28.0
    private static let memoryInvisiblePressureExitMB: Double = 24.0
    private static let memoryStabilizationEnterMB: Double = 38.0
    private static let memoryStabilizationExitMB: Double = 28.0
    private static let memorySurvivalEnterMB: Double = 45.0
    private static let memorySurvivalExitMB: Double = 35.0
    private static let memoryStateTransitionCooldown: CFTimeInterval = 1.0

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
        #if DEBUG
        let _smDelta = (CFAbsoluteTimeGetCurrent() - Self.firstCodeEntryTime) * 1000
        NSLog("[BuildKeyboardTrace] switchMode START to=%@ deltaSinceFirstCode=%.2fms", String(describing: mode), _smDelta)
        #endif
        let previousMode = currentMode

        // 계산기가 열려있으면 먼저 닫기 (모드 전환 충돌 방지)
        if let calc = calculatorView {
            calc.removeFromSuperview()
            calculatorView = nil
            modeBeforeCalculator = nil
        }

        // 단위 변환기가 열려있으면 먼저 닫기
        if let converter = unitConverterView {
            converter.removeFromSuperview()
            unitConverterView = nil
            modeBeforeUnitConverter = nil
        }

        // 날짜/시간 메뉴 닫기
        hideDateTimeMenu()

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
            updateKeyboardAppearance(caller: "switchMode.translationMode")

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
            updateKeyboardAppearance(caller: "switchMode.correctionMode")

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
        #if DEBUG
        let _smEndDelta = (CFAbsoluteTimeGetCurrent() - Self.firstCodeEntryTime) * 1000
        NSLog("[BuildKeyboardTrace] switchMode END to=%@ deltaSinceFirstCode=%.2fms", String(describing: mode), _smEndDelta)
        #endif
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
        hideLanguagePicker()
        animateBookClose([correctionLanguageBar, correctionInputView]) { [weak self] in
            self?.switchMode(to: .defaultMode)
        }
    }

    // MARK: - Saved Phrases

    private func showSavedPhrases() {
        prepareForUserRequestedHeavyAllocation(source: "savedPhrases")
        #if DEBUG
        let memBefore = currentMemoryMB()
        debugLogMemoryAttribution(event: "showSavedPhrases", phase: "start")
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
            let isDarkMode = resolvedKeyboardIsDark()
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
        debugLogMemoryAttribution(event: "showSavedPhrases", phase: "end")
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
        prepareForUserRequestedHeavyAllocation(source: "clipboard")
        #if DEBUG
        let memBefore = currentMemoryMB()
        debugLogMemoryAttribution(event: "showClipboard", phase: "start")
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
            cv.onOnboardingConfirmed = { [weak self] in
                guard let self = self else { return }
                self.syncClipboardForVisibleHistory()
                self.startClipboardMonitoring()
                self.clipboardHistoryView?.reloadData()
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
            let isDarkMode = resolvedKeyboardIsDark()
            cv.applyTheme(theme)
            cv.updateAppearance(isDark: isDarkMode)
        }
        clipboardHistoryView?.reloadData()
        // Pasteboard sync/monitor는 onboarding 완료 후에만 시작
        let canReadClipboard = clipboardHistoryView?.hasCompletedOnboarding ?? false
        if canReadClipboard {
            syncClipboardForVisibleHistory()
            startClipboardMonitoring()
        } else {
            stopClipboardMonitoring()
        }
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
        debugLogMemoryAttribution(event: "showClipboard", phase: "end")
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

    private func showCorrectionLanguagePicker() {
        guard !isLanguagePickerVisible else {
            hideLanguagePicker()
            return
        }
        prepareForUserRequestedHeavyAllocation(source: "correctionLanguagePicker")
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
        prepareForUserRequestedHeavyAllocation(source: "emoji")
        #if DEBUG
        let memBefore = currentMemoryMB()
        debugLogMemoryAttribution(event: "showEmoji", phase: "start")
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
        debugLogMemoryAttribution(event: "showEmoji", phase: "end")
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
        debugLogMemoryAttribution(event: "hideEmoji", phase: "start")
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
        debugLogMemoryAttribution(event: "hideEmoji", phase: "end")
        #endif
    }

    private func hasFullAccess() -> Bool {
        if #available(iOSApplicationExtension 11.0, *) {
            return self.hasFullAccess
        }
        return false
    }

    // MARK: - Keyboard Appearance Mode

    private func currentKeyboardAppearanceMode() -> AppConstants.KeyboardAppearanceMode {
        guard let raw = AppGroupManager.shared.string(forKey: AppConstants.UserDefaultsKeys.keyboardAppearanceMode),
              let mode = AppConstants.KeyboardAppearanceMode(rawValue: raw) else {
            return .automatic
        }
        return mode
    }

    private func resolvedKeyboardIsDark() -> Bool {
        switch currentKeyboardAppearanceMode() {
        case .automatic:
            return textDocumentProxy.keyboardAppearance == .dark
        case .light:
            return false
        case .dark:
            return true
        }
    }

    private func applyKeyboardInterfaceStyleOverride() {
        switch currentKeyboardAppearanceMode() {
        case .automatic:
            view.overrideUserInterfaceStyle = .unspecified
        case .light:
            view.overrideUserInterfaceStyle = .light
        case .dark:
            view.overrideUserInterfaceStyle = .dark
        }
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
        prepareForUserRequestedHeavyAllocation(source: "languagePicker")
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
        scheduleIdleMemoryCleanupIfNeeded()
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
        // v3: Quick Note editing 중에는 메모 내부 커서 이동
        if currentMode == .quickNoteMode, case .editing = quickNoteSubState {
            moveQuickNoteCursor(horizontal: horizontal, vertical: vertical)
            return
        }

        // 툴바 내부 입력창이 활성 타겟일 때는 내부 버퍼 커서 이동
        if currentMode == .translationMode || currentMode == .correctionMode {
            moveModeCursor(horizontal: horizontal, vertical: vertical)
            return
        }

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

    /// Quick Note 내부 cursor 이동 — trackpad 대응
    private func moveQuickNoteCursor(horizontal: Int, vertical: Int) {
        guard let handler = quickNoteTextInputHandler else { return }

        if horizontal != 0 {
            handler.moveCursor(to: handler.cursorIndex + horizontal)
            quickNoteEditView?.setCursorIndex(handler.cursorIndex)
        }

        if vertical != 0 {
            let text = handler.fullText
            let lines = text.components(separatedBy: "\n")
            // 현재 cursor가 몇 번째 줄, 몇 번째 column인지 계산
            var charCount = 0
            var currentLine = 0
            var currentCol = 0
            for (i, line) in lines.enumerated() {
                let lineLen = line.count + (i < lines.count - 1 ? 1 : 0) // \n 포함
                if charCount + lineLen > handler.cursorIndex {
                    currentLine = i
                    currentCol = handler.cursorIndex - charCount
                    break
                }
                charCount += lineLen
                if i == lines.count - 1 {
                    currentLine = i
                    currentCol = handler.cursorIndex - charCount + lineLen
                }
            }

            let targetLine = max(0, min(currentLine + vertical, lines.count - 1))
            if targetLine != currentLine {
                // target 줄의 column 위치 계산
                let targetCol = min(currentCol, lines[targetLine].count)
                var newIndex = 0
                for i in 0..<targetLine {
                    newIndex += lines[i].count + 1 // +1 for \n
                }
                newIndex += targetCol
                handler.moveCursor(to: newIndex)
                quickNoteEditView?.setCursorIndex(handler.cursorIndex)
            }
        }
    }

    /// Translation / Correction 내부 cursor 이동 — 스페이스바 트랙패드 대응.
    /// moveQuickNoteCursor 와 동일 알고리즘, modeTextInputHandler + 현재 모드의 뷰 사용.
    private func moveModeCursor(horizontal: Int, vertical: Int) {
        let view: TranslationInputView
        switch currentMode {
        case .translationMode: view = translationInputView
        case .correctionMode:  view = correctionInputView
        default: return
        }

        let handler = modeTextInputHandler

        if horizontal != 0 {
            handler.moveCursor(to: handler.cursorIndex + horizontal)
            view.setCursorIndex(handler.cursorIndex)
        }

        if vertical != 0 {
            let text = handler.fullText
            let lines = text.components(separatedBy: "\n")
            var charCount = 0
            var currentLine = 0
            var currentCol = 0
            for (i, line) in lines.enumerated() {
                let lineLen = line.count + (i < lines.count - 1 ? 1 : 0)
                if charCount + lineLen > handler.cursorIndex {
                    currentLine = i
                    currentCol = handler.cursorIndex - charCount
                    break
                }
                charCount += lineLen
                if i == lines.count - 1 {
                    currentLine = i
                    currentCol = handler.cursorIndex - charCount + lineLen
                }
            }

            let targetLine = max(0, min(currentLine + vertical, lines.count - 1))
            if targetLine != currentLine {
                let targetCol = min(currentCol, lines[targetLine].count)
                var newIndex = 0
                for i in 0..<targetLine {
                    newIndex += lines[i].count + 1
                }
                newIndex += targetCol
                handler.moveCursor(to: newIndex)
                view.setCursorIndex(handler.cursorIndex)
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

    private func updateKeyboardAppearance(rebuildKeyboard: Bool = true, caller: String = "unknown") {
        #if DEBUG
        let _uka0 = CACurrentMediaTime()
        // textDidChange는 고빈도 — 콘솔 rate-limit 방지를 위해 trace 생략
        if caller != "textDidChange" {
            let _ukaDelta = (CFAbsoluteTimeGetCurrent() - Self.firstCodeEntryTime) * 1000
            NSLog("[BuildKeyboardTrace] updateKeyboardAppearance caller=%@ rebuild=%d deltaSinceFirstCode=%.2fms", caller, rebuildKeyboard ? 1 : 0, _ukaDelta)
        }
        #endif
        applyKeyboardInterfaceStyleOverride()
        let isDark = resolvedKeyboardIsDark()
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
        keyboardLayoutView.updateAppearance(isDark: isDark, rebuildKeyboard: rebuildKeyboard)
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
        savedPhrasesView?.applyTheme(theme)
        savedPhrasesView?.updateAppearance(isDark: isDark)
        clipboardHistoryView?.applyTheme(theme)
        clipboardHistoryView?.updateAppearance(isDark: isDark)

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
        unitConverterView?.applyTheme(theme)
        unitConverterView?.updateAppearance(isDark: isDark)
        chatReplyView?.applyTheme(theme)
        chatReplyView?.updateAppearance(isDark: isDark)
        #if DEBUG
        if caller != "textDidChange" {
            let _uka1 = CACurrentMediaTime()
            NSLog("[ColdStart][updateKeyboardAppearance] total = %.2fms theme=%@ isDark=%d", (_uka1 - _uka0) * 1000, theme?.id ?? "default", isDark ? 1 : 0)
        }
        #endif
    }

    // MARK: - Context Menu (Proposal 02)

    private var contextMenuView: ContextMenuView?

    private func showContextMenu() {
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
            correctionInputView.setCursorIndex(modeTextInputHandler.cursorIndex + modeTextInputHandler.composingText.count)
            correctionManager.requestCorrection(text: displayText)
        case .phraseInputMode:
            phraseInputView.setDisplayText(displayText)
        case .translationMode:
            translationInputView.setDisplayText(displayText)
            translationInputView.setCursorIndex(modeTextInputHandler.cursorIndex + modeTextInputHandler.composingText.count)
            translationManager.requestTranslation(text: displayText)
        case .quickNoteMode:
            if handler === quickNoteTextInputHandler, case .editing = quickNoteSubState {
                quickNoteEditView?.setDisplayText(displayText)
                quickNoteEditView?.updateCharCount(displayText.count)
                if let qh = quickNoteTextInputHandler {
                    quickNoteEditView?.setCursorIndex(qh.cursorIndex + qh.composingText.count)
                }
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
            correctionInputView.setCursorIndex(modeTextInputHandler.cursorIndex + modeTextInputHandler.composingText.count)
            correctionManager.requestCorrection(text: displayText)
        case .phraseInputMode:
            phraseInputView.setDisplayText(displayText)
        case .translationMode:
            translationInputView.setDisplayText(displayText)
            translationInputView.setCursorIndex(modeTextInputHandler.cursorIndex + modeTextInputHandler.composingText.count)
            translationManager.requestTranslation(text: displayText)
        case .quickNoteMode:
            if handler === quickNoteTextInputHandler, case .editing = quickNoteSubState {
                quickNoteEditView?.setDisplayText(displayText)
                quickNoteEditView?.updateCharCount(displayText.count)
                if let qh = quickNoteTextInputHandler {
                    quickNoteEditView?.setCursorIndex(qh.cursorIndex + qh.composingText.count)
                }
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

        // delegate/overlay 연결 완료 후 첫 recovered payload replay
        coordinator.replayRecoveredState()
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
        closeUnitConverter()
        hideDateTimeMenu()
        hideEmojiKeyboard()
        hideClipboardHistory()
        hideSavedPhrases()
        prepareForUserRequestedHeavyAllocation(source: "chatReply")

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
        let isDarkMode = resolvedKeyboardIsDark()
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
        prepareForUserRequestedHeavyAllocation(source: "calculator")

        #if DEBUG
        let memBefore = currentMemoryMB()
        kbLogger.info("🔬 showCalculator START — Memory: \(memBefore, format: .fixed(precision: 2)) MB")
        #endif

        modeBeforeCalculator = currentMode

        calculatorView?.removeFromSuperview()
        calculatorView = nil

        keyboardLayoutView.performDeepMemoryCleanupForDismiss()

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

        let isDark = resolvedKeyboardIsDark()
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
        prepareForUserRequestedHeavyAllocation(source: "quickNoteList")
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
        prepareForUserRequestedHeavyAllocation(source: "quickNoteRead")
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
        prepareForUserRequestedHeavyAllocation(source: "quickNoteEdit")
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
        // Cursor editing — Quick Note tap caret
        quickNoteEditView?.setupCaretCallback()
        quickNoteEditView?.onCursorMoveRequested = { [weak self] index in
            self?.quickNoteTextInputHandler?.moveCursor(to: index)
            self?.quickNoteEditView?.setCursorIndex(index)
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

    func dictationOverlayDidTapBackspace() {
        dictationCoordinator?.sendDeleteLastCharacter()
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

    // MARK: - Toolbar Productivity Editing (Host Text)

    private func handleToolbarCursorLeft() {
        commitDefaultComposing()
        textDocumentProxy.adjustTextPosition(byCharacterOffset: -1)
    }

    private func handleToolbarCursorRight() {
        commitDefaultComposing()
        textDocumentProxy.adjustTextPosition(byCharacterOffset: 1)
    }

    private func handleToolbarDeleteWord() {
        commitDefaultComposing()

        guard let context = textDocumentProxy.documentContextBeforeInput, !context.isEmpty else { return }

        let chars = Array(context)
        var count = 0
        var i = chars.count - 1

        // Skip trailing whitespace
        while i >= 0 && (chars[i].isWhitespace || chars[i].isNewline) {
            count += 1
            i -= 1
        }

        // Skip word characters
        while i >= 0 && !chars[i].isWhitespace && !chars[i].isNewline {
            count += 1
            i -= 1
        }

        guard count > 0 else { return }
        for _ in 0..<count {
            textDocumentProxy.deleteBackward()
        }
    }

    private func handleToolbarPaste() {
        guard hasFullAccess() else {
            showToast(L("toolbar.paste_no_access"))
            return
        }
        guard UIPasteboard.general.hasStrings, let text = UIPasteboard.general.string, !text.isEmpty else {
            showToast(L("toolbar.paste_empty"))
            return
        }
        commitDefaultComposing()
        textDocumentProxy.insertText(text)
    }

    private func handleToolbarCaseTransform() {
        commitDefaultComposing()

        guard let context = textDocumentProxy.documentContextBeforeInput, !context.isEmpty else {
            showToast(L("toolbar.case_no_word"))
            return
        }

        // Find last word
        let chars = Array(context)
        var end = chars.count - 1

        // Skip trailing whitespace
        while end >= 0 && (chars[end].isWhitespace || chars[end].isNewline) {
            end -= 1
        }
        guard end >= 0 else {
            showToast(L("toolbar.case_no_word"))
            return
        }

        var start = end
        while start > 0 && !chars[start - 1].isWhitespace && !chars[start - 1].isNewline {
            start -= 1
        }

        let word = String(chars[start...end])
        let deleteCount = chars.count - start  // includes trailing whitespace

        // Delete from cursor back to word start
        for _ in 0..<deleteCount {
            textDocumentProxy.deleteBackward()
        }

        // Transform case
        let transformed: String
        if word == word.lowercased() {
            transformed = word.uppercased()
        } else {
            transformed = word.lowercased()
        }

        // Re-insert transformed word + trailing whitespace
        let trailing = String(chars[(end + 1)...])
        textDocumentProxy.insertText(transformed + trailing)
    }

    private func handleToolbarUndo() {
        showToast(L("toolbar.undo_unavailable"))
    }

    private func handleToolbarRedo() {
        showToast(L("toolbar.redo_unavailable"))
    }

    private func handleToolbarSelectAll() {
        showToast(L("toolbar.select_unavailable"))
    }

    private func handleToolbarCopy() {
        showToast(L("toolbar.copy_unavailable"))
    }

    private func handleToolbarCut() {
        showToast(L("toolbar.cut_unavailable"))
    }

    // MARK: - Date/Time Insert

    private func handleDateTimeInsert() {
        commitDefaultComposing()
        let formatter = DateFormatter()
        formatter.dateStyle = .medium
        formatter.timeStyle = .none
        formatter.locale = Locale.current
        let dateString = formatter.string(from: Date())
        textDocumentProxy.insertText(dateString)
    }

    private func showDateTimeMenu() {
        hideDateTimeMenu()
        guard let inputView = self.inputView else { return }

        let overlay = UIView()
        overlay.translatesAutoresizingMaskIntoConstraints = false
        overlay.backgroundColor = UIColor.black.withAlphaComponent(0.01)
        inputView.addSubview(overlay)
        NSLayoutConstraint.activate([
            overlay.topAnchor.constraint(equalTo: inputView.topAnchor),
            overlay.leadingAnchor.constraint(equalTo: inputView.leadingAnchor),
            overlay.trailingAnchor.constraint(equalTo: inputView.trailingAnchor),
            overlay.bottomAnchor.constraint(equalTo: inputView.bottomAnchor),
        ])

        let tapDismiss = UITapGestureRecognizer(target: self, action: #selector(dateTimeMenuDismissed))
        overlay.addGestureRecognizer(tapDismiss)

        let isDark = resolvedKeyboardIsDark()

        let menu = UIStackView()
        menu.axis = .vertical
        menu.spacing = 1
        menu.layer.cornerRadius = 12
        menu.clipsToBounds = true
        menu.translatesAutoresizingMaskIntoConstraints = false
        menu.backgroundColor = isDark ? UIColor(white: 0.2, alpha: 1) : UIColor(white: 0.85, alpha: 1)

        let now = Date()
        let locale = Locale.current

        // Date only
        let dateFmt = DateFormatter()
        dateFmt.dateStyle = .medium
        dateFmt.timeStyle = .none
        dateFmt.locale = locale

        // Time only
        let timeFmt = DateFormatter()
        timeFmt.dateStyle = .none
        timeFmt.timeStyle = .short
        timeFmt.locale = locale

        // Date + Time
        let dateTimeFmt = DateFormatter()
        dateTimeFmt.dateStyle = .medium
        dateTimeFmt.timeStyle = .short
        dateTimeFmt.locale = locale

        // ISO
        let isoFmt = DateFormatter()
        isoFmt.dateFormat = "yyyy-MM-dd"

        let options: [(String, String)] = [
            (L("datetime.date"), dateFmt.string(from: now)),
            (L("datetime.time"), timeFmt.string(from: now)),
            (L("datetime.datetime"), dateTimeFmt.string(from: now)),
            (L("datetime.iso"), isoFmt.string(from: now)),
        ]

        for (label, value) in options {
            let btn = UIButton(type: .system)
            let display = "\(label)  \(value)"
            btn.setTitle(display, for: .normal)
            btn.titleLabel?.font = .systemFont(ofSize: 14, weight: .regular)
            btn.setTitleColor(isDark ? .white : .label, for: .normal)
            btn.backgroundColor = isDark ? UIColor(white: 0.15, alpha: 1) : .white
            btn.contentHorizontalAlignment = .leading
            btn.contentEdgeInsets = UIEdgeInsets(top: 10, left: 16, bottom: 10, right: 16)
            btn.accessibilityValue = value
            btn.addTarget(self, action: #selector(dateTimeOptionTapped(_:)), for: .touchUpInside)
            menu.addArrangedSubview(btn)
        }

        overlay.addSubview(menu)
        NSLayoutConstraint.activate([
            menu.centerXAnchor.constraint(equalTo: overlay.centerXAnchor),
            menu.bottomAnchor.constraint(equalTo: overlay.bottomAnchor, constant: -60),
            menu.widthAnchor.constraint(equalToConstant: 260),
        ])

        overlay.alpha = 0
        UIView.animate(withDuration: 0.2) { overlay.alpha = 1 }

        dateTimeMenuView = overlay
        inputView.bringSubviewToFront(toastLabel)
    }

    @objc private func dateTimeOptionTapped(_ sender: UIButton) {
        guard let value = sender.accessibilityValue else { return }
        commitDefaultComposing()
        textDocumentProxy.insertText(value)
        hideDateTimeMenu()
    }

    @objc private func dateTimeMenuDismissed() {
        hideDateTimeMenu()
    }

    private func hideDateTimeMenu() {
        guard let menu = dateTimeMenuView else { return }
        UIView.animate(withDuration: 0.15, animations: {
            menu.alpha = 0
        }) { _ in
            menu.removeFromSuperview()
        }
        dateTimeMenuView = nil
    }

    // MARK: - Unit Converter

    private func showUnitConverter() {
        guard let inputView = self.inputView else { return }
        prepareForUserRequestedHeavyAllocation(source: "unitConverter")

        modeBeforeUnitConverter = currentMode

        unitConverterView?.removeFromSuperview()
        unitConverterView = nil

        keyboardLayoutView.performDeepMemoryCleanupForDismiss()

        let converter = UnitConverterView()
        converter.translatesAutoresizingMaskIntoConstraints = false

        converter.onClose = { [weak self] in
            self?.closeUnitConverter()
        }
        converter.onInsert = { [weak self] text in
            self?.textDocumentProxy.insertText(text)
        }

        inputView.addSubview(converter)
        unitConverterView = converter

        NSLayoutConstraint.activate([
            converter.topAnchor.constraint(equalTo: inputView.topAnchor),
            converter.leadingAnchor.constraint(equalTo: inputView.leadingAnchor),
            converter.trailingAnchor.constraint(equalTo: inputView.trailingAnchor),
            converter.bottomAnchor.constraint(equalTo: inputView.bottomAnchor),
        ])

        toolbarView.isHidden = true
        keyboardLayoutView.isHidden = true

        let isDark = resolvedKeyboardIsDark()
        let theme = loadTheme()
        converter.applyTheme(theme)
        converter.updateAppearance(isDark: isDark)

        converter.alpha = 0
        UIView.animate(withDuration: 0.2) { converter.alpha = 1 }

        inputView.bringSubviewToFront(toastLabel)
        checkMemorySafetyNet()
    }

    private func closeUnitConverter() {
        guard let converter = unitConverterView else { return }

        converter.removeFromSuperview()
        unitConverterView = nil

        if let previousMode = modeBeforeUnitConverter {
            modeBeforeUnitConverter = nil
            switchMode(to: previousMode)
        } else {
            toolbarView.isHidden = false
            keyboardLayoutView.isHidden = false
        }
    }
}
