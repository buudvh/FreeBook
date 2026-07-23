# Code Review: Reader & TTS Components

**Date**: 2026-07-23  
**Reviewer**: Kiro AI Assistant  
**Components Reviewed**: 
- `ReaderView.swift` - Reading interface
- `ReaderViewModel.swift` - Reading business logic  
- `TTSManager.swift` - Text-to-speech engine

---

## Executive Summary

The Reader and TTS implementation demonstrates **sophisticated architecture** with excellent separation of concerns. The codebase shows maturity with comprehensive error handling, lifecycle management, and performance optimization. However, there are areas for improvement around code complexity, memory management, and testability.

**Overall Rating**: ⭐⭐⭐⭐☆ (4/5)

---

## 1. ReaderViewModel Analysis

### ✅ Strengths

#### 1.1 Robust State Management
```swift
enum ReaderLoadState: Equatable {
    case bootstrapping
    case loading(chapterIndex: Int)
    case ready(chapterIndex: Int)
    case failed(chapterIndex: Int?, message: String)
}
```
- Clear state transitions with generation tracking prevent race conditions
- Navigation queue system with debouncing prevents UI jank
- Proper handling of concurrent chapter loads

#### 1.2 Cache Architecture
```swift
let cache = ChapterCache()
let prefetcher = PrefetchManager()
```
- Sliding window cache pattern optimizes memory usage
- One-forward speculative prefetch improves perceived performance
- Clear separation between cache and prefetch concerns

#### 1.3 Cancellation & Cleanup
```swift
func shutdown(saveProgress: Bool = true) async {
    dbSaveTask?.cancel()
    prefetchQueueTask?.cancel()
    // ... proper cleanup of all tasks
}
```
- Comprehensive task cancellation on lifecycle events
- Async/await properly utilized for cleanup sequences
- Progress persistence before teardown

### ⚠️ Issues & Recommendations

#### 1.1 High Complexity - God Object Pattern
**Problem**: `ReaderViewModel` has 1000+ lines with 20+ responsibilities:
- Chapter loading & caching
- Progress tracking & persistence  
- Translation management
- Navigation queue management
- Prefetch coordination
- SwiftData context management

**Recommendation**: **Refactor into smaller, focused components**

```swift
// PROPOSED ARCHITECTURE

// 1. Core ViewModel (coordinate only)
class ReaderViewModel {
    private let chapterLoader: ChapterLoader
    private let progressTracker: ProgressTracker
    private let navigationController: NavigationController
    private let cacheManager: CacheManager
}

// 2. Chapter Loading (single responsibility)
class ChapterLoader {
    func loadChapter(_ index: Int, forceRefresh: Bool) async throws -> ChapterContent
    func prefetchAdjacent(to index: Int) async
}

// 3. Progress Persistence (single responsibility)
class ProgressTracker {
    func record(_ progress: ReadingProgress)
    func debounceAndSave() async
}

// 4. Navigation Logic (single responsibility)  
class NavigationController {
    func requestChapter(_ index: Int, source: NavigationSource)
    private func deduplicateRequests()
    private func executeNavigation()
}
```

**Benefits**:
- Each class has one clear purpose
- Easier to test in isolation
- Reduced cognitive load
- Better reusability

#### 1.2 Synchronous Blocking Calls in Async Context

**Problem**: Heavy synchronous operations block async execution:

```swift
// CURRENT - BLOCKS
public func fetchChapter(at index: Int) -> ChapterModel? {
    let semaphore = DispatchSemaphore(value: 0)
    Task {
        result = try? await repo.getChapter(bookId: bookId, index: index)
        semaphore.signal()
    }
    _ = semaphore.wait(timeout: .now() + 2.0)  // ❌ BLOCKS thread
    return result
}
```

**Recommendation**: Make it fully async

```swift
// PROPOSED - NON-BLOCKING
public func fetchChapter(at index: Int) async throws -> ChapterModel? {
    return try await repo.getChapter(bookId: bookId, index: index)
}
```

#### 1.3 Weak Error Handling in Critical Paths

**Problem**: Silent failures hide bugs:

```swift
private func loadChapterContentFromExtension(...) async throws {
    // ... complex logic
    cache.set(index, state: .loading)
    // If this throws, state stuck in .loading forever
    let result = try await ChapterContentRepository.shared.load(request)
}
```

**Recommendation**: Add error state recovery

```swift
do {
    cache.set(index, state: .loading)
    let result = try await ChapterContentRepository.shared.load(request)
    cache.set(index, state: .loaded)
} catch {
    cache.set(index, state: .failed(message: error.localizedDescription))
    throw error
}
```

#### 1.4 Memory Management Concerns

**Problem**: Potential strong reference cycles in closures:

```swift
prefetchQueueTask = Task {
    await prefetcher.updateQueue(...) { [weak self] index in
        guard let self = self else { return }
        try await self.loadChapterContentFromExtension(index)
    }
}
```

**Recommendation**: 
- Already using `[weak self]` ✅
- But add diagnostic logging for leak detection in DEBUG

```swift
#if DEBUG
deinit {
    print("✅ ReaderViewModel deallocated for book: \(bookId)")
}
#endif
```

---

## 2. TTSManager Analysis

### ✅ Strengths

#### 2.1 Multi-Engine Architecture
```swift
private let siriService = SiriTTSService()
private let extService = ExtTTSService()
private let googleService = GoogleTTSService()
private var nghiTTSService: PiperTTSService?
```
- Clean abstraction for multiple TTS providers
- Easy to add new engines
- Fallback mechanisms built-in

#### 2.2 Prefetch Window Optimization
```swift
private func updatePrefetchWindow() {
    let targetIndices = [N + 1]  // Sliding window
    // Cancel out-of-window tasks
    for idx in prefetchTasks.keys where !targetIndices.contains(idx) {
        prefetchTasks[idx]?.cancel()
    }
}
```
- Intelligent cache management (N, N+1 only)
- Cancellation of irrelevant prefetch tasks
- Zero-latency paragraph transitions

#### 2.3 Audio Session Interruption Handling
```swift
private func handleInterruption(notification: Notification) {
    switch type {
    case .began:
        if isPlaying {
            self.wasPlayingBeforeInterruption = true
            self.pause()
        }
    case .ended:
        if self.wasPlayingBeforeInterruption {
            // Resume after 0.5s delay
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
                self.resume()
            }
        }
    }
}
```
- Robust handling of phone calls, Siri interruptions
- Automatic resume after interruption ends
- Proper AVAudioSession lifecycle

### ⚠️ Issues & Recommendations

#### 2.1 Massive File Size (1600+ lines)

**Problem**: Single file with multiple concerns:
- Audio engine management
- TTS synthesis (4 engines)
- Chapter queue management  
- Progress tracking
- Now Playing integration
- Remote control handling
- Settings management
- Download progress tracking

**Recommendation**: Split into focused files

```swift
// PROPOSED FILE STRUCTURE

TTSManager.swift              // 200 lines - coordinator only
├── TTSAudioEngine.swift      // 150 lines - AVAudioEngine wrapper
├── TTSSynthesisEngine.swift  // 100 lines - synthesis protocol
│   ├── SiriTTSService.swift
│   ├── GoogleTTSService.swift  
│   ├── PiperTTSService.swift
│   └── ExtTTSService.swift
├── TTSChapterQueue.swift     // 100 lines - queue management
├── TTSProgressTracker.swift  // 100 lines - progress persistence
├── TTSRemoteControl.swift    // 150 lines - MediaPlayer integration
├── TTSAudioSession.swift     // 100 lines - session & interruption
└── TTSPrefetchCache.swift    // 150 lines - buffer cache
```

#### 2.2 Complex State Synchronization

**Problem**: Multiple sources of truth can desync:

```swift
@Published public var isPlaying: Bool = false
@Published public var currentParagraphIndex: Int = -1
@Published public var showFloatingWidget: Bool = false

private var sessionID = UUID()
private var ttsProcessingGeneration = 0
private var currentPlaybackId: String? = nil
```

**Recommendation**: Use a single state enum

```swift
enum TTSPlaybackState {
    case stopped
    case preparing(chapter: Int, paragraph: Int)
    case playing(chapter: Int, paragraph: Int, playbackId: String)
    case paused(chapter: Int, paragraph: Int)
    case failed(error: Error)
}

@Published private(set) var playbackState: TTSPlaybackState = .stopped
```

**Benefits**:
- Impossible to have invalid state combinations
- Single source of truth
- Easier state transition logic
- Better testability

#### 2.3 Potential Memory Leak in AVAudioEngine

**Problem**: Strong capture in completion handlers:

```swift
player.scheduleBuffer(buffer, at: nil, options: []) { [weak self] in
    DispatchQueue.main.async {
        guard let self = self, self.isPlaying else { return }
        guard self.currentPlaybackId == playbackId else { return }
        self.nextParagraph()  // ✅ Already using weak self
    }
}
```

**Status**: ✅ Already properly handled with `[weak self]`

**Additional Recommendation**: Add buffer pool for reuse

```swift
private var bufferPool = NSCache<NSString, AVAudioPCMBuffer>()

func getOrCreateBuffer(for data: Data) -> AVAudioPCMBuffer? {
    let key = data.sha256() as NSString
    if let cached = bufferPool.object(forKey: key) {
        return cached
    }
    let buffer = makePCMBuffer(fromWavData: data, ...)
    bufferPool.setObject(buffer, forKey: key)
    return buffer
}
```

#### 2.4 Engine Configuration Change Handling

**Problem**: Engine rebuild on config change causes audio glitches:

```swift
private func handleEngineConfigChange() {
    stopCurrentPlayback()
    configureAudioSession()
    currentParagraphIndex = currentIdx
    speakCurrent()  // Causes brief silence gap
}
```

**Recommendation**: Prepare alternate engine in background

```swift
private var activeEngine: AVAudioEngine
private var stanbyEngine: AVAudioEngine?

func handleEngineConfigChange() {
    // Build new engine silently
    let newEngine = buildEngine()
    
    // Hot-swap when current buffer finishes
    player.scheduleBuffer(currentBuffer) { [weak self] in
        self?.swapEngine(to: newEngine)
    }
}
```

#### 2.5 Force Unwrapping Safety

**Problem**: Some force unwraps can crash:

```swift
guard let engine = audioEngine, let player = playerNode else {
    AppLogger.shared.log("ERROR: Components not initialized")
    return  // ✅ Good - safe early return
}
```

**Status**: ✅ Mostly safe with guard statements

**Minor Issue**: This pattern appears:

```swift
let chapters = self.chaptersQueue.first(where: { $0.index == nextIdx })!
```

**Fix**: Use guard or optional binding

```swift
guard let chapter = chaptersQueue.first(where: { $0.index == nextIdx }) else {
    stop()
    return
}
```

---

## 3. ReaderView Analysis

### ✅ Strengths

#### 3.1 Declarative SwiftUI Architecture
- Clean separation of view, view model, and state
- Proper use of `@State`, `@Published`, `@Environment`
- Lifecycle hooks properly managed with `.onAppear`, `.onDisappear`

#### 3.2 Translation System Integration
```swift
private var suggestionChips: [String] {
    // Multi-layer dictionary lookup
    // 1. Book-specific names
    // 2. Global names  
    // 3. Pronouns
    // 4. VietPhrase
    // 5. Hán Việt phonetic
}
```
- Sophisticated multi-source translation
- Book-specific customization
- Fallback hierarchy well-designed

#### 3.3 Selection & Definition UI
- Floating menu with smooth animations
- Context-aware dictionary lookups
- Smart selection expansion/shrinkage
- Integration with phoneme editor

### ⚠️ Issues & Recommendations

#### 3.1 View Complexity (1800+ lines)

**Problem**: Massive view file with multiple responsibilities:
- UI layout
- State management
- Translation logic
- TTS coordination
- Chapter navigation
- Dictionary integration  
- Settings management

**Recommendation**: Extract into subviews

```swift
// PROPOSED STRUCTURE

ReaderView.swift              // 300 lines - main coordinator
├── ReaderContentView.swift   // Chapter text rendering
├── ReaderHeaderView.swift    // Title, progress, controls
├── ReaderFooterView.swift    // Navigation buttons
├── ReaderTTSControl.swift    // Floating TTS widget
├── ReaderChapterList.swift   // TOC overlay
├── TranslationPanel.swift    // Dictionary/definition
└── SelectionMenu.swift       // Text selection toolbar
```

#### 3.2 Business Logic in View Layer

**Problem**: Translation logic should be in ViewModel:

```swift
// CURRENT - in View
private func translateChapterTitleIfNeeded(_ text: String) -> String {
    guard isTranslationEnabled && TranslateUtils.containsChinese(text) else {
        return text
    }
    return TranslateUtils.translateChapterTitle(text, bookId: bookId)
}
```

**Recommendation**: Move to ViewModel

```swift
// ReaderViewModel
func formattedChapterTitle(at index: Int) -> String {
    let raw = chapterTitle(at: index)
    return translationService.translate(raw, context: .chapterTitle)
}
```

#### 3.3 State Management Complexity

**Problem**: 50+ `@State` variables are hard to reason about:

```swift
@State private var showChapterTitle = true
@State private var selectedTextForDefinition = ""
@State private var showingDefinitionSheet = false
@State private var customMeaning = ""
@State private var originalSentence = ""
@State private var selectedWordOffset = 0
@State private var selectedWordLength = 0
// ... 40+ more
```

**Recommendation**: Group related state

```swift
struct SelectionState {
    var text: String = ""
    var sentence: String = ""
    var offset: Int = 0
    var length: Int = 0
    var isShowingMenu: Bool = false
}

struct TranslationState {
    var isEnabled: Bool
    var mode: TranslationMode
    var customMeaning: String = ""
    var tokens: [TranslationToken] = []
}

@State private var selection = SelectionState()
@State private var translation = TranslationState(...)
```

---

## 4. Cross-Component Integration

### ✅ Strengths

#### 4.1 Notification-Based Decoupling
```swift
// TTSManager advances chapter
NotificationCenter.default.post(
    name: NSNotification.Name("ttsDidAdvanceToNextChapter"),
    object: nil,
    userInfo: ["bookId": bookId, "chapterIndex": index]
)

// ReaderView listens and syncs UI
.onReceive(NotificationCenter.default.publisher(for: NSNotification.Name("ttsDidAdvanceToNextChapter"))) { 
    // Update UI
}
```
- Loose coupling between components
- Easy to add new listeners
- Testable in isolation

#### 4.2 Progress Ownership Pattern
```swift
enum ReadingProgressOwner {
    case reader
    case tts
}

func saveProgress() {
    let ttsOwnsProgress = ttsManager.isPlaying && ttsManager.playingBookId == bookId
    if !ttsOwnsProgress {
        viewModel?.updateProgress(...)
    }
}
```
- Clear ownership semantics prevent conflicts
- Reader defers to TTS when it's playing
- Proper handoff on state transitions

### ⚠️ Issues

#### 4.1 Circular Dependency Risk

**Problem**: Both components reference each other:

```
ReaderView → TTSManager (starts TTS)
    ↓
TTSManager → NotificationCenter → ReaderView (syncs chapter)
```

**Recommendation**: Introduce coordinator

```swift
class ReaderCoordinator {
    let viewModel: ReaderViewModel
    let ttsManager: TTSManager
    
    func startTTS(at chapter: Int, paragraph: Int) {
        let content = viewModel.getChapterContent(chapter)
        ttsManager.startSpeaking(content, from: paragraph)
    }
    
    func syncReaderToTTS() {
        guard let playing = ttsManager.currentPosition else { return }
        viewModel.navigate(to: playing.chapter, paragraph: playing.paragraph)
    }
}
```

---

## 5. Testing & Maintainability

### Current State

#### ❌ Lack of Unit Tests
No test coverage found for:
- ReaderViewModel navigation logic
- TTSManager state transitions
- Translation utilities
- Cache management

#### ❌ Testability Issues
- Heavy use of singletons (`TTSManager.shared`)
- Direct SwiftData dependencies
- No dependency injection
- File operations in production code

### Recommendations

#### 5.1 Add Protocol Abstractions

```swift
// CURRENT
class ReaderViewModel {
    let modelContext: ModelContext  // Hard dependency
}

// PROPOSED
protocol PersistenceContext {
    func fetch<T>(_ descriptor: FetchDescriptor<T>) throws -> [T]
    func save() throws
}

class ReaderViewModel {
    let persistence: PersistenceContext
}

// Now testable!
class MockPersistence: PersistenceContext { ... }
```

#### 5.2 Extract Business Logic to Pure Functions

```swift
// Testable without UI framework
struct ChapterNavigationLogic {
    static func nextValidIndex(
        from current: Int,
        total: Int,
        direction: NavigationDirection
    ) -> Int? {
        // Pure function - easy to test
    }
    
    static func shouldPrefetch(
        current: Int,
        cached: Set<Int>,
        windowSize: Int
    ) -> [Int] {
        // Pure function - easy to test
    }
}
```

#### 5.3 Add Integration Test Entry Points

```swift
#if DEBUG
extension TTSManager {
    func testMode() {
        // Disable real audio
        // Expose internal state
        // Fast-forward animations
    }
}
#endif
```

---

## 6. Performance Optimization

### ✅ Good Practices Already Applied

1. **Lazy Loading**: Chapters loaded on-demand
2. **Prefetch Window**: Only N+1 loaded ahead
3. **Cache Eviction**: Memory warning handler releases old chapters
4. **Debouncing**: Progress saves debounced (3s)
5. **Background Processing**: Translation off main thread

### 🚀 Additional Optimizations

#### 6.1 Paragraph Rendering Optimization

**Current**: All paragraphs in chapter rendered at once

```swift
ForEach(chapter.paragraphItems) { item in
    ParagraphCardView(item: item)  // Could be 100+ views
}
```

**Proposal**: Use LazyVStack with viewport tracking

```swift
LazyVStack {
    ForEach(chapter.paragraphItems) { item in
        ParagraphCardView(item: item)
            .task(id: item.id) {
                // Load heavy content only when visible
                await loadHeavyContent(for: item)
            }
    }
}
```

#### 6.2 Translation Cache Warm-up

**Idea**: Pre-translate adjacent chapters

```swift
func warmUpTranslationCache(for chapterIndex: Int) async {
    let indices = [chapterIndex - 1, chapterIndex, chapterIndex + 1]
    for idx in indices where idx >= 0 && idx < totalChapters {
        let chapter = await loadChapter(idx)
        await TranslateUtils.preloadTranslations(for: chapter.text)
    }
}
```

#### 6.3 Audio Buffer Pooling

**Current**: Buffers created and discarded per paragraph

```swift
let buffer = makePCMBuffer(fromWavData: wavData)
// Used once, then GC'd
```

**Proposal**: Reuse buffers for same content

```swift
private let bufferCache = NSCache<NSString, AVAudioPCMBuffer>()

func getBuffer(for content: Data) -> AVAudioPCMBuffer {
    let key = content.hashValue as NSString
    if let cached = bufferCache.object(forKey: key) {
        return cached
    }
    let buffer = makePCMBuffer(fromWavData: content)
    bufferCache.setObject(buffer, forKey: key)
    return buffer
}
```

---

## 7. Security & Data Safety

### ✅ Good Practices

1. **Progress Auto-Save**: On background, app termination, chapter change
2. **Task Cancellation**: All async tasks properly cancelled
3. **Error Recovery**: Failed loads don't corrupt state

### ⚠️ Concerns

#### 7.1 No Data Corruption Protection

**Problem**: Concurrent writes to SwiftData

```swift
// Thread 1
Task {
    modelContext.save()
}

// Thread 2  
Task {
    modelContext.save()
}
// Possible race condition
```

**Recommendation**: Use actor for serialization

```swift
actor PersistenceCoordinator {
    private let context: ModelContext
    
    func save<T>(_ object: T) async throws {
        // Serialized writes
        context.insert(object)
        try context.save()
    }
}
```

#### 7.2 No Validation on User Input

**Problem**: Custom translation entries not validated

```swift
func saveCustomEntry(word: String, meaning: String, ...) async throws {
    // No validation - could save malformed data
    let entry = TranslationEntry(word: word, meaning: meaning)
    modelContext.insert(entry)
}
```

**Recommendation**: Add validation layer

```swift
func saveCustomEntry(word: String, meaning: String) async throws {
    guard !word.isEmpty, word.count <= 100 else {
        throw ValidationError.invalidWord
    }
    guard !meaning.isEmpty, meaning.count <= 500 else {
        throw ValidationError.invalidMeaning
    }
    // ... save
}
```

---

## 8. Code Quality Metrics

| Metric | ReaderViewModel | TTSManager | ReaderView | Target |
|--------|----------------|------------|------------|--------|
| Lines of Code | 1,000 | 1,600 | 1,800 | <500 |
| Cyclomatic Complexity | High | High | High | Medium |
| Public API Surface | 15 methods | 25 methods | N/A | <10 |
| Dependencies | 7 | 12 | 15 | <5 |
| Test Coverage | 0% | 0% | 0% | >80% |

---

## 9. Actionable Recommendations (Priority Order)

### 🔴 Critical (Do First)

1. **Add Unit Tests** (2-3 weeks)
   - Start with pure functions (navigation logic, translation)
   - Mock external dependencies
   - Aim for 60% coverage initially

2. **Extract Business Logic from Views** (1 week)
   - Move translation logic to ViewModels
   - Move formatting logic to utilities
   - Pure views should only handle layout

3. **Refactor TTSManager** (2 weeks)
   - Split into 6-7 focused files
   - Introduce protocols for engines
   - Reduce complexity per file to <300 lines

### 🟡 Important (Do Next)

4. **Refactor ReaderViewModel** (2 weeks)
   - Extract ChapterLoader, ProgressTracker
   - Introduce NavigationController
   - Reduce to coordinator role only

5. **Add State Machine** (1 week)
   - Replace boolean flags with enum states
   - Impossible states become unrepresentable
   - Easier debugging and logging

6. **Improve Error Handling** (1 week)
   - Add retry logic for transient failures
   - User-friendly error messages
   - Logging for diagnostics

### 🟢 Nice to Have (Future)

7. **Performance Profiling** (3 days)
   - Use Instruments to find bottlenecks
   - Optimize hot paths
   - Reduce allocations

8. **Documentation** (1 week)
   - Architecture decision records
   - API documentation
   - Code examples for common tasks

9. **Accessibility** (1 week)
   - VoiceOver testing
   - Dynamic Type support
   - Reduced motion options

---

## 10. Conclusion

The Reader and TTS implementation is **functionally solid** with impressive features:
- Multiple TTS engine support
- Robust chapter caching and prefetching
- Sophisticated translation system
- Good lifecycle management

However, **maintainability and testability need improvement**:
- Files are too large (1000-1800 lines)
- Too many responsibilities per class
- No unit tests
- Business logic mixed with UI

**Recommended Path Forward**:
1. Stabilize with tests (prevent regressions)
2. Refactor incrementally (one component at a time)
3. Introduce protocols for testability
4. Extract subcomponents for maintainability

**Estimated Effort**: 6-8 weeks for full refactor  
**Risk Level**: Medium (extensive usage, careful migration needed)  
**ROI**: High (much easier to maintain and extend long-term)

---

## Appendix: Code Health Checklist

### Architecture
- ✅ Clear separation of concerns (View/ViewModel)
- ❌ Files too large (need splitting)
- ⚠️ Some circular dependencies
- ✅ Good use of async/await

### Code Quality  
- ✅ Consistent naming conventions
- ✅ Good use of Swift features (enums, protocols)
- ❌ High cyclomatic complexity
- ⚠️ Some force unwraps (mostly safe)

### Testing
- ❌ No unit tests
- ❌ No integration tests  
- ❌ Hard to test (tight coupling)
- ❌ No test fixtures

### Performance
- ✅ Good caching strategy
- ✅ Proper debouncing
- ✅ Background processing
- ⚠️ Some optimization opportunities

### Maintainability  
- ⚠️ Good comments, but not enough
- ❌ No architectural documentation
- ⚠️ Some God objects
- ✅ Clear error messages

### Security
- ✅ Progress auto-save
- ✅ Task cancellation
- ⚠️ No data validation
- ⚠️ Possible race conditions

---

**Review completed**: 2026-07-23  
**Next review recommended**: After refactoring (Q4 2026)
