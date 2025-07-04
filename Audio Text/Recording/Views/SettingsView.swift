import SwiftUI
import AVFoundation

extension Bundle {
    var appVersion: String {
        return infoDictionary?["CFBundleShortVersionString"] as? String ?? "1.0"
    }
}

struct SettingsView: View {
    @ObservedObject private var settingsService = SettingsService.shared
    @ObservedObject private var authManager = AuthenticationManager.shared
    @ObservedObject private var networkMonitor = NetworkMonitorService.shared
    @ObservedObject private var openAIService = OpenAITranscriptionService.shared
    @ObservedObject private var appleService = AppleTranscriptionService.shared
    
    @Environment(\.dismiss) private var dismiss
    @State private var localSettings: RecordingSettings
    @State private var showingResetAlert = false
    @State private var showingTranscriptionLanguageInfo = false
    @State private var showingAPIKeySetup = false
    @State private var showingTranscriptionHelp = false
    
    init() {
        _localSettings = State(initialValue: SettingsService.shared.settings)
    }
    
    var body: some View {
        NavigationView {
            Form {
                // Audio Quality Section
                audioQualitySection
                
                // Recording Options Section
                recordingOptionsSection
                
                // Transcription Settings Section
                transcriptionSettingsSection
                
                // API Configuration Section
                apiConfigurationSection
                
                // Battery & Performance Section
                batteryPerformanceSection
                
                // Storage Info Section
                storageInfoSection
                
                // Advanced Section
                advancedSection
                
                // Reset Section
                resetSection
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
            .sheet(isPresented: $showingTranscriptionLanguageInfo) {
                TranscriptionLanguageInfoView(service: localSettings.preferredTranscriptionService ?? .none)
            }
            .sheet(isPresented: $showingAPIKeySetup) {
                APIKeyConfigurationView()
            }
            .sheet(isPresented: $showingTranscriptionHelp) {
                TranscriptionHelpView()
            }
        }
    }
    
    // MARK: - Audio Quality Section
    
    private var audioQualitySection: some View {
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
    }
    
    // MARK: - Recording Options Section
    
    private var recordingOptionsSection: some View {
        Section("Recording Options") {
            Toggle("Background Recording", isOn: $localSettings.backgroundRecordingEnabled)
            Toggle("Show Audio Levels", isOn: $localSettings.showAudioLevels)
            Toggle("Auto-save Recordings", isOn: $localSettings.autoSaveEnabled)
        }
    }
    
    // MARK: - Transcription Settings Section
    
    private var transcriptionSettingsSection: some View {
        Section {
            VStack(alignment: .leading, spacing: 12) {
                HStack {
                    Text("Transcription Settings")
                        .font(.headline)
                    
                    Spacer()
                    
                    Button(action: { showingTranscriptionHelp = true }) {
                        Image(systemName: "questionmark.circle")
                            .foregroundColor(.blue)
                    }
                }
                
                Toggle("Auto-transcribe Recordings", isOn: $localSettings.enableAutoTranscription)
                
                if localSettings.enableAutoTranscription {
                    VStack(alignment: .leading, spacing: 8) {
                        // Service Selection
                        servicePicker
                        
                        // Service Status
                        serviceStatusView
                        
                        // Service Options
                        serviceOptionsView
                    }
                }
            }
        } footer: {
            if localSettings.enableAutoTranscription {
                Text("Recordings will be automatically transcribed using your preferred service. You can always change this per recording.")
            }
        }
    }
    
    private var servicePicker: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text("Preferred Service")
                .font(.subheadline)
                .foregroundColor(.secondary)
            
            Picker("Transcription Service", selection: $localSettings.preferredTranscriptionService) {
                Text("Auto-select").tag(nil as TranscriptionService?)
                
                ForEach(TranscriptionService.allCases.filter { $0 != .none }, id: \.self) { service in
                    HStack {
                        Text(service.displayName)
                        Spacer()
                        serviceAvailabilityIndicator(for: service)
                    }
                    .tag(service as TranscriptionService?)
                }
            }
            .pickerStyle(.menu)
        }
    }
    
    private var serviceStatusView: some View {
        VStack(spacing: 8) {
            ForEach(TranscriptionService.allCases.filter { $0 != .none }, id: \.self) { service in
                serviceStatusRow(for: service)
            }
        }
    }
    
    private func serviceStatusRow(for service: TranscriptionService) -> some View {
        HStack {
            HStack(spacing: 8) {
                Image(systemName: serviceIcon(for: service))
                    .foregroundColor(serviceColor(for: service))
                    .frame(width: 20)
                
                Text(service.displayName)
                    .font(.subheadline)
            }
            
            Spacer()
            
            serviceStatusIndicator(for: service)
        }
        .padding(.vertical, 2)
    }
    
    private func serviceAvailabilityIndicator(for service: TranscriptionService) -> some View {
        Circle()
            .fill(isServiceAvailable(service) ? Color.green : Color.red)
            .frame(width: 8, height: 8)
    }
    
    private func serviceStatusIndicator(for service: TranscriptionService) -> some View {
        Group {
            if isServiceAvailable(service) {
                HStack(spacing: 4) {
                    Image(systemName: "checkmark.circle.fill")
                        .foregroundColor(.green)
                    Text("Available")
                        .font(.caption)
                        .foregroundColor(.green)
                }
            } else {
                HStack(spacing: 4) {
                    Image(systemName: "exclamationmark.circle.fill")
                        .foregroundColor(.red)
                    Text(serviceUnavailableReason(for: service))
                        .font(.caption)
                        .foregroundColor(.red)
                }
            }
        }
    }
    
    private var serviceOptionsView: some View {
        VStack(alignment: .leading, spacing: 8) {
            if let service = localSettings.preferredTranscriptionService, service.requiresNetwork {
                Toggle("Allow Cellular Data", isOn: $localSettings.allowCellularTranscription)
                    .disabled(!networkMonitor.isConnected)
            }
            
            Toggle("Service Fallback", isOn: $localSettings.allowServiceFallback)
                .disabled(localSettings.preferredTranscriptionService == .none)
            
            Toggle("Prefer Local Processing", isOn: $localSettings.preferLocalProcessing)
            
            HStack {
                Text("Max Retry Attempts")
                    .font(.subheadline)
                
                Spacer()
                
                Picker("Retry Attempts", selection: $localSettings.maxRetryAttempts) {
                    ForEach(1...10, id: \.self) { count in
                        Text("\(count)").tag(count)
                    }
                }
                .pickerStyle(.menu)
            }
            
            Button("Supported Languages") {
                showingTranscriptionLanguageInfo = true
            }
            .font(.subheadline)
            .foregroundColor(.blue)
        }
    }
    
    // MARK: - API Configuration Section
    
    private var apiConfigurationSection: some View {
        Section {
            // OpenAI Configuration
            HStack {
                VStack(alignment: .leading, spacing: 4) {
                    Text("OpenAI API Key")
                        .font(.subheadline)
                    
                    if authManager.hasValidOpenAIKey {
                        HStack(spacing: 4) {
                            Image(systemName: "checkmark.circle.fill")
                                .foregroundColor(.green)
                            Text("Configured")
                                .font(.caption)
                                .foregroundColor(.green)
                        }
                    } else {
                        HStack(spacing: 4) {
                            Image(systemName: "exclamationmark.circle.fill")
                                .foregroundColor(.orange)
                            Text("Not configured")
                                .font(.caption)
                                .foregroundColor(.orange)
                        }
                    }
                }
                
                Spacer()
                
                Button(authManager.hasValidOpenAIKey ? "Update" : "Configure") {
                    showingAPIKeySetup = true
                }
                .buttonStyle(.bordered)
            }
            
            // Apple Speech Configuration
            HStack {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Apple Speech Recognition")
                        .font(.subheadline)
                    
                    switch appleService.authorizationStatus {
                    case .authorized:
                        HStack(spacing: 4) {
                            Image(systemName: "checkmark.circle.fill")
                                .foregroundColor(.green)
                            Text("Authorized")
                                .font(.caption)
                                .foregroundColor(.green)
                        }
                    case .denied, .restricted:
                        HStack(spacing: 4) {
                            Image(systemName: "xmark.circle.fill")
                                .foregroundColor(.red)
                            Text("Access denied")
                                .font(.caption)
                                .foregroundColor(.red)
                        }
                    case .notDetermined:
                        HStack(spacing: 4) {
                            Image(systemName: "questionmark.circle.fill")
                                .foregroundColor(.orange)
                            Text("Not requested")
                                .font(.caption)
                                .foregroundColor(.orange)
                        }
                    @unknown default:
                        HStack(spacing: 4) {
                            Image(systemName: "questionmark.circle.fill")
                                .foregroundColor(.gray)
                            Text("Unknown")
                                .font(.caption)
                                .foregroundColor(.gray)
                        }
                    }
                }
                
                Spacer()
                
                if appleService.authorizationStatus != .authorized {
                    Button("Request Access") {
                        Task {
                            await appleService.requestSpeechAuthorization()
                        }
                    }
                    .buttonStyle(.bordered)
                }
            }
        } header: {
            Text("API Configuration")
        } footer: {
            Text("OpenAI Whisper provides the highest accuracy for multiple languages. Apple Speech Recognition works offline but supports fewer languages.")
        }
    }
    
    // MARK: - Battery & Performance Section
    
    private var batteryPerformanceSection: some View {
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
            
            VStack(alignment: .leading, spacing: 4) {
                Text("Concurrent Transcriptions")
                    .font(.subheadline)
                
                Picker("Concurrent Transcriptions", selection: $localSettings.maxConcurrentTranscriptions) {
                    ForEach(1...5, id: \.self) { count in
                        Text("\(count)").tag(count)
                    }
                }
                .pickerStyle(.segmented)
                
                Text("Higher values process faster but use more battery")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
        }
    }
    
    // MARK: - Storage Info Section
    
    private var storageInfoSection: some View {
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
            
            HStack {
                Text("Transcription Cache")
                Spacer()
                Text(storageInfo.transcriptionCache)
                    .foregroundColor(.secondary)
            }
            
            if storageInfo.canCleanupCache {
                Button("Clear Transcription Cache") {
                    clearTranscriptionCache()
                }
                .foregroundColor(.blue)
            }
        }
    }
    
    // MARK: - Advanced Section
    
    private var advancedSection: some View {
        Section("Advanced") {
            NavigationLink("Transcription Statistics") {
                TranscriptionStatisticsView()
            }
            
            NavigationLink("Service Diagnostics") {
                ServiceDiagnosticsView()
            }
            
            Toggle("Developer Mode", isOn: $localSettings.enableDeveloperMode)
            
            if localSettings.enableDeveloperMode {
                Toggle("Detailed Logging", isOn: $localSettings.enableDetailedLogging)
                
                Button("Export Debug Logs") {
                    exportDebugLogs()
                }
                .foregroundColor(.blue)
            }
        }
    }
    
    // MARK: - Reset Section
    
    private var resetSection: some View {
        Section {
            Button("Reset to Defaults", role: .destructive) {
                showingResetAlert = true
            }
            
            Button("Clear All Data", role: .destructive) {
                clearAllData()
            }
        } footer: {
            VStack(alignment: .leading, spacing: 4) {
                Text("App version: \(Bundle.main.appVersion)")
                Text("Build: \(Bundle.main.buildVersion)")
            }
            .font(.caption)
            .foregroundColor(.secondary)
        }
    }
    
    // MARK: - Helper Methods
    
    private func isServiceAvailable(_ service: TranscriptionService) -> Bool {
        switch service {
        case .openai:
            return authManager.hasValidOpenAIKey && networkMonitor.isConnected
        case .apple:
            return appleService.isAvailable
        case .localWhisper:
            return false // Not implemented
        case .none:
            return false
        }
    }
    
    private func serviceUnavailableReason(for service: TranscriptionService) -> String {
        switch service {
        case .openai:
            if !authManager.hasValidOpenAIKey {
                return "API key required"
            } else if !networkMonitor.isConnected {
                return "Network required"
            } else {
                return "Unavailable"
            }
        case .apple:
            if appleService.authorizationStatus != .authorized {
                return "Permission required"
            } else {
                return "Unavailable"
            }
        case .localWhisper:
            return "Not implemented"
        case .none:
            return "No service"
        }
    }
    
    private func serviceIcon(for service: TranscriptionService) -> String {
        switch service {
        case .openai: return "brain"
        case .apple: return "applelogo"
        case .localWhisper: return "cpu"
        case .none: return "questionmark"
        }
    }
    
    private func serviceColor(for service: TranscriptionService) -> Color {
        switch service {
        case .openai: return .green
        case .apple: return .blue
        case .localWhisper: return .purple
        case .none: return .gray
        }
    }
    
    private func getStorageInfo() -> (available: String, estimatedTime: String, transcriptionCache: String, canCleanupCache: Bool) {
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
        
        // Calculate transcription cache size
        let cacheSize = calculateTranscriptionCacheSize()
        let cacheString = ByteCountFormatter.string(fromByteCount: cacheSize, countStyle: .file)
        
        return (availableString, estimatedTime, cacheString, cacheSize > 0)
    }
    
    private func calculateTranscriptionCacheSize() -> Int64 {
        // Calculate size of segment files and cached data
        let segmentsDirectory = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
            .appendingPathComponent(TranscriptionConstants.segmentDirectoryName)
        
        do {
            let files = try FileManager.default.contentsOfDirectory(at: segmentsDirectory, includingPropertiesForKeys: [.fileSizeKey])
            return files.reduce(0) { total, url in
                total + (url.fileSize)
            }
        } catch {
            return 0
        }
    }
    
    // MARK: - Actions
    
    private func saveSettings() {
        settingsService.updateSettings(localSettings)
        dismiss()
    }
    
    private func clearTranscriptionCache() {
        // Clear segment files and temporary data
        AudioSegmentProcessor.shared.cleanupSegmentFiles(for: UUID()) // This would need to be updated to clear all
        // Clear any other cached transcription data
    }
    
    private func clearAllData() {
        // This would clear all recordings and transcriptions
        // Implementation would need confirmation dialog
    }
    
    private func exportDebugLogs() {
        // Export debug logs for troubleshooting
        // Implementation would create a log file and share it
    }
}

// MARK: - Supporting Views

struct APIKeyConfigurationView: View {
    @State private var apiKey = ""
    @State private var isValidating = false
    @State private var validationResult: String?
    @State private var showingKey = false
    
    @ObservedObject private var authManager = AuthenticationManager.shared
    @Environment(\.dismiss) private var dismiss
    
    var body: some View {
        NavigationView {
            VStack(spacing: 24) {
                // Header
                VStack(spacing: 8) {
                    Image(systemName: "key.fill")
                        .font(.system(size: 48))
                        .foregroundColor(.blue)
                    
                    Text("OpenAI API Key")
                        .font(.title2)
                        .fontWeight(.semibold)
                    
                    Text("Your API key is stored securely on your device and never shared.")
                        .font(.caption)
                        .foregroundColor(.secondary)
                        .multilineTextAlignment(.center)
                }
                
                // API Key Input
                VStack(alignment: .leading, spacing: 8) {
                    HStack {
                        if showingKey {
                            TextField("sk-...", text: $apiKey)
                                .textFieldStyle(.roundedBorder)
                                .font(.system(.body, design: .monospaced))
                        } else {
                            SecureField("sk-...", text: $apiKey)
                                .textFieldStyle(.roundedBorder)
                                .font(.system(.body, design: .monospaced))
                        }
                        
                        Button(action: { showingKey.toggle() }) {
                            Image(systemName: showingKey ? "eye.slash" : "eye")
                                .foregroundColor(.secondary)
                        }
                    }
                    
                    if let result = validationResult {
                        Text(result)
                            .font(.caption)
                            .foregroundColor(authManager.hasValidOpenAIKey ? .green : .red)
                    }
                }
                
                // Actions
                VStack(spacing: 12) {
                    Button("Save & Validate") {
                        saveAPIKey()
                    }
                    .buttonStyle(.borderedProminent)
                    .disabled(apiKey.isEmpty || isValidating)
                    .frame(maxWidth: .infinity)
                    
                    if authManager.hasValidOpenAIKey {
                        Button("Remove API Key", role: .destructive) {
                            removeAPIKey()
                        }
                        .buttonStyle(.bordered)
                        .frame(maxWidth: .infinity)
                    }
                }
                
                // Help
                VStack(alignment: .leading, spacing: 8) {
                    Text("How to get an API key:")
                        .font(.headline)
                    
                    Text("1. Visit platform.openai.com\n2. Sign up or log in\n3. Go to API Keys section\n4. Create a new API key\n5. Copy and paste it here")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
                .padding()
                .background(Color(.systemGray6))
                .cornerRadius(8)
                
                Spacer()
            }
            .padding()
            .navigationTitle("API Configuration")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    Button("Cancel") {
                        dismiss()
                    }
                }
                
                if !apiKey.isEmpty {
                    ToolbarItem(placement: .navigationBarTrailing) {
                        Button("Save") {
                            saveAPIKey()
                        }
                        .disabled(isValidating)
                    }
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
            
            // Auto-dismiss after success
            DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) {
                dismiss()
            }
        } catch {
            validationResult = "Failed to save API key: \(error.localizedDescription)"
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

struct TranscriptionHelpView: View {
    @Environment(\.dismiss) private var dismiss
    
    var body: some View {
        NavigationView {
            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    // Introduction
                    VStack(alignment: .leading, spacing: 8) {
                        Text("About Transcription")
                            .font(.title2)
                            .fontWeight(.semibold)
                        
                        Text("Transcription automatically converts your audio recordings to text using advanced AI. This makes your recordings searchable and easier to review.")
                            .font(.body)
                    }
                    
                    // Services comparison
                    servicesComparisonSection
                    
                    // Privacy section
                    privacySection
                    
                    // Tips section
                    tipsSection
                }
                .padding()
            }
            .navigationTitle("Transcription Help")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button("Done") {
                        dismiss()
                    }
                }
            }
        }
    }
    
    private var servicesComparisonSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Transcription Services")
                .font(.headline)
            
            serviceComparisonCard(
                service: .openai,
                pros: ["Highest accuracy", "99+ languages", "Handles accents well", "Technical vocabulary"],
                cons: ["Requires internet", "Requires API key", "Costs per usage"]
            )
            
            serviceComparisonCard(
                service: .apple,
                pros: ["Works offline", "Free", "Good privacy", "Fast processing"],
                cons: ["Fewer languages", "Less accurate", "iOS devices only"]
            )
        }
    }
    
    private func serviceComparisonCard(service: TranscriptionService, pros: [String], cons: [String]) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Image(systemName: service == .openai ? "brain" : "applelogo")
                    .foregroundColor(service == .openai ? .green : .blue)
                Text(service.displayName)
                    .font(.subheadline)
                    .fontWeight(.medium)
            }
            
            VStack(alignment: .leading, spacing: 4) {
                Text("Pros:")
                    .font(.caption)
                    .fontWeight(.medium)
                    .foregroundColor(.green)
                
                ForEach(pros, id: \.self) { pro in
                    Text("• \(pro)")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
            }
            
            VStack(alignment: .leading, spacing: 4) {
                Text("Cons:")
                    .font(.caption)
                    .fontWeight(.medium)
                    .foregroundColor(.orange)
                
                ForEach(cons, id: \.self) { con in
                    Text("• \(con)")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
            }
        }
        .padding()
        .background(Color(.systemGray6))
        .cornerRadius(8)
    }
    
    private var privacySection: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Privacy & Security")
                .font(.headline)
            
            Text("Your audio recordings are processed according to these privacy principles:")
                .font(.body)
            
            VStack(alignment: .leading, spacing: 4) {
                Text("• OpenAI: Audio sent to OpenAI servers, processed according to their privacy policy")
                Text("• Apple: Processed locally on your device or Apple servers with privacy protections")
                Text("• All transcriptions stored locally on your device")
                Text("• API keys stored securely in iOS Keychain")
                Text("• You can delete transcriptions at any time")
            }
            .font(.caption)
            .foregroundColor(.secondary)
        }
        .padding()
        .background(Color(.systemGray6))
        .cornerRadius(8)
    }
    
    private var tipsSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Tips for Better Transcription")
                .font(.headline)
            
            VStack(alignment: .leading, spacing: 4) {
                Text("• Record in a quiet environment")
                Text("• Speak clearly and at normal pace")
                Text("• Keep device close to speaker")
                Text("• Use higher audio quality settings")
                Text("• Minimize background noise")
                Text("• For technical terms, consider editing afterward")
            }
            .font(.caption)
            .foregroundColor(.secondary)
        }
        .padding()
        .background(Color(.systemGray6))
        .cornerRadius(8)
    }
}

// MARK: - Additional Extensions

extension Bundle {
    var buildVersion: String {
        return infoDictionary?["CFBundleVersion"] as? String ?? "1"
    }
}
