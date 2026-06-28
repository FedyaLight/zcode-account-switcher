import Foundation

public enum TimeSupport {
    public static var millisecondsNow: Int64 {
        Int64(Date().timeIntervalSince1970 * 1000)
    }

    public static func timestampName(date: Date = Date()) -> String {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "yyyyMMdd-HHmmss"
        return formatter.string(from: date)
    }
}
