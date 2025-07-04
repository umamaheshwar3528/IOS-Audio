import SwiftUI
import AVFoundation

struct SettingsView: View {
    @ObservedObject private var settingsService = SettingsService.shared
    @Environment(\.dismiss) private var dismiss
    @State private var localSettings: RecordingSettings
    @State private var showingResetAlert = false
    
    init() {
        _localSettings = State(initialValue: SettingsService.shared.settings)
    }
    
    var body: some View {
        NavigationView {
            Form {
                Section("Audio Quality") {
                    Picker("Quality", selection: $localSettings.audioQuality) {
                        ForEach(AudioConfiguration.Quality.allCases, id: \.self) { quality in
                            VStack(alignment: .leading, spacing: 2) {
                                Text(quality.rawValue)
                                Text("\(Int(quality.sampleRate)) Hz, \(quality.bitDepth)-bit")
                                    .font(.caption)
                                    .foregroundColor(.secondary)
                            }
                            .tag(quality)
                        }
                    }
                    .pickerStyle(.menu)
                    
                    Text("Higher quality uses more storage space")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
                
                Section("Recording Options") {
                    Toggle("Background Recording", isOn: $localSettings.backgroundRecordingEnabled)
                    
                    Toggle("Show Audio Levels", isOn: $localSettings.showAudioLevels)
                    
                    Toggle("Auto-save Recordings", isOn: $localSettings.autoSaveEnabled)
                }
                
                Section("Battery & Performance") {
                    Toggle("Auto-stop on Low Battery", isOn: $localSettings.autoStopOnLowBattery)
                    
                    VStack(alignment: .leading, spacing: 8) {
                        Text("Maximum Recording Duration")
                        
                        Picker("Duration", selection: $localSettings.maxRecordingDuration) {
                            Text("30 minutes").tag(TimeInterval(1800))
                            Text("1 hour").tag(TimeInterval(3600))
                            Text("2 hours").tag(TimeInterval(7200))
                            Text("4 hours").tag(TimeInterval(14400))
                            Text("Unlimited").tag(TimeInterval.infinity)
                        }
                        .pickerStyle(.menu)
                    }
                }
                
                Section("Storage Info") {
                    let storageInfo = getStorageInfo()
                    
                    HStack {
                        Text("Available Storage")
                        Spacer()
                        Text(storageInfo.available)
                            .foregroundColor(.secondary)
                    }
                    
                    HStack {
                        Text("Estimated Recording Time")
                        Spacer()
                        Text(storageInfo.estimatedTime)
                            .foregroundColor(.secondary)
                    }
                }
                
                Section {
                    Button("Reset to Defaults", role: .destructive) {
                        showingResetAlert = true
                    }
                } footer: {
                    Text("App version: \(Bundle.main.appVersion)")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
            }
            .navigationTitle("Settings")
            .navigationBarTitleDisplayMode(.large)
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    Button("Cancel") {
                        dismiss()
                    }
                }
                
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button("Save") {
                        saveSettings()
                    }
                    .fontWeight(.semibold)
                }
            }
            .alert("Reset Settings", isPresented: $showingResetAlert) {
                Button("Cancel", role: .cancel) {}
                Button("Reset", role: .destructive) {
                    localSettings = RecordingSettings.default
                }
            } message: {
                Text("This will reset all settings to their default values.")
            }
        }
    }
    
    private func saveSettings() {
        settingsService.updateSettings(localSettings)
        dismiss()
    }
    
    private func getStorageInfo() -> (available: String, estimatedTime: String) {
        let fileManager = FileManagerService.shared
        let availableBytes = fileManager.availableSpace
        let availableString = ByteCountFormatter.string(fromByteCount: availableBytes, countStyle: .file)
        
        let config = AudioConfiguration(
            sampleRate: localSettings.audioQuality.sampleRate,
            bitDepth: localSettings.audioQuality.bitDepth,
            channels: 1,
            format: kAudioFormatLinearPCM,
            quality: localSettings.audioQuality
        )
        
        let estimatedSeconds = AudioQualityService.shared.estimatedRecordingTime(
            for: config,
            availableBytes: availableBytes
        )
        
        let estimatedTime = estimatedSeconds.formattedDuration
        
        return (availableString, estimatedTime)
    }
}

// Extension for Bundle version
extension Bundle {
    var appVersion: String {
        return infoDictionary?["CFBundleShortVersionString"] as? String ?? "1.0"
    }
}
