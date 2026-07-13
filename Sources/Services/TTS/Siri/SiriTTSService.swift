import Foundation
import AVFoundation

public final class SiriTTSService: NSObject, @preconcurrency AVSpeechSynthesizerDelegate {
    private var systemSynthesizer: AVSpeechSynthesizer?
    private var currentUtterance: AVSpeechUtterance?
    private var onFinishCallback: (() -> Void)?
    
    public override init() {
        super.init()
    }
    
    public func speak(text: String, voiceName: String, speed: Double, pitch: Double, onFinish: @escaping () -> Void) {
        stop()
        self.onFinishCallback = onFinish
        
        let utterance = AVSpeechUtterance(string: text)
        
        // Ánh xạ dải speed 0.5x - 5.0x sang AVSpeechUtterance rate (0.0 - 1.0)
        let utteranceRate: Float
        if speed <= 1.0 {
            utteranceRate = Float(0.25 + (speed - 0.5) * 0.5)
        } else {
            utteranceRate = Float(0.5 + (speed - 1.0) * (0.5 / 4.0))
        }
        utterance.rate = utteranceRate
        utterance.pitchMultiplier = Float(pitch)
        
        if !voiceName.isEmpty, let voice = AVSpeechSynthesisVoice.speechVoices().first(where: { $0.identifier == voiceName || $0.name == voiceName }) {
            utterance.voice = voice
        } else if let defaultVoice = AVSpeechSynthesisVoice(language: "vi-VN") {
            utterance.voice = defaultVoice
        }
        
        let synth = AVSpeechSynthesizer()
        synth.delegate = self
        self.systemSynthesizer = synth
        self.currentUtterance = utterance
        
        synth.speak(utterance)
    }
    
    public func pause() {
        systemSynthesizer?.pauseSpeaking(at: .immediate)
    }
    
    public func resume() {
        if systemSynthesizer?.isPaused == true {
            systemSynthesizer?.continueSpeaking()
        }
    }
    
    public func stop() {
        systemSynthesizer?.stopSpeaking(at: .immediate)
        systemSynthesizer = nil
        currentUtterance = nil
        onFinishCallback = nil
    }
    
    public var isPaused: Bool {
        return systemSynthesizer?.isPaused == true
    }
    
    public var isSpeaking: Bool {
        return systemSynthesizer?.isSpeaking == true
    }
    
    // MARK: - AVSpeechSynthesizerDelegate
    
    public func speechSynthesizer(_ synthesizer: AVSpeechSynthesizer, didFinish utterance: AVSpeechUtterance) {
        if utterance == currentUtterance {
            let callback = onFinishCallback
            onFinishCallback = nil
            currentUtterance = nil
            callback?()
        }
    }
}
