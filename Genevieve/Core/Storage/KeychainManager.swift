import Foundation
import Security

/// Secure storage for API keys using macOS Keychain
final class KeychainManager: @unchecked Sendable {
    static let shared = KeychainManager()

    private let serviceName = "com.genevieve.app"

    // MARK: - Keychain Keys

    enum KeychainKey: String, CaseIterable {
        case claudeAPIKey = "claude_api_key"
        case geminiAPIKey = "gemini_api_key"
        case openAIAPIKey = "openai_api_key"

        var displayName: String {
            switch self {
            case .claudeAPIKey: return "Claude API Key"
            case .geminiAPIKey: return "Gemini API Key"
            case .openAIAPIKey: return "OpenAI API Key"
            }
        }

        var providerType: AIProviderType {
            switch self {
            case .claudeAPIKey: return .claude
            case .geminiAPIKey: return .gemini
            case .openAIAPIKey: return .openAI
            }
        }

        static func key(for provider: AIProviderType) -> KeychainKey {
            switch provider {
            case .claude: return .claudeAPIKey
            case .gemini: return .geminiAPIKey
            case .openAI: return .openAIAPIKey
            }
        }
    }

    // MARK: - Errors

    enum KeychainError: LocalizedError {
        case invalidData
        case saveFailed(OSStatus)
        case deleteFailed(OSStatus)
        case retrieveFailed(OSStatus)

        var errorDescription: String? {
            switch self {
            case .invalidData:
                return "Invalid keychain data"
            case .saveFailed(let status):
                return "Failed to save to keychain: \(status)"
            case .deleteFailed(let status):
                return "Failed to delete from keychain: \(status)"
            case .retrieveFailed(let status):
                return "Failed to retrieve from keychain: \(status)"
            }
        }
    }

    // MARK: - Private Init

    private init() {}

    // MARK: - Public Methods

    /// Save a value to the keychain
    func save(_ value: String, for key: KeychainKey) throws {
        guard let data = value.data(using: .utf8) else {
            throw KeychainError.invalidData
        }

        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: serviceName,
            kSecAttrAccount as String: key.rawValue
        ]

        // Check if item already exists
        let existsStatus = SecItemCopyMatching(query as CFDictionary, nil)

        if existsStatus == errSecSuccess {
            // Item exists, update it
            let updateAttributes: [String: Any] = [
                kSecValueData as String: data
            ]
            let updateStatus = SecItemUpdate(query as CFDictionary, updateAttributes as CFDictionary)
            guard updateStatus == errSecSuccess else {
                throw KeychainError.saveFailed(updateStatus)
            }
        } else if existsStatus == errSecItemNotFound {
            // Item doesn't exist, add it
            var addQuery = query
            addQuery[kSecValueData as String] = data
            addQuery[kSecAttrAccessible as String] = kSecAttrAccessibleWhenUnlockedThisDeviceOnly

            let addStatus = SecItemAdd(addQuery as CFDictionary, nil)
            guard addStatus == errSecSuccess else {
                throw KeychainError.saveFailed(addStatus)
            }
        } else {
            throw KeychainError.saveFailed(existsStatus)
        }
    }

    /// Retrieve a value from the keychain
    func retrieve(for key: KeychainKey) throws -> String? {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: serviceName,
            kSecAttrAccount as String: key.rawValue,
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne
        ]

        var result: AnyObject?
        let status = SecItemCopyMatching(query as CFDictionary, &result)

        if status == errSecItemNotFound {
            return nil
        }

        guard status == errSecSuccess else {
            throw KeychainError.retrieveFailed(status)
        }

        guard let data = result as? Data,
              let string = String(data: data, encoding: .utf8) else {
            throw KeychainError.invalidData
        }

        return string
    }

    /// Delete a value from the keychain
    func delete(for key: KeychainKey) throws {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: serviceName,
            kSecAttrAccount as String: key.rawValue
        ]

        let status = SecItemDelete(query as CFDictionary)

        // Ignore "item not found" errors
        guard status == errSecSuccess || status == errSecItemNotFound else {
            throw KeychainError.deleteFailed(status)
        }
    }

    /// Check if a key exists in the keychain
    func exists(for key: KeychainKey) -> Bool {
        (try? retrieve(for: key)) != nil
    }

    /// Get all configured providers
    func configuredProviders() -> [AIProviderType] {
        KeychainKey.allCases.compactMap { key in
            exists(for: key) ? key.providerType : nil
        }
    }

    /// Delete all stored keys
    func deleteAll() throws {
        for key in KeychainKey.allCases {
            try delete(for: key)
        }
    }
}
