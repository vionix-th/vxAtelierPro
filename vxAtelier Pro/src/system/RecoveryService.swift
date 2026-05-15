import Foundation
import SwiftData

#if os(macOS)
    import AppKit
#endif

@MainActor
enum AppRecoveryService {
    static func resetUserDefaults() {
        AppDefaults.resetUserDefaults()
    }

    static func cleanLocalStorage(using queryManager: QueryManager) throws {
        try queryManager.cleanLocalStorage()
    }

    static func createBackup(from context: ModelContext) async throws -> Data {
        try await DataManager.shared.createBackup(from: context)
    }

    static func restoreBackup(from data: Data, into context: ModelContext) async throws {
        try await DataManager.shared.restoreBackup(from: data, into: context)
    }

    static func restoreBackup(from url: URL, into context: ModelContext) async throws {
        try await DataManager.shared.restoreBackup(from: url, into: context)
    }

    static func importData(from data: Data, into context: ModelContext) async throws -> Any {
        try await DataManager.shared.importData(from: data, into: context)
    }

    static func importData(from url: URL, into context: ModelContext) async throws -> Any {
        try await DataManager.shared.importData(from: url, into: context)
    }

    static func validateBackup(from url: URL) async throws {
        let bootstrap = AppBootstrap.inMemory()
        try await DataManager.shared.restoreBackup(from: url, into: bootstrap.modelContainer.mainContext)
    }

    static func validateImport(from url: URL) async throws {
        let bootstrap = AppBootstrap.inMemory()
        _ = try await DataManager.shared.importData(from: url, into: bootstrap.modelContainer.mainContext)
    }

    static func wipePersistentStore() throws {
        try StartupRecoveryStore.wipePersistentStore()
    }

    #if os(macOS)
        static func relaunchNormalApp() throws {
            try StartupRecoveryStore.relaunchCurrentApplication()
        }
    #endif
}

enum StartupRecoveryStore {
    static func persistentStoreDirectoryCandidates(
        bundleIdentifier: String? = Bundle.main.bundleIdentifier,
        executableName: String? = Bundle.main.object(forInfoDictionaryKey: "CFBundleExecutable") as? String,
        appName: String? = Bundle.main.object(forInfoDictionaryKey: "CFBundleName") as? String,
        fileManager: FileManager = .default
    ) throws -> [URL] {
        guard let applicationSupport = fileManager.urls(for: .applicationSupportDirectory, in: .userDomainMask).first else {
            throw CocoaError(.fileNoSuchFile)
        }

        let names = [bundleIdentifier, executableName, appName]
            .compactMap { candidate -> String? in
                guard let trimmed = candidate?.trimmingCharacters(in: .whitespacesAndNewlines),
                      !trimmed.isEmpty else {
                    return nil
                }
                return trimmed
            }

        var seen = Set<String>()
        return names.compactMap { name in
            guard seen.insert(name).inserted else { return nil }
            return applicationSupport.appendingPathComponent(name, isDirectory: true)
        }
    }

    static func wipePersistentStore(
        bundleIdentifier: String? = Bundle.main.bundleIdentifier,
        executableName: String? = Bundle.main.object(forInfoDictionaryKey: "CFBundleExecutable") as? String,
        appName: String? = Bundle.main.object(forInfoDictionaryKey: "CFBundleName") as? String,
        fileManager: FileManager = .default
    ) throws {
        let rootCandidates = try persistentStoreDirectoryCandidates(
            bundleIdentifier: bundleIdentifier,
            executableName: executableName,
            appName: appName,
            fileManager: fileManager
        )

        let storeCandidates = rootCandidates.flatMap { root in
            [
                root,
                root.appendingPathExtension("store"),
                root.appendingPathExtension("sqlite"),
                root.appendingPathExtension("sqlite-shm"),
                root.appendingPathExtension("sqlite-wal"),
                root.appendingPathExtension("store-shm"),
                root.appendingPathExtension("store-wal"),
            ]
        }

        for url in storeCandidates {
            if fileManager.fileExists(atPath: url.path) {
                try fileManager.removeItem(at: url)
                vxAtelierPro.log.notice("Removed persistent store item: \(url.path)")
            }
        }
    }

    #if os(macOS)
        static func relaunchCurrentApplication() throws {
            let openURL = URL(fileURLWithPath: "/usr/bin/open")
            let process = Process()
            process.executableURL = openURL
            process.arguments = ["-n", "-a", Bundle.main.bundleURL.path]
            try process.run()

            DispatchQueue.main.asyncAfter(deadline: .now() + 0.25) {
                NSApp.terminate(nil)
            }
        }
    #endif
}
