import Foundation
import IOKit.ps
import Observation

/// Source de vérité observable pour l'UI. Rafraîchit la lecture IOKit :
/// - toutes les 3 s (les watts bougent en permanence) ;
/// - immédiatement quand le système signale un changement d'alimentation
///   (branchement/débranchement du secteur) via `IOPSNotificationCreateRunLoopSource`.
@MainActor
@Observable
final class BatteryService {
    private(set) var snapshot = BatterySnapshot()
    private(set) var hasBattery = true
    /// Drain moyen sur ~2 min : la base STABLE des estimations d'autonomie.
    /// La valeur instantanée saute en permanence (8 W → 0,3 W) ; sans lissage,
    /// « 2 h restantes » deviendrait « 8 h » puis « 1 h » à chaque seconde.
    private(set) var smoothedDrainWatts: Double?

    @ObservationIgnored private var pollTask: Task<Void, Never>?
    @ObservationIgnored private var powerSource: CFRunLoopSource?
    @ObservationIgnored private var drainHistory: [Double] = []
    @ObservationIgnored private var lastExternalState: Bool?

    init() {
        refresh()
        startPolling()
        registerForPowerChanges()
    }

    func refresh() {
        if let snap = BatteryReader.read() {
            snapshot = snap
            hasBattery = true
            updateDrainAverage(snap)
        } else {
            hasBattery = false
        }
    }

    // MARK: - Autonomie (sur drain lissé)

    var estimatedAutonomyHours: Double? {
        guard let drain = smoothedDrainWatts, drain > 0.3,
              snapshot.remainingEnergyWh > 0 else { return nil }
        return snapshot.remainingEnergyWh / drain
    }

    /// Minutes gagnées en libérant `freeingWatts` (conso soutenue d'une app).
    func autonomyGainMinutes(freeingWatts: Double) -> Double? {
        guard freeingWatts > 0.05,
              let drain = smoothedDrainWatts,
              drain - freeingWatts > 0.3,
              snapshot.remainingEnergyWh > 0 else { return nil }
        let now = snapshot.remainingEnergyWh / drain
        let without = snapshot.remainingEnergyWh / (drain - freeingWatts)
        return (without - now) * 60
    }

    private func updateDrainAverage(_ snap: BatterySnapshot) {
        // Brancher/débrancher change le régime de consommation : on repart
        // à zéro plutôt que de moyenner deux réalités différentes.
        if lastExternalState != snap.isExternalConnected {
            drainHistory.removeAll()
            lastExternalState = snap.isExternalConnected
        }
        guard let instant = snap.referenceDrainWatts else {
            smoothedDrainWatts = nil
            return
        }
        drainHistory.append(instant)
        if drainHistory.count > 40 { drainHistory.removeFirst(drainHistory.count - 40) }
        smoothedDrainWatts = drainHistory.reduce(0, +) / Double(drainHistory.count)
    }

    private func startPolling() {
        pollTask = Task { [weak self] in
            while !Task.isCancelled {
                // Tolérance : laisse macOS coalescer les réveils (App Nap).
                try? await Task.sleep(for: .seconds(3), tolerance: .seconds(1))
                self?.refresh()
            }
        }
    }

    private func registerForPowerChanges() {
        let context = Unmanaged.passUnretained(self).toOpaque()
        guard let source = IOPSNotificationCreateRunLoopSource({ context in
            guard let context else { return }
            let service = Unmanaged<BatteryService>.fromOpaque(context).takeUnretainedValue()
            // Le callback est délivré sur la run loop principale.
            MainActor.assumeIsolated { service.refresh() }
        }, context)?.takeRetainedValue() else { return }

        CFRunLoopAddSource(CFRunLoopGetMain(), source, .defaultMode)
        powerSource = source
    }
}
