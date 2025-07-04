import SwiftUI

struct PermissionRequestView: View {
    @ObservedObject private var permissionService = AudioPermissionService.shared
    @State private var isRequesting = false
    
    var body: some View {
        VStack(spacing: 24) {
            Image(systemName: "mic.fill")
                .font(.system(size: 60))
                .foregroundColor(.blue)
            
            VStack(spacing: 12) {
                Text("Microphone Access Required")
                    .font(.title2)
                    .fontWeight(.semibold)
                
                Text("This app needs access to your microphone to record audio. Your recordings are stored locally on your device.")
                    .font(.body)
                    .multilineTextAlignment(.center)
                    .foregroundColor(.secondary)
            }
            
            Button(action: requestPermission) {
                HStack {
                    if isRequesting {
                        ProgressView()
                            .scaleEffect(0.8)
                    } else {
                        Image(systemName: "mic")
                    }
                    Text(isRequesting ? "Requesting..." : "Grant Access")
                }
                .frame(maxWidth: .infinity)
                .padding()
                .background(Color.blue)
                .foregroundColor(.white)
                .cornerRadius(12)
            }
            .disabled(isRequesting)
        }
        .padding()
    }
    
    private func requestPermission() {
        isRequesting = true
        Task {
            await permissionService.requestPermission()
            await MainActor.run {
                isRequesting = false
            }
        }
    }
}
