import Foundation

/// User-visible performance paths measured by `screenlog-performance` and
/// exposed as Instruments signposts in production builds.
public enum PerformanceMetricID: String, CaseIterable, Codable, Hashable, Sendable {
    case warmLibrarySearch
    case firstThumbnailDecode
    case timelineFrameExtraction
    case processCPU
    case residentMemory
}

public enum PerformanceMeasurementUnit: String, Codable, Sendable {
    case milliseconds
    case percent
    case mebibytes
}

public struct PerformanceBudget: Equatable, Codable, Sendable {
    public let metric: PerformanceMetricID
    public let statistic: String
    public let unit: PerformanceMeasurementUnit
    public let limit: Double
    public let warningRatio: Double

    public init(
        metric: PerformanceMetricID,
        statistic: String,
        unit: PerformanceMeasurementUnit,
        limit: Double,
        warningRatio: Double = 0.8
    ) {
        self.metric = metric
        self.statistic = statistic
        self.unit = unit
        self.limit = limit
        self.warningRatio = warningRatio
    }

    /// Initial product budgets for the documented 5,000-frame release fixture.
    /// They are review thresholds, not CI wall-time assertions.
    public static let screenloggerDefaults: [PerformanceBudget] = [
        PerformanceBudget(
            metric: .warmLibrarySearch,
            statistic: "p95",
            unit: .milliseconds,
            limit: 120
        ),
        PerformanceBudget(
            metric: .firstThumbnailDecode,
            statistic: "first",
            unit: .milliseconds,
            limit: 100
        ),
        PerformanceBudget(
            metric: .timelineFrameExtraction,
            statistic: "p95",
            unit: .milliseconds,
            limit: 100
        ),
        PerformanceBudget(
            metric: .processCPU,
            statistic: "paced-average",
            unit: .percent,
            limit: 25
        ),
        PerformanceBudget(
            metric: .residentMemory,
            statistic: "peak",
            unit: .mebibytes,
            limit: 350
        ),
    ]
}

public struct PerformanceObservation: Equatable, Codable, Sendable {
    public let metric: PerformanceMetricID
    public let statistic: String
    public let unit: PerformanceMeasurementUnit
    public let value: Double
    public let sampleCount: Int
    public let samples: [Double]

    public init(
        metric: PerformanceMetricID,
        statistic: String,
        unit: PerformanceMeasurementUnit,
        value: Double,
        sampleCount: Int,
        samples: [Double] = []
    ) {
        self.metric = metric
        self.statistic = statistic
        self.unit = unit
        self.value = value
        self.sampleCount = sampleCount
        self.samples = samples
    }
}

public enum PerformanceBudgetStatus: String, Codable, Sendable {
    case withinBudget
    case nearBudget
    case overBudget
    case missing
}

public struct PerformanceBudgetEvaluation: Equatable, Codable, Sendable {
    public let budget: PerformanceBudget
    public let observation: PerformanceObservation?
    public let status: PerformanceBudgetStatus
    public let utilization: Double?
}

public enum PerformanceBudgetEvaluator {
    public static func evaluate(
        budgets: [PerformanceBudget],
        observations: [PerformanceObservation]
    ) -> [PerformanceBudgetEvaluation] {
        budgets.map { budget in
            guard
                let observation = observations.first(where: {
                    $0.metric == budget.metric
                        && $0.statistic == budget.statistic
                        && $0.unit == budget.unit
                })
            else {
                return PerformanceBudgetEvaluation(
                    budget: budget,
                    observation: nil,
                    status: .missing,
                    utilization: nil
                )
            }

            let utilization = budget.limit > 0 ? observation.value / budget.limit : .infinity
            let status: PerformanceBudgetStatus
            if observation.value > budget.limit {
                status = .overBudget
            } else if utilization >= budget.warningRatio {
                status = .nearBudget
            } else {
                status = .withinBudget
            }
            return PerformanceBudgetEvaluation(
                budget: budget,
                observation: observation,
                status: status,
                utilization: utilization
            )
        }
    }
}

public enum PerformanceStatistics {
    /// Nearest-rank percentile. Deterministic for small benchmark sample sets and
    /// intentionally independent of Foundation measurement APIs.
    public static func percentile(_ samples: [Double], percentile: Double) -> Double? {
        guard !samples.isEmpty, percentile.isFinite else { return nil }
        let sorted = samples.sorted()
        let bounded = min(1, max(0, percentile))
        let rank = max(1, Int(ceil(bounded * Double(sorted.count))))
        return sorted[min(sorted.count - 1, rank - 1)]
    }
}

public struct PerformanceBenchmarkReport: Codable, Sendable {
    public let schemaVersion: Int
    public let recordedAt: Date
    public let environment: [String: String]
    public let workload: [String: String]
    public let observations: [PerformanceObservation]
    public let evaluations: [PerformanceBudgetEvaluation]

    public init(
        recordedAt: Date = Date(),
        environment: [String: String],
        workload: [String: String],
        observations: [PerformanceObservation],
        budgets: [PerformanceBudget] = PerformanceBudget.screenloggerDefaults
    ) {
        self.schemaVersion = 1
        self.recordedAt = recordedAt
        self.environment = environment
        self.workload = workload
        self.observations = observations
        self.evaluations = PerformanceBudgetEvaluator.evaluate(
            budgets: budgets,
            observations: observations
        )
    }
}
