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

enum RefreshInterval: Double, CaseIterable, Identifiable {
    case live = 1
    case balanced = 5
    case quiet = 30

    var id: Double {
        rawValue
    }

    var shortTitle: String {
        "\(Int(rawValue))s"
    }

    var menuTitle: String {
        switch self {
        case .live: "Live · 1s"
        case .balanced: "Balanced · 5s"
        case .quiet: "Quiet · 30s"
        }
    }
}

enum TopAppRowCount: Int, CaseIterable, Identifiable {
    case compact = 5
    case standard = 8
    case deep = 12

    var id: Int {
        rawValue
    }

    var shortTitle: String {
        "\(rawValue)"
    }

    var menuTitle: String {
        "\(rawValue) Rows"
    }
}

final class DisplayPreferences: ObservableObject {
    static let shared = DisplayPreferences()

    private static let primaryMetricKey = "display.primaryMetric"
    private static let visibleSectionsKey = "display.visibleSections"
    private static let refreshIntervalKey = "display.refreshInterval"
    private static let topAppRowsKey = "display.topAppRows"
    private static let defaultPrimaryMetric: MetricKind = .cpu
    private static let defaultVisibleSections: Set<MetricKind> = [.cpu, .memory, .gpu, .pressure, .fans]
    private static let defaultRefreshInterval: RefreshInterval = .balanced
    private static let defaultTopAppRows: TopAppRowCount = .standard

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

    @Published var refreshInterval: RefreshInterval {
        didSet {
            defaults.set(refreshInterval.rawValue, forKey: Self.refreshIntervalKey)
        }
    }

    @Published var topAppRows: TopAppRowCount {
        didSet {
            defaults.set(topAppRows.rawValue, forKey: Self.topAppRowsKey)
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

        let savedInterval = defaults.double(forKey: Self.refreshIntervalKey)
        refreshInterval = RefreshInterval(rawValue: savedInterval) ?? Self.defaultRefreshInterval

        let savedRows = defaults.integer(forKey: Self.topAppRowsKey)
        topAppRows = TopAppRowCount(rawValue: savedRows) ?? Self.defaultTopAppRows
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
