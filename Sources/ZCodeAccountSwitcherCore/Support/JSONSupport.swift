import Foundation

public enum JSONSupport {
    public static let decoder: JSONDecoder = {
        let decoder = JSONDecoder()
        return decoder
    }()

    public static let encoder: JSONEncoder = {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        return encoder
    }()

    public static func readDecodable<T: Decodable>(_ type: T.Type, from url: URL) throws -> T {
        let data = try Data(contentsOf: url)
        return try decoder.decode(T.self, from: data)
    }

    public static func writeEncodable<T: Encodable>(_ value: T, to url: URL, pretty: Bool = true) throws {
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        let encoder = JSONEncoder()
        encoder.outputFormatting = pretty ? [.prettyPrinted, .sortedKeys] : []
        let data = try encoder.encode(value)
        try atomicWrite(data, to: url)
    }

    public static func parseText(_ text: String) throws -> Any {
        let data = Data(text.utf8)
        return try JSONSerialization.jsonObject(with: data)
    }

    public static func parseDictionary(_ text: String) throws -> [String: Any] {
        guard let dictionary = try parseText(text) as? [String: Any] else {
            throw AccountError.invalidSnapshot
        }
        return dictionary
    }

    public static func readDictionary(from url: URL, fallback: [String: Any] = [:]) throws -> [String: Any] {
        guard FileManager.default.fileExists(atPath: url.path) else {
            return fallback
        }
        let data = try Data(contentsOf: url)
        guard let dictionary = try JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            throw AccountError.invalidSnapshot
        }
        return dictionary
    }

    public static func writeJSONObject(_ object: Any, to url: URL, pretty: Bool = true) throws {
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        let options: JSONSerialization.WritingOptions = pretty ? [.prettyPrinted, .sortedKeys] : []
        let data = try JSONSerialization.data(withJSONObject: object, options: options)
        try atomicWrite(data, to: url)
    }

    public static func compactJSONString(_ object: Any) throws -> String {
        let data = try JSONSerialization.data(withJSONObject: object, options: [])
        return String(decoding: data, as: UTF8.self)
    }

    public static func atomicWrite(_ data: Data, to url: URL) throws {
        let tmp = url.deletingLastPathComponent().appendingPathComponent(
            url.lastPathComponent + ".zcas.tmp-\(ProcessInfo.processInfo.processIdentifier)-\(TimeSupport.millisecondsNow)"
        )
        try data.write(to: tmp, options: .atomic)
        if FileManager.default.fileExists(atPath: url.path) {
            try FileManager.default.removeItem(at: url)
        }
        try FileManager.default.moveItem(at: tmp, to: url)
    }

    public static func string(_ value: Any?) -> String? {
        guard let value else { return nil }
        if let string = value as? String { return string }
        if let number = value as? NSNumber { return number.stringValue }
        return nil
    }

    public static func bool(_ value: Any?) -> Bool {
        if let bool = value as? Bool { return bool }
        if let number = value as? NSNumber { return number.boolValue }
        if let string = value as? String { return ["true", "1", "yes"].contains(string.lowercased()) }
        return false
    }

    public static func array(_ value: Any?) -> [Any]? {
        value as? [Any]
    }
}
