import Foundation
import Speech
import AVFoundation

protocol SpeechRecognitionManagerDelegate: AnyObject {
    func speechRecognition(_ manager: SpeechRecognitionManager, didReceivePartial text: String)
    func speechRecognition(_ manager: SpeechRecognitionManager, didReceiveFinal text: String)
    func speechRecognition(_ manager: SpeechRecognitionManager, didFailWith error: Error)
    func speechRecognitionDidReachTimeLimit(_ manager: SpeechRecognitionManager)
}

final class SpeechRecognitionManager {

    weak var delegate: SpeechRecognitionManagerDelegate?

    private var audioEngine: AVAudioEngine?
    private var recognizer: SFSpeechRecognizer?
    private var recognitionRequest: SFSpeechAudioBufferRecognitionRequest?
    private var recognitionTask: SFSpeechRecognitionTask?

    private var silenceTimer: Timer?
    private var taskStartTime: Date?

    private(set) var isRunning: Bool = false
    private(set) var currentLocale: Locale = Locale(identifier: "en-US")

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
        return true
    }

    // MARK: - Start

    func start() throws {
        guard !isRunning else { return }

        if recognizer == nil {
            recognizer = SFSpeechRecognizer(locale: currentLocale)
        }
        guard let recognizer = recognizer, recognizer.isAvailable else {
            throw SpeechError.recognizerUnavailable
        }

        let audioSession = AVAudioSession.sharedInstance()
        try audioSession.setCategory(.record, mode: .measurement, options: .duckOthers)
        try audioSession.setActive(true, options: .notifyOthersOnDeactivation)

        let engine = AVAudioEngine()
        let request = SFSpeechAudioBufferRecognitionRequest()
        request.shouldReportPartialResults = true

        let task = recognizer.recognitionTask(with: request) { [weak self] result, error in
            guard let self = self else { return }

            if let result = result {
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
                // 1분 제한 도달 (code 216 = kAFAssistantErrorDomain)
                if nsError.code == 216 || nsError.code == 209 {
                    self.delegate?.speechRecognitionDidReachTimeLimit(self)
                } else if self.isRunning {
                    self.delegate?.speechRecognition(self, didFailWith: error)
                }
            }
        }

        let inputNode = engine.inputNode
        let recordingFormat = inputNode.outputFormat(forBus: 0)
        inputNode.installTap(onBus: 0, bufferSize: 1024, format: recordingFormat) { buffer, _ in
            request.append(buffer)
        }

        engine.prepare()
        try engine.start()

        self.audioEngine = engine
        self.recognitionRequest = request
        self.recognitionTask = task
        self.taskStartTime = Date()
        self.isRunning = true

        startSilenceTimer()
    }

    // MARK: - Stop

    func stop() {
        guard isRunning else { return }
        isRunning = false

        silenceTimer?.invalidate()
        silenceTimer = nil

        recognitionRequest?.endAudio()
        recognitionRequest = nil

        audioEngine?.inputNode.removeTap(onBus: 0)
        audioEngine?.stop()
        audioEngine = nil

        recognitionTask?.cancel()
        recognitionTask = nil

        try? AVAudioSession.sharedInstance().setActive(false, options: .notifyOthersOnDeactivation)
    }

    // MARK: - Cancel

    func cancel() {
        guard isRunning else { return }
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
