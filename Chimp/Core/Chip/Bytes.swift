import Foundation

extension Data {
    /// Octets en hexadécimal minuscule, sans séparateur (format du bridge et du terminal).
    nonisolated var hexString: String {
        map { String(format: "%02x", $0) }.joined()
    }

    /// Lit une chaîne hexadécimale (majuscules ou minuscules, sans séparateur). `nil` si elle est invalide.
    init?(hex: String) {
        guard hex.count.isMultiple(of: 2), hex.allSatisfy(\.isHexDigit) else { return nil }
        var bytes = [UInt8]()
        bytes.reserveCapacity(hex.count / 2)
        var index = hex.startIndex
        while index < hex.endIndex {
            let next = hex.index(index, offsetBy: 2)
            guard let byte = UInt8(hex[index..<next], radix: 16) else { return nil }
            bytes.append(byte)
            index = next
        }
        self.init(bytes)
    }
}
