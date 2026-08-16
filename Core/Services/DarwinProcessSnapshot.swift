import AppKit
import Darwin
import Foundation

public enum CacheRootEvidence: String, Sendable {
    case explicit
    case implicitAdoptedDefault
    case missing
}

public struct ChatGPTProcessSnapshot: Equatable, Sendable {
    public let mainPID: Int32
    public let accountBearingPIDs: Set<Int32>
    public let commandLines: [String]
    public let userDataRoots: Set<String>
    public let cacheRoots: Set<String>
    public let codexHomeRoots: Set<String>
    public let mainArgumentsReadable: Bool
    public let mainHasExplicitCacheOverride: Bool

    public init(
        mainPID: Int32,
        accountBearingPIDs: Set<Int32>,
        commandLines: [String],
        userDataRoots: Set<String>,
        cacheRoots: Set<String>,
        codexHomeRoots: Set<String>,
        mainArgumentsReadable: Bool,
        mainHasExplicitCacheOverride: Bool
    ) {
        self.mainPID = mainPID
        self.accountBearingPIDs = accountBearingPIDs
        self.commandLines = commandLines
        self.userDataRoots = userDataRoots
        self.cacheRoots = cacheRoots
        self.codexHomeRoots = codexHomeRoots
        self.mainArgumentsReadable = mainArgumentsReadable
        self.mainHasExplicitCacheOverride = mainHasExplicitCacheOverride
    }

    public func cacheEvidence(for profile: CodexProfile) -> CacheRootEvidence {
        let expectedCacheRoot = profile.electronCacheURL.standardizedFileURL.path
        if cacheRoots.contains(expectedCacheRoot) {
            return .explicit
        }
        let usesVerifiedImplicitAdoptedCache = profile.storageKind == .adoptedDefault &&
            profile.electronCacheURL.standardizedFileURL == CodexSwitchPaths.defaultElectronCache.standardizedFileURL &&
            mainArgumentsReadable &&
            !mainHasExplicitCacheOverride &&
            cacheRoots.isEmpty
        return usesVerifiedImplicitAdoptedCache ? .implicitAdoptedDefault : .missing
    }

    public func exposes(profile: CodexProfile) -> Bool {
        return userDataRoots.contains(profile.electronDataURL.standardizedFileURL.path) &&
            cacheEvidence(for: profile) != .missing &&
            codexHomeRoots.contains(profile.codexHomeURL.standardizedFileURL.path)
    }
}

private struct DarwinProcessRecord {
    let pid: Int32
    let executablePath: String
    let arguments: [String]
    let codexHome: String?
    let argumentsReadable: Bool

    var commandLine: String { ([executablePath] + arguments).joined(separator: " ") }
}

struct DarwinProcessArguments: Equatable {
    let arguments: [String]
    let codexHome: String?

    static func parse(_ bytes: [UInt8]) -> DarwinProcessArguments? {
        guard bytes.count >= MemoryLayout<Int32>.size else { return nil }
        let argc = bytes.withUnsafeBytes { rawBuffer -> Int in
            Int(rawBuffer.loadUnaligned(as: Int32.self))
        }
        guard argc > 0 else { return nil }
        var cursor = MemoryLayout<Int32>.size
        guard readCString(from: bytes, cursor: &cursor) != nil else { return nil }
        while cursor < bytes.count, bytes[cursor] == 0 {
            cursor += 1
        }

        var argv: [String] = []
        for _ in 0..<argc {
            guard let value = readCString(from: bytes, cursor: &cursor) else { return nil }
            argv.append(value)
        }

        while cursor < bytes.count, bytes[cursor] == 0 {
            cursor += 1
        }
        var environment: [[UInt8]] = []
        while cursor < bytes.count {
            let start = cursor
            while cursor < bytes.count, bytes[cursor] != 0 {
                cursor += 1
            }
            if start < cursor {
                environment.append(Array(bytes[start..<cursor]))
            }
            while cursor < bytes.count, bytes[cursor] == 0 {
                cursor += 1
            }
        }

        let codexPrefix = Array("CODEX_HOME=".utf8)
        let codexHome = environment.first { token in
            token.starts(with: codexPrefix)
        }.map {
            String(decoding: $0.dropFirst(codexPrefix.count), as: UTF8.self)
        }
        return DarwinProcessArguments(arguments: Array(argv.dropFirst()), codexHome: codexHome)
    }

    private static func readCString(from bytes: [UInt8], cursor: inout Int) -> String? {
        guard cursor < bytes.count else { return nil }
        let start = cursor
        while cursor < bytes.count, bytes[cursor] != 0 {
            cursor += 1
        }
        guard cursor < bytes.count else { return nil }
        let value = String(bytes: bytes[start..<cursor], encoding: .utf8)
        cursor += 1
        return value
    }
}

public final class DarwinProcessSnapshotProvider: @unchecked Sendable {
    private let locator: ChatGPTLocator

    public init(locator: ChatGPTLocator = ChatGPTLocator()) {
        self.locator = locator
    }

    public func snapshot() throws -> ChatGPTProcessSnapshot? {
        let app = try locator.locate()
        let applications = NSRunningApplication.runningApplications(withBundleIdentifier: app.bundleIdentifier)
            .filter { !$0.isTerminated }
        guard !applications.isEmpty else { return nil }
        guard applications.count == 1, let application = applications.first else {
            throw ProfileError.transactionFailed("Multiple ChatGPT instances are running; close the extra instance before continuing.")
        }
        guard application.executableURL?.standardizedFileURL == app.executableURL.standardizedFileURL else {
            throw ProfileError.unsupportedProfile("The running ChatGPT executable does not match the validated installation.")
        }

        let mainPID = application.processIdentifier
        let parentMap = processParentMap()
        var pids = Set([mainPID])
        var changed = true
        while changed {
            changed = false
            for (pid, parent) in parentMap where pids.contains(parent) {
                if pids.insert(pid).inserted {
                    changed = true
                }
            }
        }

        let records = pids.compactMap(record(for:))
            .filter { $0.executablePath.hasPrefix(app.bundleURL.path + "/Contents/") || $0.pid == mainPID }
        guard let mainRecord = records.first(where: { $0.pid == mainPID }) else { return nil }

        let accountBearing = records.filter { !$0.executablePath.hasSuffix("/browser_crashpad_handler") }
        let commandLines = accountBearing.map(\.commandLine)
        let userRoots = Set(accountBearing.flatMap { values(for: "--user-data-dir", in: $0.arguments) }.map(normalizedPath))
        let cacheRoots = Set(accountBearing.flatMap { values(for: "--disk-cache-dir", in: $0.arguments) }.map(normalizedPath))
        let codexHomes = Set(accountBearing.compactMap(\.codexHome).map(normalizedPath))

        return ChatGPTProcessSnapshot(
            mainPID: mainPID,
            accountBearingPIDs: Set(accountBearing.map(\.pid)),
            commandLines: commandLines,
            userDataRoots: userRoots,
            cacheRoots: cacheRoots,
            codexHomeRoots: codexHomes,
            mainArgumentsReadable: mainRecord.argumentsReadable,
            mainHasExplicitCacheOverride: !values(for: "--disk-cache-dir", in: mainRecord.arguments).isEmpty
        )
    }

    public func processExists(_ pid: Int32, matchingBundleURL bundleURL: URL) -> Bool {
        guard let record = record(for: pid) else { return false }
        guard record.argumentsReadable else { return false }
        return record.executablePath.hasPrefix(bundleURL.path + "/Contents/") &&
            !record.executablePath.hasSuffix("/browser_crashpad_handler")
    }

    public func process(_ pid: Int32, exposes profile: CodexProfile) -> Bool {
        guard let record = record(for: pid) else { return false }
        let userRoots = Set(values(for: "--user-data-dir", in: record.arguments).map(normalizedPath))
        let cacheRoots = Set(values(for: "--disk-cache-dir", in: record.arguments).map(normalizedPath))
        let codexHomes = Set([record.codexHome].compactMap { $0 }.map(normalizedPath))
        return userRoots.contains(profile.electronDataURL.standardizedFileURL.path) &&
            cacheRoots.contains(profile.electronCacheURL.standardizedFileURL.path) &&
            codexHomes.contains(profile.codexHomeURL.standardizedFileURL.path)
    }

    private func processParentMap() -> [Int32: Int32] {
        var capacity = 4096
        while capacity <= 65536 {
            var pids = [Int32](repeating: 0, count: capacity)
            let byteCount = pids.withUnsafeMutableBytes { rawBuffer in
                proc_listallpids(rawBuffer.baseAddress, Int32(rawBuffer.count))
            }
            guard byteCount >= 0 else { return [:] }
            let count = Int(byteCount) / MemoryLayout<Int32>.stride
            if count >= capacity {
                capacity *= 2
                continue
            }
            var result: [Int32: Int32] = [:]
            for pid in pids.prefix(count) where pid > 0 {
                var info = proc_bsdinfo()
                let infoSize = Int32(MemoryLayout<proc_bsdinfo>.size)
                let received = withUnsafeMutablePointer(to: &info) { pointer in
                    proc_pidinfo(pid, PROC_PIDTBSDINFO, 0, pointer, infoSize)
                }
                if received == infoSize {
                    result[pid] = Int32(info.pbi_ppid)
                }
            }
            return result
        }
        return [:]
    }

    private func record(for pid: Int32) -> DarwinProcessRecord? {
        var pathBuffer = [CChar](repeating: 0, count: Int(PATH_MAX))
        let pathLength = pathBuffer.withUnsafeMutableBufferPointer { buffer in
            proc_pidpath(pid, buffer.baseAddress, UInt32(buffer.count))
        }
        guard pathLength > 0 else { return nil }
        let executablePath = String(decoding: pathBuffer.prefix { $0 != 0 }.map { UInt8(bitPattern: $0) }, as: UTF8.self)
        let metadata = argumentsAndEnvironment(for: pid)
        return DarwinProcessRecord(
            pid: pid,
            executablePath: executablePath,
            arguments: metadata?.arguments ?? [],
            codexHome: metadata?.codexHome,
            argumentsReadable: metadata != nil
        )
    }

    private func argumentsAndEnvironment(for pid: Int32) -> DarwinProcessArguments? {
        var mib = [CTL_KERN, KERN_PROCARGS2, Int32(pid)]
        var size = 0
        guard sysctl(&mib, UInt32(mib.count), nil, &size, nil, 0) == 0, size > 0 else { return nil }
        var bytes = [UInt8](repeating: 0, count: size)
        guard sysctl(&mib, UInt32(mib.count), &bytes, &size, nil, 0) == 0, size >= MemoryLayout<Int32>.size else {
            return nil
        }
        return DarwinProcessArguments.parse(bytes)
    }

    private func values(for option: String, in arguments: [String]) -> [String] {
        var result: [String] = []
        var index = 0
        while index < arguments.count {
            let argument = arguments[index]
            if argument == option, index + 1 < arguments.count {
                result.append(arguments[index + 1])
                index += 2
                continue
            }
            let prefix = option + "="
            if argument.hasPrefix(prefix) {
                result.append(String(argument.dropFirst(prefix.count)))
            }
            index += 1
        }
        return result
    }

    private func normalizedPath(_ value: String) -> String {
        URL(fileURLWithPath: value, isDirectory: true).standardizedFileURL.path
    }
}
