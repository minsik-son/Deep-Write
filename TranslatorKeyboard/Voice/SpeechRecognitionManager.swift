import Foundation
import Speech
import AVFoundation
import OSLog

// DEBUG TRACE: VoiceRecognition investigation
private let speechLog = Logger(
    subsystem: "com.translatorkeyboard.app.voice",
    category: "speech"
)

protocol SpeechRecognitionManagerDelegate: AnyObject {
    func speechRecognition(_ manager: SpeechRecognitionManager, didReceivePartial text: String)
    func speechRecognition(_ manager: SpeechRecognitionManager, didReceiveFinal text: String)
    func speechRecognition(_ manager: SpeechRecognitionManager, didFailWith error: Error)
    func speechRecognitionDidReachTimeLimit(_ manager: SpeechRecognitionManager)
}

final class SpeechRecognitionManager: NSObject, SFSpeechRecognizerDelegate {

    weak var delegate: SpeechRecognitionManagerDelegate?

    private var audioEngine: AVAudioEngine?
    private var recognizer: SFSpeechRecognizer?
    private var recognitionRequest: SFSpeechAudioBufferRecognitionRequest?
    private var recognitionTask: SFSpeechRecognitionTask?

    private var silenceTimer: Timer?
    private var taskStartTime: Date?

    private(set) var isRunning: Bool = false
    private(set) var currentLocale: Locale = Locale(identifier: "en-US")

    // Pipeline 진단용 카운터
    private var tapBufferCount: Int = 0

    // ★ v2: restartRecognition() 재진입 방어
    private var isRestarting: Bool = false

    // MARK: - Interruption Observer

    private var interruptionObserver: Any?

    private func startInterruptionObserver() {
        interruptionObserver = NotificationCenter.default.addObserver(
            forName: AVAudioSession.interruptionNotification,
            object: AVAudioSession.sharedInstance(),
            queue: .main
        ) { [weak self] notification in
            guard let self = self else { return }
            guard let typeValue = notification.userInfo?[AVAudioSessionInterruptionTypeKey] as? UInt,
                  let type = AVAudioSession.InterruptionType(rawValue: typeValue) else { return }

            switch type {
            case .began:
                speechLog.error("event=audio_interruption type=began running=\(self.isRunning, privacy: .public) paused=\(self.isPaused, privacy: .public)")
            case .ended:
                let shouldResume = (notification.userInfo?[AVAudioSessionInterruptionOptionKey] as? UInt)
                    .map { AVAudioSession.InterruptionOptions(rawValue: $0).contains(.shouldResume) } ?? false
                speechLog.debug("event=audio_interruption type=ended shouldResume=\(shouldResume, privacy: .public) running=\(self.isRunning, privacy: .public)")
            @unknown default:
                speechLog.debug("event=audio_interruption type=unknown")
            }
        }
    }

    private func stopInterruptionObserver() {
        if let observer = interruptionObserver {
            NotificationCenter.default.removeObserver(observer)
            interruptionObserver = nil
        }
    }

    // MARK: - SFSpeechRecognizerDelegate

    func speechRecognizer(_ speechRecognizer: SFSpeechRecognizer, availabilityDidChange available: Bool) {
        speechLog.debug("event=recognizer_availability available=\(available, privacy: .public) locale=\(self.currentLocale.identifier, privacy: .public) running=\(self.isRunning, privacy: .public)")
    }

    // MARK: - Permissions

    static func requestPermissions(completion: @escaping (Bool, Bool) -> Void) {
        SFSpeechRecognizer.requestAuthorization { speechStatus in
            let speechGranted = speechStatus == .authorized
            AVAudioApplication.requestRecordPermission { micGranted in
                DispatchQueue.main.async {
                    completion(speechGranted, micGranted)
                }
            }
        }
    }

    static var isSpeechAuthorized: Bool {
        SFSpeechRecognizer.authorizationStatus() == .authorized
    }

    static var isMicAuthorized: Bool {
        AVAudioApplication.shared.recordPermission == .granted
    }

    // MARK: - Locale Validation

    func setLocale(_ identifier: String) -> Bool {
        let locale = Locale(identifier: identifier)
        guard let rec = SFSpeechRecognizer(locale: locale), rec.isAvailable else {
            return false
        }
        currentLocale = locale
        recognizer = rec
        recognizer?.delegate = self
        return true
    }

    // MARK: - Start

    func start() throws {
        guard !isRunning else { return }

        if recognizer == nil {
            recognizer = SFSpeechRecognizer(locale: currentLocale)
            recognizer?.delegate = self
        }
        guard let recognizer = recognizer, recognizer.isAvailable else {
            // DEBUG TRACE: VoiceRecognition investigation
            speechLog.error("event=start_fail reason=recognizerUnavailable locale=\(self.currentLocale.identifier, privacy: .public)")
            throw SpeechError.recognizerUnavailable
        }

        // DEBUG TRACE: VoiceRecognition investigation
        speechLog.debug("event=start locale=\(self.currentLocale.identifier, privacy: .public)")

        let audioSession = AVAudioSession.sharedInstance()
        try audioSession.setCategory(.record, mode: .measurement, options: .duckOthers)
        try audioSession.setActive(true, options: .notifyOthersOnDeactivation)
        // DEBUG TRACE: audio session activation
        speechLog.debug("event=audio_session_active category=record mode=measurement")

        // DEBUG TRACE: audio route 확인
        let inputs = audioSession.currentRoute.inputs.map { $0.portType.rawValue }.joined(separator: ",")
        let outputs = audioSession.currentRoute.outputs.map { $0.portType.rawValue }.joined(separator: ",")
        speechLog.debug("event=audio_route inputs=\(inputs, privacy: .public) outputs=\(outputs, privacy: .public)")

        // DEBUG TRACE: recognizer status
        speechLog.debug("event=recognizer_status available=\(recognizer.isAvailable, privacy: .public) locale=\(self.currentLocale.identifier, privacy: .public)")

        let engine = AVAudioEngine()
        let request = SFSpeechAudioBufferRecognitionRequest()
        request.shouldReportPartialResults = true

        // request를 identity token으로 사용 — callback이 현재 request에 속하는지 확인
        let currentRequest = request

        // tap 카운터 리셋
        tapBufferCount = 0

        let task = recognizer.recognitionTask(with: request) { [weak self] result, error in
            guard let self = self else { return }

            // DEBUG TRACE: callback 진입 자체를 최우선 기록
            speechLog.debug("event=srm_callback_enter result_nil=\(result == nil, privacy: .public) error_nil=\(error == nil, privacy: .public) running=\(self.isRunning, privacy: .public) paused=\(self.isPaused, privacy: .public)")

            if let result = result {
                // DEBUG TRACE: guard 앞에서 result 내용 기록
                speechLog.debug("event=srm_result final=\(result.isFinal, privacy: .public) running=\(self.isRunning, privacy: .public) paused=\(self.isPaused, privacy: .public)")
                guard self.isRunning else { return }

                // task identity 방어선: old task의 late result가 새 session에 영향주지 않게
                // stop() 시 recognitionRequest = nil → old request와 현재 request 비교
                guard self.recognitionRequest === currentRequest else {
                    speechLog.debug("event=srm_result_stale final=\(result.isFinal, privacy: .public)")
                    return
                }

                let text = result.bestTranscription.formattedString
                self.resetSilenceTimer()

                if result.isFinal {
                    self.delegate?.speechRecognition(self, didReceiveFinal: text)
                } else {
                    self.delegate?.speechRecognition(self, didReceivePartial: text)
                }
            }

            if let error = error {
                // DEBUG TRACE: guard 앞에서 error callback 진입 자체를 먼저 기록
                let nsError = error as NSError
                speechLog.error("event=srm_error code=\(nsError.code, privacy: .public) running=\(self.isRunning, privacy: .public) paused=\(self.isPaused, privacy: .public) reason=\(error.localizedDescription, privacy: .public)")
                guard self.isRunning && !self.isPaused else { return }

                // task identity 방어선: old task의 callback이 새 session을 죽이지 않게
                // stop() 시 recognitionRequest = nil → old request와 현재 request 비교
                guard self.recognitionRequest === currentRequest else { return }

                if nsError.code == 216 || nsError.code == 209 {
                    self.delegate?.speechRecognitionDidReachTimeLimit(self)
                } else {
                    self.delegate?.speechRecognition(self, didFailWith: error)
                }
            }
        }

        let inputNode = engine.inputNode
        let recordingFormat = inputNode.outputFormat(forBus: 0)
        inputNode.installTap(onBus: 0, bufferSize: 1024, format: recordingFormat) { [weak self] buffer, _ in
            guard let self = self else { return }
            self.tapBufferCount += 1

            // DEBUG TRACE: 첫 버퍼 도착 기록
            if self.tapBufferCount == 1 {
                speechLog.debug("event=audio_tap_first_buffer frameLength=\(buffer.frameLength, privacy: .public)")
            }

            // ★ 변경: local 캡처 대신 인스턴스 변수 참조 → request 교체 가능
            self.recognitionRequest?.append(buffer)

            // DEBUG TRACE: 첫 append 기록
            if self.tapBufferCount == 1 {
                speechLog.debug("event=request_append_first_buffer")
            }

            // DEBUG TRACE: 50회마다 샘플링
            if self.tapBufferCount % 50 == 0 {
                speechLog.debug("event=audio_tap_sample count=\(self.tapBufferCount, privacy: .public)")
            }
        }

        engine.prepare()
        try engine.start()
        // DEBUG TRACE: engine start
        speechLog.debug("event=engine_start success=true")

        self.audioEngine = engine
        self.recognitionRequest = request
        self.recognitionTask = task
        self.taskStartTime = Date()
        self.isRunning = true
        // ★ v2 추가: fallback start() 시 paused 잔류 방지
        self.isPaused = false

        startSilenceTimer()
        startInterruptionObserver()
    }

    // MARK: - Pause (mic 캡처만 중단, engine/session은 유지)

    private(set) var isPaused: Bool = false

    func pause() {
        guard isRunning, !isPaused else { return }
        // DEBUG TRACE: VoiceRecognition investigation
        speechLog.debug("event=pause")
        isPaused = true

        silenceTimer?.invalidate()
        silenceTimer = nil

        // audio engine pause — tap은 유지하되 캡처만 멈춤
        audioEngine?.pause()
    }

    func resumeAfterPause() throws {
        guard isRunning, isPaused else { return }
        // DEBUG TRACE: VoiceRecognition investigation
        speechLog.debug("event=resume")
        isPaused = false

        try audioEngine?.start()
        startSilenceTimer()
    }

    // MARK: - Lightweight Recognition Restart (engine 유지, task/request만 교체)

    /// Engine과 AudioSession은 유지한 채, recognition task/request만 새로 생성.
    /// pause→resume, backspace resync, seamless restart에서 사용.
    /// 실패 시 false 반환 — caller가 full restart 또는 에러 처리 결정.
    func restartRecognition() -> Bool {
        // ★ v2: 재진입 방어 — 동시 호출 시 두 번째 호출 차단
        guard !isRestarting else {
            speechLog.warning("event=restartRecognition_reentrant_blocked")
            return false
        }
        guard isRunning, let engine = audioEngine, engine.isRunning else {
            speechLog.error("event=restartRecognition_fail reason=engineNotRunning")
            return false
        }
        guard let recognizer = recognizer, recognizer.isAvailable else {
            speechLog.error("event=restartRecognition_fail reason=recognizerUnavailable")
            return false
        }

        isRestarting = true
        defer { isRestarting = false }
        speechLog.debug("event=restartRecognition_start tapCount=\(self.tapBufferCount, privacy: .public)")

        // 1. 기존 task/request 정리 (engine/tap은 유지)
        recognitionRequest?.endAudio()
        recognitionRequest = nil
        recognitionTask?.cancel()
        recognitionTask = nil

        // 2. 새 request 생성 — 이 시점부터 tap이 새 request에 append
        let newRequest = SFSpeechAudioBufferRecognitionRequest()
        newRequest.shouldReportPartialResults = true
        self.recognitionRequest = newRequest  // ★ v2: nil 구간 최소화 — 즉시 할당

        // identity token — callback에서 stale 판별용
        let currentRequest = newRequest

        // 3. 새 task 생성
        let task = recognizer.recognitionTask(with: newRequest) { [weak self] result, error in
            guard let self = self else { return }

            speechLog.debug("event=srm_callback_enter result_nil=\(result == nil, privacy: .public) error_nil=\(error == nil, privacy: .public) running=\(self.isRunning, privacy: .public) paused=\(self.isPaused, privacy: .public)")

            if let result = result {
                speechLog.debug("event=srm_result final=\(result.isFinal, privacy: .public) running=\(self.isRunning, privacy: .public) paused=\(self.isPaused, privacy: .public)")
                guard self.isRunning else { return }
                guard self.recognitionRequest === currentRequest else {
                    speechLog.debug("event=srm_result_stale final=\(result.isFinal, privacy: .public)")
                    return
                }
                let text = result.bestTranscription.formattedString
                self.resetSilenceTimer()
                if result.isFinal {
                    self.delegate?.speechRecognition(self, didReceiveFinal: text)
                } else {
                    self.delegate?.speechRecognition(self, didReceivePartial: text)
                }
            }

            if let error = error {
                let nsError = error as NSError
                speechLog.error("event=srm_error code=\(nsError.code, privacy: .public) running=\(self.isRunning, privacy: .public) paused=\(self.isPaused, privacy: .public) reason=\(error.localizedDescription, privacy: .public)")
                guard self.isRunning && !self.isPaused else { return }
                guard self.recognitionRequest === currentRequest else { return }
                if nsError.code == 216 || nsError.code == 209 {
                    self.delegate?.speechRecognitionDidReachTimeLimit(self)
                } else {
                    self.delegate?.speechRecognition(self, didFailWith: error)
                }
            }
        }

        // 4. 인스턴스 변수 업데이트
        self.recognitionTask = task
        self.taskStartTime = Date()

        // silence timer 리셋
        startSilenceTimer()

        speechLog.debug("event=restartRecognition_success")
        return true
    }

    /// Recognition task/request 정리. Engine은 계속 running 유지.
    /// tap은 recognitionRequest가 nil이므로 버퍼를 버림 (무해).
    func pauseRecognition() {
        guard isRunning, !isPaused else { return }
        speechLog.debug("event=pauseRecognition tapCount=\(self.tapBufferCount, privacy: .public)")
        isPaused = true

        silenceTimer?.invalidate()
        silenceTimer = nil

        // Recognition task/request 정리 (engine/tap은 유지)
        recognitionRequest?.endAudio()
        recognitionRequest = nil
        recognitionTask?.cancel()
        recognitionTask = nil

        // ★ v4: engine.pause() 제거
        // 이유: 백그라운드에서 engine.pause()→start() 반복 시 AURemoteIO I/O 시작 거부 (2003329396)
        // engine은 계속 running — tap closure가 recognitionRequest?.append(buffer)를 호출하지만
        // recognitionRequest가 nil이므로 아무 일도 안 함 (v2 A-1 변경으로 안전 보장)
        speechLog.debug("event=pauseRecognition_complete engineKeptRunning=true")
    }

    /// pauseRecognition() 이후 재개.
    /// Engine은 이미 running — restartRecognition()으로 새 task/request만 생성.
    /// backspace/seamlessRestart와 동일한 패턴.
    func resumeRecognition() throws {
        guard isRunning, isPaused else { return }
        speechLog.debug("event=resumeRecognition engineRunning=\(self.audioEngine?.isRunning ?? false, privacy: .public)")

        // ★ v4: engine.start() 제거
        // pause에서 engine을 멈추지 않으므로 재시작 불필요
        // restartRecognition()만으로 새 task/request 생성 — backspace와 동일 패턴

        // Engine 존재 확인
        guard let engine = audioEngine, engine.isRunning else {
            speechLog.error("event=resumeRecognition_fail reason=engineNotRunning")
            throw SpeechError.recognizerUnavailable
        }

        // 새 recognition task/request 생성
        speechLog.debug("event=resumeRecognition_step1_restartRecognition")
        if !restartRecognition() {
            speechLog.error("event=resumeRecognition_fail reason=restartRecognitionFailed")
            throw SpeechError.recognizerUnavailable
        }

        // 모든 단계 성공 후에만 isPaused 해제
        isPaused = false
        speechLog.debug("event=resumeRecognition_success")
    }

    // MARK: - Stop (완전 종료 — teardown)

    func stop() {
        guard isRunning else { return }
        // DEBUG TRACE: VoiceRecognition investigation
        speechLog.debug("event=stop_teardown tapCount=\(self.tapBufferCount, privacy: .public)")
        isRunning = false
        isPaused = false

        silenceTimer?.invalidate()
        silenceTimer = nil

        recognitionRequest?.endAudio()
        recognitionRequest = nil

        audioEngine?.inputNode.removeTap(onBus: 0)
        audioEngine?.stop()
        audioEngine = nil

        recognitionTask?.cancel()
        recognitionTask = nil

        stopInterruptionObserver()
        try? AVAudioSession.sharedInstance().setActive(false, options: .notifyOthersOnDeactivation)
    }

    // MARK: - Cancel

    func cancel() {
        guard isRunning else { return }
        // DEBUG TRACE: VoiceRecognition investigation
        speechLog.debug("event=cancel_teardown tapCount=\(self.tapBufferCount, privacy: .public)")
        isRunning = false

        silenceTimer?.invalidate()
        silenceTimer = nil

        recognitionTask?.cancel()
        recognitionTask = nil

        recognitionRequest?.endAudio()
        recognitionRequest = nil

        audioEngine?.inputNode.removeTap(onBus: 0)
        audioEngine?.stop()
        audioEngine = nil

        stopInterruptionObserver()
        try? AVAudioSession.sharedInstance().setActive(false, options: .notifyOthersOnDeactivation)
    }

    // MARK: - Time Limit Check

    var elapsedSeconds: TimeInterval {
        guard let start = taskStartTime else { return 0 }
        return Date().timeIntervalSince(start)
    }

    var isNearTimeLimit: Bool {
        elapsedSeconds >= DictationConstants.Limits.seamlessRestartThreshold
    }

    // MARK: - Silence Timer

    private func startSilenceTimer() {
        silenceTimer?.invalidate()
        silenceTimer = Timer.scheduledTimer(withTimeInterval: DictationConstants.Limits.silenceTimeout, repeats: false) { [weak self] _ in
            guard let self = self, self.isRunning else { return }
            // DEBUG TRACE: VoiceRecognition investigation
            speechLog.debug("event=silence_timer_fire tapCount=\(self.tapBufferCount, privacy: .public)")
            self.delegate?.speechRecognition(self, didFailWith: SpeechError.silenceTimeout)
        }
    }

    private func resetSilenceTimer() {
        startSilenceTimer()
    }

    // MARK: - Error

    enum SpeechError: LocalizedError {
        case recognizerUnavailable
        case silenceTimeout

        var errorDescription: String? {
            switch self {
            case .recognizerUnavailable:
                return "Speech recognizer is not available for this language."
            case .silenceTimeout:
                return "No speech detected. Recording stopped."
            }
        }
    }
}
