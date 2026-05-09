import Foundation
import os

/// Shared loggers. We use `os.Logger` so messages flow into Console.app and log streams
/// can be filtered by category.
public enum Log {
    public static let scan     = Logger(subsystem: PurpleDedup.bundleIdentifier, category: "scan")
    public static let hash     = Logger(subsystem: PurpleDedup.bundleIdentifier, category: "hash")
    public static let cluster  = Logger(subsystem: PurpleDedup.bundleIdentifier, category: "cluster")
    public static let storage  = Logger(subsystem: PurpleDedup.bundleIdentifier, category: "storage")
    public static let backup   = Logger(subsystem: PurpleDedup.bundleIdentifier, category: "backup")
    public static let cli      = Logger(subsystem: PurpleDedup.bundleIdentifier, category: "cli")
    public static let app      = Logger(subsystem: PurpleDedup.bundleIdentifier, category: "app")
}
