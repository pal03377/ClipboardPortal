/// End-to-end-encrypt and sign clipboard contents
import Foundation
import Security
import CryptoKit

enum CryptoErrors {
    case privateKeyNotFound
    case keychainReadFailed(errorMessage: String?)
    case privateKeySaveFailed(errorMessage: String?)
    case invalidEncryptedData(errorType: String)
}
extension CryptoErrors: LocalizedError { // Nice error messages
    public var errorDescription: String? {
        switch self {
        case .privateKeyNotFound: "" // Never shown in UI, just used for control flow
        case .keychainReadFailed(let errorMessage): "Reading from Keychain failed. (\(errorMessage ?? "No details")"
        case .privateKeySaveFailed(let errorMessage): "Saving the private encryption key in Keychain failed. (\(errorMessage ?? "No details"))"
        case .invalidEncryptedData(let errorType): "The received encrypted data is invalid (\(errorType)). It might have been tampered with."
        }
    }
}
typealias PrivateKey = Curve25519.KeyAgreement.PrivateKey
typealias PublicKey = Curve25519.KeyAgreement.PublicKey

extension PublicKey {
    static func fromBase64(_ base64: String) throws -> Self {
        try PublicKey(rawRepresentation: Data(base64Encoded: base64)!)
    }
}

/// Get own private keys for signing and encryption
private func getPrivateKey() throws -> PrivateKey {
    // Try loading the private keys from Keychain
    let keyTag = "\(Bundle.main.bundleIdentifier!).private-key" // ID for private key in Keychain e.g. de.pschwind.ClipboardPortal.private-key
    do {
        // Load private key from Keychain
        let query = [kSecClass: kSecClassGenericPassword,
                     kSecAttrAccount: keyTag,
                     kSecUseDataProtectionKeychain: true,
                     kSecReturnData: true] as [String: Any]
        var item: CFTypeRef?
        switch SecItemCopyMatching(query as CFDictionary, &item) {
        case errSecSuccess:
            guard let data = item as? Data else { throw CryptoErrors.keychainReadFailed(errorMessage: nil) }
            return try PrivateKey(rawRepresentation: data)  // Convert back to a key.
        case errSecItemNotFound: throw CryptoErrors.privateKeyNotFound
        case let status: throw CryptoErrors.keychainReadFailed(errorMessage: "Keychain read failed: \(status)")
        }
    }
    catch CryptoErrors.privateKeyNotFound {} // No message if private key simply does not exist yet
    catch { print(error) } // Fall back to generating private key on error, e.g. if the key does not exist yet
    
    // Generate and save new private keys if none was found
    let privateKey = PrivateKey() // Generate private key
    let query = [kSecClass: kSecClassGenericPassword, // Treat the key data as a generic password because there is no more specific support
                 kSecAttrAccount: keyTag,
                 kSecAttrAccessible: kSecAttrAccessibleWhenUnlocked,
                 kSecUseDataProtectionKeychain: true,
                 kSecValueData: privateKey.rawRepresentation] as [String: Any]
    let status = SecItemAdd(query as CFDictionary, nil)
    guard status == errSecSuccess else {
        throw CryptoErrors.privateKeySaveFailed(errorMessage: "Unable to store item: \(status)")
    }
    // Return generated private key
    return privateKey
}

/// Get own public key to give to others
func getPublicKey() throws -> PublicKey {
    return try getPrivateKey().publicKey
}

/// Helper function to get the secret symmetric key between a friend and me
private func getSymmetricKey(friendPublicKey: PublicKey) throws -> SymmetricKey {
    let sharedSecret = try getPrivateKey().sharedSecretFromKeyAgreement(with: friendPublicKey) // Generate shared secret for encryption. Using a shared secret that only we can generate (because we have the private key) also guarantees authenticity.
    return sharedSecret.hkdfDerivedSymmetricKey(using: SHA256.self,
                                                salt: Bundle.main.bundleIdentifier!.data(using: .utf8)!,
                                                sharedInfo: Data(),
                                                outputByteCount: 32)
}

/// Encrypt data for a friend using a shared secret that also guarantees authenticity
func encrypt(data: Data, friendPublicKey: PublicKey) throws -> Data {
    let symmetricKey = try getSymmetricKey(friendPublicKey: friendPublicKey)
    let sealedBox = try ChaChaPoly.seal(data, using: symmetricKey) // Create sealed box
    let encryptedData = sealedBox.combined
    // Debug messages
    // print("decrypted 1", data.base64EncodedString())
    // print("encrypted 1", encryptedData.base64EncodedString())
    // print("encrypted 1 key", symmetricKey.withUnsafeBytes { Data(Array($0)) }.map { String(format: "%02hhx", $0) }.joined())
    return encryptedData // Return sealed box data
}

/// Decrypt data from a friend and verify its authenticity (i.e. make sure that it was really that friend who sent the message)
func decrypt(encryptedData: Data, friendPublicKey: PublicKey) throws -> Data {
    let sealedBox = try ChaChaPoly.SealedBox(combined: encryptedData) // Create sealed box from data
    do {
        let symmetricKey = try getSymmetricKey(friendPublicKey: friendPublicKey)
        let data = try ChaChaPoly.open(sealedBox, using: symmetricKey) // Unpack data from sealed box
        // Debug messages
        // print("decrypted 2", data.base64EncodedString())
        // print("encrypted 2", encryptedData.base64EncodedString())
        // print("encrypted 2 key", symmetricKey.withUnsafeBytes { Data(Array($0)) }.map { String(format: "%02hhx", $0) }.joined())
        return data
    }
    catch CryptoKitError.authenticationFailure  { throw CryptoErrors.invalidEncryptedData(errorType: "authentication") }
    catch CryptoKitError.incorrectParameterSize { throw CryptoErrors.invalidEncryptedData(errorType: "parameter size") }
    catch CryptoKitError.incorrectKeySize       { throw CryptoErrors.invalidEncryptedData(errorType: "incorrect key size") }
    catch CryptoKitError.invalidParameter       { throw CryptoErrors.invalidEncryptedData(errorType: "invalid parameter") }
    catch CryptoKitError.unwrapFailure          { throw CryptoErrors.invalidEncryptedData(errorType: "unwrap failure") }
    catch { throw error }
}
