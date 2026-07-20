import Foundation
import StoreKit
import SwiftUI

// MARK: - Gestion du Premium (StoreKit 2)

/// Infrastructure d'achat intégré, prête pour l'App Store.
/// Mise en service : créer le produit non-consommable `premiumProductID` dans
/// App Store Connect (nécessite le compte développeur payant) — rien d'autre à changer.
/// Tant que le produit n'existe pas, l'achat est indisponible et `debugUnlockAll`
/// garde tout ouvert sur les builds Debug (sideload compte gratuit).
@MainActor
final class PremiumStore: ObservableObject {
    static let shared = PremiumStore()

    static let premiumProductID = "fr.devshield.gymtracker.premium.lifetime"

    /// Limites de l'offre gratuite
    enum FreeTier {
        static let maxTemplates = 3
    }

    @Published private(set) var product: Product?
    @Published private(set) var hasPurchased = false

    /// Déverrouillage complet réservé aux builds de développement.
    /// En Release (donc sur l'App Store), le paywall est toujours actif :
    /// impossible d'expédier par erreur une version où tout est offert.
    #if DEBUG
    private let debugUnlockAll = true
    #else
    private let debugUnlockAll = false
    #endif

    var isPremium: Bool { hasPurchased || debugUnlockAll }

    private var updatesTask: Task<Void, Never>?

    private init() {
        updatesTask = Task { await listenForTransactions() }
        Task {
            await refreshEntitlements()
            await loadProduct()
        }
    }

    func loadProduct() async {
        product = try? await Product.products(for: [Self.premiumProductID]).first
    }

    func refreshEntitlements() async {
        for await result in Transaction.currentEntitlements {
            if case .verified(let transaction) = result,
               transaction.productID == Self.premiumProductID,
               transaction.revocationDate == nil {
                hasPurchased = true
            }
        }
    }

    func purchase() async {
        guard let product,
              let result = try? await product.purchase() else { return }
        if case .success(let verification) = result,
           case .verified(let transaction) = verification {
            hasPurchased = true
            await transaction.finish()
        }
    }

    func restore() async {
        try? await AppStore.sync()
        await refreshEntitlements()
    }

    private func listenForTransactions() async {
        for await result in Transaction.updates {
            if case .verified(let transaction) = result,
               transaction.productID == Self.premiumProductID {
                hasPurchased = transaction.revocationDate == nil
                await transaction.finish()
            }
        }
    }
}

// MARK: - Écran paywall

struct PaywallView: View {
    @ObservedObject private var store = PremiumStore.shared
    @Environment(\.dismiss) private var dismiss
    @State private var isPurchasing = false

    var body: some View {
        NavigationStack {
            VStack(spacing: 24) {
                Image(systemName: "crown.fill")
                    .font(.system(size: 52))
                    .foregroundStyle(.yellow)
                    .padding(.top, 24)

                Text("LiftRun Premium")
                    .font(.title2.bold())

                VStack(alignment: .leading, spacing: 14) {
                    feature("infinity", "Séances personnalisées illimitées",
                            "L'offre gratuite est limitée à \(PremiumStore.FreeTier.maxTemplates) séances.")
                    feature("map.fill", "Circuits de course",
                            "Parcours préenregistrés affichés sur la carte pendant ta course.")
                    feature("flame.fill", "Coach nutrition",
                            "Calories et macros selon ton objectif : sèche, maintien ou prise de masse, avec journal alimentaire.")
                    feature("heart.fill", "Achat unique, pas d'abonnement",
                            "Tu débloques tout, pour toujours, et tu soutiens le développement.")
                }
                .padding(20)
                .background(Color(.secondarySystemGroupedBackground),
                            in: RoundedRectangle(cornerRadius: 20, style: .continuous))

                Spacer()

                if let product = store.product {
                    Button {
                        isPurchasing = true
                        Task {
                            await store.purchase()
                            isPurchasing = false
                            if store.isPremium { dismiss() }
                        }
                    } label: {
                        Text(isPurchasing ? "Achat en cours…" : "Débloquer · \(product.displayPrice)")
                            .font(.headline)
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 14)
                    }
                    .buttonStyle(.borderedProminent)
                    .tint(.indigo)
                    .disabled(isPurchasing)

                    Button("Restaurer mes achats") {
                        Task { await store.restore() }
                    }
                    .font(.footnote)
                } else {
                    Text("Achat bientôt disponible sur l'App Store.")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }
            }
            .padding()
            .background(Color(.systemGroupedBackground))
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Fermer") { dismiss() }
                }
            }
        }
    }

    private func feature(_ icon: String, _ title: String, _ detail: String) -> some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: icon)
                .font(.title3)
                .foregroundStyle(.indigo)
                .frame(width: 30)
            VStack(alignment: .leading, spacing: 2) {
                Text(title).font(.subheadline.weight(.semibold))
                Text(detail).font(.caption).foregroundStyle(.secondary)
            }
        }
    }
}
