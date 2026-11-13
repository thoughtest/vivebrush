import CryptoKit
import Foundation

// Verification needs only the public key; it never accesses the Keychain.
guard CommandLine.arguments.count == 4,
      let key = Data(base64Encoded: CommandLine.arguments[1]),
      let signature = Data(base64Encoded: CommandLine.arguments[3]) else {
    fputs("Usage: verify-signature <public key> <file> <signature>\n", stderr)
    exit(2)
}
do {
    let verifier = try Curve25519.Signing.PublicKey(rawRepresentation: key)
    let data = try Data(contentsOf: URL(fileURLWithPath: CommandLine.arguments[2]))
    guard verifier.isValidSignature(signature, for: data) else {
        fputs("Invalid Ed25519 signature.\n", stderr)
        exit(1)
    }
} catch {
    fputs("Signature verification failed: \(error.localizedDescription)\n", stderr)
    exit(1)
}
