import Foundation
import Security
import Combine

class AuthenticationManager: ObservableObject {
    static let shared = AuthenticationManager()
    
    @Published var hasValidOpenAIKey = false
    @Published var hasValidAppleCredentials = false
    
    private let keychainService = "com.audiotext.transcription"
    private let openAIKeyIdentifier = "openai_api_key"
    
    private init() {
        checkStoredCredentials()
    }
    
    // MARK: - OpenAI API Key Management
    
    var openAIAPIKey: String? {
        return getKeychainValue(for: openAIKeyIdentifier)
    }
    
    func setOpenAIAPIKey(_ key: String) throws {
        try setKeychainValue(key, for: openAIKeyIdentifier)
        hasValidOpenAIKey = !key.isEmpty
        
        // Validate the key asynchronously
        Task {
            await validateOpenAIKey()
        }
    }
    
    func removeOpenAIAPIKey() throws {
        try removeKeychainValue(for: openAIKeyIdentifier)
        hasValidOpenAIKey = false
    }
    
    private func validateOpenAIKey() async {
        guard let apiKey = openAIAPIKey, !apiKey.isEmpty else {
            DispatchQueue.main.async {
                self.hasValidOpenAIKey = false
            }
            return
        }
        
        let isValid = await OpenAITranscriptionService.shared.validateAPIKey()
        
        DispatchQueue.main.async {
            self.hasValidOpenAIKey = isValid
            if !isValid {
                Logger.shared.warning("OpenAI API key validation failed")
            }
        }
    }
    
    // MARK: - Apple Credentials Management
    
    private func checkAppleCredentials() {
        // Apple Speech Recognition uses system-level authorization
        hasValidAppleCredentials = AppleTranscriptionService.shared.authorizationStatus == .authorized
    }
    
    private func checkStoredCredentials() {
        hasValidOpenAIKey = openAIAPIKey != nil && !openAIAPIKey!.isEmpty
        checkAppleCredentials()
    }
    
    // MARK: - Keychain Operations
    
    private func setKeychainValue(_ value: String, for identifier: String) throws {
        let data = value.data(using: .utf8)!
        
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: keychainService,
            kSecAttrAccount as String: identifier,
            kSecValueData as String: data,
            kSecAttrAccessible as String: kSecAttrAccessibleWhenUnlockedThisDeviceOnly
        ]
        
        // Delete existing item
        SecItemDelete(query as CFDictionary)
        
        // Add new item
        let status = SecItemAdd(query as CFDictionary, nil)
        
        guard status == errSecSuccess else {
            throw KeychainError.saveFailed(status)
        }
    }
    
    private func getKeychainValue(for identifier: String) -> String? {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: keychainService,
            kSecAttrAccount as String: identifier,
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne
        ]
        
        var dataTypeRef: AnyObject?
        let status = SecItemCopyMatching(query as CFDictionary, &dataTypeRef)
        
        guard status == errSecSuccess,
              let data = dataTypeRef as? Data,
              let value = String(data: data, encoding: .utf8) else {
            return nil
        }
        
        return value
    }
    
    private func removeKeychainValue(for identifier: String) throws {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: keychainService,
            kSecAttrAccount as String: identifier
        ]
        
        let status = SecItemDelete(query as CFDictionary)
        
        guard status == errSecSuccess || status == errSecItemNotFound else {
            throw KeychainError.deleteFailed(status)
        }
    }
    
    // MARK: - Security Utilities
    
    func clearAllCredentials() throws {
        try removeOpenAIAPIKey()
        // Apple credentials are managed by the system
        
        hasValidOpenAIKey = false
        hasValidAppleCredentials = false
    }
    
    func exportEncryptedCredentials(password: String) throws -> Data {
        // This would implement credential export with encryption
        // for backup/restore functionality
        throw KeychainError.notImplemented
    }
    
    func importEncryptedCredentials(_ data: Data, password: String) throws {
        // This would implement credential import with decryption
        throw KeychainError.notImplemented
    }
}

// MARK: - Keychain Errors

enum KeychainError: Error, LocalizedError {
    case saveFailed(OSStatus)
    case deleteFailed(OSStatus)
    case notFound
    case notImplemented
    
    var errorDescription: String? {
        switch self {
        case .saveFailed(let status):
            return "Failed to save to keychain: \(status)"
        case .deleteFailed(let status):
            return "Failed to delete from keychain: \(status)"
        case .notFound:
            return "Item not found in keychain"
        case .notImplemented:
            return "Feature not implemented"
        }
    }
}

// MARK: - Settings Extension for Network and Auth

extension SettingsService {
    var allowCellularTranscription: Bool {
        // This would be added to RecordingSettings
        return false // Default to Wi-Fi only
    }
    
    var preferOnDeviceProcessing: Bool {
        // This would be added to RecordingSettings
        return true // Default to prefer on-device for privacy
    }
    
    var maxRetryAttempts: Int {
        // This would be added to RecordingSettings
        return TranscriptionConstants.maxRetryAttempts
    }
}
