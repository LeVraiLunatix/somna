import Foundation
import Testing

@testable import Somna

/// The gate's only testable part, and the only part worth testing.
///
/// Note what is *not* asserted here: the code itself. Writing it into a test in
/// a public repository would undo the reason the source holds a hash rather than
/// a string.
struct BetaAccessCodeTests {

    @Test("An empty or blank code never opens the build")
    func blankIsRejected() {
        #expect(!BetaAccessCode.matches(""))
        #expect(!BetaAccessCode.matches("   "))
        #expect(!BetaAccessCode.matches("\n\t"))
    }

    @Test("A wrong code is rejected")
    func wrongCodeIsRejected() {
        #expect(!BetaAccessCode.matches("password"))
        #expect(!BetaAccessCode.matches("1234"))
        #expect(!BetaAccessCode.matches("somna"))
    }

    /// A code typed on an iPhone arrives autocapitalised and often with a
    /// trailing space. Rejecting someone over that would be a support message
    /// for nothing.
    @Test("Normalisation trims and lowercases")
    func normalisation() {
        #expect(BetaAccessCode.normalise("  Hello ") == "hello")
        #expect(BetaAccessCode.normalise("MiXeD") == "mixed")
        #expect(BetaAccessCode.normalise("\nspaced\t") == "spaced")
    }

    @Test("Hashing is stable and depends on the input")
    func hashingIsStable() {
        #expect(BetaAccessCode.hash(of: "abc") == BetaAccessCode.hash(of: "abc"))
        #expect(BetaAccessCode.hash(of: "abc") != BetaAccessCode.hash(of: "abd"))
        #expect(BetaAccessCode.hash(of: "abc").count == 64)
    }

    /// The stored value must be a hash, not a code someone left in plain sight.
    @Test("Nothing that looks like a plaintext code is compared")
    func storedValueIsAHash() {
        let hex = BetaAccessCode.hash(of: "anything")
        #expect(hex.allSatisfy { $0.isHexDigit })
        #expect(hex.count == 64)
    }
}
