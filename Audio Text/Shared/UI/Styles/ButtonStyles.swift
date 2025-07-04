import SwiftUI

struct RecordButtonStyle: ButtonStyle {
    let isRecording: Bool
    let isEnabled: Bool
    
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .frame(width: 80, height: 80)
            .background(
                Circle()
                    .fill(isRecording ? Color.red : Color.blue)
                    .opacity(isEnabled ? 1.0 : 0.5)
            )
            .scaleEffect(configuration.isPressed ? 0.95 : 1.0)
            .animation(.easeInOut(duration: 0.1), value: configuration.isPressed)
    }
}

struct ControlButtonStyle: ButtonStyle {
    let isEnabled: Bool
    
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .frame(width: 60, height: 60)
            .background(
                Circle()
                    .fill(Color.secondary)
                    .opacity(isEnabled ? 0.2 : 0.1)
            )
            .foregroundColor(isEnabled ? .primary : .secondary)
            .scaleEffect(configuration.isPressed ? 0.95 : 1.0)
            .animation(.easeInOut(duration: 0.1), value: configuration.isPressed)
    }
}
