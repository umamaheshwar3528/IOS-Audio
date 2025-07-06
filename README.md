# Audio Text

Audio Text is an iOS application for recording audio and transcribing it into text using Apple and OpenAI transcription services. The app provides a seamless experience for managing recordings, monitoring audio levels, and viewing transcription progress.

## Features

- Record audio with real-time audio level monitoring
- Manage and organize audio recordings
- Transcribe audio using Apple or OpenAI services
- View and export transcription results
- Background recording support
- User-friendly interface with customizable settings

## Requirements

- macOS 12.0+ or iOS 15.0+
- Xcode 14+
- Swift 5.5+
- OpenAI API key (for OpenAI transcription)

## Setup Instructions

### 1. Clone the Repository

```sh
git clone [url] "Audio Text"
cd "Audio Text"
```

### 2. Open the Project in Xcode

- Open `Audio Text.xcodeproj` in Xcode.

### 3. Configure Entitlements

- Ensure the app has the necessary permissions for microphone access and background audio.

### 4. Add OpenAI API Key (Optional)

- To use OpenAI transcription, launch the app and set the key in the settings screen
- Or alternatively edit `OpenAITranscriptionService.swift` to load your API key securely (e.g., via Xcode project secrets, environment variable, or Keychain).

### 5. Build and Run

- Select the desired target (macOS or iOS) and run the app on a simulator or device.

## Project Structure

- `App/` — App entry point and main views
- `Network/` — Network and authentication logic
- `Recording/` — Audio recording core, models, services, and UI
- `Transcription/` — Transcription logic, models, services, and UI
- `Shared/` — Shared utilities, extensions, and UI components
- `Resources/` — App resources and localization

## Usage

1. Launch the app and grant microphone permissions.
2. Start a new recording and monitor audio levels.
3. Stop the recording to save it.
4. Select a recording to transcribe using Apple or OpenAI.
5. View, edit, or export the transcription results.
