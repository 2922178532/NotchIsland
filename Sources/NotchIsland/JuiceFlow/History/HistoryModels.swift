import Foundation

// Types légers servis aux vues Historique.

struct CurvePoint: Identifiable, Equatable {
    var id: Date { timestamp }
    let timestamp: Date
    let percentage: Int
    let isExternalConnected: Bool
}

struct AppDayTotal: Identifiable, Equatable {
    var id: String { name }
    let name: String
    let bundleID: String?
    let energyMWh: Double
}

struct DaySummary: Equatable {
    var minutesOnBattery: Int
    var energyWh: Double
}
