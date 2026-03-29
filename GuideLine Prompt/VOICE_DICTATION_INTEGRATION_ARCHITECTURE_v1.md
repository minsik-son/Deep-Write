# Voice Dictation Feature - Integration Architecture Specification

**Project Context:**
- iOS Keyboard Extension with 30MB memory limit (PRIMARY CONSTRAINT)
- Container App handles heavy operations
- Inter-process communication via App Groups, Darwin notifications, URL schemes
- Keyboard Extension handles only lightweight UI and text insertion

**Status:** Design Phase (NO CODING WITHOUT EXPLICIT APPROVAL)

---

## 1. NEW FILES TO CREATE

### 1.1 Shared Framework (Both Container App & Extension)

**Location:** `/TranslatorKeyboard/Shared/`

#### A. `DictationConstants.swift` (NEW)
**Purpose:** Centralized constants for dictation feature (minimal memory footprint)

```
- Darwin notification names
  - "com.translatorkeyboard.dictation.start"
  - "com.translatorkeyboard.dictation.partial"
  - "com.translatorkeyboard.dictation.final"
  - "com.translatorkeyboard.dictation.error"
  - "com.translatorkeyboard.dictation.stop"

- AppGroup keys for shared data
  - "dictation_partial_text"
  - "dictation_is_final"
  - "dictation_error_message"
  - "dictation_language_code"
  - "dictation_session_id"
  - "dictation_confidence_scores"

- Dictation limits & timeouts
  - Max recording duration: 60 seconds
  - Partial result debounce: 200ms
  - Session timeout: 90 seconds
```

#### B. `DictationDataModel.swift` (NEW)
**Purpose:** Codable data structures for inter-process communication

```
struct DictationSession: Codable {
  - sessionId: UUID
  - startTime: Date
  - languageCode: String
  - sourceText: String (partial results)
  - isFinal: Bool
  - confidence: Float
  - errorMessage: String? (if error)
}

struct DictationConfig: Codable {
  - language: String
  - enablePartialResults: Bool
  - maxDuration: TimeInterval
}
```

#### C. `DarwinNotificationManager.swift` (NEW)
**Purpose:** Unified Darwin notification wrapper (lightweight, reusable)

```
class DarwinNotificationManager {
  - static shared: DarwinNotificationManager
  - func postNotification(_ name: String)
  - func observeNotification(_ name: String, handler: @escaping () -> Void)
  - func removeObserver(_ name: String)
}

// Minimal implementation using Darwin C APIs (libnotify)
// RATIONALE: Avoids NSNotificationCenter overhead in extension
```

---

### 1.2 Container App (Main Application)

**Location:** `/TranslatorKeyboard/TranslatorKeyboard/Voice/` (NEW)

#### A. `SpeechRecognitionManager.swift`
**Purpose:** Wrapper around SFSpeechRecognizer

```
class SpeechRecognitionManager: NSObject {
  - private var speechRecognizer: SFSpeechRecognizer?
  - private var audioEngine: AVAudioEngine
  - private var recognitionRequest: SFSpeechAudioBufferRecognitionRequest?
  - private var recognitionTask: SFSpeechRecognitionTask?

  - func startRecording(
      language: String,
      onPartialResult: (String) -> Void,
      onFinalResult: (String) -> Void,
      onError: (Error) -> Void
    ) -> UUID

  - func stopRecording(sessionId: UUID)
  - func cancelRecording(sessionId: UUID)
}
```

**Design Notes:**
- AVAudioEngine (not AVAudioRecorder) for raw audio access
- SFSpeechRecognitionTask returns partial + final results
- Session ID tracking for multi-tab scenarios (future)
- Error handling for microphone permission, speech recognizer availability

#### B. `DictationResultDispatcher.swift`
**Purpose:** Routes SFSpeechRecognizer results to extension via AppGroup + Darwin notifications

```
class DictationResultDispatcher {
  - func dispatchPartialResult(_ text: String, sessionId: UUID)
  - func dispatchFinalResult(_ text: String, sessionId: UUID)
  - func dispatchError(_ error: NSError, sessionId: UUID)

  // Implementation:
  // 1. Encode DictationSession to JSON
  // 2. Write to AppGroup UserDefaults
  // 3. Post Darwin notification to wake extension
}
```

#### C. `DictationViewController.swift`
**Purpose:** Modal UI for recording (presented when extension taps mic button)

```
UIViewController showing:
- Animated recording indicator
- Partial text display (live updates)
- Stop/Cancel buttons
- Language selector
- Accessibility labels

// Dismissed automatically when:
// - User taps Stop button
// - Final result received (auto-insert if enabled)
// - Error occurs or timeout
```

---

### 1.3 Keyboard Extension

**Location:** `/KeyboardExtension/Voice/` (NEW)

#### A. `DictationUIManager.swift`
**Purpose:** Lightweight UI for dictation state in keyboard

```
class DictationUIManager: UIView {
  - private var statusLabel: UILabel
  - private var animatedMicButton: UIButton
  - private var cancelButton: UIButton

  - func showRecording()
  - func showProcessing()
  - func hideRecording()
  - func updatePartialText(_ text: String) // displayed inline if space
}

// MEMORY CONSTRAINT:
// - No heavy animations (use CABasicAnimation, not Lottie)
// - Reuse existing UILabel instead of SwiftUI
// - Lazy-load only when recording active
```

#### B. `DictationResultHandler.swift`
**Purpose:** Observes Darwin notifications & applies results to textDocumentProxy

```
class DictationResultHandler {
  - private var darwinObserver: DarwinNotificationManager
  - weak var textDocumentProxy: UITextDocumentProxy?
  - weak var keyboardViewController: KeyboardViewController?

  - func setupObservers()
  - private func handlePartialResult()
  - private func handleFinalResult()
  - private func insertOrRollback(_ text: String, isFinal: Bool)

  // INSERTION STRATEGY:
  // If isFinal:
  //   - Delete any partial insertions
  //   - Insert final text once
  //   - Update keyboard state
  // Else (partial):
  //   - Store partial text in memory (not in keyboard)
  //   - Update inline preview only if room
}
```

#### C. `RollbackInsertion.swift`
**Purpose:** Undo partial text insertions if final result differs

```
class RollbackInsertion {
  - static func deleteRecentInsertions(count: Int, proxy: UITextDocumentProxy)
  - static func insertText(_ text: String, proxy: UITextDocumentProxy)

  // RATIONALE:
  // SFSpeechRecognizer emits multiple partial results before final
  // Can't atomically replace — must delete + insert
  // Track insertion count to know how many chars to delete
}
```

---

## 2. EXISTING FILES TO MODIFY

### 2.1 Constants.swift

**Add to `UserDefaultsKeys` enum:**
```swift
static let dictationEnabled = "dictation_enabled"
static let dictationLanguage = "dictation_language"
static let dictationPartialText = "dictation_partial_text"
static let dictationSessionId = "dictation_session_id"
static let dictationAutoInsert = "dictation_auto_insert"
```

**Why:** Centralized configuration storage shared across app & extension.

---

### 2.2 ToolbarConfiguration.swift

**Add to `ToolbarItemType` enum:**
```swift
case dictation
```

**Rationale:** Users can add/remove dictation button from toolbar like other tools.

---

### 2.3 ToolbarView.swift

**In `applyToolbarItems(_ items:)` switch statement, add case:**
```swift
case .dictation:
    toolbarStack.addArrangedSubview(
        makeToolbarButton(
            iconName: "icon_toolbar_dictation",
            action: #selector(dictationButtonTapped),
            tag: 9,
            iconSize: iconRenderSize
        )
    )

@objc private func dictationButtonTapped() {
    onDictationTap?()
}

// Add callback:
var onDictationTap: (() -> Void)?
```

---

### 2.4 KeyboardViewController.swift

**In class properties (after line ~100), add:**
```swift
// MARK: - Dictation State
private var dictationManager: DictationResultHandler?
private var dictationUIManager: DictationUIManager?
private var currentDictationSessionId: UUID?
private var lastPartialInsertionCount: Int = 0
```

**In `setupCallbacks()` method, add:**
```swift
toolbarView.onDictationTap = { [weak self] in
    self?.startDictation()
}
```

**Add new method (before ~400 lines):**
```swift
@objc private func startDictation() {
    // 1. Open container app with dictation:// scheme
    // 2. Container app presents DictationViewController
    // 3. DictationViewController manages recording & sends results via AppGroup + Darwin
    // 4. This extension watches Darwin notifications

    openContainingApp(path: "dictation")

    // Setup result handler if not already done
    if dictationManager == nil {
        dictationManager = DictationResultHandler()
        dictationManager?.textDocumentProxy = textDocumentProxy
        dictationManager?.keyboardViewController = self
        dictationManager?.setupObservers()
    }
}
```

**In `viewWillAppear()` method (after line ~365), add:**
```swift
// Restore any pending dictation state from AppGroup
if let sessionId = AppGroupManager.shared.string(forKey: AppConstants.UserDefaultsKeys.dictationSessionId) {
    currentDictationSessionId = UUID(uuidString: sessionId)
    // Dictation result handler automatically listens for Darwin notifications
}
```

---

### 2.5 SceneDelegate.swift

**Add to `handleURL()` switch statement (before line ~58):**
```swift
case "dictation":
    // Launch dictation UI in container app
    if let tabBar = tabBar as? TabBarController {
        let dictationVC = DictationViewController()
        dictationVC.modalPresentationStyle = .fullScreen
        let presenter = tabBar.presentedViewController ?? tabBar
        presenter.present(dictationVC, animated: true)
    }
```

---

### 2.6 Info.plist (Container App)

**Add these keys inside `<dict>`:**
```xml
<key>NSMicrophoneUsageDescription</key>
<string>We need access to your microphone to transcribe your voice into text for the keyboard.</string>

<key>NSSpeechRecognitionUsageDescription</key>
<string>Speech recognition helps us convert your voice to text accurately.</string>

<key>UIBackgroundModes</key>
<array>
    <string>audio</string>
</array>
```

---

### 2.7 Info.plist (Keyboard Extension)

**No changes needed.** Extension inherits App Groups from container app.

---

## 3. COMMUNICATION PROTOCOL DESIGN

### 3.1 Darwin Notification Flow

```
Sequence:
1. User taps dictation button in extension
   ↓
2. Extension calls openContainingApp(path: "dictation")
   ↓
3. Container app presents DictationViewController
   ↓
4. User starts recording
   ↓
5. SFSpeechRecognizer emits partial result (every ~100ms)
   ↓
6. DictationResultDispatcher writes to AppGroup UserDefaults:
   {
     "dictation_partial_text": "Hello wor",
     "dictation_session_id": "XXXX",
     "dictation_is_final": false
   }
   ↓
7. DictationResultDispatcher posts Darwin notification:
   "com.translatorkeyboard.dictation.partial"
   ↓
8. DictationResultHandler in extension wakes up & reads AppGroup data
   ↓
9. RollbackInsertion deletes previous partial insertion (e.g., 9 chars)
   ↓
10. RollbackInsertion inserts new partial text ("Hello wor")
    ↓
11. Repeat steps 5-10 until SFSpeechRecognizer emits final result
    ↓
12. Final result: DictationResultDispatcher posts:
    "com.translatorkeyboard.dictation.final"
    ↓
13. DictationResultHandler:
    - Deletes all partial insertions
    - Inserts final text once
    - Posts completion Darwin notification
    ↓
14. Container app closes DictationViewController
```

### 3.2 AppGroup Keys (UserDefaults)

| Key | Type | Written By | Read By | Lifetime |
|-----|------|------------|---------|----------|
| `dictation_partial_text` | String | Container | Extension | Until final |
| `dictation_is_final` | Bool | Container | Extension | Until next session |
| `dictation_error_message` | String? | Container | Extension | Until cleared |
| `dictation_session_id` | String | Container | Both | For duration of recording |
| `dictation_language_code` | String | Extension | Container | Current session |
| `dictation_confidence_scores` | Data (JSON) | Container | Extension | Informational only |

---

## 4. MODULE ARCHITECTURE & DEPENDENCY MAP

### 4.1 Dependency Graph

```
┌─────────────────────────────────────────────────────────┐
│                      Shared Layer                        │
│  DictationConstants.swift                               │
│  DictationDataModel.swift                               │
│  DarwinNotificationManager.swift                        │
│  (Linked into both app & extension targets)            │
└─────────────────────────────────────────────────────────┘
                    ▲                    ▲
                    │                    │
        ┌───────────┴────────┐      ┌────┴──────────────┐
        │                    │      │                   │
┌───────▼────────────────┐   │    ┌─▼─────────────────┐
│  Container App Layer    │   │    │ Extension Layer   │
│                        │   │    │                   │
│ SpeechRecognitionMgr◄──┼───┘    │ DictationUIManager│
│ DictationResultDispatcher        │ DictationResult   │
│ DictationViewController          │ Handler◄──────────┼─┐
│                        │   ┌─────┤ RollbackInsertion │ │
│ (Heavy lifting)        │   │    │ (Lightweight ops) │ │
└────────────────────────┘   │    └───────────────────┘ │
                             │              ▲            │
                             │              │            │
                    Darwin Notifications & AppGroup ─────┘
                        (IPC Channel)
```

### 4.2 Class Responsibilities

| Class | Layer | Responsibility | Memory Cost |
|-------|-------|-----------------|------------|
| DictationConstants | Shared | Config + notification names | <1 KB |
| DarwinNotificationManager | Shared | Cross-process signaling | <2 KB |
| DictationDataModel | Shared | Codable structs | <1 KB |
| SpeechRecognitionManager | Container | Audio capture + SFSpeechRecognizer | ~5-8 MB |
| DictationResultDispatcher | Container | AppGroup writes + Darwin posts | <1 KB |
| DictationViewController | Container | Recording UI modal | ~2-3 MB |
| DictationUIManager | Extension | Lightweight status UI | <0.5 MB |
| DictationResultHandler | Extension | Darwin observer + result routing | <1 KB |
| RollbackInsertion | Extension | Text deletion + insertion | <1 KB |

**Total Extension Cost:** ~3-4 MB (well under 30 MB limit)

---

### 4.3 Protocol-Based Design (Dependency Injection)

```swift
protocol DictationObserver: AnyObject {
    func dictationDidStartPartial(_ text: String, sessionId: UUID)
    func dictationDidFinalize(_ text: String, sessionId: UUID)
    func dictationDidError(_ error: NSError, sessionId: UUID)
}

protocol SpeechRecognitionDelegate: AnyObject {
    func speechRecognitionDidUpdatePartial(_ text: String)
    func speechRecognitionDidFinalize(_ text: String)
    func speechRecognitionDidFail(_ error: Error)
}

// Benefits:
// - Easy to test (mock implementations)
// - Loose coupling between extension UI and result handler
// - Multiple observers can listen (future: analytics, logging)
```

---

## 5. DATA FLOW DIAGRAM

```
┌─────────────────────────────────────────────────────────────────┐
│ KEYBOARD EXTENSION                                               │
├─────────────────────────────────────────────────────────────────┤
│                                                                   │
│  ┌──────────────────┐                    ┌──────────────────┐   │
│  │  ToolbarView     │                    │ KeyboardLayout   │   │
│  │  (dictation btn) │                    │  (text input)    │   │
│  └────────┬─────────┘                    └────────┬─────────┘   │
│           │                                       ▲               │
│           │ onDictationTap()                      │               │
│           │                                       │ textDocProxy  │
│           ▼                                       │               │
│  ┌──────────────────────────────────────────────────┐            │
│  │      KeyboardViewController                      │            │
│  │ (startDictation() → openContainingApp("dictation"))           │
│  └──────────────┬───────────────────────────────────┘            │
│                │ URL scheme                                      │
│                │ "translatorkeyboard://dictation"                │
│                │                                                  │
│   ┌────────────┴──────────────────────────────┐                 │
│   │    DictationResultHandler (watches)       │                 │
│   │ setupObservers() for Darwin notifications │                 │
│   │ - "com.translatorkeyboard.dictation.partial"                │
│   │ - "com.translatorkeyboard.dictation.final"                  │
│   │                                            │                 │
│   │    ┌────────────────────────────────────────┐                │
│   │    │  RollbackInsertion                     │                │
│   │    │  .deleteRecentInsertions(count, proxy) │                │
│   │    │  .insertText(text, proxy)              │                │
│   │    └────────────────────────────────────────┘                │
│   └────────────────────────────────────────────┘                 │
│                                                                   │
└─────────────────────────────────────────────────────────────────┘
                          ▲
                          │
                ┌─────────┴──────────┐
                │   App Groups +     │
                │   Darwin Notif     │
                │   (Shared Keys)    │
                └────────┬───────────┘
                         │
                         ▼
┌──────────────────────────────────────────────────────────────────┐
│ CONTAINER APP (Main Application)                                 │
├──────────────────────────────────────────────────────────────────┤
│                                                                   │
│  SceneDelegate.handleURL("translatorkeyboard://dictation")      │
│         │                                                         │
│         ▼                                                         │
│  ┌──────────────────────────────────────────────────────────┐   │
│  │        DictationViewController (Modal)                   │   │
│  │  - Present when: user taps dictation button              │   │
│  │  - Show: recording UI, partial text, stop button         │   │
│  │  - On stop: dismiss self                                 │   │
│  │                                                           │   │
│  │  ┌──────────────────────────────────────────────────┐   │   │
│  │  │ SpeechRecognitionManager                         │   │   │
│  │  │ - startRecording(language, callbacks)            │   │   │
│  │  │ - Uses: AVAudioEngine + SFSpeechRecognizer       │   │   │
│  │  │ - Emits partial results every ~100ms             │   │   │
│  │  │ - Emits final result when done                   │   │   │
│  │  └──────────────────┬───────────────────────────────┘   │   │
│  │                     │ callbacks                          │   │
│  │                     ▼                                    │   │
│  │  ┌──────────────────────────────────────────────────┐   │   │
│  │  │ DictationResultDispatcher                        │   │   │
│  │  │ - onPartialResult(text) →                        │   │   │
│  │  │   Write to AppGroup:                             │   │   │
│  │  │   {dictation_partial_text, session_id, ...}      │   │   │
│  │  │   Post Darwin: "dictation.partial"               │   │   │
│  │  │                                                   │   │   │
│  │  │ - onFinalResult(text) →                          │   │   │
│  │  │   Write to AppGroup:                             │   │   │
│  │  │   {dictation_partial_text, is_final: true, ...}  │   │   │
│  │  │   Post Darwin: "dictation.final"                 │   │   │
│  │  │                                                   │   │   │
│  │  │ - onError(error) →                               │   │   │
│  │  │   Write to AppGroup: {dictation_error_message}   │   │   │
│  │  │   Post Darwin: "dictation.error"                 │   │   │
│  │  └──────────────────────────────────────────────────┘   │   │
│  │                                                           │   │
│  └──────────────────────────────────────────────────────────┘   │
│                                                                   │
└──────────────────────────────────────────────────────────────────┘
```

---

## 6. IMPLEMENTATION PHASES

### Phase 1: Infrastructure (Foundation)
**Duration:** 1-2 days | **Files:** 3 new shared files

1. Create `DictationConstants.swift` (Darwin notification names, AppGroup keys)
2. Create `DictationDataModel.swift` (Codable structs)
3. Create `DarwinNotificationManager.swift` (lightweight notification wrapper)
4. Update `Constants.swift` (add dictation UserDefaults keys)

**Validation:**
- Build without errors
- Verify constants are accessible from both targets

---

### Phase 2: Container App Speech Engine
**Duration:** 2-3 days | **Files:** 3 new container files + 2 modified

1. Create `SpeechRecognitionManager.swift`
   - AVAudioEngine setup
   - SFSpeechRecognizer initialization
   - Session ID tracking
   - Error handling for permissions

2. Create `DictationResultDispatcher.swift`
   - AppGroup writes
   - Darwin notification posts
   - Session lifecycle

3. Create `DictationViewController.swift`
   - Modal UI for recording
   - Live partial text display
   - Cancel/Stop buttons
   - Auto-dismiss on final result

4. Modify `SceneDelegate.swift` (add "dictation" URL route)
5. Modify `Info.plist` (add microphone + speech recognition permissions, audio background mode)

**Validation:**
- Test microphone permission flow
- Verify SFSpeechRecognizer provides partial + final results
- Check AppGroup writes are successful
- Confirm Darwin notifications post without errors

---

### Phase 3: Keyboard Extension Dictation UI & Result Handling
**Duration:** 2-3 days | **Files:** 3 new extension files + 3 modified

1. Create `DictationUIManager.swift`
   - Lightweight status indicator
   - Animated mic button
   - Cancel button
   - Inline partial text preview (optional, space-permitting)

2. Create `DictationResultHandler.swift`
   - Darwin notification observer setup
   - AppGroup key reads
   - Session state tracking
   - Integration with textDocumentProxy

3. Create `RollbackInsertion.swift`
   - Rollback logic (delete recent insertions)
   - Final text insertion
   - Fallback for proxy limitations

4. Modify `ToolbarConfiguration.swift` (add `.dictation` case)
5. Modify `ToolbarView.swift` (add dictation button + callback)
6. Modify `KeyboardViewController.swift` (add dictation state, setupObservers, startDictation method)

**Validation:**
- Verify Darwin notifications are received in extension
- Test partial text insertion & rollback
- Confirm final text insertion
- Check memory usage remains <4 MB for extension dictation code
- Verify no regressions in existing keyboard functionality

---

### Phase 4: Integration Testing & Edge Cases
**Duration:** 2-3 days | **Testing & refinement**

1. End-to-end flow:
   - User taps dictation in keyboard
   - Container app opens
   - Recording starts
   - Partial results flow to extension
   - Final result inserts correctly
   - Dismiss workflow

2. Edge cases:
   - Network interrupted during recording
   - User denies microphone permission
   - Multi-touch: user types while recording in container app
   - Timeout (>60 seconds)
   - Language mismatch between extension setting & recording
   - Rollback insertion when proxy doesn't support deletion
   - Memory pressure: extension receives memory warning during dictation

3. Memory profiling:
   - Measure extension footprint before + after dictation code
   - Verify stays <30 MB total
   - Test under low memory conditions

4. Localization:
   - Ensure UI strings support multiple languages (Korean, English, etc.)
   - Test language picker in DictationViewController
   - Verify SFSpeechRecognizer language codes match picker

5. Accessibility:
   - VoiceOver labels for all buttons
   - Proper focus management
   - Audio session handling during accessibility

---

## 7. ARCHITECTURE DECISIONS & RATIONALE

### 7.1 Why Separate Container App for Recording?

**Issue:** Keyboard extensions have 30 MB memory limit and cannot access certain APIs.

**Solution:** Heavy lifting (AVAudioEngine, SFSpeechRecognizer) in container app.

**Trade-off:**
- Pro: Stays under 30 MB limit
- Pro: Better audio quality (less system interference)
- Con: Requires IPC (Darwin notifications, AppGroup)
- Con: Slightly higher latency for partial results

**Alternative Considered:** DirectAccess from extension
- Rejected: Would exceed memory limit + violate Apple guidelines

---

### 7.2 Why Darwin Notifications + AppGroup?

**Issue:** IPC between extension and container app.

**Options Evaluated:**

| Method | Pro | Con |
|--------|-----|-----|
| Darwin Notifications | Fast, real-time, lightweight | Requires manual observer mgmt |
| AppGroup UserDefaults | Persistent, both can read | Slower, polling overhead |
| Distributed Notifications | NSNotificationCenter-like | Doesn't cross process boundary |
| Shared Memory (POSIX) | Direct memory access | Complex, error-prone, security |

**Decision:** Darwin + AppGroup
- Darwin for signaling (extension wakes immediately when result arrives)
- AppGroup for data (structured, easy to serialize/deserialize)
- Combined: Best latency + reliability

**Equivalent to:** iOS Shared Extensions communication pattern (keyboard ↔ main app)

---

### 7.3 Rollback Insertion Strategy

**Issue:** SFSpeechRecognizer emits multiple partial results before final.
- Partial 1: "H"
- Partial 2: "He"
- Partial 3: "Hel"
- ...
- Final: "Hello"

Can't atomically replace. UITextDocumentProxy lacks atomic "replace" API.

**Solution:** Delete previous insertions, then insert new text.

```
Step 1: Insert "H" (1 char)
Step 2: Delete "H", insert "He" (1 char deleted, 2 inserted)
Step 3: Delete "He", insert "Hel" (2 deleted, 3 inserted)
...
Final: Delete all partials, insert "Hello" once
```

**Limitation:** If proxy is read-only (some apps), insertion fails silently. Fallback: just show notification.

---

### 7.4 Language Support & Localization

**Approach:**
- Language picker in DictationViewController (user selects before recording)
- User's choice → passed to SFSpeechRecognizer
- SFSpeechRecognizer language codes: "en-US", "ko-KR", "ja-JP", etc.
- UI strings localized in multiple languages (.strings files)

**Future Enhancement:** Auto-detect based on keyboard's current language setting.

---

## 8. MEMORY BUDGET ANALYSIS

### 8.1 Extension Memory Cost Breakdown

| Component | Estimated | Notes |
|-----------|-----------|-------|
| DictationUIManager | 0.5 MB | One UIView + buttons |
| DictationResultHandler | <1 KB | Just an observer, no UI |
| RollbackInsertion | <1 KB | Static utility functions |
| Darwin notif observer | <1 KB | C API, minimal overhead |
| AppGroup reader | <1 KB | UserDefaults read-only |
| **Total Extension Overhead** | **~0.5 MB** | |

### 8.2 Container App Memory Cost Breakdown

| Component | Estimated | Notes |
|-----------|-----------|-------|
| AVAudioEngine | ~2-3 MB | Audio buffer management |
| SFSpeechRecognizer | ~2-3 MB | Speech recognition engine |
| DictationViewController | ~0.5 MB | Modal UI |
| DictationResultDispatcher | <1 KB | Lightweight dispatcher |
| **Total Container App Overhead** | **~5-7 MB** | OK (app typically has 50+ MB available) |

**Critical Finding:** Dictation feature uses <4 MB in extension, well within 30 MB limit.

---

## 9. APPLE GUIDELINES COMPLIANCE CHECK

### 9.1 Keyboard Extension Requirements

Per: https://developer.apple.com/documentation/uikit/keyboards_and_input/creating_a_custom_keyboard

✓ **Must NOT:**
- Store sensitive user data (usernames, passwords)
- Access files outside app group
- Perform network requests directly (proxy through container app)

✓ **Must SUPPORT:**
- Text insertion via UITextDocumentProxy
- Dismissing keyboard
- Providing custom keyboard layout

✓ **Optional:**
- Microphone access (delegated to container app)
- Speech recognition (delegated to container app)

**Compliance Status:** Architecture delegates microphone/speech to container app. Extension only handles lightweight UI + text insertion. COMPLIANT.

### 9.2 Speech Recognition (SFSpeechRecognizer)

Per: https://developer.apple.com/documentation/speech

✓ **Requires:**
- NSSpeechRecognitionUsageDescription in Info.plist
- NSMicrophoneUsageDescription in Info.plist
- User permission prompt (first use)

✓ **Automatically handled:**
- Offline speech recognition support (device-dependent)
- Streaming results
- Language selection

**Compliance Status:** Info.plist keys will be added. Permission system handled by iOS. COMPLIANT.

### 9.3 App Store Review Risk Assessment

**Current Status:** Project not yet submitted to App Store (per CLAUDE.md note).

**Dictation Feature Risk Level: LOW**

✓ No prohibited APIs used
✓ Memory usage within limits
✓ No privacy violations
✓ Standard Apple frameworks (SFSpeechRecognizer is fully approved)
✓ Clear privacy messaging in usage descriptions

**No review risk increase.**

---

## 10. FILE SUMMARY TABLE

| File Path | Type | Lines | Purpose | Memory Cost |
|-----------|------|-------|---------|------------|
| `/Shared/DictationConstants.swift` | NEW | ~50 | Notification names, AppGroup keys | <1 KB |
| `/Shared/DictationDataModel.swift` | NEW | ~40 | Codable structs | <1 KB |
| `/Shared/DarwinNotificationManager.swift` | NEW | ~60 | Darwin notification wrapper | <2 KB |
| `/TranslatorKeyboard/Voice/SpeechRecognitionManager.swift` | NEW | ~150 | AVAudioEngine + SFSpeechRecognizer | ~5-8 MB (container) |
| `/TranslatorKeyboard/Voice/DictationResultDispatcher.swift` | NEW | ~80 | AppGroup writes + Darwin posts | <1 KB |
| `/TranslatorKeyboard/Voice/DictationViewController.swift` | NEW | ~200 | Recording UI modal | ~2-3 MB |
| `/KeyboardExtension/Voice/DictationUIManager.swift` | NEW | ~120 | Status UI + buttons | ~0.5 MB |
| `/KeyboardExtension/Voice/DictationResultHandler.swift` | NEW | ~100 | Darwin observer + routing | <1 KB |
| `/KeyboardExtension/Voice/RollbackInsertion.swift` | NEW | ~60 | Text deletion + insertion utility | <1 KB |
| `/Shared/Constants.swift` | MODIFY | +10 lines | Add dictation UserDefaults keys | 0 |
| `/Shared/ToolbarConfiguration.swift` | MODIFY | +2 lines | Add `.dictation` case | 0 |
| `/KeyboardExtension/UI/ToolbarView.swift` | MODIFY | +20 lines | Dictation button + callback | 0 |
| `/KeyboardExtension/KeyboardViewController.swift` | MODIFY | +40 lines | Dictation state + startDictation() | 0 |
| `/TranslatorKeyboard/App/SceneDelegate.swift` | MODIFY | +10 lines | Add "dictation" URL route | 0 |
| `/TranslatorKeyboard/Resources/Info.plist` | MODIFY | +4 entries | Microphone + speech permissions | 0 |

---

## 11. TESTING CHECKLIST

### Unit Tests

- [ ] DictationConstants exports correct notification names
- [ ] DictationDataModel Codable encode/decode round-trip
- [ ] DarwinNotificationManager posts/observes notifications
- [ ] RollbackInsertion correctly calculates deletion counts
- [ ] SpeechRecognitionManager initializes AVAudioEngine

### Integration Tests

- [ ] End-to-end: tap dictation → container app opens → recording → partial results → final result → text inserted
- [ ] Partial text rollback on successive results
- [ ] Final result overwrites all partials
- [ ] Cancel recording → cleanup (no dangling state)
- [ ] Timeout after 60 seconds → auto-stop
- [ ] Language picker → correct language passed to SFSpeechRecognizer
- [ ] Microphone permission denied → graceful error message

### Memory Tests

- [ ] Extension memory increase <4 MB when dictation feature active
- [ ] Total extension memory <30 MB under all conditions
- [ ] No memory leaks in Darwin observer lifecycle
- [ ] Proper cleanup on DictationViewController dismiss

### Compatibility Tests

- [ ] Works with all supported iOS versions (check SFSpeechRecognizer availability)
- [ ] Works with different keyboard themes
- [ ] Works with different toolbar configurations
- [ ] Accessibility: VoiceOver labels correct, focus management works
- [ ] Localization: UI strings display in multiple languages

---

## 12. FUTURE ENHANCEMENTS (Out of Scope)

1. **Auto-language detection** — Use keyboard's current language setting
2. **Confidence scores** — Display word-level confidence in UI
3. **Custom vocabulary** — Feed user's saved phrases to SFSpeechRecognizer
4. **Offline recording** — Store audio locally, upload when network available
5. **Analytics** — Track dictation usage, error rates, duration
6. **Undo/Redo** — Full undo stack for dictation insertions
7. **Voice commands** — "Punctuation: period", "Delete line", etc.
8. **Multi-language mixing** — Auto-detect language changes mid-sentence
9. **Haptic feedback** — Vibration on partial/final results
10. **Wake word** — "Hey Translator" to activate without button tap

---

## 13. APPROVAL & NEXT STEPS

**This document is a design specification ONLY. No coding has been performed.**

**Required before proceeding to Phase 1:**

1. User reviews this architecture document
2. User approves the design (file structure, communication protocol, memory strategy)
3. User confirms understanding of 4-phase rollout
4. User explicitly grants approval to begin Phase 1 coding (with explicit confirmation required)

**Delivery format for Phase 1 coding:**
- Will be delivered as a new `.md` prompt file in `/GuideLine Prompt/` directory
- New prompt version (not overwriting existing prompts)
- Suitable for Claude Code CLI execution

---

**Document Version:** v1.0
**Date:** 2026-03-28
**Status:** DESIGN PHASE (Awaiting User Approval)
