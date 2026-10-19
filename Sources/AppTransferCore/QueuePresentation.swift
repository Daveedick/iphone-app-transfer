import Foundation

/// Ordering for the visible queue only. The coordinator retains its FIFO array.
public enum QueuePresentation {
    public static func newestFirst(_ jobs: [TransferJob]) -> [TransferJob] {
        jobs.enumerated().sorted { lhs, rhs in
            if lhs.element.queuePresentationDate != rhs.element.queuePresentationDate {
                return lhs.element.queuePresentationDate > rhs.element.queuePresentationDate
            }
            // Array order is insertion order, including legacy jobs with equal dates.
            return lhs.offset > rhs.offset
        }.map(\.element)
    }
}

public struct EnqueueOutcome: Sendable {
    public let jobID: UUID
    public let inserted: Bool
    public init(jobID: UUID, inserted: Bool) { self.jobID = jobID; self.inserted = inserted }
}
