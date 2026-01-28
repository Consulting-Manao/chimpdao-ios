/**
 * Centralized Logging Utility
 * Uses OSLog for production-ready logging with proper categories and privacy protection
 */

import Foundation
import os.log

/// Logging categories for different subsystems
enum LogCategory: String {
    case nfc = "NFC"
    case blockchain = "Blockchain"
    case crypto = "Crypto"
    case ui = "UI"
    case network = "Network"
}

/// Centralized logger using OSLog
final class Logger {
    private static let subsystem = "com.consulting-manao.chimp"
    
    /// Get logger for a specific category
    /// - Parameter category: Log category
    /// - Returns: OSLog instance for the category
    private static func logger(for category: LogCategory) -> OSLog {
        return OSLog(subsystem: subsystem, category: category.rawValue)
    }
    
    /// Redact sensitive information from log messages
    /// - Parameter message: Original message that may contain secrets
    /// - Returns: Message with sensitive data redacted
    private static func redact(_ message: String) -> String {
        var redacted = message
        
        // Redact Stellar secret seeds (S followed by 55 base32 characters)
        // Pattern: S[A-Z2-7]{55}
        let secretSeedPattern = #"S[A-Z2-7]{55}"#
        if let regex = try? NSRegularExpression(pattern: secretSeedPattern, options: []) {
            let range = NSRange(location: 0, length: redacted.utf16.count)
            redacted = regex.stringByReplacingMatches(in: redacted, options: [], range: range, withTemplate: "[REDACTED_SECRET_SEED]")
        }
        
        // Redact patterns that look like secret keys or seeds in various formats
        // Look for common patterns like "secretKey: ...", "secretSeed: ...", etc.
        let secretKeyPatterns = [
            #"(?i)secret[_\s]?key\s*[:=]\s*[^\s,}]+"#,
            #"(?i)secret[_\s]?seed\s*[:=]\s*[^\s,}]+"#,
            #"(?i)private[_\s]?key\s*[:=]\s*[^\s,}]+"#,
            #"(?i)mnemonic\s*[:=]\s*[^\s,}]+"#
        ]
        
        for pattern in secretKeyPatterns {
            if let regex = try? NSRegularExpression(pattern: pattern, options: []) {
                let range = NSRange(location: 0, length: redacted.utf16.count)
                redacted = regex.stringByReplacingMatches(in: redacted, options: [], range: range, withTemplate: "[REDACTED_SECRET]")
            }
        }
        
        return redacted
    }
    
    /// Log an informational message
    /// - Parameters:
    ///   - message: Message to log
    ///   - category: Log category
    static func logInfo(_ message: String, category: LogCategory) {
        let redactedMessage = redact(message)
        os_log("%{public}@", log: logger(for: category), type: .info, redactedMessage)
    }
    
    /// Log an error message
    /// - Parameters:
    ///   - message: Message to log
    ///   - category: Log category
    static func logError(_ message: String, category: LogCategory) {
        let redactedMessage = redact(message)
        os_log("%{public}@", log: logger(for: category), type: .error, redactedMessage)
    }
    
    /// Log a debug message (only in debug builds)
    /// - Parameters:
    ///   - message: Message to log
    ///   - category: Log category
    static func logDebug(_ message: String, category: LogCategory) {
        #if DEBUG
        let redactedMessage = redact(message)
        os_log("%{public}@", log: logger(for: category), type: .debug, redactedMessage)
        #endif
    }
    
    /// Log a warning message
    /// - Parameters:
    ///   - message: Message to log
    ///   - category: Log category
    static func logWarning(_ message: String, category: LogCategory) {
        let redactedMessage = redact(message)
        os_log("%{public}@", log: logger(for: category), type: .default, redactedMessage)
    }
    
    /// Log an error with additional details
    /// - Parameters:
    ///   - message: Message to log
    ///   - error: Error object
    ///   - category: Log category
    static func logError(_ message: String, error: Error, category: LogCategory) {
        let errorDescription = (error as? LocalizedError)?.errorDescription ?? error.localizedDescription
        let redactedMessage = redact(message)
        let redactedError = redact(errorDescription)
        os_log("%{public}@: %{public}@", log: logger(for: category), type: .error, redactedMessage, redactedError)
    }
}
