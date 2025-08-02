import SwiftUI
import AVFoundation

struct SettingsView: View {
    @ObservedObject private var settingsService = SettingsService.shared
    @ObservedObject private var authManager = AuthenticationManager.shared
    @ObservedObject private var networkMonitor = NetworkMonitorService.shared
    @ObservedObject private var openAIService = OpenAITranscriptionService.shared
    @ObservedObject private var appleService = AppleTranscriptionService.shared
    
    @Environment(\.dismiss) private var dismiss
    @State private var localSettings: RecordingSettings
    @State private var showingResetAlert = false
    @State private var showingAPIKeySetup = false
    @State private var showingError = false
    @State private var errorMessage = ""
    @State private var isLoading = false
    
    init() {
        _localSettings = State(initialValue: SettingsService.shared.settings)
    }
    
    var body: some View {
        NavigationView {
            Form {
                // Quick Settings
                quickSettingsSection
                
                // Audio Settings
                audioSection
                
                // Transcription Settings
                transcriptionSection
                
                // Services Status
                servicesSection
                
                // Storage & Performance
                storageSection
                
                // About & Reset
                aboutSection
            }
            .navigationTitle("Settings")
            .navigationBarTitleDisplayMode(.large)
            .background(Color(.systemGroupedBackground))
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
                    .disabled(isLoading)
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
            .alert("Error", isPresented: $showingError) {
                Button("OK") {}
            } message: {
                Text(errorMessage)
            }
            .sheet(isPresented: $showingAPIKeySetup) {
                APIKeyConfigurationView()
            }
        }
    }
    
    // MARK: - Quick Settings
    
    private var quickSettingsSection: some View {
        Section {
            QuickToggle(
                title: "Auto-transcribe Recordings",
                subtitle: "Start transcription automatically",
                isOn: $localSettings.enableAutoTranscription,
                icon: "waveform.badge.magnifyingglass",
                color: .blue
            )
            
            QuickToggle(
                title: "Background Recording",
                subtitle: "Continue recording in background",
                isOn: $localSettings.backgroundRecordingEnabled,
                icon: "app.badge",
                color: .green
            )
            
            QuickToggle(
                title: "Show Audio Levels",
                subtitle: "Display live audio visualization",
                isOn: $localSettings.showAudioLevels,
                icon: "waveform",
                color: .orange
            )
        } header: {
            Text("Quick Settings")
        }
    }
    
    // MARK: - Audio Section
    
    private var audioSection: some View {
        Section {
            // Quality picker
            VStack(alignment: .leading, spacing: 8) {
                HStack {
                    Image(systemName: "dial.high")
                        .foregroundColor(.blue)
                        .frame(width: 24)
                    
                    Text("Recording Quality")
                        .font(.subheadline)
                    
                    Spacer()
                }
                
                Picker("Quality", selection: $localSettings.audioQuality) {
                    ForEach(AudioConfiguration.Quality.allCases, id: \.self) { quality in
                        VStack(alignment: .leading, spacing: 2) {
                            Text(quality.rawValue.capitalized)
                                .font(.subheadline)
                            Text(quality.description)
                                .font(.caption)
                                .foregroundColor(.secondary)
                        }
                        .tag(quality)
                    }
                }
                .pickerStyle(.menu)
            }
            
            // Max duration
            VStack(alignment: .leading, spacing: 8) {
                HStack {
                    Image(systemName: "timer")
                        .foregroundColor(.orange)
                        .frame(width: 24)
                    
                    Text("Max Recording Duration")
                        .font(.subheadline)
                    
                    Spacer()
                }
                
                Picker("Duration", selection: $localSettings.maxRecordingDuration) {
                    Text("30 minutes").tag(TimeInterval(1800))
                    Text("1 hour").tag(TimeInterval(3600))
                    Text("2 hours").tag(TimeInterval(7200))
                    Text("4 hours").tag(TimeInterval(14400))
                    Text("Unlimited").tag(TimeInterval.infinity)
                }
                .pickerStyle(.menu)
            }
            
        } header: {
            Text("Audio Settings")
        } footer: {
            Text("Higher quality settings use more storage space and battery.")
        }
    }
    
    // MARK: - Transcription Section
    
    private var transcriptionSection: some View {
        Section {
            if localSettings.enableAutoTranscription {
                // Service selection
                serviceSelectionView
                
                // Service options
                serviceOptionsView
            } else {
                HStack {
                    Image(systemName: "info.circle")
                        .foregroundColor(.blue)
                    
                    Text("Enable auto-transcription to configure transcription services")
                        .font(.subheadline)
                        .foregroundColor(.secondary)
                }
            }
            
        } header: {
            Text("Transcription")
        } footer: {
            if localSettings.enableAutoTranscription {
                Text("Transcription converts your audio recordings to searchable text.")
            }
        }
    }
    
    private var serviceSelectionView: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Image(systemName: "brain")
                    .foregroundColor(.purple)
                    .frame(width: 24)
                
                Text("Preferred Service")
                    .font(.subheadline)
                
                Spacer()
            }
            
            Picker("Service", selection: $localSettings.preferredTranscriptionService) {
                Text("Auto-select").tag(nil as TranscriptionService?)
                
                ForEach(TranscriptionService.allCases.filter { $0 != .none }, id: \.self) { service in
                    HStack {
                        Text(service.displayName)
                        Spacer()
                        serviceStatusDot(for: service)
                    }
                    .tag(service as TranscriptionService?)
                }
            }
            .pickerStyle(.menu)
        }
    }
    
    private var serviceOptionsView: some View {
        Group {
            QuickToggle(
                title: "Allow Service Fallback",
                subtitle: "Try other services if preferred fails",
                isOn: $localSettings.allowServiceFallback,
                icon: "arrow.triangle.swap",
                color: .cyan
            )
            
            if localSettings.preferredTranscriptionService?.requiresNetwork == true {
                QuickToggle(
                    title: "Allow Cellular Data",
                    subtitle: "Use cellular for transcription",
                    isOn: $localSettings.allowCellularTranscription,
                    icon: "antenna.radiowaves.left.and.right",
                    color: .green
                )
            }
        }
    }
    
    // MARK: - Services Section
    
    private var servicesSection: some View {
        Section {
            // OpenAI status
            ServiceStatusRow(
                service: .openai,
                isConfigured: authManager.hasValidOpenAIKey,
                isAvailable: authManager.hasValidOpenAIKey && networkMonitor.isConnected,
                onConfigure: { showingAPIKeySetup = true }
            )
            
            // Apple Speech status
            ServiceStatusRow(
                service: .apple,
                isConfigured: appleService.authorizationStatus == .authorized,
                isAvailable: appleService.isAvailable,
                onConfigure: {
                    Task {
                        await appleService.requestSpeechAuthorization()
                    }
                }
            )
            
        } header: {
            Text("Service Status")
        } footer: {
            Text("OpenAI Whisper provides the highest accuracy. Apple Speech works offline but supports fewer languages.")
        }
    }
    
    // MARK: - Storage Section
    
    private var storageSection: some View {
        Section {
            StorageInfoRow()
            
            Button("Clear Transcription Cache") {
                clearTranscriptionCache()
            }
            .foregroundColor(.blue)
            
        } header: {
            Text("Storage & Performance")
        }
    }
    
    // MARK: - About Section
    
    private var aboutSection: some View {
        Section {
            HStack {
                Text("Version")
                Spacer()
                Text(Bundle.main.appVersion)
                    .foregroundColor(.secondary)
            }
            
            HStack {
                Text("Build")
                Spacer()
                Text(Bundle.main.buildVersion)
                    .foregroundColor(.secondary)
            }
            
            Button("Reset to Defaults", role: .destructive) {
                showingResetAlert = true
            }
            
        } header: {
            Text("About")
        }
    }
    
    // MARK: - Helper Methods
    
    private func serviceStatusDot(for service: TranscriptionService) -> some View {
        Circle()
            .fill(isServiceAvailable(service) ? Color.green : Color.red)
            .frame(width: 8, height: 8)
    }
    
    private func isServiceAvailable(_ service: TranscriptionService) -> Bool {
        switch service {
        case .openai:
            return authManager.hasValidOpenAIKey && networkMonitor.isConnected
        case .apple:
            return appleService.isAvailable
        case .localWhisper:
            return false
        case .none:
            return false
        }
    }
    
    // MARK: - Actions
    
    private func saveSettings() {
        isLoading = true
        
        do {
            settingsService.updateSettings(localSettings)
            
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
                self.isLoading = false
                self.dismiss()
            }
        } catch {
            isLoading = false
            showError("Failed to save settings: \(error.localizedDescription)")
        }
    }
    
    private func clearTranscriptionCache() {
        // Implementation for clearing cache
        // This would clear segment files and temporary data
    }
    
    private func showError(_ message: String) {
        errorMessage = message
        showingError = true
    }
}

// MARK: - Supporting Views

struct QuickToggle: View {
    let title: String
    let subtitle: String
    @Binding var isOn: Bool
    let icon: String
    let color: Color
    
    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: icon)
                .foregroundColor(color)
                .frame(width: 24, height: 24)
            
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.subheadline)
                
                Text(subtitle)
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
            
            Spacer()
            
            Toggle("", isOn: $isOn)
                .labelsHidden()
        }
        .padding(.vertical, 4)
    }
}

struct ServiceStatusRow: View {
    let service: TranscriptionService
    let isConfigured: Bool
    let isAvailable: Bool
    let onConfigure: () -> Void
    
    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: serviceIcon)
                .foregroundColor(serviceColor)
                .frame(width: 24, height: 24)
            
            VStack(alignment: .leading, spacing: 2) {
                Text(service.displayName)
                    .font(.subheadline)
                
                Text(statusText)
                    .font(.caption)
                    .foregroundColor(statusColor)
            }
            
            Spacer()
            
            if !isConfigured {
                Button("Setup", action: onConfigure)
                    .buttonStyle(.bordered)
                    .controlSize(.small)
            } else {
                StatusIndicator(isAvailable: isAvailable)
            }
        }
        .padding(.vertical, 4)
    }
    
    private var serviceIcon: String {
        switch service {
        case .openai: return "brain"
        case .apple: return "applelogo"
        case .localWhisper: return "cpu"
        case .none: return "questionmark"
        }
    }
    
    private var serviceColor: Color {
        switch service {
        case .openai: return .green
        case .apple: return .blue
        case .localWhisper: return .purple
        case .none: return .gray
        }
    }
    
    private var statusText: String {
        if !isConfigured {
            return "Setup required"
        } else if isAvailable {
            return "Available"
        } else {
            return "Unavailable"
        }
    }
    
    private var statusColor: Color {
        if !isConfigured {
            return .orange
        } else if isAvailable {
            return .green
        } else {
            return .red
        }
    }
}

struct StatusIndicator: View {
    let isAvailable: Bool
    
    var body: some View {
        HStack(spacing: 4) {
            Circle()
                .fill(isAvailable ? Color.green : Color.red)
                .frame(width: 8, height: 8)
            
            Text(isAvailable ? "Ready" : "Offline")
                .font(.caption)
                .fontWeight(.medium)
                .foregroundColor(isAvailable ? .green : .red)
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 4)
        .background(
            Capsule()
                .fill((isAvailable ? Color.green : Color.red).opacity(0.1))
        )
    }
}

struct StorageInfoRow: View {
    @State private var storageInfo = getStorageInfo()
    
    var body: some View {
        VStack(spacing: 12) {
            HStack {
                Image(systemName: "internaldrive")
                    .foregroundColor(.blue)
                    .frame(width: 24)
                
                VStack(alignment: .leading, spacing: 2) {
                    Text("Storage")
                        .font(.subheadline)
                    
                    Text("Available: \(storageInfo.available)")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
                
                Spacer()
            }
            
            // Storage usage bar
            StorageBar(
                used: storageInfo.usedPercentage,
                color: storageInfo.usedPercentage > 0.8 ? .red : (storageInfo.usedPercentage > 0.6 ? .orange : .green)
            )
        }
        .padding(.vertical, 4)
        .onAppear {
            storageInfo = StorageInfoRow.getStorageInfo()
        }
    }
    
    private static func getStorageInfo() -> (available: String, usedPercentage: Double) {
        let fileManager = FileManagerService.shared
        let availableBytes = fileManager.availableSpace
        let totalBytes = AudioFileManager.shared.totalStorageSpace()
        let usedBytes = totalBytes - availableBytes
        
        let availableString = ByteCountFormatter.string(fromByteCount: availableBytes, countStyle: .file)
        let usedPercentage = totalBytes > 0 ? Double(usedBytes) / Double(totalBytes) : 0
        
        return (availableString, usedPercentage)
    }
}

struct StorageBar: View {
    let used: Double
    let color: Color
    
    var body: some View {
        GeometryReader { geometry in
            ZStack(alignment: .leading) {
                // Background
                RoundedRectangle(cornerRadius: 3)
                    .fill(Color(.systemGray5))
                    .frame(height: 6)
                
                // Used portion
                RoundedRectangle(cornerRadius: 3)
                    .fill(color)
                    .frame(width: geometry.size.width * used, height: 6)
                    .animation(.smooth(duration: 0.5), value: used)
            }
        }
        .frame(height: 6)
    }
}

// MARK: - API Key Configuration View

struct APIKeyConfigurationView: View {
    @State private var apiKey = ""
    @State private var isValidating = false
    @State private var validationResult: String?
    @State private var showingKey = false
    
    @ObservedObject private var authManager = AuthenticationManager.shared
    @Environment(\.dismiss) private var dismiss
    
    var body: some View {
        NavigationView {
            VStack(spacing: 32) {
                // Header
                VStack(spacing: 16) {
                    Image(systemName: "key.fill")
                        .font(.system(size: 48))
                        .foregroundColor(.blue)
                    
                    VStack(spacing: 8) {
                        Text("OpenAI API Key")
                            .font(.title2)
                            .fontWeight(.semibold)
                        
                        Text("Your API key is stored securely on your device and never shared.")
                            .font(.subheadline)
                            .foregroundColor(.secondary)
                            .multilineTextAlignment(.center)
                    }
                }
                
                // Input section
                VStack(spacing: 16) {
                    HStack {
                        Group {
                            if showingKey {
                                TextField("sk-...", text: $apiKey)
                            } else {
                                SecureField("sk-...", text: $apiKey)
                            }
                        }
                        .textFieldStyle(.roundedBorder)
                        .font(.system(.body, design: .monospaced))
                        
                        Button(action: { showingKey.toggle() }) {
                            Image(systemName: showingKey ? "eye.slash" : "eye")
                                .foregroundColor(.secondary)
                        }
                    }
                    
                    if let result = validationResult {
                        Label(result, systemImage: authManager.hasValidOpenAIKey ? "checkmark.circle" : "exclamationmark.circle")
                            .font(.caption)
                            .foregroundColor(authManager.hasValidOpenAIKey ? .green : .red)
                    }
                }
                
                // Actions
                VStack(spacing: 12) {
                    Button(action: saveAPIKey) {
                        HStack {
                            if isValidating {
                                ProgressView()
                                    .scaleEffect(0.8)
                            }
                            
                            Text("Save & Validate")
                        }
                    }
                    .buttonStyle(.borderedProminent)
                    .frame(maxWidth: .infinity)
                    .disabled(apiKey.isEmpty || isValidating)
                    
                    if authManager.hasValidOpenAIKey {
                        Button("Remove API Key", role: .destructive, action: removeAPIKey)
                            .buttonStyle(.bordered)
                            .frame(maxWidth: .infinity)
                    }
                }
                
                // Help section
                APIKeyHelpView()
                
                Spacer()
            }
            .padding()
            .navigationTitle("API Configuration")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    Button("Cancel", action: { dismiss() })
                }
            }
            .onAppear {
                apiKey = authManager.openAIAPIKey ?? ""
            }
        }
    }
    
    private func saveAPIKey() {
        isValidating = true
        validationResult = nil
        
        do {
            try authManager.setOpenAIAPIKey(apiKey)
            validationResult = "API key saved successfully"
            
            DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) {
                dismiss()
            }
        } catch {
            validationResult = "Failed to save API key"
        }
        
        isValidating = false
    }
    
    private func removeAPIKey() {
        do {
            try authManager.removeOpenAIAPIKey()
            apiKey = ""
            validationResult = "API key removed"
        } catch {
            validationResult = "Failed to remove API key"
        }
    }
}

struct APIKeyHelpView: View {
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("How to get an API key:")
                .font(.headline)
            
            VStack(alignment: .leading, spacing: 8) {
                HelpStep(number: 1, text: "Visit platform.openai.com")
                HelpStep(number: 2, text: "Sign up or log in to your account")
                HelpStep(number: 3, text: "Navigate to API Keys section")
                HelpStep(number: 4, text: "Create a new API key")
                HelpStep(number: 5, text: "Copy and paste it here")
            }
        }
        .padding()
        .background(Color(.systemGray6))
        .cornerRadius(12)
    }
}

struct HelpStep: View {
    let number: Int
    let text: String
    
    var body: some View {
        HStack(spacing: 12) {
            ZStack {
                Circle()
                    .fill(Color.blue)
                    .frame(width: 24, height: 24)
                
                Text("\(number)")
                    .font(.caption)
                    .fontWeight(.bold)
                    .foregroundColor(.white)
            }
            
            Text(text)
                .font(.subheadline)
                .foregroundColor(.secondary)
            
            Spacer()
        }
    }
}

// MARK: - Extensions

extension Bundle {
    var appVersion: String {
        return infoDictionary?["CFBundleShortVersionString"] as? String ?? "1.0"
    }
    
    var buildVersion: String {
        return infoDictionary?["CFBundleVersion"] as? String ?? "1"
    }
}

extension AudioConfiguration.Quality {
    var description: String {
        switch self {
        case .high:
            return "\(Int(sampleRate)) Hz, \(bitDepth)-bit"
        case .medium:
            return "\(Int(sampleRate)) Hz, \(bitDepth)-bit"
        case .low:
            return "\(Int(sampleRate)) Hz, \(bitDepth)-bit"
        case .custom:
            return "\(Int(sampleRate)) Hz, \(bitDepth)-bit"
        }
    }
}
