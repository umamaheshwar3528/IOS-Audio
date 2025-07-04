import SwiftUI
import AVFoundation

struct RecordingControlsView: View {
    @ObservedObject private var recordingManager = AudioRecordingManager.shared
    @State private var showingError = false
    @State private var showingSettings = false
    @State private var currentError: RecordingError?
    
    var body: some View {
        HStack(spacing: 30) {
            // Stop Button
            Button(action: stopRecording) {
                Image(systemName: "stop.fill")
                    .font(.title2)
            }
            .buttonStyle(ControlButtonStyle(isEnabled: canStop))
            .disabled(!canStop)
            
            // Record/Pause Button
            Button(action: toggleRecording) {
                Image(systemName: recordButtonIcon)
                    .font(.title)
                    .foregroundColor(.white)
            }
            .buttonStyle(RecordButtonStyle(
                isRecording: recordingManager.currentState.isRecording,
                isEnabled: canRecord
            ))
            .disabled(!canRecord)
            
            // Settings Button
            Button(action: { showingSettings = true }) {
                Image(systemName: "gearshape.fill")
                    .font(.title2)
            }
            .buttonStyle(ControlButtonStyle(isEnabled: true))
        }
        .onChange(of: recordingManager.currentState) { newState in
            if case .error(let error) = newState {
                currentError = error
                showingError = true
            }
        }
        .alert("Recording Error", isPresented: $showingError) {
            Button("OK") {
                recordingManager.currentState = .idle
            }
            if let error = currentError, shouldShowRetry(for: error) {
                Button("Retry") {
                    retryRecording()
                }
            }
        } message: {
            if let error = currentError {
                Text(error.localizedDescription)
            }
        }
        .sheet(isPresented: $showingSettings) {
            SettingsView()
        }
    }
    
    private var recordButtonIcon: String {
        switch recordingManager.currentState {
        case .recording:
            return "pause.fill"
        case .paused:
            return "play.fill"
        default:
            return "mic.fill"
        }
    }
    
    private var canRecord: Bool {
        switch recordingManager.currentState {
        case .idle, .stopped, .paused:
            return true
        case .recording:
            return true // Can pause
        case .error:
            return false
        }
    }
    
    private var canStop: Bool {
        switch recordingManager.currentState {
        case .recording, .paused:
            return true
        default:
            return false
        }
    }
    
    private func toggleRecording() {
        Task {
            switch recordingManager.currentState {
            case .idle, .stopped:
                do {
                    let settings = SettingsService.shared.settings
                    let config = AudioConfiguration(
                        sampleRate: settings.audioQuality.sampleRate,
                        bitDepth: settings.audioQuality.bitDepth,
                        channels: 1,
                        format: kAudioFormatLinearPCM,
                        quality: settings.audioQuality
                    )
                    try await recordingManager.startRecording(with: config)
                } catch {
                    // Error handling is done in the manager
                }
            case .recording:
                recordingManager.pauseRecording()
            case .paused:
                recordingManager.resumeRecording()
            case .error:
                break
            }
        }
    }
    
    private func stopRecording() {
        _ = recordingManager.stopRecording()
    }
    
    private func shouldShowRetry(for error: RecordingError) -> Bool {
        switch error {
        case .audioSessionConfigurationFailed, .audioEngineStartFailed:
            return true
        default:
            return false
        }
    }
    
    private func retryRecording() {
        Task {
            do {
                let settings = SettingsService.shared.settings
                let config = AudioConfiguration(
                    sampleRate: settings.audioQuality.sampleRate,
                    bitDepth: settings.audioQuality.bitDepth,
                    channels: 1,
                    format: kAudioFormatLinearPCM,
                    quality: settings.audioQuality
                )
                try await recordingManager.startRecording(with: config)
            } catch {
                // Error will be handled by the state change
            }
        }
    }
}
