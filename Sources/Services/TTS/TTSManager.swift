import Foundation
import AVFoundation
import MediaPlayer
import Combine

@MainActor
public final class TTSManager: NSObject, ObservableObject {
    public static let shared = TTSManager()
    
    // Cấu hình (lưu qua AppStorage/UserDefaults)
    @Published public var tool: String {
        didSet { UserDefaults.standard.set(tool, forKey: "ttsTool") }
    }
    @Published public var speed: Double {
        didSet { UserDefaults.standard.set(speed, forKey: "ttsRate"); updatePlaybackParams() }
    }
    @Published public var pitch: Double {
        didSet { UserDefaults.standard.set(pitch, forKey: "ttsPitch"); updatePlaybackParams() }
    }
    @Published public var selectedVoice: String {
        didSet { UserDefaults.standard.set(selectedVoice, forKey: "ttsVoice") }
    }
    @Published public var chunkLength: Int {
        didSet { UserDefaults.standard.set(chunkLength, forKey: "ttsChunkLength") }
    }
    
    // Trạng thái playback
    @Published public var isPlaying: Bool = false
    @Published public var currentParagraphIndex: Int = -1
    @Published public var highlightRange: NSRange? = nil
    
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
        self.tool = UserDefaults.standard.string(forKey: "ttsTool") ?? "system"
        self.speed = UserDefaults.standard.object(forKey: "ttsRate") != nil ? UserDefaults.standard.double(forKey: "ttsRate") : 1.0
        self.pitch = UserDefaults.standard.object(forKey: "ttsPitch") != nil ? UserDefaults.standard.double(forKey: "ttsPitch") : 1.0
        self.selectedVoice = UserDefaults.standard.string(forKey: "ttsVoice") ?? ""
        self.chunkLength = UserDefaults.standard.object(forKey: "ttsChunkLength") != nil ? UserDefaults.standard.integer(forKey: "ttsChunkLength") : 1000
        
        super.init()
        
        setupEngines()
        setupAudioEngine()
        setupRemoteCommandCenter()
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
            try session.setCategory(.playback, mode: .spokenAudio, options: [.duckOthers, .interruptSpokenAudioAndMixWithOthers])
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
    
    public func startSpeaking(chapterContent: String, startCharIndex: Int, bookTitle: String, chapterTitle: String) {
        self.configureAudioSession()
        self.chapterContent = chapterContent
        self.bookTitle = bookTitle
        self.chapterTitle = chapterTitle
        
        // Phân đoạn văn bản
        self.paragraphs = parseParagraphs(chapterContent)
        
        // Tìm phân đoạn chứa vị trí ký tự yêu cầu
        let targetIdx = paragraphs.firstIndex(where: {
            $0.range.location <= startCharIndex && startCharIndex < $0.range.location + $0.range.length
        }) ?? 0
        
        self.currentParagraphIndex = targetIdx
        self.isPlaying = true
        
        speakCurrent()
    }
    
    public func pause() {
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
        self.isPlaying = false
        self.currentParagraphIndex = -1
        self.highlightRange = nil
        
        systemSynthesizer?.stopSpeaking(at: .immediate)
        playerNode?.stop()
        audioEngine?.stop()
        cleanUpTempFile()
        
        updateNowPlayingInfo()
    }
    
    public func skipForward() {
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
        guard isPlaying else { return }
        if currentParagraphIndex > 0 {
            stopCurrentPlayback()
            currentParagraphIndex -= 1
            speakCurrent()
        }
    }
    
    private func stopCurrentPlayback() {
        if tool == "system" {
            systemSynthesizer?.stopSpeaking(at: .immediate)
        } else {
            playerNode?.stop()
        }
        cleanUpTempFile()
    }
    
    private func nextParagraph() {
        guard isPlaying else { return }
        if currentParagraphIndex + 1 < paragraphs.count {
            currentParagraphIndex += 1
            speakCurrent()
        } else {
            // Hết chương, chuyển chương mới tự động
            stop()
            onChapterFinished?()
        }
    }
    
    private func speakCurrent() {
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
        guard let engine = audioEngine, let player = playerNode, let pitchNode = timePitchNode else { return }
        
        cleanUpTempFile()
        
        let tempDir = NSTemporaryDirectory()
        let fileURL = URL(fileURLWithPath: tempDir).appendingPathComponent(UUID().uuidString + ".wav")
        try data.write(to: fileURL)
        self.currentTempFileUrl = fileURL
        
        let file = try AVAudioFile(forReading: fileURL)
        
        player.stop()
        engine.disconnectNodeOutput(player)
        engine.disconnectNodeOutput(pitchNode)
        
        engine.connect(player, to: pitchNode, format: file.processingFormat)
        engine.connect(pitchNode, to: engine.mainMixerNode, format: file.processingFormat)
        
        if !engine.isRunning {
            try engine.start()
        }
        
        // Điều chỉnh tốc độ và cao độ tại trình phát
        pitchNode.rate = Float(speed)
        let cents = 1200.0 * log2(pitch)
        pitchNode.pitch = Float(cents)
        
        player.scheduleFile(file, at: nil) { [weak self] in
            DispatchQueue.main.async {
                guard let self = self, self.isPlaying else { return }
                self.cleanUpTempFile()
                self.nextParagraph()
            }
        }
        
        player.play()
        updateNowPlayingInfo()
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
        var tempBuffer = ""
        var tempBufferRange = NSRange(location: 0, length: 0)
        
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
                // Flush buffer cũ trước
                if !tempBuffer.isEmpty {
                    result.append(TTSParagraph(text: tempBuffer.trimmed, range: tempBufferRange))
                    tempBuffer = ""
                }
                
                // Tách nhỏ đoạn quá dài
                let subParagraphs = splitSentence(trimmed, maxLength: maxLen, baseOffset: range.location)
                result.append(contentsOf: subParagraphs)
            } else {
                if tempBuffer.isEmpty {
                    tempBuffer = trimmed
                    tempBufferRange = range
                } else if tempBuffer.count + 1 + trimmed.count <= maxLen {
                    tempBuffer += "\n" + trimmed
                    tempBufferRange.length = (range.location + range.length) - tempBufferRange.location
                } else {
                    result.append(TTSParagraph(text: tempBuffer.trimmed, range: tempBufferRange))
                    tempBuffer = trimmed
                    tempBufferRange = range
                }
            }
            currentOffset = range.location + range.length
        }
        
        if !tempBuffer.isEmpty {
            result.append(TTSParagraph(text: tempBuffer.trimmed, range: tempBufferRange))
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

extension TTSManager: AVSpeechSynthesizerDelegate {
    public func speechSynthesizer(_ synthesizer: AVSpeechSynthesizer, didFinish utterance: AVSpeechUtterance) {
        guard isPlaying else { return }
        nextParagraph()
    }
}
