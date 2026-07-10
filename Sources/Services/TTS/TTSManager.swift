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
            clearPrefetchCache()
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
            clearPrefetchCache()
        }
    }
    @Published public var chunkLength: Int {
        didSet { UserDefaults.standard.set(chunkLength, forKey: "ttsChunkLength") }
    }
    
    // Trạng thái playback
    @Published public var isPlaying: Bool = false
    @Published public var currentParagraphIndex: Int = -1
    @Published public var currentParentParagraphIndex: Int = -1
    @Published public var highlightRange: NSRange? = nil
    @Published public var showFloatingWidget: Bool = false
    
    // Thông tin phát nhạc độc lập toàn cục
    @Published public private(set) var playingBookId: String = ""
    @Published public private(set) var playingChapterUrl: String = ""
    @Published public private(set) var playingChapterIndex: Int = -1
    @Published public private(set) var extensionInfo: TTSExtensionInfo? = nil
    
    private var chaptersQueue: [TTSChapterInfo] = []
    private var preloadedNextChapterContent: String? = nil
    private var isPreloading: Bool = false
    private var currentPlaybackId: String? = nil
    
    // Cache lưu trữ dữ liệu âm thanh đã được tổng hợp trước cho các đoạn văn
    private var preloadedWavs: [Int: AVAudioPCMBuffer] = [:]
    private var prefetchTasks: [Int: Task<Void, Never>] = [:]
    
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
        chapterContent: String,
        startParagraphIndex: Int,
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
        self.chapterContent = chapterContent
        self.showFloatingWidget = true
        
        // Hủy dữ liệu tải trước cũ
        self.preloadedNextChapterContent = nil
        
        // Xóa bộ đệm tải trước của đoạn văn cũ
        self.clearPrefetchCache()
        
        guard currentIndex >= 0 && currentIndex < chapters.count else { return }
        let currentChapter = chapters[currentIndex]
        self.playingChapterUrl = currentChapter.url
        self.chapterTitle = currentChapter.title
        
        self.continueStartSpeaking(startParagraphIndex: startParagraphIndex)
    }
    
    private func continueStartSpeaking(startParagraphIndex: Int) {
        // Phân đoạn văn bản sạch
        self.paragraphs = parseParagraphs(chapterContent)
        
        // Tìm chunk đầu tiên có paragraphIndex khớp với chỉ số đoạn văn yêu cầu
        let targetIdx = paragraphs.firstIndex(where: {
            $0.paragraphIndex == startParagraphIndex
        }) ?? 0
        
        self.currentParagraphIndex = targetIdx
        self.isPlaying = true
        
        speakCurrent()
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
        self.currentParentParagraphIndex = -1
        self.highlightRange = nil
        self.showFloatingWidget = false
        
        clearPrefetchCache()
        
        systemSynthesizer?.stopSpeaking(at: .immediate)
        playerNode?.stop()
        audioEngine?.stop()
        cleanUpTempFile()
        
        updateNowPlayingInfo()
        MPNowPlayingInfoCenter.default().playbackState = .stopped
    }
    
    public func restartCurrentParagraph() {
        guard isPlaying else { return }
        stopCurrentPlayback()
        clearPrefetchCache()
        speakCurrent()
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
            // Hết chương, báo cho ReaderView chuyển chương mới
            let nextIdx = playingChapterIndex + 1
            if nextIdx < chaptersQueue.count {
                stopCurrentPlayback()
                
                // Gửi thông báo chuyển chương mới để ReaderView làm sạch và dịch chương mới
                NotificationCenter.default.post(
                    name: NSNotification.Name("ttsDidAdvanceToNextChapter"),
                    object: nil,
                    userInfo: ["bookId": playingBookId, "chapterIndex": nextIdx]
                )
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
        self.currentParentParagraphIndex = paragraph.paragraphIndex
        
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
    
    private func clearPrefetchCache() {
        for task in prefetchTasks.values {
            task.cancel()
        }
        prefetchTasks.removeAll()
        preloadedWavs.removeAll()
        AppLogger.shared.log("🔊 [TTSManager] Đã làm sạch bộ đệm prefetch và hủy các task đang chạy nền.")
    }
    
    private func updatePrefetchWindow() {
        guard isPlaying, tool != "system" else { return }
        
        let N = currentParagraphIndex
        let targetIndices = [N + 1].filter { $0 >= 0 && $0 < paragraphs.count }
        
        // 1. Hủy các task prefetch không còn nằm trong cửa sổ mục tiêu [N+1]
        var tasksToCancel: [Int] = []
        for idx in prefetchTasks.keys {
            if !targetIndices.contains(idx) {
                tasksToCancel.append(idx)
            }
        }
        for idx in tasksToCancel {
            prefetchTasks[idx]?.cancel()
            prefetchTasks.removeValue(forKey: idx)
        }
        
        // 2. Xóa các cache không còn nằm trong cửa sổ [N, N+1]
        let cacheKeepIndices = [N, N + 1]
        var cacheToClear: [Int] = []
        for idx in preloadedWavs.keys {
            if !cacheKeepIndices.contains(idx) {
                cacheToClear.append(idx)
            }
        }
        for idx in cacheToClear {
            preloadedWavs.removeValue(forKey: idx)
        }
        
        // 3. Bắt đầu prefetch cho các chỉ số thiếu trong [N+1]
        for idx in targetIndices {
            if preloadedWavs[idx] == nil && prefetchTasks[idx] == nil {
                startPrefetchTask(for: idx)
            }
        }
    }
    
    private func startPrefetchTask(for index: Int) {
        guard index >= 0 && index < paragraphs.count else { return }
        let text = paragraphs[index].text
        let voice = selectedVoice
        
        guard let service = nghiTTSService else { return }
        
        let task = Task { [weak self] in
            guard let self = self else { return }
            do {
                AppLogger.shared.log("🔊 [TTSManager] Bắt đầu tải trước cho đoạn \(index)...")
                let wavData = try await service.synthesize(text: text, voice: voice, speed: 1.0)
                
                if !Task.isCancelled && self.selectedVoice == voice && self.tool != "system" {
                    if let buffer = self.makePCMBuffer(fromWavData: wavData) {
                        self.preloadedWavs[index] = buffer
                        AppLogger.shared.log("🔊 [TTSManager] Đã tải trước và lưu cache PCMBuffer thành công cho đoạn \(index).")
                    } else {
                        AppLogger.shared.log("❌ [TTSManager] Lỗi chuyển đổi WAV sang PCMBuffer cho đoạn \(index).")
                    }
                }
                self.prefetchTasks.removeValue(forKey: index)
            } catch {
                self.prefetchTasks.removeValue(forKey: index)
                AppLogger.shared.log("🔊 [TTSManager] Tải trước thất bại cho đoạn \(index): \(error.localizedDescription)")
            }
        }
        prefetchTasks[index] = task
    }
    
    private func playNghiTTS(_ text: String) {
        guard let service = nghiTTSService else {
            AppLogger.shared.log("NghiTTS engine not initialized.")
            stop()
            return
        }
        
        let index = currentParagraphIndex
        
        // Cập nhật cửa sổ prefetch gối đầu ngay khi bắt đầu phát đoạn mới
        updatePrefetchWindow()
        
        // Kiểm tra xem dữ liệu của đoạn index hiện tại đã có sẵn trong cache chưa
        if let cachedBuffer = preloadedWavs[index] {
            AppLogger.shared.log("🔊 [TTSManager] Phát hiện cache PCMBuffer cho đoạn \(index), phát lập tức.")
            self.playAudioBuffer(cachedBuffer)
            return
        }
        
        // Nếu chưa có cache (ví dụ người dùng bấm nhảy đoạn thủ công quá nhanh hoặc lỗi), ta đợi task prefetch đang chạy (nếu có)
        // hoặc tự động tạo task tổng hợp mới
        Task {
            do {
                let buffer: AVAudioPCMBuffer
                if let activeTask = prefetchTasks[index] {
                    // Chờ task đang chạy hoàn thành
                    _ = await activeTask.value
                    if let cached = preloadedWavs[index] {
                        buffer = cached
                    } else {
                        // Nếu chờ task prefetch bị hủy hoặc lỗi, ta chạy tự tổng hợp lại
                        let wavData = try await service.synthesize(text: text, voice: selectedVoice, speed: 1.0)
                        guard let b = self.makePCMBuffer(fromWavData: wavData) else {
                            throw NSError(domain: "TTSManager", code: -10, userInfo: [NSLocalizedDescriptionKey: "WAV conversion failed"])
                        }
                        buffer = b
                    }
                } else {
                    let wavData = try await service.synthesize(text: text, voice: selectedVoice, speed: 1.0)
                    guard let b = self.makePCMBuffer(fromWavData: wavData) else {
                        throw NSError(domain: "TTSManager", code: -10, userInfo: [NSLocalizedDescriptionKey: "WAV conversion failed"])
                    }
                    buffer = b
                }
                
                guard self.isPlaying && self.currentParagraphIndex == index else {
                    return
                }
                
                await MainActor.run {
                    self.playAudioBuffer(buffer)
                }
            } catch {
                await MainActor.run {
                    AppLogger.shared.log("🔊 [TTSManager] Chơi trực tiếp thất bại cho đoạn \(index): \(error.localizedDescription)")
                    self.stop()
                }
            }
        }
    }
    
    private func playAudioBuffer(_ buffer: AVAudioPCMBuffer) {
        let playbackId = String(UUID().uuidString.prefix(4))
        self.currentPlaybackId = playbackId
        let paragraphIndex = self.currentParagraphIndex
        let startTime = CACurrentMediaTime()
        
        AppLogger.shared.log("🔊 [TTSManager] [ID=\(playbackId)] Bắt đầu playAudioBuffer, paragraphIndex: \(paragraphIndex)")
        guard let engine = audioEngine, let player = playerNode, let pitchNode = timePitchNode else { 
            AppLogger.shared.log("🔊 [TTSManager] [ID=\(playbackId)] LỖI: Các thành phần AVAudioEngine chưa được khởi tạo.")
            return 
        }
        
        cleanUpTempFile()
        
        AppLogger.shared.log("🔊 [TTSManager] [ID=\(playbackId)] Gọi player.stop()...")
        player.stop()
        AppLogger.shared.log("🔊 [TTSManager] [ID=\(playbackId)] Gọi player.stop() xong.")
        
        AppLogger.shared.log("🔊 [TTSManager] [ID=\(playbackId)] Bắt đầu chạy Audio Engine nếu chưa chạy...")
        if !engine.isRunning {
            do {
                try engine.start()
                AppLogger.shared.log("🔊 [TTSManager] [ID=\(playbackId)] Audio Engine đã khởi động thành công.")
            } catch {
                AppLogger.shared.log("🔊 [TTSManager] [ID=\(playbackId)] LỖI: Không thể khởi động Audio Engine: \(error.localizedDescription)")
                return
            }
        }
        
        pitchNode.rate = Float(speed)
        let cents = 1200.0 * log2(pitch)
        pitchNode.pitch = Float(cents)
        
        AppLogger.shared.log("🔊 [TTSManager] [ID=\(playbackId)] Đang lập lịch phát buffer âm thanh (scheduleBuffer)... t=\(startTime)")
        player.scheduleBuffer(buffer, at: nil, options: [], completionHandler: { [weak self] in
            let completionTime = CACurrentMediaTime()
            AppLogger.shared.log("🔊 [TTSManager] [ID=\(playbackId)] scheduleBuffer completion callback: paragraph=\(paragraphIndex) t=\(completionTime)")
            
            DispatchQueue.main.async {
                guard let self = self, self.isPlaying else { return }
                guard self.currentPlaybackId == playbackId else {
                    AppLogger.shared.log("🔊 [TTSManager] [ID=\(playbackId)] Bỏ qua callback kết thúc vì currentPlaybackId (\(self.currentPlaybackId ?? "nil")) đã thay đổi.")
                    return
                }
                self.cleanUpTempFile()
                self.nextParagraph()
            }
        })
        
        AppLogger.shared.log("🔊 [TTSManager] [ID=\(playbackId)] Gọi player.play()... t=\(CACurrentMediaTime())")
        player.play()
        updateNowPlayingInfo()
        AppLogger.shared.log("🔊 [TTSManager] [ID=\(playbackId)] Phát buffer hoàn tất thiết lập.")
    }
    
    private func makePCMBuffer(fromWavData wavData: Data) -> AVAudioPCMBuffer? {
        guard wavData.count >= 44 else { return nil }
        
        let channels = Int(wavData[22]) | (Int(wavData[23]) << 8)
        let sampleRate = Double(Int(wavData[24]) | (Int(wavData[25]) << 8) | (Int(wavData[26]) << 16) | (Int(wavData[27]) << 24))
        let payloadSize = Int(wavData[40]) | (Int(wavData[41]) << 8) | (Int(wavData[42]) << 16) | (Int(wavData[43]) << 24)
        
        guard wavData.count >= 44 + payloadSize else { return nil }
        
        guard let format = AVAudioFormat(commonFormat: .pcmFormatFloat32, sampleRate: sampleRate, channels: AVAudioChannelCount(channels), interleaved: false) else {
            return nil
        }
        
        let sampleCount = payloadSize / 2
        let frameCount = AVAudioFrameCount(sampleCount / channels)
        
        guard let buffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: frameCount) else {
            return nil
        }
        
        buffer.frameLength = frameCount
        
        if let floatChannelData = buffer.floatChannelData {
            wavData.withUnsafeBytes { rawBuffer in
                if let baseAddress = rawBuffer.baseAddress {
                    let srcPointer = baseAddress.advanced(by: 44).assumingMemoryBound(to: Int16.self)
                    
                    for channel in 0..<channels {
                        let destPointer = floatChannelData[channel]
                        for frame in 0..<Int(frameCount) {
                            let sampleIndex = frame * channels + channel
                            let intVal = srcPointer[sampleIndex]
                            destPointer[frame] = Float(intVal) / (intVal < 0 ? 32768.0 : 32767.0)
                        }
                    }
                }
            }
        }
        
        return buffer
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
        let lines = content.components(separatedBy: "\n")
        var currentOffset = 0
        
        for i in 0..<lines.count {
            let line = lines[i]
            let trimmed = line.trimmingCharacters(in: .whitespacesAndNewlines)
            let lineRange = NSRange(location: currentOffset, length: line.count)
            
            let paragraphRange: NSRange
            if let trimmedRange = content.range(of: trimmed, range: Range(lineRange, in: content)!) {
                paragraphRange = NSRange(trimmedRange, in: content)
            } else {
                paragraphRange = NSRange(location: currentOffset, length: trimmed.count)
            }
            
            let maxLen = max(chunkLength, 1000)
            if trimmed.count > maxLen {
                let subParagraphs = splitSentence(trimmed, maxLength: maxLen, baseOffset: paragraphRange.location, paragraphIndex: i)
                result.append(contentsOf: subParagraphs)
            } else {
                result.append(
                    TTSParagraph(
                        text: trimmed,
                        range: paragraphRange,
                        paragraphIndex: i
                    )
                )
            }
            currentOffset += line.count + 1
        }
        return result
    }
    
    private func splitSentence(_ text: String, maxLength: Int, baseOffset: Int, paragraphIndex: Int) -> [TTSParagraph] {
        var result: [TTSParagraph] = []
        
        var tempText = text
        tempText = tempText.replacingOccurrences(of: "...", with: ",,,")
        tempText = tempText.replacingOccurrences(of: "..", with: ",,")
        
        let nsText = text as NSString
        let nsTempText = tempText as NSString
        
        let pattern = "[^.!?。！？]+[.!?。！？]?"
        guard let regex = try? NSRegularExpression(pattern: pattern, options: []) else {
            return [TTSParagraph(text: text, range: NSRange(location: baseOffset, length: text.count), paragraphIndex: paragraphIndex)]
        }
        
        let matches = regex.matches(in: tempText, options: [], range: NSRange(location: 0, length: nsTempText.length))
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
                    result.append(TTSParagraph(text: currentSubText.trimmed, range: currentSubRange, paragraphIndex: paragraphIndex))
                }
                currentSubText = matchText
                currentSubRange = NSRange(location: baseOffset + match.range.location, length: match.range.length)
            }
        }
        
        if !currentSubText.isEmpty {
            result.append(TTSParagraph(text: currentSubText.trimmed, range: currentSubRange, paragraphIndex: paragraphIndex))
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
        
        // Toggle Play/Pause (Tai nghe / AirPods / Thiết bị Bluetooth)
        commandCenter.togglePlayPauseCommand.isEnabled = true
        commandCenter.togglePlayPauseCommand.addTarget { [weak self] _ in
            guard let self = self else { return .commandFailed }
            if self.isPlaying {
                self.pause()
            } else {
                self.resume()
            }
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
        commandCenter.skipForwardCommand.preferredIntervals = [15]
        commandCenter.skipForwardCommand.isEnabled = true
        commandCenter.skipForwardCommand.addTarget { [weak self] _ in
            guard let self = self else { return .commandFailed }
            self.skipForward()
            return .success
        }
        
        // Skip Backward (Đoạn trước)
        commandCenter.skipBackwardCommand.preferredIntervals = [15]
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
