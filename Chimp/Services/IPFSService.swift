//
//  IPFSService.swift
//  Chimp
//
//  Service for downloading NFT metadata from IPFS
//

import Foundation
import OSLog

/// NFT metadata structure following SEP-50 standard
struct NFTMetadata: Codable {
    let name: String?
    let description: String?
    let image: String?
    let attributes: [NFTAttribute]?

    enum CodingKeys: String, CodingKey {
        case name
        case description
        case image
        case attributes
    }
}

/// NFT attribute structure
struct NFTAttribute: Codable {
    let trait_type: String
    let value: String

    enum CodingKeys: String, CodingKey {
        case trait_type = "trait_type"
        case value
    }
}

final class IPFSService {
    private let session: URLSession

    init() {
        let config = URLSessionConfiguration.default
        config.timeoutIntervalForRequest = 30.0
        config.timeoutIntervalForResource = 60.0
        self.session = URLSession(configuration: config)
    }

    /// Download NFT metadata from IPFS URL
    /// - Parameter ipfsUrl: IPFS URL string
    /// - Returns: NFT metadata
    /// - Throws: AppError if download or parsing fails
    func downloadNFTMetadata(from ipfsUrl: String) async throws -> NFTMetadata {

        guard let url = URL(string: ipfsUrl) else {
            throw AppError.ipfs(.invalidHash)
        }

        let (data, response) = try await session.data(from: url)

        // Check HTTP response
        if let httpResponse = response as? HTTPURLResponse {
            Logger.logDebug("HTTP status: \(httpResponse.statusCode)", category: .network)
            guard (200...299).contains(httpResponse.statusCode) else {
                throw AppError.ipfs(.downloadFailed("HTTP \(httpResponse.statusCode)"))
            }
        }

        // Check if response looks like HTML (error page)
        if let responseString = String(data: data, encoding: .utf8) {
            if responseString.hasPrefix("<!DOCTYPE") || responseString.hasPrefix("<html") || responseString.contains("<html") {
                Logger.logError("Received HTML instead of JSON. This might be an IPFS gateway error page.", category: .network)
                throw AppError.ipfs(.parseFailed("IPFS gateway returned HTML error page instead of JSON"))
            }
        }

        // Parse JSON
        let decoder = JSONDecoder()
        do {
            let metadata = try decoder.decode(NFTMetadata.self, from: data)
            Logger.logDebug("Successfully parsed NFT metadata", category: .network)
            return metadata
        } catch {
            Logger.logError("Failed to parse NFT metadata", category: .network)
            throw AppError.ipfs(.parseFailed("Failed to parse NFT metadata"))
        }
    }

    /// Download image data from IPFS URL
    /// - Parameter ipfsUrl: IPFS URL string
    /// - Returns: Image data
    /// - Throws: AppError if download fails
    func downloadImageData(from ipfsUrl: String) async throws -> Data {

        guard let url = URL(string: ipfsUrl) else {
            throw AppError.ipfs(.invalidHash)
        }

        let (data, response) = try await session.data(from: url)

        // Check HTTP response
        if let httpResponse = response as? HTTPURLResponse {
            guard (200...299).contains(httpResponse.statusCode) else {
                throw AppError.ipfs(.downloadFailed("HTTP \(httpResponse.statusCode)"))
            }
        }

        Logger.logDebug("Successfully downloaded image data (\(data.count) bytes)", category: .network)
        return data
    }

    /// Convert token/metadata URI to fetchable HTTPS URL.
    /// Supports: https:// (pass-through), ipfs:// (gateway), bare IPFS hashes (Qm, bafy, bafk).
    /// Rejects: http:// and any other scheme.
    /// - Parameter uri: Token URI or metadata image URI (https://, ipfs://, or bare hash)
    /// - Returns: HTTPS URL string
    /// - Throws: AppError.ipfs if scheme is unsupported or result URL is invalid
    func convertToHTTPGateway(_ uri: String) throws -> String {
        let trimmed = uri.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.isEmpty {
            throw AppError.ipfs(.invalidHash)
        }

        var result: String

        if trimmed.hasPrefix("https://") {
            result = trimmed
        } else if trimmed.hasPrefix("http://") {
            throw AppError.ipfs(.unsupportedUriScheme("http:// is not supported; use https://"))
        } else if trimmed.hasPrefix("ipfs://") {
            let path = trimmed.replacingOccurrences(of: "ipfs://", with: "")
            result = "https://ipfs.io/ipfs/\(path)"
        } else if trimmed.hasPrefix("Qm") || trimmed.hasPrefix("bafy") || trimmed.hasPrefix("bafk") {
            result = "https://ipfs.io/ipfs/\(trimmed)"
        } else {
            throw AppError.ipfs(.unsupportedUriScheme("Only https://, ipfs://, or bare IPFS hashes are supported"))
        }

        guard let url = URL(string: result), url.scheme?.lowercased() == "https" else {
            throw AppError.ipfs(.invalidHash)
        }
        return result
    }
}

