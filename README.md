# 🏃 LiftRun

**LiftRun : l'app iOS qui centralise toute ton activité sportive** — musculation, course GPS, Live Activities dans la Dynamic Island, widgets d'écran d'accueil. 100 % frameworks Apple, zéro dépendance externe, données 100 % locales.

![iOS](https://img.shields.io/badge/iOS-17.0%2B-black?logo=apple)
![Swift](https://img.shields.io/badge/Swift-5-F05138?logo=swift&logoColor=white)
![SwiftUI](https://img.shields.io/badge/SwiftUI-blue)
![SwiftData](https://img.shields.io/badge/SwiftData-local--first-purple)
![Dépendances](https://img.shields.io/badge/d%C3%A9pendances-z%C3%A9ro-brightgreen)

<p align="center">
  <img src="docs/screenshots/accueil.png" width="300" alt="Écran d'accueil — dashboard Liquid Glass" />
</p>

---

## ✨ Fonctionnalités

### 💪 Musculation
- Programme A/B/C pré-chargé (instructions en français) + éditeur complet de séances
- Saisie reps/poids (pas de 1,25 kg), timer de repos automatique, check d'objectif
- **Bibliothèque de 1 324 exercices** : recherche, filtres par zone (10) et matériel (28), fiches avec exécution pas-à-pas
- **Photos de mouvement libres de droits** ([Free Exercise DB](https://github.com/yuhonas/free-exercise-db), domaine public) sur 155 exercices dont tout le programme — illustration vectorielle sinon

### 🏃 Course GPS (style Strava)
- Carte MapKit avec tracé en temps réel, allure instantanée lissée sur 200 m
- Fonctionne **écran verrouillé** (background location), pause/reprise
- **Circuits préenregistrés** : 4 parcours réels inclus (bords de l'Erdre et île de Nantes à Nantes, tour de ville et boucle du centre à Challans — tracés générés par routage piéton OpenStreetMap). Dépose n'importe quel `.gpx` dans `GymTracker/Circuits/` pour en ajouter ; le parcours choisi s'affiche en pointillés sur la carte pendant ta course
- **Export GPX** de chaque course enregistrée (bouton partager sur le détail du parcours)

### 🏝️ Dynamic Island & écran verrouillé (Live Activities)
- Timer de repos : décompte animé par le système (économe en batterie)
- Course : allure / distance / temps en direct
- Mises à jour 100 % locales — aucun serveur, aucun push distant

### 📱 Widgets d'écran d'accueil
- **Streak** : jauge de jours d'activité consécutifs (muscu + course confondues)
- **Volume d'entraînement** : courbe des kg soulevés par semaine (Swift Charts dans WidgetKit)
- **Courir** : raccourci qui ouvre l'app directement sur le mode course
- Base SwiftData partagée app ↔ widgets via App Group

### 📈 Progression
- Muscu : courbe de charge max par exercice, record / dernière / évolution
- Course : courbes d'**allure**, de **distance** et de **durée** par sortie, records et total couru
- Calendrier mensuel unifié : pastilles séances (indigo) et courses (vert)

### 👤 Profil & onboarding
- Au premier lancement, l'app demande prénom, sexe, taille et poids (modifiables via l'icône profil de l'accueil, IMC calculé)
- L'accueil salue l'utilisateur par son prénom — tout reste en local, aucun compte

### 👑 Premium (infrastructure prête)
- StoreKit 2 intégré : produit lifetime, paywall, restauration d'achats
- **Config StoreKit locale** (`Products.storekit` branchée au scheme) : l'achat se teste dans Xcode sans App Store Connect
- Offre gratuite limitée à 3 séances personnalisées ; circuits GPX et widgets en Premium

## 📸 Captures

| Accueil | Séances | Course |
|:---:|:---:|:---:|
| <img src="docs/screenshots/accueil.png" alt="Accueil — dashboard" /> | <img src="docs/screenshots/seances.png" alt="Séances — programme A/B/C" /> | <img src="docs/screenshots/course.png" alt="Course — GPS et circuits" /> |

| Calendrier | Progression |
|:---:|:---:|
| <img src="docs/screenshots/calendrier.png" alt="Calendrier des activités" width="300" /> | <img src="docs/screenshots/progression.jpeg" alt="Progression — muscu et course" width="300" /> |

## 🧱 Architecture

```
GymTracker/                         # TARGET APP (fr.devshield.gymtracker)
├── GymTrackerApp.swift             # @main, ModelContainer (App Group), seed A/B/C
├── Models.swift                    # Modèles SwiftData + SharedStore (conteneur partagé)
├── RootTabView.swift               # 5 onglets + deeplink gymtracker://run
├── HomeView.swift                  # Dashboard Liquid Glass (streak, volume, km)
├── TemplatesView.swift             # Séances + éditeur (limite gratuite : 3)
├── ActiveWorkoutView.swift         # Séance en cours → Live Activity + notification
├── RunningView.swift               # Course : carte, stats live, circuits GPX
├── RunTracker.swift                # CoreLocation : distance, allure lissée
├── GPXCircuits.swift               # Parser GPX léger → [CLLocationCoordinate2D]
├── PremiumStore.swift              # StoreKit 2 + PaywallView
├── ProgressChartsView.swift        # Courbes muscu (Swift Charts)
├── RunProgressView.swift           # Courbes course (allure/distance/durée)
├── HistoryView.swift               # Calendrier unifié séances + courses
├── LiveActivityManager.swift       # Démarre/màj/termine les Live Activities
├── NotificationManager.swift       # Notifications locales (fin de repos)
├── ExerciseCatalog.swift           # Catalogue + illustrations SF Symbols
├── ExerciseLibraryView.swift       # Bibliothèque, filtres, fiches
├── ExerciseTranslationsFR.swift    # Instructions FR du programme
├── Circuits/*.gpx                  # Parcours préenregistrés (ressources)
├── exercises_catalog.json          # 1 324 exercices (texte uniquement)
└── Shared/LiveActivityAttributes.swift   # Partagé avec le widget

GymTrackerWidgets/                  # TARGET WIDGET EXTENSION (.widgets)
├── GymTrackerWidgetsBundle.swift   # Live Activities + widgets accueil
├── RestTimerLiveActivity.swift     # Îlot + écran verrouillé (repos)
├── RunLiveActivity.swift           # Îlot + écran verrouillé (course)
└── HomeWidgets.swift               # StreakWidget + RunShortcutWidget
```

**Modèle de données (SwiftData)** : `WorkoutTemplate` 1—N `ExerciseTemplate` (programme éditable) · `WorkoutSession` 1—N `SetRecord` (historique muscu) · `RunSession` (courses, tracé GPS encodé). Base stockée dans l'App Group `group.fr.devshield.gymtracker`, lisible par les widgets.

## 🛠️ Installation

Prérequis : Xcode 26+ (icône Icon Composer), iPhone sous iOS 17+.

```bash
git clone <ce-repo>
cd GymTracker
open GymTracker.xcodeproj
```

1. Dans Xcode : sélectionne ton équipe (**Signing & Capabilities → Team**) sur **les deux cibles** — l'App Group `group.fr.devshield.gymtracker` et les bundle IDs sont déjà configurés (adapte-les si tu utilises ta propre équipe)
2. iPhone branché, **Mode développeur** activé (Réglages → Confidentialité et sécurité)
3. **⌘R** — au premier lancement, fais confiance au certificat (Réglages → Général → VPN et gestion d'appareils) et accepte localisation + notifications

> ⏳ **Compte Apple gratuit** : la signature expire après 7 jours → rebrancher et ⌘R (les données sont conservées). Max 3 apps sideloadées.

## 🔒 Données & confidentialité

Tout est **local** : SwiftData sur l'appareil, aucun compte, aucun serveur, aucune télémétrie. La seule connexion sortante possible est le fond de carte Apple Maps en mode course.

## ⚖️ Licences

- **Code** : © DevShield — tous droits réservés (licence à définir avant réutilisation).
- **Catalogue d'exercices** : structure textuelle (noms, muscles, instructions) issue de [hasaneyldrm/exercises-dataset](https://github.com/hasaneyldrm/exercises-dataset). Les médias propriétaires (images/GIFs) ont été **retirés** de ce dépôt. ⚠️ Vérifie la licence du dataset source avant tout usage commercial ou soumission App Store.
- **Photos d'exercices** : [Free Exercise DB](https://github.com/yuhonas/free-exercise-db) — domaine public ([Unlicense](https://unlicense.org)), chargées à la demande.

## 🗺️ Roadmap

- [x] Visuels d'exercices libres de droits — Free Exercise DB (155 exercices mappés, matching nom + muscle + matériel)
- [x] Widgets de courbes de progression (WidgetKit + Swift Charts) — volume hebdo
- [x] Export GPX des courses enregistrées
- [x] Config StoreKit locale pour tester le paywall sans App Store Connect
- [ ] Produit In-App dans App Store Connect (nécessite l'adhésion Apple Developer payante — le code et l'ID `fr.devshield.gymtracker.premium.lifetime` sont prêts)
- [ ] Étendre le mapping photos au-delà des 155 exercices (API [wger](https://wger.de) en complément)
