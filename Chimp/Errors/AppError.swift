/**
 * Unified Error Handling System
 *
 * This file contains the complete error hierarchy for the Chimp app.
 * All errors should be defined here to ensure consistency and maintainability.
 */

import Foundation

/// Top-level error enum for the entire application
/// All app errors should be represented as cases of this enum
enum AppError: Error, LocalizedError {
    // MARK: - Blockchain Errors

    /// Errors related to blockchain operations and smart contracts
    case blockchain(BlockchainError)

    // MARK: - Service Errors

    /// Errors related to NFC operations
    case nfc(NFCError)

    /// Errors related to wallet operations
    case wallet(WalletError)

    /// Errors related to IPFS operations
    case ipfs(IPFSError)

    /// Errors related to secure storage operations
    case secureStorage(SecureKeyStorageError)

    /// Errors related to cryptographic operations
    case crypto(CryptoError)

    /// Errors related to DER signature parsing
    case derSignature(DERSignatureParserError)

    // MARK: - Generic Errors

    /// Unexpected errors that don't fit other categories
    case unexpected(String)

    /// User input validation errors
    case validation(String)

    var errorDescription: String? {
        switch self {
        case .blockchain(let error):
            return error.localizedDescription
        case .nfc(let error):
            return error.localizedDescription
        case .wallet(let error):
            return error.localizedDescription
        case .ipfs(let error):
            return error.localizedDescription
        case .secureStorage(let error):
            return error.localizedDescription
        case .crypto(let error):
            return error.localizedDescription
        case .derSignature(let error):
            return error.localizedDescription
        case .unexpected(let message):
            return "An unexpected error occurred: \(message)"
        case .validation(let message):
            return message
        }
    }
}

// MARK: - Blockchain Errors

enum BlockchainError: LocalizedError {
    // MARK: - Contract Errors

    /// Smart contract execution errors with specific error codes
    case contract(ContractError)

    // MARK: - Transaction Errors

    /// Transaction was rejected by the network
    case transactionRejected(String?)

    /// Transaction failed during execution
    case transactionFailed

    /// Transaction submission timed out
    case transactionTimeout

    // MARK: - Network Errors

    /// Invalid response from blockchain network
    case invalidResponse

    /// Network connectivity issues
    case networkError(String)

    var errorDescription: String? {
        switch self {
        case .contract(let contractError):
            return contractError.localizedDescription
        case .transactionRejected(let message):
            return message ?? "Transaction rejected. Check network."
        case .transactionFailed:
            return "Transaction failed. Check funds and try again."
        case .transactionTimeout:
            return "Transaction timed out. Check status later."
        case .invalidResponse:
            return "Invalid network response."
        case .networkError(let message):
            return "Blockchain network error: \(message)"
        }
    }
}

// MARK: - Contract Errors (nfc-nft NonFungibleTokenError 101–109)

enum ContractError: LocalizedError {
    case invalidSignature       // 101
    case nonExistentToken       // 102
    case tokenIDsAreDepleted    // 103
    case tokenAlreadyMinted     // 104
    case tokenNotClaimed        // 109

    case unknown(code: UInt32)

    var errorDescription: String? {
        switch self {
        case .invalidSignature:
            return "Invalid signature detected."
        case .nonExistentToken:
            return "This token does not exist."
        case .tokenIDsAreDepleted:
            return "No more tokens can be minted."
        case .tokenAlreadyMinted:
            return "Token was already minted."
        case .tokenNotClaimed:
            return "Token exists but has not been claimed yet."
        case .unknown(let code):
            return "Contract error (code \(code))."
        }
    }

    var code: UInt32 {
        switch self {
        case .invalidSignature: return 101
        case .nonExistentToken: return 102
        case .tokenIDsAreDepleted: return 103
        case .tokenAlreadyMinted: return 104
        case .tokenNotClaimed: return 109
        case .unknown(let code): return code
        }
    }

    static func fromCode(_ code: UInt32) -> ContractError {
        switch code {
        // The 2xx codes are the numbers before the contracts were renumbered. Mainnet runs
        // them until the upgrade lands; delete these once it has.
        case 101, 200: return .invalidSignature
        case 102, 201: return .nonExistentToken
        case 103, 203: return .tokenIDsAreDepleted
        case 104, 210: return .tokenAlreadyMinted
        case 109, 212: return .tokenNotClaimed
        default: return .unknown(code: code)
        }
    }

    static func fromErrorString(_ errorString: String) -> ContractError? {
        let range = NSRange(location: 0, length: errorString.utf16.count)
        let patterns = [
            #"Error\(Contract,\s*#?(\d+)\)"#,
            #"\["failing with contract error", (\d+)\]"#,
            #"(?<!\d)(\d{3})(?!\d)"#
        ]
        for pattern in patterns {
            guard let regex = try? NSRegularExpression(pattern: pattern, options: []),
                  let match = regex.firstMatch(in: errorString, options: [], range: range),
                  match.numberOfRanges > 1,
                  let captureRange = Range(match.range(at: 1), in: errorString),
                  let code = UInt32(errorString[captureRange]) else { continue }
            if pattern == #"(?<!\d)(\d{3})(?!\d)"# {
                guard (101...109).contains(code) || (200...220).contains(code) else { continue }
            }
            return ContractError.fromCode(code)
        }
        // Fallbacks only when string looks like a contract/Stellar error; match exact codes to avoid false positives (e.g. 1040 → 104)
        let looksLikeContractError = errorString.contains("Contract") ||
            errorString.contains("contract") ||
            errorString.contains("failing") ||
            errorString.contains("InvalidSignature") ||
            errorString.contains("NonExistentToken") ||
            errorString.contains("TokenIDsAreDepleted") ||
            errorString.contains("TokenAlreadyMinted") ||
            errorString.contains("TokenNotClaimed")
        guard looksLikeContractError else { return nil }
        if errorString.contains("InvalidSignature") { return .invalidSignature }
        if errorString.contains("NonExistentToken") { return .nonExistentToken }
        if errorString.contains("TokenIDsAreDepleted") { return .tokenIDsAreDepleted }
        if errorString.contains("TokenAlreadyMinted") { return .tokenAlreadyMinted }
        if errorString.contains("TokenNotClaimed") { return .tokenNotClaimed }
        // Exact code match (whole number, not 1040 or 1030)
        for code in [101, 102, 103, 104, 109, 200, 201, 203, 210, 212] as [UInt32] {
            if ContractError.fromErrorStringMatchesExactCode(errorString, code) { return fromCode(code) }
        }
        return nil
    }

    /// Returns true if the string contains the given contract error code as a whole number (not e.g. 104 inside 1040).
    private static func fromErrorStringMatchesExactCode(_ errorString: String, _ code: UInt32) -> Bool {
        let codeStr = String(code)
        guard let range = errorString.range(of: codeStr) else { return false }
        let after = range.upperBound
        let before = range.lowerBound
        if after < errorString.endIndex {
            let next = errorString[after]
            if next.isNumber { return false }
        }
        if before > errorString.startIndex {
            let prev = errorString[errorString.index(before: before)]
            if prev.isNumber { return false }
        }
        return true
    }
}

// MARK: - NFC Errors

enum NFCError: LocalizedError {
    /// NFC is not available on this device
    case notAvailable

    /// NFC tag read/write failed
    case readWriteFailed(String)

    /// NFC chip communication error
    case chipError(String)

    var errorDescription: String? {
        switch self {
        case .notAvailable:
            return "NFC is not available on this device."
        case .readWriteFailed(let message):
            return "NFC read/write failed: \(message)"
        case .chipError(let message):
            return "NFC chip error: \(message)"
        }
    }
}

// MARK: - Wallet Errors

enum WalletError: LocalizedError {
    /// No wallet is configured
    case noWallet

    /// Failed to sign transaction
    case signingFailed(String)

    var errorDescription: String? {
        switch self {
        case .noWallet:
            return "No wallet configured."
        case .signingFailed(let message):
            return "Failed to sign transaction: \(message)"
        }
    }
}

// MARK: - IPFS Errors

enum IPFSError: LocalizedError {
    /// Failed to download from IPFS
    case downloadFailed(String)

    /// Invalid IPFS hash or URL
    case invalidHash

    /// Unsupported URI scheme (e.g. http:// or unknown)
    case unsupportedUriScheme(String)

    /// Failed to parse IPFS metadata
    case parseFailed(String)

    var errorDescription: String? {
        switch self {
        case .downloadFailed(let message):
            return "Failed to download from IPFS: \(message)"
        case .invalidHash:
            return "Invalid IPFS hash or URL format."
        case .unsupportedUriScheme(let message):
            return "Unsupported URI scheme: \(message)"
        case .parseFailed(let message):
            return "Failed to parse IPFS data: \(message)"
        }
    }
}

// MARK: - Secure Storage Errors

enum SecureKeyStorageError: LocalizedError {
    /// Failed to store data securely
    case storageFailed(String)

    /// Failed to retrieve data from secure storage
    case retrievalFailed(String)

    /// Failed to delete data from secure storage
    case deletionFailed(String)

    /// Authentication required for secure storage access
    case authenticationRequired

    var errorDescription: String? {
        switch self {
        case .storageFailed(let message):
            return "Failed to securely store data: \(message)"
        case .retrievalFailed(let message):
            return "Failed to retrieve data from secure storage: \(message)"
        case .deletionFailed(let message):
            return "Failed to delete data from secure storage: \(message)"
        case .authenticationRequired:
            return "Authentication required."
        }
    }
}

// MARK: - Crypto Errors

enum CryptoError: LocalizedError {
    /// Invalid cryptographic operation
    case invalidOperation(String)

    /// Invalid signature format
    case invalidSignature

    /// Invalid cryptographic key
    case invalidKey(String)

    var errorDescription: String? {
        switch self {
        case .invalidOperation(let message):
            return "Invalid cryptographic operation: \(message)"
        case .invalidSignature:
            return "Invalid signature format."
        case .invalidKey(let message):
            return "Invalid cryptographic key: \(message)"
        }
    }
}

// MARK: - DER Signature Parser Errors

enum DERSignatureParserError: LocalizedError {
    /// Invalid DER format
    case invalidFormat

    /// Failed to parse DER signature
    case parseFailed(String)

    /// Invalid signature components
    case invalidComponents

    var errorDescription: String? {
        switch self {
        case .invalidFormat:
            return "Invalid DER signature format."
        case .parseFailed(let message):
            return "Failed to parse DER signature: \(message)"
        case .invalidComponents:
            return "Invalid DER signature components."
        }
    }
}

// MARK: - Error → User Message (display boundary only)

extension Error {
    /// User-facing message. Use at UI boundary (error banner, NFC completion).
    var userMessage: String {
        (self as? LocalizedError)?.errorDescription ?? localizedDescription
    }
}
