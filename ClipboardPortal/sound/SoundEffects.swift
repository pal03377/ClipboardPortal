import AVFoundation

enum SoundEffects {
    case send
    case receive
    
    var audioFileName: String {
        switch self {
        case .send: "send.mp3"
        case .receive: "receive.mp3"
        }
    }
    
    var audioFilePath: URL? {
        URL(fileURLWithPath: Bundle.main.path(forResource: audioFileName, ofType: nil)!)
    }
}

var soundEffectPlayers: Dictionary<SoundEffects, AVAudioPlayer> = [:]
@MainActor
func playSoundEffect(_ effect: SoundEffects) async {
    guard (effect == .receive && SettingsStore.shared.settingsData.receiveSoundEnabled) ||
          (effect == .send    && SettingsStore.shared.settingsData.sendSoundEnabled) else { return } // Abort if sound is not enabled
    print("Sound effect \(effect)")
    if soundEffectPlayers[effect] == nil { // Audio player needs to be initialized?
        guard let audioFilePath = effect.audioFilePath else {
            print("Invalid audio path for sound effect \(effect)")
            return
        }
        guard let player = try? AVAudioPlayer(contentsOf: audioFilePath) else {
            print("Sound effect audio player init failed")
            return
        }
        soundEffectPlayers[effect] = player // Init audio player
    }
    soundEffectPlayers[effect]!.play()
}
