import Foundation
import Testing
import SwiftRage

/// A temporary directory that is deleted when the value is released.
final class TemporaryDirectory {
    let url: URL

    init() throws {
        url = FileManager.default.temporaryDirectory
            .appending(path: "SwiftRageTests-\(UUID().uuidString)", directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
    }

    deinit {
        try? FileManager.default.removeItem(at: url)
    }

    /// A URL for `name` in this directory.
    func file(_ name: String) -> URL {
        url.appending(path: name)
    }

    /// Writes `contents` to `name` in this directory and returns its URL.
    @discardableResult
    func write(_ contents: String, to name: String) throws -> URL {
        let fileURL = file(name)
        try contents.write(to: fileURL, atomically: true, encoding: .utf8)
        return fileURL
    }

    /// The names of the files in this directory.
    func contents() throws -> [String] {
        try FileManager.default.contentsOfDirectory(atPath: url.path(percentEncoded: false)).sorted()
    }
}

enum Fixtures {
    /// The passphrase of the passphrase-protected SSH key fixtures.
    static let sshKeyPassphrase = "snakeoil"

    /// The plaintext of the fixtures encrypted with the age CLI.
    static let agePlaintext = "Hello from age\n"

    /// The identity that decrypts x25519.age.txt and x25519-crlf.age.txt, to "World\n".
    static let x25519VectorIdentity = "AGE-SECRET-KEY-1GRU0NKAAXMLS8UPCQEHHY40XYWUC8NM0DM7XXM66CY3DT9UDH0HQFRT6M0"

    /// The passphrase that decrypts scrypt.age.txt, to "Hello\n".
    static let scryptVectorPassphrase = "x"

    static func url(_ name: String) -> URL {
        Bundle.module.url(forResource: name, withExtension: nil, subdirectory: "Fixtures")!
    }

    static func path(_ name: String) -> String {
        url(name).path(percentEncoded: false)
    }

    static func string(_ name: String) throws -> String {
        try String(contentsOf: url(name), encoding: .utf8)
    }
}

/// Expects `body` to throw an ``AgeError`` with `code`.
func expectAgeError<R>(
    _ code: AgeError.Code,
    sourceLocation: SourceLocation = #_sourceLocation,
    _ body: () throws -> R
) {
    let error = #expect(throws: AgeError.self, sourceLocation: sourceLocation) {
        _ = try body()
    }
    #expect(error?.code == code, "Got \(String(describing: error))", sourceLocation: sourceLocation)
    #expect(error?.message.isEmpty == false, sourceLocation: sourceLocation)
}
