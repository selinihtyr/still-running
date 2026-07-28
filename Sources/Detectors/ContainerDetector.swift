import Foundation
import ProcessKit

/// Containers left up from a project you stopped working on. The Engine API has
/// no cheap per-container CPU reading, so age carries the decision — which is
/// the right rule here: a container up for a day is exactly the target.
public struct ContainerDetector: Detector {
    public let kind: FindingKind = .container

    public init() {}

    public func findings(in snapshot: Snapshot, history: History, settings: Settings) -> [Finding] {
        snapshot.containers.compactMap { container -> Finding? in
            let age = snapshot.takenAt.timeIntervalSince(container.startedAt)
            guard age >= settings.minimumAge else { return nil }

            return Finding(
                identity: "container:\(container.name)",
                kind: .container,
                title: container.name,
                detail: container.image,
                cpuPercent: 0,
                memoryBytes: 0,
                age: age,
                target: .container(container.id),
                severity: .notable,
                explanation: "\(FindingKind.container.plainDescription) It has been up for \(Formatting.duration(age)) on the \(container.image) image. Stopping it is undoable — it starts again exactly as it was.",
                revealPath: nil,
                details: """
                    Container: \(container.name)
                    Image: \(container.image)
                    Id: \(container.id)
                    Up: \(Formatting.duration(age))

                    docker logs \(container.name)
                    docker stop \(container.name)
                    """,
                command: "docker run … \(container.image)")
        }
        .sorted { $0.age > $1.age }
    }
}
