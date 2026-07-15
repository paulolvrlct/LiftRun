import Foundation
import CoreLocation

// MARK: - Circuit de course préenregistré

/// Parcours figé chargé depuis un fichier .gpx embarqué dans le bundle.
/// Pour ajouter un circuit : déposer un .gpx standard dans `GymTracker/Circuits/`.
struct RunCircuit: Identifiable {
    let id: String              // nom de fichier
    let name: String
    let coordinates: [CLLocationCoordinate2D]

    /// Longueur du tracé en km (somme des segments)
    var distanceKm: Double {
        guard coordinates.count > 1 else { return 0 }
        var total = 0.0
        for i in 1..<coordinates.count {
            let a = CLLocation(latitude: coordinates[i - 1].latitude, longitude: coordinates[i - 1].longitude)
            let b = CLLocation(latitude: coordinates[i].latitude, longitude: coordinates[i].longitude)
            total += b.distance(from: a)
        }
        return total / 1000
    }
}

extension RunCircuit: Hashable {
    static func == (lhs: RunCircuit, rhs: RunCircuit) -> Bool { lhs.id == rhs.id }
    func hash(into hasher: inout Hasher) { hasher.combine(id) }
}

// MARK: - Bibliothèque des circuits du bundle

enum CircuitLibrary {
    static let all: [RunCircuit] = {
        let urls = Bundle.main.urls(forResourcesWithExtension: "gpx", subdirectory: nil) ?? []
        return urls
            .compactMap { GPXParser.parse(url: $0) }
            .sorted { $0.name < $1.name }
    }()
}

// MARK: - Export GPX d'une course enregistrée

enum GPXExporter {
    /// Document GPX 1.1 du tracé (points sans horodatage individuel — non stocké)
    static func document(for run: RunSession) -> String {
        let iso = ISO8601DateFormatter().string(from: run.date)
        let points = run.routePoints
            .map { String(format: "      <trkpt lat=\"%.6f\" lon=\"%.6f\"></trkpt>", $0.lat, $0.lon) }
            .joined(separator: "\n")
        return """
        <?xml version="1.0" encoding="UTF-8"?>
        <gpx version="1.1" creator="GymTracker" xmlns="http://www.topografix.com/GPX/1/1">
          <metadata><time>\(iso)</time></metadata>
          <trk>
            <name>Course GymTracker — \(String(format: "%.2f", run.distanceKm)) km</name>
            <trkseg>
        \(points)
            </trkseg>
          </trk>
        </gpx>
        """
    }

    /// Écrit le .gpx dans le dossier temporaire (pour ShareLink) et renvoie son URL
    static func exportFile(for run: RunSession) -> URL? {
        guard run.routePoints.count > 1 else { return nil }
        let stamp = run.date.formatted(.iso8601.year().month().day())
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("GymTracker-course-\(stamp).gpx")
        do {
            try document(for: run).write(to: url, atomically: true, encoding: .utf8)
            return url
        } catch {
            return nil
        }
    }
}

// MARK: - Parser GPX léger (XMLParser Foundation)

/// Extrait le premier <name> et tous les points <trkpt>/<rtept> (attributs lat/lon).
final class GPXParser: NSObject, XMLParserDelegate {
    private var coordinates: [CLLocationCoordinate2D] = []
    private var name: String?
    private var currentElement = ""

    static func parse(url: URL) -> RunCircuit? {
        guard let parser = XMLParser(contentsOf: url) else { return nil }
        let delegate = GPXParser()
        parser.delegate = delegate
        guard parser.parse(), delegate.coordinates.count > 1 else { return nil }
        return RunCircuit(
            id: url.lastPathComponent,
            name: delegate.name ?? url.deletingPathExtension().lastPathComponent,
            coordinates: delegate.coordinates
        )
    }

    func parser(_ parser: XMLParser, didStartElement elementName: String,
                namespaceURI: String?, qualifiedName: String?,
                attributes attributeDict: [String: String] = [:]) {
        currentElement = elementName
        if elementName == "trkpt" || elementName == "rtept",
           let lat = attributeDict["lat"].flatMap(Double.init),
           let lon = attributeDict["lon"].flatMap(Double.init) {
            coordinates.append(CLLocationCoordinate2D(latitude: lat, longitude: lon))
        }
    }

    func parser(_ parser: XMLParser, foundCharacters string: String) {
        guard currentElement == "name", name == nil else { return }
        let trimmed = string.trimmingCharacters(in: .whitespacesAndNewlines)
        if !trimmed.isEmpty { name = trimmed }
    }

    func parser(_ parser: XMLParser, didEndElement elementName: String,
                namespaceURI: String?, qualifiedName: String?) {
        currentElement = ""
    }
}
