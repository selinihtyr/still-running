import Darwin
import Foundation
import Synchronization

public protocol SnapshotSource: Sendable {
    func sample() async -> Snapshot
}

/// Reads the machine's process table. Everything here works for the current
/// user's processes without elevated privileges.
///
/// Reading one process's arguments means a sysctl into a buffer the size of
/// ARGMAX, which is a megabyte. Doing that for eight hundred processes every
/// few seconds costs more than everything this app is trying to save, so
/// arguments are cached: they cannot change while a process lives, and a pid
/// paired with its start time identifies a process uniquely.
public final class LiveProcessSource: Sendable {
    private struct Cached {
        let startedAt: Date
        let arguments: [String]
    }

    private let cache = Mutex<[Int32: Cached]>([:])

    public init() {}

    public func processes() -> [ProcessSample] {
        let entries = kinfoProcs()
        // One scratch buffer for the whole sweep. ARGMAX is a megabyte, and
        // allocating that per process is what made sampling expensive.
        let scratch = UnsafeMutablePointer<CChar>.allocate(capacity: Self.argumentMax)
        defer { scratch.deallocate() }

        let known = cache.withLock { $0 }
        var fresh: [Int32: Cached] = [:]
        fresh.reserveCapacity(entries.count)

        let samples = entries.compactMap { kp -> ProcessSample? in
            guard let started = Self.startTime(kp) else { return nil }
            let pid = kp.kp_proc.p_pid

            let arguments: [String]
            if let hit = known[pid], hit.startedAt == started {
                arguments = hit.arguments
            } else {
                arguments = readArguments(pid, into: scratch)
            }
            fresh[pid] = Cached(startedAt: started, arguments: arguments)

            return sample(from: kp, startedAt: started, arguments: arguments)
        }

        // Dropping everything not seen this time also evicts dead pids.
        cache.withLock { $0 = fresh }
        return samples
    }

    /// ARGMAX, read once. It does not change while the machine is up.
    private static let argumentMax: Int = {
        var value: Int32 = 0
        var size = MemoryLayout<Int32>.size
        var mib: [Int32] = [CTL_KERN, KERN_ARGMAX]
        guard sysctl(&mib, 2, &value, &size, nil, 0) == 0, value > 0 else { return 1 << 20 }
        return Int(value)
    }()

    private static func startTime(_ kp: kinfo_proc) -> Date? {
        guard kp.kp_proc.p_pid > 0 else { return nil }
        return Date(timeIntervalSince1970:
            Double(kp.kp_proc.p_starttime.tv_sec) +
            Double(kp.kp_proc.p_starttime.tv_usec) / 1_000_000)
    }

    private func kinfoProcs() -> [kinfo_proc] {
        var mib: [Int32] = [CTL_KERN, KERN_PROC, KERN_PROC_ALL, 0]
        var size = 0
        guard sysctl(&mib, 4, nil, &size, nil, 0) == 0, size > 0 else { return [] }
        let stride = MemoryLayout<kinfo_proc>.stride
        var procs = [kinfo_proc](repeating: kinfo_proc(), count: size / stride)
        guard sysctl(&mib, 4, &procs, &size, nil, 0) == 0 else { return [] }
        return Array(procs.prefix(size / stride))
    }

    private func sample(from kp: kinfo_proc, startedAt started: Date,
                        arguments: [String]) -> ProcessSample? {
        let pid = kp.kp_proc.p_pid

        var info = proc_taskinfo()
        let infoSize = Int32(MemoryLayout<proc_taskinfo>.size)
        let gotInfo = proc_pidinfo(pid, PROC_PIDTASKINFO, 0, &info, infoSize) == infoSize

        return ProcessSample(
            pid: pid,
            ppid: kp.kp_eproc.e_ppid,
            uid: kp.kp_eproc.e_ucred.cr_uid,
            executablePath: executablePath(pid),
            arguments: arguments,
            startedAt: started,
            hasControllingTTY: kp.kp_eproc.e_tdev != -1,
            cpuTimeNanos: gotInfo ? info.pti_total_user + info.pti_total_system : 0,
            residentBytes: gotInfo ? info.pti_resident_size : 0
        )
    }

    private func executablePath(_ pid: Int32) -> String {
        var buffer = [CChar](repeating: 0, count: Int(MAXPATHLEN) * 4)
        guard proc_pidpath(pid, &buffer, UInt32(buffer.count)) > 0 else { return "" }
        return String(cString: buffer)
    }

    /// Reads argv via KERN_PROCARGS2 into a caller-owned buffer, so one
    /// allocation serves the whole sweep. Returns [] for processes we may not
    /// inspect.
    private func readArguments(_ pid: Int32, into scratch: UnsafeMutablePointer<CChar>) -> [String] {
        var written = Self.argumentMax
        var mib: [Int32] = [CTL_KERN, KERN_PROCARGS2, pid]
        guard sysctl(&mib, 3, scratch, &written, nil, 0) == 0,
              written > MemoryLayout<Int32>.size else { return [] }

        var argc: Int32 = 0
        memcpy(&argc, scratch, MemoryLayout<Int32>.size)
        guard argc > 0 else { return [] }

        // Everything below stays inside what sysctl actually wrote. The buffer
        // is reused across processes, so bytes past that point are another
        // process's leftovers rather than a terminator.
        let limit = min(written, Self.argumentMax)

        func string(at start: Int) -> (value: String, next: Int)? {
            guard start < limit else { return nil }
            var end = start
            while end < limit, scratch[end] != 0 { end += 1 }
            let raw = UnsafeRawBufferPointer(start: UnsafeRawPointer(scratch + start), count: end - start)
            return (String(decoding: raw, as: UTF8.self), end + 1)
        }

        guard let path = string(at: MemoryLayout<Int32>.size) else { return [] }
        var index = path.next
        while index < limit, scratch[index] == 0 { index += 1 }   // padding after the exec path

        var result: [String] = []
        var read: Int32 = 0
        while read < argc, let argument = string(at: index) {
            // Tools that rewrite their own process title (npm, and anything
            // using setproctitle) leave empty slots behind. They are never
            // meaningful and they confuse anything reading argv positionally.
            if !argument.value.isEmpty { result.append(argument.value) }
            index = argument.next
            read += 1
        }
        return result
    }
}
