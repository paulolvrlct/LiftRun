import SwiftUI
import VisionKit

// MARK: - Open Food Facts
// Base collaborative de produits emballés (~3 M de références, licence ODbL).
// Complète la table CIQUAL : celle-ci couvre les aliments génériques, Open Food
// Facts couvre les produits de marque identifiés par leur code-barres.

/// Produit scanné : valeurs pour 100 g + poids net du paquet quand il est connu
/// (permet de saisir « la moitié du paquet » au lieu de compter les grammes).
struct ScannedProduct: Codable, Equatable {
    let food: CiqualFood
    let packageGrams: Double?
}

enum OpenFoodFacts {

    enum LookupError: LocalizedError {
        case notFound
        case noNutrition
        case network

        var errorDescription: String? {
            switch self {
            case .notFound:    "Produit introuvable dans Open Food Facts."
            case .noNutrition: "Ce produit n'a pas de valeurs nutritionnelles renseignées."
            case .network:     "Connexion impossible. Vérifie ta connexion internet."
            }
        }
    }

    /// Récupère un produit par son code-barres : valeurs pour 100 g + poids net
    /// du paquet (pour proposer « la moitié du paquet », etc.).
    static func lookup(barcode: String) async throws -> ScannedProduct {
        // déjà scanné : on répond hors ligne
        if let cached = ScannedFoodCache.load(barcode: barcode) { return cached }

        let fields = "product_name,product_name_fr,brands,categories_tags,nutriments,product_quantity"
        guard let url = URL(string:
                "https://world.openfoodfacts.org/api/v2/product/\(barcode).json?fields=\(fields)")
        else { throw LookupError.notFound }

        var request = URLRequest(url: url)
        request.timeoutInterval = 12
        // Open Food Facts demande un User-Agent identifiant l'app
        request.setValue("LiftRun/1.0 (iOS; contact: pololivierlecourt@gmail.com)",
                         forHTTPHeaderField: "User-Agent")

        let data: Data
        do {
            (data, _) = try await URLSession.shared.data(for: request)
        } catch {
            throw LookupError.network
        }

        guard let response = try? JSONDecoder().decode(Response.self, from: data),
              let product = response.product, response.status == 1
        else { throw LookupError.notFound }

        guard let scanned = product.asScannedProduct() else { throw LookupError.noNutrition }
        ScannedFoodCache.save(scanned, barcode: barcode)
        return scanned
    }

    // MARK: Décodage

    private struct Response: Decodable {
        let status: Int
        let product: Product?
    }

    private struct Product: Decodable {
        let productName: String?
        let productNameFR: String?
        let brands: String?
        let categoriesTags: [String]?
        let nutriments: Nutriments?
        let productQuantity: Double?      // poids net du paquet, en grammes

        enum CodingKeys: String, CodingKey {
            case productName = "product_name"
            case productNameFR = "product_name_fr"
            case brands
            case categoriesTags = "categories_tags"
            case nutriments
            case productQuantity = "product_quantity"
        }

        init(from decoder: Decoder) throws {
            let c = try decoder.container(keyedBy: CodingKeys.self)
            productName = try? c.decodeIfPresent(String.self, forKey: .productName)
            productNameFR = try? c.decodeIfPresent(String.self, forKey: .productNameFR)
            brands = try? c.decodeIfPresent(String.self, forKey: .brands)
            categoriesTags = try? c.decodeIfPresent([String].self, forKey: .categoriesTags)
            nutriments = try? c.decodeIfPresent(Nutriments.self, forKey: .nutriments)
            // OFF renvoie ce champ tantôt en nombre, tantôt en chaîne
            if let d = try? c.decode(Double.self, forKey: .productQuantity) {
                productQuantity = d
            } else if let s = try? c.decode(String.self, forKey: .productQuantity) {
                productQuantity = Double(s.filter { $0.isNumber || $0 == "." })
            } else {
                productQuantity = nil
            }
        }

        /// Nom lisible : « Skyr nature — Danone »
        var displayName: String {
            let base = [productNameFR, productName]
                .compactMap { $0?.trimmingCharacters(in: .whitespacesAndNewlines) }
                .first { !$0.isEmpty } ?? "Produit scanné"
            guard let brand = brands?.split(separator: ",").first
                .map({ $0.trimmingCharacters(in: .whitespaces) }), !brand.isEmpty,
                  !base.localizedCaseInsensitiveContains(brand)
            else { return base }
            return "\(base) — \(brand)"
        }

        func asScannedProduct() -> ScannedProduct? {
            guard let n = nutriments, let kcal = n.kcalPer100g else { return nil }
            let food = CiqualFood(n: displayName,
                                  g: Self.category(from: categoriesTags).rawValue,
                                  k: kcal,
                                  p: n.proteins ?? 0,
                                  c: n.carbohydrates ?? 0,
                                  f: n.fat ?? 0)
            // on ne garde un poids de paquet que s'il est plausible
            let pack = productQuantity.flatMap { $0 > 0 && $0 <= 5000 ? $0 : nil }
            return ScannedProduct(food: food, packageGrams: pack)
        }

        /// Rapproche les tags Open Food Facts des catégories internes
        static func category(from tags: [String]?) -> FoodCategory {
            let joined = (tags ?? []).joined(separator: " ").lowercased()
            func has(_ words: [String]) -> Bool { words.contains { joined.contains($0) } }

            if has(["beverage", "boisson", "water", "juice", "soda"]) { return .drinks }
            if has(["dairy", "dairies", "laitier", "yogurt", "yaourt", "cheese", "fromage", "milk", "lait"]) { return .dairy }
            if has(["meat", "viande", "fish", "poisson", "seafood", "egg", "oeuf", "charcuter"]) { return .meatFish }
            if has(["cereal", "bread", "pain", "pasta", "pâtes", "rice", "riz", "flour", "farine"]) { return .cereals }
            if has(["fruit", "vegetable", "legume", "légume"]) { return .fruitsVeg }
            if has(["snack", "sweet", "sucre", "chocolat", "biscuit", "dessert", "candy", "confiser", "ice-cream", "glace"]) { return .sweets }
            if has(["fat", "oil", "huile", "butter", "beurre", "margarine"]) { return .fats }
            if has(["meal", "plat", "pizza", "sandwich", "soup", "soupe"]) { return .dishes }
            return .misc
        }
    }

    /// Les champs numériques d'Open Food Facts arrivent tantôt en nombre,
    /// tantôt en chaîne : on accepte les deux.
    private struct Nutriments: Decodable {
        let energyKcal: Double?
        let energyKJ: Double?
        let proteins: Double?
        let carbohydrates: Double?
        let fat: Double?

        /// kcal pour 100 g, converties depuis les kJ si besoin
        var kcalPer100g: Double? {
            if let energyKcal, energyKcal > 0 { return energyKcal }
            if let energyKJ, energyKJ > 0 { return energyKJ / 4.184 }
            return nil
        }

        enum CodingKeys: String, CodingKey {
            case energyKcal = "energy-kcal_100g"
            case energyKJ = "energy_100g"
            case proteins = "proteins_100g"
            case carbohydrates = "carbohydrates_100g"
            case fat = "fat_100g"
        }

        init(from decoder: Decoder) throws {
            let c = try decoder.container(keyedBy: CodingKeys.self)
            func value(_ key: CodingKeys) -> Double? {
                if let d = try? c.decode(Double.self, forKey: key) { return d }
                if let s = try? c.decode(String.self, forKey: key) { return Double(s) }
                return nil
            }
            energyKcal = value(.energyKcal)
            energyKJ = value(.energyKJ)
            proteins = value(.proteins)
            carbohydrates = value(.carbohydrates)
            fat = value(.fat)
        }
    }
}

// MARK: - Cache local des produits scannés
// Permet de re-scanner un produit déjà vu sans connexion.

enum ScannedFoodCache {
    private static let fileName = "scanned_foods.json"

    private static var fileURL: URL? {
        try? FileManager.default.url(for: .applicationSupportDirectory, in: .userDomainMask,
                                     appropriateFor: nil, create: true)
            .appendingPathComponent(fileName)
    }

    private static func all() -> [String: ScannedProduct] {
        guard let fileURL, let data = try? Data(contentsOf: fileURL),
              let dict = try? JSONDecoder().decode([String: ScannedProduct].self, from: data)
        else { return [:] }
        return dict
    }

    static func load(barcode: String) -> ScannedProduct? { all()[barcode] }

    static func save(_ product: ScannedProduct, barcode: String) {
        guard let fileURL else { return }
        var dict = all()
        dict[barcode] = product
        try? JSONEncoder().encode(dict).write(to: fileURL, options: .atomic)
    }
}

// MARK: - Scanner de code-barres (VisionKit)

private struct BarcodeScannerView: UIViewControllerRepresentable {
    var onScan: (String) -> Void

    func makeUIViewController(context: Context) -> DataScannerViewController {
        let controller = DataScannerViewController(
            recognizedDataTypes: [.barcode(symbologies: [.ean13, .ean8, .upce])],
            qualityLevel: .balanced,
            recognizesMultipleItems: false,
            isHighFrameRateTrackingEnabled: false,
            isHighlightingEnabled: true
        )
        controller.delegate = context.coordinator
        return controller
    }

    func updateUIViewController(_ controller: DataScannerViewController, context: Context) {
        try? controller.startScanning()
    }

    static func dismantleUIViewController(_ controller: DataScannerViewController,
                                          coordinator: Coordinator) {
        controller.stopScanning()
    }

    func makeCoordinator() -> Coordinator { Coordinator(onScan: onScan) }

    final class Coordinator: NSObject, DataScannerViewControllerDelegate {
        private let onScan: (String) -> Void
        private var hasScanned = false

        init(onScan: @escaping (String) -> Void) { self.onScan = onScan }

        func dataScanner(_ scanner: DataScannerViewController,
                         didAdd addedItems: [RecognizedItem],
                         allItems: [RecognizedItem]) {
            guard !hasScanned else { return }
            for case let .barcode(barcode) in addedItems {
                guard let code = barcode.payloadStringValue, !code.isEmpty else { continue }
                hasScanned = true
                UINotificationFeedbackGenerator().notificationOccurred(.success)
                scanner.stopScanning()
                onScan(code)
                return
            }
        }
    }
}

// MARK: - Feuille de scan (caméra + recherche du produit)

struct FoodScanSheet: View {
    /// Appelé avec le produit trouvé ; la feuille se ferme ensuite.
    var onFound: (ScannedProduct) -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var isSearching = false
    @State private var errorMessage: String?
    @State private var manualCode = ""
    @FocusState private var manualFocused: Bool

    private var scannerAvailable: Bool {
        DataScannerViewController.isSupported && DataScannerViewController.isAvailable
    }

    var body: some View {
        NavigationStack {
            ZStack {
                if scannerAvailable {
                    BarcodeScannerView { code in handle(code) }
                        .ignoresSafeArea(edges: .bottom)
                    reticle
                } else {
                    unavailableState
                }

                if isSearching {
                    Color.black.opacity(0.55).ignoresSafeArea()
                    VStack(spacing: 12) {
                        ProgressView().controlSize(.large).tint(.white)
                        Text("Recherche du produit…")
                            .font(.subheadline).foregroundStyle(.white)
                    }
                }
            }
            .overlay(alignment: .bottom) {
                if let errorMessage, !isSearching {
                    errorBanner(errorMessage)
                } else if scannerAvailable && !isSearching {
                    hint
                }
            }
            .navigationTitle("Scanner un produit")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Fermer") { dismiss() }
                }
            }
        }
    }

    // MARK: Sous-vues

    /// Viseur : le pourtour est assombri, une fenêtre nette indique où viser
    private var reticle: some View {
        GeometryReader { geo in
            let w = min(geo.size.width * 0.80, 330)
            let h = w * 0.60
            ZStack {
                Color.black.opacity(0.45)
                    .mask {
                        Rectangle()
                            .overlay(alignment: .center) {
                                RoundedRectangle(cornerRadius: 22, style: .continuous)
                                    .frame(width: w, height: h)
                                    .blendMode(.destinationOut)
                            }
                            .compositingGroup()
                    }
                RoundedRectangle(cornerRadius: 22, style: .continuous)
                    .stroke(.white.opacity(0.95), lineWidth: 3)
                    .frame(width: w, height: h)
                    .shadow(color: .black.opacity(0.35), radius: 6)
            }
            .frame(width: geo.size.width, height: geo.size.height)
        }
        .ignoresSafeArea()
        .allowsHitTesting(false)
    }

    private var hint: some View {
        Text("Vise le code-barres du produit")
            .font(.footnote.weight(.medium))
            .foregroundStyle(.white)
            .padding(.horizontal, 16).padding(.vertical, 10)
            .background(.black.opacity(0.55), in: Capsule())
            .padding(.bottom, 28)
    }

    private func errorBanner(_ message: String) -> some View {
        VStack(spacing: 10) {
            Text(message)
                .font(.footnote)
                .multilineTextAlignment(.center)
            Button("Réessayer") { errorMessage = nil }
                .font(.footnote.weight(.semibold))
        }
        .padding(14)
        .frame(maxWidth: .infinity)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
        .padding(.horizontal)
        .padding(.bottom, 24)
    }

    /// Simulateur ou appareil sans scanner : saisie manuelle du code
    private var unavailableState: some View {
        VStack(spacing: 16) {
            Image(systemName: "barcode.viewfinder")
                .font(.system(size: 46))
                .foregroundStyle(Color.brand)
            Text("Scanner indisponible")
                .font(.headline)
            Text("La caméra n'est pas accessible ici. Tu peux saisir le code-barres à la main.")
                .font(.subheadline).foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
            HStack {
                TextField("Code-barres", text: $manualCode)
                    .keyboardType(.numberPad)
                    .textFieldStyle(.roundedBorder)
                    .focused($manualFocused)
                Button("Chercher") { handle(manualCode) }
                    .buttonStyle(.borderedProminent)
                    .tint(Color.brand)
                    .disabled(manualCode.count < 6)
            }
        }
        .padding(24)
    }

    // MARK: Recherche

    private func handle(_ code: String) {
        let barcode = code.trimmingCharacters(in: .whitespaces)
        guard !barcode.isEmpty, !isSearching else { return }
        manualFocused = false
        isSearching = true
        errorMessage = nil

        Task {
            do {
                let product = try await OpenFoodFacts.lookup(barcode: barcode)
                isSearching = false
                onFound(product)
                dismiss()
            } catch {
                isSearching = false
                errorMessage = error.localizedDescription
            }
        }
    }
}
