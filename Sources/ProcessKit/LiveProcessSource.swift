import Darwin
import Foundation

public protocol SnapshotSource: Sendable {
    func sample() async -> Snapshot
}

/// Reads the machine's process table. Everything here works for the current
/// user's processes without elevated privileges.
public struct LiveProcessSource: Sendable {
    public init() {}

    public func processes() -> [ProcessSample] {
        kinfoProcs().compactMap { sample(from: $0) }
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

    private func sample(from kp: kinfo_proc) -> ProcessSample? {
        let pid = kp.kp_proc.p_pid
        guard pid > 0 else { return nil }

        var info = proc_taskinfo()
        let infoSize = Int32(MemoryLayout<proc_taskinfo>.size)
        let gotInfo = proc_pidinfo(pid, PROC_PIDTASKINFO, 0, &info, infoSize) == infoSize

        let started = Date(timeIntervalSince1970:
            Double(kp.kp_proc.p_starttime.tv_sec) +
            Double(kp.kp_proc.p_starttime.tv_usec) / 1_000_000)

        return ProcessSample(
            pid: pid,
            ppid: kp.kp_eproc.e_ppid,
            uid: kp.kp_eproc.e_ucred.cr_uid,
            executablePath: executablePath(pid),
            arguments: arguments(pid),
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

    /// Reads argv via KERN_PROCARGS2. Returns [] for processes we may not inspect.
    private func arguments(_ pid: Int32) -> [String] {
        var argmax: Int32 = 0
        var argmaxSize = MemoryLayout<Int32>.size
        var argmaxMIB: [Int32] = [CTL_KERN, KERN_ARGMAX]
        guard sysctl(&argmaxMIB, 2, &argmax, &argmaxSize, nil, 0) == 0, argmax > 0 else { return [] }

        var buffer = [CChar](repeating: 0, count: Int(argmax))
        var bufferSize = Int(argmax)
        var mib: [Int32] = [CTL_KERN, KERN_PROCARGS2, pid]
        guard sysctl(&mib, 3, &buffer, &bufferSize, nil, 0) == 0,
              bufferSize > MemoryLayout<Int32>.size else { return [] }

        var argc: Int32 = 0
        memcpy(&argc, buffer, MemoryLayout<Int32>.size)
        guard argc > 0 else { return [] }

        var result: [String] = []
        buffer.withUnsafeBufferPointer { pointer in
            guard let base = pointer.baseAddress else { return }
            let end = base + bufferSize
            var cursor = base + MemoryLayout<Int32>.size
            while cursor < end, cursor.pointee != 0 { cursor += 1 }   // skip exec path
            while cursor < end, cursor.pointee == 0 { cursor += 1 }   // skip padding
            var read: Int32 = 0
            while cursor < end, read < argc {
                let argument = String(cString: cursor)
                result.append(argument)
                cursor += argument.utf8.count + 1
                read += 1
            }
        }
        return result
    }
}
