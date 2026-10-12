import Foundation

typealias JSONDict = [String: Any]

/// 宽松 JSON 访问：脚本返回的字段可能是 String / Number / Bool，这里统一转成 String
enum JSONValue {
    static func object(_ text: String) -> Any? {
        guard let data = text.data(using: .utf8) else { return nil }
        return try? JSONSerialization.jsonObject(with: data, options: [.fragmentsAllowed])
    }

    static func string(_ any: Any?) -> String? {
        guard let any else { return nil }
        switch any {
        case let value as String:
            return value
        case let value as NSNumber:
            if CFGetTypeID(value) == CFBooleanGetTypeID() {
                return value.boolValue ? "true" : "false"
            }
            return value.stringValue
        default:
            return nil
        }
    }

    static func int(_ any: Any?) -> Int? {
        if let value = any as? NSNumber { return value.intValue }
        if let value = any as? String { return Int(value.trimmingCharacters(in: .whitespaces)) }
        return nil
    }

    static func double(_ any: Any?) -> Double? {
        if let value = any as? NSNumber { return value.doubleValue }
        if let value = any as? String { return Double(value.trimmingCharacters(in: .whitespaces)) }
        return nil
    }

    static func dicts(_ any: Any?) -> [JSONDict] {
        (any as? [Any] ?? []).compactMap { $0 as? JSONDict }
    }

    static func array(_ any: Any?) -> [Any] {
        any as? [Any] ?? []
    }
}

extension Dictionary where Key == String, Value == Any {
    func str(_ key: String) -> String? { JSONValue.string(self[key]) }
    func num(_ key: String) -> Int? { JSONValue.int(self[key]) }
    func val(_ key: String) -> Double? { JSONValue.double(self[key]) }
    func dict(_ key: String) -> JSONDict? { self[key] as? JSONDict }
    func list(_ key: String) -> [JSONDict] { JSONValue.dicts(self[key]) }

    /// 依次取第一个非空字段
    func strAny(_ keys: [String]) -> String? {
        for key in keys {
            if let value = str(key), !value.isEmpty { return value }
        }
        return nil
    }
}
