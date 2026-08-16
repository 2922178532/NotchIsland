import Foundation
import IOKit

/// Photographie instantanée de l'état de la batterie, lue depuis le registre
/// IOKit `AppleSmartBattery`. Aucun privilège requis.
struct BatterySnapshot: Sendable, Equatable {
    enum PowerState: Sendable {
        case charging            // branché, en charge
        case discharging         // sur batterie
        case full                // branché, batterie pleine
        case pluggedNotCharging  // branché, charge en pause (optimisation, limite…)
    }

    var percentage: Int = 0
    var state: PowerState = .discharging
    /// Puissance instantanée en watts. Positive en charge, négative en décharge.
    var watts: Double = 0
    var voltage: Double = 0   // volts
    var amperage: Double = 0  // ampères, signé
    var cycleCount: Int = 0
    var designCapacity: Int = 0       // mAh, capacité d'origine
    var nominalCapacity: Int = 0      // mAh, capacité actuelle réelle
    var rawCurrentCapacity: Int = 0   // mAh restants (base du calcul d'autonomie)
    var temperature: Double = 0   // °C
    /// Minutes restantes (décharge) ou avant charge complète. `nil` si inconnu.
    var timeRemainingMinutes: Int?
    var isExternalConnected = false
    /// Capteurs SMC temps réel (nil si indisponibles sur cette machine).
    var systemWatts: Double?
    var adapterWatts: Double?

    /// Santé de la batterie : capacité actuelle vs capacité d'origine.
    var healthPercent: Double {
        guard designCapacity > 0 else { return 0 }
        return Double(nominalCapacity) / Double(designCapacity) * 100
    }
}

/// Lecture du registre IOKit. Fonction pure et non isolée : utilisable depuis
/// le service observable comme depuis la ligne de commande (`--dump`).
enum BatteryReader {
    static func read() -> BatterySnapshot? {
        let service = IOServiceGetMatchingService(
            kIOMainPortDefault,
            IOServiceMatching("AppleSmartBattery")
        )
        guard service != 0 else { return nil }
        defer { IOObjectRelease(service) }

        var propsRef: Unmanaged<CFMutableDictionary>?
        guard IORegistryEntryCreateCFProperties(service, &propsRef, kCFAllocatorDefault, 0) == KERN_SUCCESS,
              let props = propsRef?.takeRetainedValue() as? [String: Any] else {
            return nil
        }

        var snap = BatterySnapshot()

        let currentCapacity = intValue(props["CurrentCapacity"]) ?? 0
        let maxCapacity = max(intValue(props["MaxCapacity"]) ?? 100, 1)
        snap.percentage = min(currentCapacity * 100 / maxCapacity, 100)

        snap.cycleCount = intValue(props["CycleCount"]) ?? 0
        snap.designCapacity = intValue(props["DesignCapacity"]) ?? 0
        snap.nominalCapacity = intValue(props["NominalChargeCapacity"])
            ?? intValue(props["AppleRawMaxCapacity"]) ?? 0
        snap.rawCurrentCapacity = intValue(props["AppleRawCurrentCapacity"]) ?? 0

        // Température exprimée en centièmes de degré Celsius.
        if let raw = intValue(props["Temperature"]) {
            snap.temperature = Double(raw) / 100
        }

        // Puissance instantanée : tension (mV) × courant (mA).
        // Le courant est signé : négatif en décharge, positif en charge.
        let voltage = Double(intValue(props["Voltage"]) ?? 0) / 1000
        let amperage = Double(intValue(props["InstantAmperage"]) ?? intValue(props["Amperage"]) ?? 0) / 1000
        snap.voltage = voltage
        snap.amperage = amperage
        snap.watts = voltage * amperage

        let externalConnected = props["ExternalConnected"] as? Bool ?? false
        let isCharging = props["IsCharging"] as? Bool ?? false
        let fullyCharged = props["FullyCharged"] as? Bool ?? false
        snap.isExternalConnected = externalConnected

        switch (externalConnected, isCharging, fullyCharged) {
        case (true, true, _): snap.state = .charging
        case (true, false, true): snap.state = .full
        case (true, false, false): snap.state = .pluggedNotCharging
        case (false, _, _): snap.state = .discharging
        }

        // 65535 (ou 0) signifie « estimation indisponible ».
        let timeKey = snap.state == .charging ? "AvgTimeToFull" : "AvgTimeToEmpty"
        if let minutes = intValue(props[timeKey]), minutes > 0, minutes < 65535 {
            snap.timeRemainingMinutes = minutes
        }

        // Le SMC fournit la puissance en temps réel, alors que la jauge du
        // registre ne se rafraîchit que toutes les ~20-60 s : il est prioritaire.
        if let sensors = SMCPowerReader.shared?.read() {
            if let batteryWatts = sensors.batteryWatts {
                snap.watts = batteryWatts
            }
            snap.systemWatts = sensors.systemWatts
            snap.adapterWatts = sensors.adapterWatts
        }

        return snap
    }

    /// Certains firmwares encodent les valeurs négatives (Amperage) en
    /// complément à deux sur 32 bits non signés — on redresse le cas échéant.
    private static func intValue(_ any: Any?) -> Int? {
        guard let number = any as? NSNumber else { return nil }
        let value = number.int64Value
        if value > Int64(Int32.max), value <= Int64(UInt32.max) {
            return Int(Int32(bitPattern: UInt32(value)))
        }
        return Int(value)
    }
}
