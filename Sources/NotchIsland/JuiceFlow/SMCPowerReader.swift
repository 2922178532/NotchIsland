import Foundation
import IOKit

/// Lecture des capteurs de puissance via le SMC (System Management Controller).
/// Contrairement au registre `AppleSmartBattery` — rafraîchi par la jauge de la
/// batterie toutes les ~20 à 60 s seulement — les clés SMC sont mises à jour en
/// continu. Aucun privilège requis.
///
/// Clés (Apple Silicon), valeurs en watts, type `flt ` :
///   PPBR : puissance débitée par la batterie (> 0 en décharge)
///   PDTR : puissance entrante du chargeur
///   PSTR : puissance totale consommée par le système
final class SMCPowerReader: Sendable {
    static let shared: SMCPowerReader? = SMCPowerReader()

    private let connection: io_connect_t

    struct PowerSensors: Sendable {
        var batteryWatts: Double?  // signé, convention app : > 0 en charge, < 0 en décharge
        var adapterWatts: Double?
        var systemWatts: Double?
    }

    private init?() {
        let service = IOServiceGetMatchingService(kIOMainPortDefault, IOServiceMatching("AppleSMC"))
        guard service != 0 else { return nil }
        defer { IOObjectRelease(service) }

        var conn: io_connect_t = 0
        guard IOServiceOpen(service, mach_task_self_, 0, &conn) == KERN_SUCCESS else { return nil }
        connection = conn
    }

    func read() -> PowerSensors {
        var sensors = PowerSensors()
        // PPBR est positif quand la batterie débite : on inverse pour garder
        // la convention de l'app (charge > 0, décharge < 0).
        sensors.batteryWatts = readFloat("PPBR").map { -Double($0) }
        sensors.adapterWatts = readFloat("PDTR").map(Double.init)
        sensors.systemWatts = readFloat("PSTR").map(Double.init)
        return sensors
    }

    // MARK: - Protocole SMC

    /// Structure d'échange avec AppleSMC : 80 octets, layout aplati reproduisant
    /// exactement les offsets du struct C (padding d'alignement compris).
    private struct SMCKeyData {
        var key: UInt32 = 0                                              // 0
        var versMajor: UInt8 = 0, versMinor: UInt8 = 0                   // 4, 5
        var versBuild: UInt8 = 0, versReserved: UInt8 = 0                // 6, 7
        var versRelease: UInt16 = 0                                      // 8
        var pad0: UInt16 = 0                                             // 10 (padding C)
        var pLimitVersion: UInt16 = 0, pLimitLength: UInt16 = 0          // 12, 14
        var pLimitCPU: UInt32 = 0, pLimitGPU: UInt32 = 0                 // 16, 20
        var pLimitMem: UInt32 = 0                                        // 24
        var keyInfoDataSize: UInt32 = 0                                  // 28
        var keyInfoDataType: UInt32 = 0                                  // 32
        var keyInfoDataAttributes: UInt8 = 0                             // 36
        var pad1: UInt8 = 0, pad2: UInt8 = 0, pad3: UInt8 = 0            // 37-39 (padding C)
        var result: UInt8 = 0                                            // 40
        var status: UInt8 = 0                                            // 41
        var data8: UInt8 = 0                                             // 42
        var pad4: UInt8 = 0                                              // 43 (padding C)
        var data32: UInt32 = 0                                           // 44
        var bytes: (UInt8, UInt8, UInt8, UInt8, UInt8, UInt8, UInt8, UInt8,
                    UInt8, UInt8, UInt8, UInt8, UInt8, UInt8, UInt8, UInt8,
                    UInt8, UInt8, UInt8, UInt8, UInt8, UInt8, UInt8, UInt8,
                    UInt8, UInt8, UInt8, UInt8, UInt8, UInt8, UInt8, UInt8) =
            (0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0,
             0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0)              // 48-79
    }

    private static let selectorHandleYPCEvent: UInt32 = 2
    private static let commandReadKey: UInt8 = 5
    private static let commandGetKeyInfo: UInt8 = 9
    private static let typeFloat = fourCC("flt ")

    private func readFloat(_ key: String) -> Float? {
        let keyCode = Self.fourCC(key)

        var info = SMCKeyData()
        info.key = keyCode
        info.data8 = Self.commandGetKeyInfo
        guard let infoResult = call(info), infoResult.result == 0,
              infoResult.keyInfoDataSize == 4,
              infoResult.keyInfoDataType == Self.typeFloat else { return nil }

        var read = SMCKeyData()
        read.key = keyCode
        read.keyInfoDataSize = infoResult.keyInfoDataSize
        read.data8 = Self.commandReadKey
        guard let readResult = call(read), readResult.result == 0 else { return nil }

        let b = readResult.bytes
        let bits = UInt32(b.0) | UInt32(b.1) << 8 | UInt32(b.2) << 16 | UInt32(b.3) << 24
        let value = Float(bitPattern: bits)
        return value.isFinite ? value : nil
    }

    private func call(_ input: SMCKeyData) -> SMCKeyData? {
        var input = input
        var output = SMCKeyData()
        var outputSize = MemoryLayout<SMCKeyData>.stride
        let status = IOConnectCallStructMethod(
            connection, Self.selectorHandleYPCEvent,
            &input, MemoryLayout<SMCKeyData>.stride,
            &output, &outputSize
        )
        return status == KERN_SUCCESS ? output : nil
    }

    private static func fourCC(_ string: String) -> UInt32 {
        string.utf8.reduce(0) { $0 << 8 | UInt32($1) }
    }
}
