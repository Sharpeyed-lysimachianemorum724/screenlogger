import Foundation

/// Pure pixel-sample helpers used by `DifferentialOCRService` (unit-testable without Vision).
public enum DifferentialOCRMath {
    /// Pixel-sample similarity in 0...1. Samples within |diff| <= 3 count as matching.
    public static func similarity(_ a: [UInt8], _ b: [UInt8]) -> Double {
        guard !a.isEmpty, a.count == b.count else { return 0 }
        var same = 0
        for i in 0..<a.count {
            if abs(Int(a[i]) - Int(b[i])) <= 3 { same += 1 }
        }
        return Double(same) / Double(a.count)
    }

    /// FNV-1a 64-bit hash of a luminance sample.
    public static func fnv1a(_ bytes: [UInt8]) -> UInt64 {
        var hash: UInt64 = 0xcbf2_9ce4_8422_2325
        for b in bytes {
            hash ^= UInt64(b)
            hash &*= 0x100_0000_01b3
        }
        return hash
    }
}
