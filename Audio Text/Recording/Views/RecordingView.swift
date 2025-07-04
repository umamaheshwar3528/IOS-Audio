import SwiftUI

struct RecordingView: View {
    @ObservedObject private var recordingManager = AudioRecordingManager.shared
    @ObservedObject private var permissionService = AudioPermissionService.shared
    @State private var showingSessionList = false
    
    var body: some View {
        NavigationView {
            VStack(spacing: 40) {
                if permissionService.permissionStatus.isGranted {
                    recordingInterface
                } else {
                    PermissionRequestView()
                }
            }
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button("Sessions") {
                        showingSessionList = true
                    }
                }
            }
            .sheet(isPresented: $showingSessionList) {
                RecordingSessionListView()
            }
        }
    }
    
    private var recordingInterface: some View {
        VStack(spacing: 40) {
            // Status Section
            VStack(spacing: 16) {
                Text(recordingManager.currentState.displayText)
                    .font(.title2)
                    .fontWeight(.medium)
                
                if recordingManager.currentState.isRecording || recordingManager.currentState.isPaused {
                    Text(recordingManager.recordingDuration.formattedDuration)
                        .font(.system(size: 48, weight: .light, design: .monospaced))
                        .foregroundColor(.primary)
                }
            }
            
            // Audio Level Meter
            if recordingManager.currentState.isRecording {
                VStack(spacing: 12) {
                    Text("Audio Level")
                        .font(.caption)
                        .foregroundColor(.secondary)
                    
                    AudioLevelMeterView()
                }
                .transition(.opacity)
            }
            
            Spacer()
            
            // Recording Controls
            RecordingControlsView()
            
            Spacer()
        }
        .padding()
    }
}
