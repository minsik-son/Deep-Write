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

            request.append(buffer)

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
