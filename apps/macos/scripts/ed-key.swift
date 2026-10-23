// SPDX-License-Identifier: GPL-3.0-or-later
//
// Throwaway EdDSA keys for the offline update test (scripts/update-test.sh), without the
// Keychain: Sparkle's generate_keys always stores its key there.
//
//   swift scripts/ed-key.swift generate <private-key-file>
//     writes the base64 private key (the 32-byte seed Sparkle's --ed-key-file reads) and
//     prints the base64 public key for SUPublicEDKey.
//   swift scripts/ed-key.swift verify <public-key> <file> <signature>
//     checks a sparkle:edSignature the way the app will; exits 1 when it does not match.

import CryptoKit
import Foundation

func fail(_ message: String) -> Never {
  FileHandle.standardError.write(Data("ed-key: \(message)\n".utf8))
  exit(1)
}

let arguments = Array(CommandLine.arguments.dropFirst())
switch arguments.first {
case "generate" where arguments.count == 2:
  let key = Curve25519.Signing.PrivateKey()
  let url = URL(fileURLWithPath: arguments[1])
  do {
    try Data(key.rawRepresentation.base64EncodedString().utf8).write(to: url)
    try FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: url.path)
  } catch {
    fail("cannot write \(url.path): \(error)")
  }
  print(key.publicKey.rawRepresentation.base64EncodedString())
case "verify" where arguments.count == 4:
  guard let raw = Data(base64Encoded: arguments[1]),
    let publicKey = try? Curve25519.Signing.PublicKey(rawRepresentation: raw)
  else { fail("not a public key") }
  guard let file = FileManager.default.contents(atPath: arguments[2]) else {
    fail("cannot read \(arguments[2])")
  }
  guard let signature = Data(base64Encoded: arguments[3]),
    publicKey.isValidSignature(signature, for: file)
  else { fail("signature does not match \(arguments[2])") }
  print("ed-key: signature matches \(arguments[2])")
default:
  fail("usage: ed-key.swift generate <private-key-file> | verify <public-key> <file> <signature>")
}
