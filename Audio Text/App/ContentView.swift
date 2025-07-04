import SwiftUI

struct ContentView: View {
    var body: some View {
        RecordingView()
            .preferredColorScheme(.light) // Can be changed to support dark mode
    }
}

#Preview {
    ContentView()
}
