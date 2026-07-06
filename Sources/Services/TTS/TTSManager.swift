import Foundation
import AVFoundation
import MediaPlayer
import Combine
import QuartzCore

@MainActor
public final class TTSManager: NSObject, ObservableObject {
    public static let shared = TTSManager()
    
    // Cấu hình (lưu qua AppStorage/UserDefaults)
    @Published public var tool: String {
        didSet {
            UserDefaults.standard.set(tool, forKey: "ttsTool")
            loadParamsForCurrentTool()
        }
    }
    @Published public var speed: Double {
        didSet {
            UserDefaults.standard.set(speed, forKey: "ttsRate")
            if tool == "system" {
                UserDefaults.standard.set(speed, forKey: "systemRate")
            } else {
                UserDefaults.standard.set(speed, forKey: "nghittsRate")
            }
            updatePlaybackParams()
        }
    }
    @Published public var pitch: Double {
        didSet {
            UserDefaults.standard.set(pitch, forKey: "ttsPitch")
            if tool == "system" {
                UserDefaults.standard.set(pitch, forKey: "systemPitch")
            } else {
                UserDefaults.standard.set(pitch, forKey: "nghittsPitch")
            }
            updatePlaybackParams()
        }
    }
    @Published public var selectedVoice: String {
        didSet {
            UserDefaults.standard.set(selectedVoice, forKey: "ttsVoice")
            if tool == "system" {
                UserDefaults.standard.set(selectedVoice, forKey: "systemVoice")
            } else {
                UserDefaults.standard.set(selectedVoice, forKey: "nghittsVoice")
            }
        }
    }
    @Published public var chunkLength: Int {
        didSet { UserDefaults.standard.set(chunkLength, forKey: "ttsChunkLength") }
    }
    
    // Trạng thái playback
    @Published public var isPlaying: Bool = false
    @Published public var currentParagraphIndex: Int = -1
    @Published public var highlightRange: NSRange? = nil
    
    // Thông tin phát nhạc độc lập toàn cục
    @Published public private(set) var playingBookId: String = ""
    @Published public private(set) var playingChapterUrl: String = ""
    @Published public private(set) var playingChapterIndex: Int = -1
    
    private var chaptersQueue: [TTSChapterInfo] = []
    private var extensionInfo: TTSExtensionInfo? = nil
    private var preloadedNextChapterContent: String? = nil
    private var isPreloading: Bool = false
    private var currentPlaybackId: String? = nil
    
    // Tiến trình tải model NghiTTS
    @Published public var downloadingVoices: [String: Double] = [:] // voiceName -> progress (0.0 ... 1.0)
    @Published public var downloadingMessages: [String: String] = [:] // voiceName -> message
    
    // Thông tin sách & chương hiện tại
    public var bookTitle: String = ""
    public var chapterTitle: String = ""
    
    // Callbacks chuyển chương
    public var onChapterFinished: (() -> Void)?
    public var onChapterPrev: (() -> Void)?
    public var onChapterNext: (() -> Void)?
    
    // Dữ liệu phân đoạn
    public private(set) var paragraphs: [TTSParagraph] = []
    private var chapterContent: String = ""
    
    // Trình phát & Engine
    private var systemSynthesizer: AVSpeechSynthesizer?
    private var nghiTTSService: PiperTTSService?
    public private(set) var nghiTTSClient: NghiTTSClient?
    private var modelStore: ModelStore?
    
    // AVAudioEngine cho NghiTTS
    private var audioEngine: AVAudioEngine?
    private var playerNode: AVAudioPlayerNode?
    private var timePitchNode: AVAudioUnitTimePitch?
    private var currentTempFileUrl: URL?
    
    private override init() {
        // Nạp cấu hình từ UserDefaults
        let toolVal = UserDefaults.standard.string(forKey: "ttsTool") ?? "system"
        self.tool = toolVal
        
        let defaultRate = UserDefaults.standard.object(forKey: "ttsRate") != nil ? UserDefaults.standard.double(forKey: "ttsRate") : 1.0
        let defaultPitch = UserDefaults.standard.object(forKey: "ttsPitch") != nil ? UserDefaults.standard.double(forKey: "ttsPitch") : 1.0
        
        if toolVal == "system" {
            self.speed = UserDefaults.standard.double(forKey: "systemRate") > 0 ? UserDefaults.standard.double(forKey: "systemRate") : defaultRate
            self.pitch = UserDefaults.standard.double(forKey: "systemPitch") > 0 ? UserDefaults.standard.double(forKey: "systemPitch") : defaultPitch
            self.selectedVoice = UserDefaults.standard.string(forKey: "systemVoice") ?? (UserDefaults.standard.string(forKey: "ttsVoice") ?? "")
        } else {
            self.speed = UserDefaults.standard.double(forKey: "nghittsRate") > 0 ? UserDefaults.standard.double(forKey: "nghittsRate") : defaultRate
            self.pitch = UserDefaults.standard.double(forKey: "nghittsPitch") > 0 ? UserDefaults.standard.double(forKey: "nghittsPitch") : defaultPitch
            self.selectedVoice = UserDefaults.standard.string(forKey: "nghittsVoice") ?? (UserDefaults.standard.string(forKey: "ttsVoice") ?? "Ngọc Huyền (mới)")
        }
        
        self.chunkLength = UserDefaults.standard.object(forKey: "ttsChunkLength") != nil ? UserDefaults.standard.integer(forKey: "ttsChunkLength") : 1000
        
        super.init()
        
        setupEngines()
        setupAudioEngine()
        setupRemoteCommandCenter()
    }
    
    private func loadParamsForCurrentTool() {
        let defaultRate = UserDefaults.standard.object(forKey: "ttsRate") != nil ? UserDefaults.standard.double(forKey: "ttsRate") : 1.0
        let defaultPitch = UserDefaults.standard.object(forKey: "ttsPitch") != nil ? UserDefaults.standard.double(forKey: "ttsPitch") : 1.0
        
        if tool == "system" {
            self.speed = UserDefaults.standard.double(forKey: "systemRate") > 0 ? UserDefaults.standard.double(forKey: "systemRate") : defaultRate
            self.pitch = UserDefaults.standard.double(forKey: "systemPitch") > 0 ? UserDefaults.standard.double(forKey: "systemPitch") : defaultPitch
            self.selectedVoice = UserDefaults.standard.string(forKey: "systemVoice") ?? ""
        } else {
            self.speed = UserDefaults.standard.double(forKey: "nghittsRate") > 0 ? UserDefaults.standard.double(forKey: "nghittsRate") : defaultRate
            self.pitch = UserDefaults.standard.double(forKey: "nghittsPitch") > 0 ? UserDefaults.standard.double(forKey: "nghittsPitch") : defaultPitch
            self.selectedVoice = UserDefaults.standard.string(forKey: "nghittsVoice") ?? "Ngọc Huyền (mới)"
        }
    }
    
    private func setupEngines() {
        do {
            let store = try ModelStore()
            self.modelStore = store
            self.nghiTTSClient = NghiTTSClient(modelStore: store)
            self.nghiTTSService = PiperTTSService(modelStore: store, engine: ONNXPiperEngine())
            
            // Đặt giọng NghiTTS mặc định nếu chưa chọn
            if self.selectedVoice.isEmpty {
                self.selectedVoice = NghiTTSClient.defaultVietnameseVoice.name
            }
        } catch {
            AppLogger.shared.log("Error initializing TTS model store: \(error.localizedDescription)")
        }
    }
    
    private func setupAudioEngine() {
        let engine = AVAudioEngine()
        let player = AVAudioPlayerNode()
        let pitchNode = AVAudioUnitTimePitch()
        
        engine.attach(player)
        engine.attach(pitchNode)
        
        // Connect Player -> TimePitch -> mainMixer
        engine.connect(player, to: pitchNode, format: nil)
        engine.connect(pitchNode, to: engine.mainMixerNode, format: nil)
        
        self.audioEngine = engine
        self.playerNode = player
        self.timePitchNode = pitchNode
    }
    
    private func configureAudioSession() {
        let session = AVAudioSession.sharedInstance()
        do {
            try session.setCategory(.playback, mode: .spokenAudio, options: [])
            try session.setActive(true)
        } catch {
            AppLogger.shared.log("Failed to configure AVAudioSession: \(error.localizedDescription)")
        }
    }
    
    private func updatePlaybackParams() {
        if isPlaying {
            if tool == "system" {
                // AVSpeechSynthesizer không hỗ trợ thay đổi tốc độ thời gian thực của câu đang nói,
                // nhưng cấu hình sẽ được áp dụng cho phân đoạn tiếp theo.
            } else if let pitchNode = timePitchNode {
                pitchNode.rate = Float(speed)
                let cents = 1200.0 * log2(pitch)
                pitchNode.pitch = Float(cents)
            }
            updateNowPlayingInfo()
        }
    }
    
    // MARK: - Playback Control
    
    public func startSpeaking(
        bookId: String,
        chapters: [TTSChapterInfo],
        currentIndex: Int,
        startCharIndex: Int,
        bookTitle: String,
        extensionInfo: TTSExtensionInfo?
    ) {
        // Dọn dẹp trình phát cũ trước tiên để tránh xung đột luồng và callback lặp
        self.stopCurrentPlayback()
        
        self.configureAudioSession()
        self.playingBookId = bookId
        self.chaptersQueue = chapters
        self.playingChapterIndex = currentIndex
        self.bookTitle = bookTitle
        self.extensionInfo = extensionInfo
        
        // Hủy dữ liệu tải trước cũ
        self.preloadedNextChapterContent = nil
        
        guard currentIndex >= 0 && currentIndex < chapters.count else { return }
        let currentChapter = chapters[currentIndex]
        self.playingChapterUrl = currentChapter.url
        self.chapterTitle = currentChapter.title
        
        if let cached = currentChapter.cachedContent, !cached.isEmpty {
            Task {
                let translated = await self.translateContentInBackground(cached)
                await MainActor.run {
                    if self.playingBookId == bookId && self.playingChapterIndex == currentIndex {
                        self.chaptersQueue[currentIndex].cachedContent = translated
                        self.chapterContent = translated
                        self.continueStartSpeaking(startCharIndex: startCharIndex)
                    }
                }
            }
        } else {
            // Tải chương online nếu chưa được cache
            Task {
                do {
                    let content = try await self.downloadChapterOnline(url: currentChapter.url)
                    let translated = await self.translateContentInBackground(content)
                    
                    await MainActor.run {
                        // Cập nhật lại cache trong hàng đợi
                        if self.playingBookId == bookId && self.playingChapterIndex == currentIndex {
                            self.chaptersQueue[currentIndex].cachedContent = translated
                            self.chapterContent = translated
                            self.continueStartSpeaking(startCharIndex: startCharIndex)
                        }
                    }
                } catch {
                    AppLogger.shared.log("Lỗi tải chương online cho TTS: \(error.localizedDescription)")
                    await MainActor.run {
                        self.stop()
                    }
                }
            }
        }
    }
    
    private func continueStartSpeaking(startCharIndex: Int) {
        // Phân đoạn văn bản
        self.paragraphs = parseParagraphs(chapterContent)
        
        // Tìm phân đoạn chứa vị trí ký tự yêu cầu
        let targetIdx = paragraphs.firstIndex(where: {
            $0.range.location <= startCharIndex && startCharIndex < $0.range.location + $0.range.length
        }) ?? 0
        
        self.currentParagraphIndex = targetIdx
        self.isPlaying = true
        
        speakCurrent()
        
        // Kích hoạt preload chương tiếp theo
        triggerPreloadNextChapter()
    }
    
    // Tải nội dung chương online thông qua ExtensionManager
    private func downloadChapterOnline(url: String) async throws -> String {
        guard let extInfo = extensionInfo else {
            throw NSError(domain: "TTSManager", code: -1, userInfo: [NSLocalizedDescriptionKey: "Extension info is missing"])
        }
        let rawContent = try await ExtensionManager.shared.chap(
            localPath: extInfo.localPath,
            downloadUrl: extInfo.downloadUrl,
            url: url,
            configJson: extInfo.configJson ?? ""
        )
        return rawContent.cleanHTML()
    }
    
    // Dịch nội dung chương chạy ngầm
    private func translateContentInBackground(_ originalContent: String) async -> String {
        guard TranslateUtils.containsChinese(originalContent) else {
            return originalContent
        }
        // Gọi bộ dịch
        return TranslateUtils.translateContent(originalContent, bookId: playingBookId)
    }
    
    // Kích hoạt preload chương kế tiếp
    private func triggerPreloadNextChapter() {
        guard !isPreloading else { return }
        let nextIdx = playingChapterIndex + 1
        guard nextIdx < chaptersQueue.count else { return }
        
        let nextChapter = chaptersQueue[nextIdx]
        
        // Nếu chương tiếp theo đã được tải/cache nội dung dịch sẵn, không cần preload
        if let cached = nextChapter.cachedContent, !cached.isEmpty {
            isPreloading = true
            Task {
                let translated = await self.translateContentInBackground(cached)
                await MainActor.run {
                    self.isPreloading = false
                    if nextIdx < self.chaptersQueue.count && self.chaptersQueue[nextIdx].url == nextChapter.url {
                        self.chaptersQueue[nextIdx].cachedContent = translated
                        self.preloadedNextChapterContent = translated
                        AppLogger.shared.log("🚀 [TTSManager] Đã dịch xong chương tiếp theo (từ cache): \(nextChapter.title)")
                    }
                }
            }
            return
        }
        
        isPreloading = true
        Task {
            do {
                let raw = try await self.downloadChapterOnline(url: nextChapter.url)
                let translated = await self.translateContentInBackground(raw)
                
                await MainActor.run {
                    self.isPreloading = false
                    // Lưu vào cache hàng đợi
                    if nextIdx < self.chaptersQueue.count && self.chaptersQueue[nextIdx].url == nextChapter.url {
                        self.chaptersQueue[nextIdx].cachedContent = translated
                        self.preloadedNextChapterContent = translated
                        AppLogger.shared.log("🚀 [TTSManager] Đã preload xong chương tiếp theo: \(nextChapter.title)")
                    }
                }
            } catch {
                await MainActor.run {
                    self.isPreloading = false
                }
                AppLogger.shared.log("Lỗi preload chương tiếp theo: \(error.localizedDescription)")
            }
        }
    }
    
    public func pause() {
        let pid = currentPlaybackId ?? "NONE"
        AppLogger.shared.log("🔊 [TTSManager] [ID=\(pid)] pause() được gọi.")
        guard isPlaying else { return }
        self.isPlaying = false
        
        if tool == "system" {
            systemSynthesizer?.pauseSpeaking(at: .immediate)
        } else {
            playerNode?.pause()
        }
        updateNowPlayingInfo()
    }
    
    public func resume() {
        let pid = currentPlaybackId ?? "NONE"
        AppLogger.shared.log("🔊 [TTSManager] [ID=\(pid)] resume() được gọi.")
        guard !isPlaying else { return }
        self.configureAudioSession()
        self.isPlaying = true
        
        if tool == "system" {
            if systemSynthesizer?.isPaused == true {
                systemSynthesizer?.continueSpeaking()
            } else {
                speakCurrent()
            }
        } else {
            if let engine = audioEngine, !engine.isRunning {
                try? engine.start()
            }
            playerNode?.play()
        }
        updateNowPlayingInfo()
    }
    
    public func stop() {
        let pid = currentPlaybackId ?? "NONE"
        AppLogger.shared.log("🔊 [TTSManager] [ID=\(pid)] stop() được gọi.")
        self.isPlaying = false
        self.currentParagraphIndex = -1
        self.highlightRange = nil
        
        systemSynthesizer?.stopSpeaking(at: .immediate)
        playerNode?.stop()
        audioEngine?.stop()
        cleanUpTempFile()
        
        updateNowPlayingInfo()
        MPNowPlayingInfoCenter.default().playbackState = .stopped
    }
    
    public func skipForward() {
        let pid = currentPlaybackId ?? "NONE"
        AppLogger.shared.log("🔊 [TTSManager] [ID=\(pid)] skipForward() được gọi.")
        guard isPlaying else { return }
        if currentParagraphIndex + 1 < paragraphs.count {
            stopCurrentPlayback()
            currentParagraphIndex += 1
            speakCurrent()
        } else {
            // Đã hết chương, chuyển chương mới
            stopCurrentPlayback()
            onChapterFinished?()
        }
    }
    
    public func skipBackward() {
        let pid = currentPlaybackId ?? "NONE"
        AppLogger.shared.log("🔊 [TTSManager] [ID=\(pid)] skipBackward() được gọi.")
        guard isPlaying else { return }
        if currentParagraphIndex > 0 {
            stopCurrentPlayback()
            currentParagraphIndex -= 1
            speakCurrent()
        }
    }
    
    private func stopCurrentPlayback() {
        let pid = currentPlaybackId ?? "NONE"
        AppLogger.shared.log("🔊 [TTSManager] [ID=\(pid)] stopCurrentPlayback() được gọi.")
        if tool == "system" {
            systemSynthesizer?.stopSpeaking(at: .immediate)
        } else {
            playerNode?.stop()
        }
        cleanUpTempFile()
    }
    
    private func nextParagraph() {
        let pid = currentPlaybackId ?? "NONE"
        AppLogger.shared.log("🔊 [TTSManager] [ID=\(pid)] nextParagraph() được gọi.")
        guard isPlaying else { return }
        if currentParagraphIndex + 1 < paragraphs.count {
            currentParagraphIndex += 1
            speakCurrent()
        } else {
            // Hết chương, tự động chuyển chương mới nếu có trong Queue
            let nextIdx = playingChapterIndex + 1
            if nextIdx < chaptersQueue.count {
                self.playingChapterIndex = nextIdx
                let nextChapter = chaptersQueue[nextIdx]
                self.playingChapterUrl = nextChapter.url
                self.chapterTitle = nextChapter.title
                
                // Gửi thông báo chuyển chương mới
                NotificationCenter.default.post(
                    name: NSNotification.Name("ttsDidAdvanceToNextChapter"),
                    object: nil,
                    userInfo: ["bookId": playingBookId, "chapterIndex": nextIdx]
                )
                
                if let preloaded = preloadedNextChapterContent, !preloaded.isEmpty {
                    // Sử dụng nội dung tải trước
                    self.chapterContent = preloaded
                    self.preloadedNextChapterContent = nil
                    self.continueStartSpeaking(startCharIndex: 0)
                } else if let cached = nextChapter.cachedContent, !cached.isEmpty {
                    Task {
                        let translated = await self.translateContentInBackground(cached)
                        await MainActor.run {
                            if self.playingChapterIndex == nextIdx {
                                self.chaptersQueue[nextIdx].cachedContent = translated
                                self.chapterContent = translated
                                self.continueStartSpeaking(startCharIndex: 0)
                            }
                        }
                    }
                } else {
                    // Chưa preload kịp, tiến hành tải trực tiếp
                    Task {
                        do {
                            let raw = try await self.downloadChapterOnline(url: nextChapter.url)
                            let translated = await self.translateContentInBackground(raw)
                            
                            await MainActor.run {
                                if self.playingChapterIndex == nextIdx {
                                    self.chaptersQueue[nextIdx].cachedContent = translated
                                    self.chapterContent = translated
                                    self.continueStartSpeaking(startCharIndex: 0)
                                }
                            }
                        } catch {
                            AppLogger.shared.log("Lỗi tải chương mới khi tự chuyển chương: \(error.localizedDescription)")
                            await MainActor.run {
                                self.stop()
                            }
                        }
                    }
                }
            } else {
                // Đã hết sách hoàn toàn
                stop()
                onChapterFinished?()
            }
        }
    }
    
    private func speakCurrent() {
        let pid = currentPlaybackId ?? "NONE"
        AppLogger.shared.log("🔊 [TTSManager] [ID=\(pid)] speakCurrent() được gọi. index=\(currentParagraphIndex)")
        guard isPlaying, currentParagraphIndex >= 0 && currentParagraphIndex < paragraphs.count else { return }
        
        let paragraph = paragraphs[currentParagraphIndex]
        self.highlightRange = paragraph.range
        
        if tool == "system" {
            playSystemTTS(paragraph.text)
        } else {
            playNghiTTS(paragraph.text)
        }
    }
    
    private func playSystemTTS(_ text: String) {
        let utterance = AVSpeechUtterance(string: text)
        
        // Cấu hình giọng đọc hệ thống
        if let voice = AVSpeechSynthesisVoice.speechVoices().first(where: { $0.identifier == selectedVoice || $0.name == selectedVoice }) {
            utterance.voice = voice
        } else {
            utterance.voice = AVSpeechSynthesisVoice(language: "vi-VN")
        }
        
        // Ánh xạ dải speed 0.5x - 5.0x sang AVSpeechUtterance rate (0.0 - 1.0)
        let utteranceRate: Float
        if speed <= 1.0 {
            utteranceRate = Float(0.25 + (speed - 0.5) * 0.5)
        } else {
            utteranceRate = Float(0.5 + (speed - 1.0) * (0.5 / 4.0))
        }
        utterance.rate = utteranceRate
        utterance.pitchMultiplier = Float(pitch)
        
        if systemSynthesizer == nil {
            let synth = AVSpeechSynthesizer()
            synth.delegate = self
            systemSynthesizer = synth
        }
        
        systemSynthesizer?.speak(utterance)
        updateNowPlayingInfo()
    }
    
    private func playNghiTTS(_ text: String) {
        guard let service = nghiTTSService else {
            AppLogger.shared.log("NghiTTS engine not initialized.")
            stop()
            return
        }
        
        Task {
            do {
                // Suy luận với tốc độ mặc định 1.0
                let wavData = try await service.synthesize(text: text, voice: selectedVoice, speed: 1.0)
                
                guard self.isPlaying else {
                    self.cleanUpTempFile()
                    return
                }
                
                try self.playWavData(wavData)
            } catch {
                AppLogger.shared.log("NghiTTS synthesize failed: \(error.localizedDescription)")
                // Tự động dừng
                DispatchQueue.main.async {
                    self.stop()
                }
            }
        }
    }
    
    private func playWavData(_ data: Data) throws {
        let playbackId = String(UUID().uuidString.prefix(4))
        self.currentPlaybackId = playbackId
        let paragraphIndex = self.currentParagraphIndex
        let startTime = CACurrentMediaTime()
        
        AppLogger.shared.log("🔊 [TTSManager] [ID=\(playbackId)] Bắt đầu playWavData. Kích thước dữ liệu: \(data.count) bytes, paragraphIndex: \(paragraphIndex)")
        guard let engine = audioEngine, let player = playerNode, let pitchNode = timePitchNode else { 
            AppLogger.shared.log("🔊 [TTSManager] [ID=\(playbackId)] LỖI: Các thành phần AVAudioEngine chưa được khởi tạo.")
            return 
        }
        
        cleanUpTempFile()
        
        let tempDir = NSTemporaryDirectory()
        let fileURL = URL(fileURLWithPath: tempDir).appendingPathComponent(UUID().uuidString + ".wav")
        AppLogger.shared.log("🔊 [TTSManager] [ID=\(playbackId)] Đang ghi file tạm thời: \(fileURL.lastPathComponent)")
        try data.write(to: fileURL)
        self.currentTempFileUrl = fileURL
        
        AppLogger.shared.log("🔊 [TTSManager] [ID=\(playbackId)] Đang đọc AVAudioFile...")
        let file = try AVAudioFile(forReading: fileURL)
        
        AppLogger.shared.log("""
        🔊 [TTSManager] [ID=\(playbackId)] Trạng thái trước khi schedule:
        - engine.isRunning: \(engine.isRunning)
        - player.isPlaying: \(player.isPlaying)
        - file.length: \(file.length) frames
        - file.sampleRate: \(file.processingFormat.sampleRate) Hz
        """)
        
        AppLogger.shared.log("🔊 [TTSManager] [ID=\(playbackId)] Gọi player.stop()...")
        player.stop()
        AppLogger.shared.log("🔊 [TTSManager] [ID=\(playbackId)] Gọi player.stop() xong.")
        
        AppLogger.shared.log("🔊 [TTSManager] [ID=\(playbackId)] Bắt đầu chạy Audio Engine nếu chưa chạy...")
        if !engine.isRunning {
            try engine.start()
            AppLogger.shared.log("🔊 [TTSManager] [ID=\(playbackId)] Audio Engine đã khởi động thành công.")
        }
        
        pitchNode.rate = Float(speed)
        let cents = 1200.0 * log2(pitch)
        pitchNode.pitch = Float(cents)
        
        AppLogger.shared.log("🔊 [TTSManager] [ID=\(playbackId)] Đang lập lịch phát file âm thanh (scheduleFile)... t=\(startTime)")
        player.scheduleFile(file, at: nil, completionCallbackType: .dataPlayedBack) { [weak self] callbackType in
            let completionTime = CACurrentMediaTime()
            AppLogger.shared.log("🔊 [TTSManager] [ID=\(playbackId)] scheduleFile completion callback: paragraph=\(paragraphIndex) t=\(completionTime) (diff=\(completionTime - startTime)s), callbackType: \(callbackType.rawValue)")
            
            DispatchQueue.main.async {
                guard let self = self, self.isPlaying else { return }
                self.cleanUpTempFile()
                self.nextParagraph()
            }
        }
        
        AppLogger.shared.log("🔊 [TTSManager] [ID=\(playbackId)] Gọi player.play()... t=\(CACurrentMediaTime())")
        player.play()
        updateNowPlayingInfo()
        AppLogger.shared.log("🔊 [TTSManager] [ID=\(playbackId)] Phát WAV hoàn tất thiết lập.")
    }
    
    private func cleanUpTempFile() {
        if let url = currentTempFileUrl {
            try? FileManager.default.removeItem(at: url)
            currentTempFileUrl = nil
        }
    }
    
    // MARK: - Text Segmentation (Phân đoạn văn bản)
    
    private func parseParagraphs(_ content: String) -> [TTSParagraph] {
        var result: [TTSParagraph] = []
        let nsText = content as NSString
        var currentOffset = 0
        
        let lines = content.components(separatedBy: "\n")
        let maxLen = chunkLength > 0 ? chunkLength : 1000 // Mặc định 1000 ký tự
        
        for line in lines {
            let trimmed = line.trimmingCharacters(in: .whitespacesAndNewlines)
            if trimmed.isEmpty {
                currentOffset += line.count + 1
                continue
            }
            
            let range = nsText.range(of: line, options: [], range: NSRange(location: currentOffset, length: nsText.length - currentOffset))
            if range.location == NSNotFound {
                currentOffset += line.count + 1
                continue
            }
            
            if trimmed.count > maxLen {
                // Tách nhỏ dòng quá dài dựa trên dấu câu
                let subParagraphs = splitSentence(trimmed, maxLength: maxLen, baseOffset: range.location)
                result.append(contentsOf: subParagraphs)
            } else {
                // Thêm trực tiếp dòng này thành 1 đoạn đọc độc lập (không gom dòng)
                result.append(TTSParagraph(text: trimmed, range: range))
            }
            
            currentOffset = range.location + range.length
        }
        
        return result
    }
    
    private func splitSentence(_ text: String, maxLength: Int, baseOffset: Int) -> [TTSParagraph] {
        var result: [TTSParagraph] = []
        let nsText = text as NSString
        
        let pattern = "[^.!?。！？]+[.!?。！？]?"
        guard let regex = try? NSRegularExpression(pattern: pattern, options: []) else {
            return [TTSParagraph(text: text, range: NSRange(location: baseOffset, length: text.count))]
        }
        
        let matches = regex.matches(in: text, options: [], range: NSRange(location: 0, length: nsText.length))
        var currentSubText = ""
        var currentSubRange = NSRange(location: baseOffset, length: 0)
        
        for match in matches {
            let matchText = nsText.substring(with: match.range)
            if currentSubText.count + matchText.count <= maxLength {
                if currentSubText.isEmpty {
                    currentSubRange.location = baseOffset + match.range.location
                }
                currentSubText += matchText
                currentSubRange.length += match.range.length
            } else {
                if !currentSubText.isEmpty {
                    result.append(TTSParagraph(text: currentSubText.trimmed, range: currentSubRange))
                }
                currentSubText = matchText
                currentSubRange = NSRange(location: baseOffset + match.range.location, length: match.range.length)
            }
        }
        
        if !currentSubText.isEmpty {
            result.append(TTSParagraph(text: currentSubText.trimmed, range: currentSubRange))
        }
        
        return result
    }
    
    // MARK: - Lock Screen & Remote Control Sync
    
    private func setupRemoteCommandCenter() {
        let commandCenter = MPRemoteCommandCenter.shared()
        
        // Bắt đầu nhận sự kiện điều khiển từ xa
        UIApplication.shared.beginReceivingRemoteControlEvents()
        
        // Play
        commandCenter.playCommand.isEnabled = true
        commandCenter.playCommand.addTarget { [weak self] _ in
            guard let self = self else { return .commandFailed }
            self.resume()
            return .success
        }
        
        // Pause
        commandCenter.pauseCommand.isEnabled = true
        commandCenter.pauseCommand.addTarget { [weak self] _ in
            guard let self = self else { return .commandFailed }
            self.pause()
            return .success
        }
        
        // Next Chapter
        commandCenter.nextTrackCommand.isEnabled = true
        commandCenter.nextTrackCommand.addTarget { [weak self] _ in
            guard let self = self else { return .commandFailed }
            if let onNext = self.onChapterNext {
                onNext()
                return .success
            }
            return .noSuchContent
        }
        
        // Prev Chapter
        commandCenter.previousTrackCommand.isEnabled = true
        commandCenter.previousTrackCommand.addTarget { [weak self] _ in
            guard let self = self else { return .commandFailed }
            if let onPrev = self.onChapterPrev {
                onPrev()
                return .success
            }
            return .noSuchContent
        }
        
        // Skip Forward (Đoạn sau)
        commandCenter.skipForwardCommand.isEnabled = true
        commandCenter.skipForwardCommand.addTarget { [weak self] _ in
            guard let self = self else { return .commandFailed }
            self.skipForward()
            return .success
        }
        
        // Skip Backward (Đoạn trước)
        commandCenter.skipBackwardCommand.isEnabled = true
        commandCenter.skipBackwardCommand.addTarget { [weak self] _ in
            guard let self = self else { return .commandFailed }
            self.skipBackward()
            return .success
        }
    }
    
    private func updateNowPlayingInfo() {
        var info: [String: Any] = [:]
        info[MPMediaItemPropertyTitle] = bookTitle
        
        let chapTitle = chapterTitle.isEmpty ? "Chương hiện tại" : chapterTitle
        let currentPart = paragraphs.isEmpty ? "" : " (Đoạn \(currentParagraphIndex + 1)/\(paragraphs.count))"
        info[MPMediaItemPropertyArtist] = chapTitle + currentPart
        
        info[MPNowPlayingInfoPropertyIsLiveStream] = true
        info[MPNowPlayingInfoPropertyPlaybackRate] = isPlaying ? speed : 0.0
        
        MPNowPlayingInfoCenter.default().nowPlayingInfo = info
        MPNowPlayingInfoCenter.default().playbackState = isPlaying ? .playing : .paused
    }
    
    // MARK: - NghiTTS Downloader Wrapper
    
    public func downloadNghiTTSModel(voice: Voice) async {
        guard let client = nghiTTSClient else { return }
        downloadingVoices[voice.name] = 0.0
        downloadingMessages[voice.name] = "Bắt đầu tải..."
        
        do {
            _ = try await client.prefetchModels(voices: [voice.name]) { [weak self] msg, progress in
                DispatchQueue.main.async {
                    self?.downloadingVoices[voice.name] = progress
                    self?.downloadingMessages[voice.name] = msg
                }
            }
            DispatchQueue.main.async {
                self.downloadingVoices.removeValue(forKey: voice.name)
                self.downloadingMessages.removeValue(forKey: voice.name)
            }
        } catch {
            DispatchQueue.main.async {
                self.downloadingVoices.removeValue(forKey: voice.name)
                self.downloadingMessages.removeValue(forKey: voice.name)
                AppLogger.shared.log("Lỗi tải model NghiTTS \(voice.name): \(error.localizedDescription)")
            }
        }
    }
}

// MARK: - AVSpeechSynthesizerDelegate

extension TTSManager: @preconcurrency AVSpeechSynthesizerDelegate {
    public func speechSynthesizer(_ synthesizer: AVSpeechSynthesizer, didFinish utterance: AVSpeechUtterance) {
        guard isPlaying else { return }
        nextParagraph()
    }
}
