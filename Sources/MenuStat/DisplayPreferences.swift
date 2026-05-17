import Combine
import Foundation

enum MetricKind: String, CaseIterable, Identifiable {
    case cpu
    case memory
    case gpu
    case pressure
    case fans

    var id: String {
        rawValue
    }

    var shortTitle: String {
        switch self {
        case .cpu: "CPU"
        case .memory: "MEM"
        case .gpu: "GPU"
        case .pressure: "PRES"
        case .fans: "FAN"
        }
    }
}

final class DisplayPreferences: ObservableObject {
    static let shared = DisplayPreferences()

    private static let primaryMetricKey = "display.primaryMetric"
    private static let visibleSectionsKey = "display.visibleSections"
    private static let defaultPrimaryMetric: MetricKind = .cpu
    private static let defaultVisibleSections: Set<MetricKind> = [.cpu, .memory, .gpu, .pressure, .fans]

    @Published var primaryMetric: MetricKind {
        didSet {
            defaults.set(primaryMetric.rawValue, forKey: Self.primaryMetricKey)
        }
    }

    @Published private(set) var visibleSections: Set<MetricKind> {
        didSet {
            let rawValues = visibleSections.map(\.rawValue)
            defaults.set(rawValues, forKey: Self.visibleSectionsKey)
        }
    }

    private let defaults: UserDefaults

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults

        if let rawPrimary = defaults.string(forKey: Self.primaryMetricKey),
           let metric = MetricKind(rawValue: rawPrimary)
        {
            primaryMetric = metric
        } else {
            primaryMetric = Self.defaultPrimaryMetric
        }

        if let rawSections = defaults.array(forKey: Self.visibleSectionsKey) as? [String] {
            let sections = Set(rawSections.compactMap(MetricKind.init(rawValue:)))
            visibleSections = sections.isEmpty ? Self.defaultVisibleSections : sections
        } else {
            visibleSections = Self.defaultVisibleSections
        }
    }

    func isVisible(_ section: MetricKind) -> Bool {
        visibleSections.contains(section)
    }

    func setVisible(_ visible: Bool, for section: MetricKind) {
        if visible {
            visibleSections.insert(section)
            return
        }

        guard visibleSections.count > 1 else { return }
        visibleSections.remove(section)
        if primaryMetric == section {
            primaryMetric = visibleSections.sortedByDisplayOrder.first ?? .cpu
        }
    }

    func visibleSectionsInDisplayOrder() -> [MetricKind] {
        visibleSections.sortedByDisplayOrder
    }
}

extension Set<MetricKind> {
    var sortedByDisplayOrder: [MetricKind] {
        MetricKind.allCases.filter { contains($0) }
    }
}
