# 키보드 익스텐션 메모리 30MB 이하 최적화 보고서 (Memory Optimization Plan)

현재 키보드 익스텐션의 메모리가 초기화 단계(`viewDidLoad`)에서 이미 62.5MB에 도달하며, 뷰가 나타나는 과정에서 70MB 이상으로 치솟아 결국 시스템에 의해 강제 종료(Exit Code 9)되는 심각한 이슈가 발생하고 있습니다. iOS 키보드 익스텐션의 메모리 한계는 보통 70~80MB 내외로 매우 제한적입니다. 이를 30MB 이하로 줄이기 위한 종합적인 아키텍처 및 로직 개선 계획을 수립했습니다.

---

## 1. 핵심 성능 병목 및 메모리 누수 위험 분석

### A. 거대한 JSON 사전 데이터의 메모리 적재 (PredictionEngine.swift)
- **문제점:** `ngram_en.json`, `ngram_ko.json` 파일의 Trigram, Bigram, Unigram 데이터를 `JSONSerialization`을 통해 Swift의 기본 `Dictionary([String: [(String, Int)]])` 구조로 전체를 파싱하고 있습니다. JSON 파일 크기가 수 MB라도, 이를 파싱하여 Swift의 구조체 및 객체로 변환하면 객체 오버헤드로 인해 메모리 점유율이 20~40MB 이상 폭증하게 됩니다.
- **최적화 방안:** JSON 전체 메모리 로딩을 즉시 중단해야 합니다. n-gram 데이터는 **SQLite** 데이터베이스나 **CoreData**를 이용해 디스크 기반으로 쿼리(Lazy Query)하도록 변경해야 합니다. 초기 구동 시에는 DB 커넥션만 열어두고, 사용자가 입력할 때만 필요한 단어 조합을 쿼리하여 메모리를 1~2MB 이내로 유지해야 합니다.

### B. 시스템 내부 사전을 호출하는 UITextChecker (AutocorrectEngine.swift)
- **문제점:** `UITextChecker`는 시스템 레벨의 교정 사전을 메모리로 불러옵니다. 초기화 및 언어 설정 시점에 적게는 10MB에서 많게는 20MB 이상의 메모리를 사용합니다. `SuggestionManager`에서 이 객체를 강하게(eager) 들고 있을 경우 베이스라인 메모리가 급격히 상승합니다.
- **최적화 방안:** `UITextChecker`를 `lazy var`로 선언하여, 자동 완성 기능을 실제 사용할 때만 인스턴스화되게 지연(Deferred)시켜야 합니다. 가능하다면 자체적인 가벼운 로직으로 대체하거나, 메모리 경고 시(`didReceiveMemoryWarning`) 즉각 해제(nil 처리)할 수 있는 구조로 변경해야 합니다.

### C. 불필요한 SwiftUI 브릿징 오버헤드 (KeyboardViewController.swift)
- **문제점:** 로그에서 확인되듯 `setupSettingsLink` 호출 시 `UIHostingController(rootView: SettingsLinkView())`를 삽입하면서 순간적으로 약 3MB의 메모리 상승이 일어납니다. SwiftUI 환경을 UIKit 기반의 익스텐션에 구동시키는 것 자체가 추가 프레임워크 로드 비용을 발생시킵니다.
- **최적화 방안:** `SettingsLinkView` 같은 간단한 버튼 뷰는 무거운 `UIHostingController`를 쓰지 말고, 순수 UIKit (`UIButton`, `UIStackView` 등)을 사용해 Native로 다시 작성해야 합니다. 이렇게 하면 SwiftUI 브릿징으로 인한 베이스 메모리 증가를 원천 차단할 수 있습니다.

### D. 무거운 테마와 애니메이션 뷰 관리 (ThemeManager 및 Animation Views)
- **문제점:** `MatrixRainView`, `StardustView`, `SnowfallView`, `CherryBlossomView` 등은 파티클을 렌더링하고 `CADisplayLink`를 사용합니다. 여러 테마를 전환하거나 인스턴스를 들고 있을 때, 계층에 쌓인 `CALayer`나 내부 상태들이 제대로 해제되지 않으면 극심한 메모리 누수로 이어집니다.
- **최적화 방안:**
    1. **On-Demand 로딩 및 완전한 소멸:** 테마 뷰는 화면에 보일 때만 할당하고, 키보드가 닫히거나(`viewWillDisappear`) 테마가 변경되면 `removeFromSuperview()` 및 내부의 `CADisplayLink`를 완전히 invalidate 시키고 인스턴스를 강제로 `nil`로 만들어야 합니다.
    2. **이미지 캐싱 방지:** `UIImage(named:)`는 시스템 메모리 캐시에 이미지를 유지시킵니다. 큰 배경 이미지나 목재 타일(Wood Theme)과 같은 에셋은 `UIImage(contentsOfFile:)`을 사용하여 메모리에 캐시되지 않도록 변경해야 합니다.

### E. 클래스 프로퍼티의 Eager Initialization (지연 초기화 부재)
- **문제점:** `KeyboardViewController`에서 `translationManager`, `correctionManager`, `sessionManager`, `suggestionManager` 등의 주요 매니저들이 뷰 컨트롤러가 로드될 때 한 번에 생성됩니다. 
- **최적화 방안:** 의존성을 가지는 모든 주요 프로퍼티들을 `lazy var` 로 선언하여, 실제 사용자가 해당 기능을 호출하기 전까지는 절대 메모리에 적재되지 않도록 해야 합니다.

---

## 2. 단계별 30MB 언더 메모리 최적화 워크플로우

### Phase 1: 아키텍처 및 자료구조 대규모 리팩토링 (가장 시급함)
1. **[데이터베이스 마이그레이션]** `PredictionEngine.swift` 내부의 `ngram` JSON 로딩 로직 완전 제거. 대신 `SQLite.swift` 또는 경량 로컬 DB 솔루션을 도입. `Bundle` 내에 미리 컴파일된 `.sqlite` 파일을 두고 `SELECT` 쿼리로만 동작하도록 변경 (기대 효과: 메모리 약 15~30MB 감소).
2. **[SwiftUI 제거]** 익스텐션 내부에서 사용 중인 `UIHostingController` 의존성 제거. `SettingsLinkView` 등을 `UIView` 기반으로 마이그레이션 (기대 효과: 베이스라인 메모리 약 3~5MB 감소).

### Phase 2: 지연 생성(Lazy Loading) 및 리소스 관리 도입
1. **[엔진 지연 로드]** `AutocorrectEngine`, `PredictionEngine`, `UITextChecker`를 모두 `lazy var` 타입으로 변경 및 Singleton 참조 구조 완화. 메모리 압박 이벤트 시 초기화된 캐시를 날릴 수 있도록 `clearCache()` 인터페이스 구성.
2. **[매니저 지연 할당]** `KeyboardViewController`의 인스턴스 프로퍼티들(`translationManager`, `correctionManager` 등)을 `lazy var`로 통일하여 초기 뷰 로딩 타임의 부담 축소.

### Phase 3: 에셋 및 애니메이션 메모리 누수 방어
1. **[이미지 로딩 최적화]** `UIImage(named:)` 전역 검색 후, 자주 바뀌는 테마 이미지나 큰 해상도의 에셋은 `UIImage(contentsOfFile:)`로 교체하여 캐시 메모리 폭주 방지.
2. **[애니메이션 뷰 해제 보장]** 모든 Animation View(`MercuryRippleView.swift` 등)의 `deinit`에 브레이크포인트를 걸어 해제가 제대로 되는지 확인. 부모 뷰에서 제거 시 타이머와 `CADisplayLink`를 반드시 해제하는 `stopAnimation()` 메서드 강제 호출 패턴 도입.
3. **[스파게티 코드 분리 및 강한 참조 순환(Retain Cycle) 제거]** 클로저(Closure) 내부에서 무심코 사용된 `self.` 호출 부분을 점검하여 `[weak self]` 처리가 누락된 비동기 네트워크 통신(`TranslationManager`, `CorrectionManager`) 로직 보완.

## 3. 결론

현재 `viewDidLoad` 단계에서 62.5MB의 메모리가 찍히는 가장 큰 원인은 **초기화 시점에 무거운 JSON 데이터(N-gram 사전)의 메모리 파싱**과 **UITextChecker를 포함한 기능성 싱글톤/매니저들의 일괄 할당**, 그리고 **SwiftUI 환경의 로딩 오버헤드**가 겹쳤기 때문입니다. 이 세 가지 요소만 지연 로딩(Lazy loading) 및 디스크 쿼리(DB) 방식으로 변경해도 메모리 사용량을 30MB 이하로 드라마틱하게 억제할 수 있을 것입니다. 
코드 수정에 착수할 때 이 보고서의 Phase 1을 최우선 순위로 진행하시기 바랍니다.