import Foundation

// MARK: - Health Status
enum HealthStatus: String, Codable {
    case normal     = "Normal"
    case borderline = "Borderline"
    case warning    = "High"

    var label: String { rawValue }
}

// MARK: - Metric
struct HealthMetric: Identifiable, Codable {
    var id: UUID = UUID()
    var name: String
    var value: String
    var unit: String
    var normalRange: String
    var status: HealthStatus
    var icon: String
    var progress: Double   // 0–1 for progress bar
}

// MARK: - Report
struct HealthReport: Codable {
    var metrics: [HealthMetric]
    var reportDate: Date
    var labName: String

    var abnormalCount: Int { metrics.filter { $0.status != .normal }.count }
    var warningCount:  Int { metrics.filter { $0.status == .warning }.count }

    // MARK: Demo Data
    static let demo = HealthReport(
        metrics: [
            HealthMetric(name: "Blood Pressure",  value: "138/89", unit: "mmHg",   normalRange: "< 120/80",  status: .warning,    icon: "heart.fill",                  progress: 0.82),
            HealthMetric(name: "Fasting Glucose", value: "112",    unit: "mg/dL",  normalRange: "< 100",     status: .warning,    icon: "drop.fill",                   progress: 0.74),
            HealthMetric(name: "HbA1c",           value: "6.1",    unit: "%",      normalRange: "< 5.7",     status: .warning,    icon: "waveform.path.ecg",           progress: 0.78),
            HealthMetric(name: "LDL Cholesterol", value: "145",    unit: "mg/dL",  normalRange: "< 130",     status: .borderline, icon: "chart.line.uptrend.xyaxis",   progress: 0.65),
            HealthMetric(name: "HDL Cholesterol", value: "52",     unit: "mg/dL",  normalRange: "> 40",      status: .normal,     icon: "shield.fill",                 progress: 0.55),
            HealthMetric(name: "Triglycerides",   value: "198",    unit: "mg/dL",  normalRange: "< 150",     status: .borderline, icon: "flame.fill",                  progress: 0.70),
            HealthMetric(name: "BMI",             value: "25.8",   unit: "",       normalRange: "18.5–24",   status: .borderline, icon: "figure.stand",                progress: 0.68),
            HealthMetric(name: "Total Cholesterol", value: "215",  unit: "mg/dL",  normalRange: "< 200",     status: .borderline, icon: "circle.hexagongrid.fill",     progress: 0.72),
        ],
        reportDate: Calendar.current.date(byAdding: .day, value: -7, to: Date()) ?? Date(),
        labName: "NTU Hospital Health Center"
    )
}
