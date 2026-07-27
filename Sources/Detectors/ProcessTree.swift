import Foundation
import ProcessKit

/// Parent/child lookups over one snapshot.
///
/// Both the browser and dev-server detectors need the same thing: a root
/// process plus everything it spawned, reported as one row and stopped as one
/// unit. Without it a single `npm run dev` shows up three times — itself, the
/// framework it launched, and that framework's bundler.
struct ProcessTree {
    private let childrenOf: [Int32: [ProcessSample]]

    init(_ processes: [ProcessSample]) {
        var children: [Int32: [ProcessSample]] = [:]
        for process in processes { children[process.ppid, default: []].append(process) }
        self.childrenOf = children
    }

    func children(of pid: Int32) -> [ProcessSample] { childrenOf[pid] ?? [] }

    /// The seed and everything beneath it, skipping anything already claimed.
    func group(from seed: ProcessSample, claimed: inout Set<Int32>) -> [ProcessSample] {
        var group: [ProcessSample] = []
        var stack = [seed]
        while let current = stack.popLast() {
            guard !claimed.contains(current.pid) else { continue }
            claimed.insert(current.pid)
            group.append(current)
            stack.append(contentsOf: children(of: current.pid))
        }
        return group
    }
}

extension Array where Element == ProcessSample {
    /// Root first, so a signal to the head tears the rest down with it.
    var pidsRootFirst: [Int32] {
        let pids = Set(map(\.pid))
        let roots = filter { !pids.contains($0.ppid) }
        let rest = filter { pids.contains($0.ppid) }
        return roots.map(\.pid) + rest.map(\.pid)
    }

    var totalResidentBytes: UInt64 { reduce(0) { $0 + $1.residentBytes } }
}
