import SwiftUI
import AVFoundation

struct RecordingDetailView: View {
    let session: RecordingSession
    @State private var isPlaying = false
    @State private var audioPlayer: AVAudioPlayer?
    @State private var currentTime: TimeInterval = 0
    @State private var timer: Timer?
    
    var body: some View {
        VStack(spacing: 24) {
            // Header
            VStack(spacing: 8) {
                Text(session.title)
                    .font(.title2)
                    .fontWeight(.semibold)
                
                Text(session.startTime, style: .date)
                    .font(.subheadline)
                    .foregroundColor(.secondary)
            }
            
            // Audio Info
            VStack(spacing: 16) {
                HStack {
                    VStack(alignment: .leading) {
                        Text("Duration")
                            .font(.caption)
                            .foregroundColor(.secondary)
                        Text(session.formattedDuration)
                            .font(.title3)
                            .fontWeight(.medium)
                    }
                    
                    Spacer()
                    
                    VStack(alignment: .trailing) {
                        Text("File Size")
                            .font(.caption)
                            .foregroundColor(.secondary)
                        Text(session.formattedFileSize)
                            .font(.title3)
                            .fontWeight(.medium)
                    }
                }
                
                HStack {
                    VStack(alignment: .leading) {
                        Text("Quality")
                            .font(.caption)
                            .foregroundColor(.secondary)
                        Text(session.configuration.quality.rawValue)
                            .font(.title3)
                            .fontWeight(.medium)
                    }
                    
                    Spacer()
                    
                    VStack(alignment: .trailing) {
                        Text("Sample Rate")
                            .font(.caption)
                            .foregroundColor(.secondary)
                        Text("\(Int(session.configuration.sampleRate)) Hz")
                            .font(.title3)
                            .fontWeight(.medium)
                    }
                }
            }
            .padding()
            .background(Color.backgroundSecondary)
            .cornerRadius(12)
            
            // Playback Controls
            if let _ = session.fileURL {
                VStack(spacing: 16) {
                    // Progress bar would go here
                    
                    HStack(spacing: 30) {
                        Button(action: togglePlayback) {
                            Image(systemName: isPlaying ? "pause.fill" : "play.fill")
                                .font(.title2)
                                .foregroundColor(.white)
                        }
                        .frame(width: 60, height: 60)
                        .background(Circle().fill(Color.blue))
                        
                        Button(action: shareRecording) {
                            Image(systemName: "square.and.arrow.up")
                                .font(.title2)
                        }
                        .buttonStyle(ControlButtonStyle(isEnabled: true))
                    }
                }
            }
            
            Spacer()
        }
        .padding()
        .navigationBarTitleDisplayMode(.inline)
        .onDisappear {
            stopPlayback()
        }
    }
    
    private func togglePlayback() {
        if isPlaying {
            pausePlayback()
        } else {
            startPlayback()
        }
    }
    
    private func startPlayback() {
        guard let fileURL = session.fileURL else { return }
        
        do {
            audioPlayer = try AVAudioPlayer(contentsOf: fileURL)
            audioPlayer?.play()
            isPlaying = true
            
            // Start timer for progress tracking
            timer = Timer.scheduledTimer(withTimeInterval: 0.1, repeats: true) { _ in
                if let player = audioPlayer {
                    currentTime = player.currentTime
                    if !player.isPlaying {
                        stopPlayback()
                    }
                }
            }
        } catch {
            Logger.shared.error("Failed to start playback: \(error)")
        }
    }
    
    private func pausePlayback() {
        audioPlayer?.pause()
        isPlaying = false
        timer?.invalidate()
    }
    
    private func stopPlayback() {
        audioPlayer?.stop()
        audioPlayer = nil
        isPlaying = false
        timer?.invalidate()
        currentTime = 0
    }
    
    private func shareRecording() {
        guard let fileURL = session.fileURL else { return }
        
        let activityVC = UIActivityViewController(
            activityItems: [fileURL],
            applicationActivities: nil
        )
        
        if let windowScene = UIApplication.shared.connectedScenes.first as? UIWindowScene,
           let window = windowScene.windows.first,
           let rootVC = window.rootViewController {
            rootVC.present(activityVC, animated: true)
        }
    }
}
