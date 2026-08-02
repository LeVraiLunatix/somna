# Changelog

Toutes les modifications notables de Somna sont consignées ici.

Format inspiré de [Keep a Changelog](https://keepachangelog.com/fr/1.1.0/).
Versionnement sémantique. Les entrées de la section publiée la plus récente
alimentent automatiquement les notes de version de la source AltStore (Phase 7).

---

## [Non publié]

### Ajouté
- Phase 1 — Analyse de faisabilité complète : contraintes iOS de l'enregistrement nocturne,
  capacités réelles du microphone, stratégies audio / ML / stockage / distribution, registre des risques.
- Phase 2 — Arborescence du projet, définition XcodeGen (`project.yml`), conventions de code,
  README et journal de version.
- Phase 7 (minimale) — Workflow CI GitHub Actions validant la chaîne complète : sélection
  dynamique d'Xcode et du simulateur, garde sur le SDK iOS 26, génération du projet, tests
  unitaires et UI, archive non signée, packaging IPA et vérification du `Info.plist` empaqueté.
- Point d'entrée applicatif minimal, écran témoin, extension de version de bundle,
  catalogue d'assets initial et tests de non-régression sur le background mode `audio`.
- `scripts/validate-project.py` — 15 vérifications de `project.yml` exécutables depuis Windows.

- Phase 3A — Couche domaine en Swift pur, schéma SwiftData versionné, repository `@ModelActor`,
  mappers tolérants aux valeurs inconnues, réglages utilisateur.
- Vocabulaire prudent transformé en invariant testé : le build échoue si un libellé emploie du
  langage clinique, si une étiquette de mouvement affirme un mouvement corporel, ou si deux
  niveaux de confiance se lisent à l'identique.

- Phase 3B — Design system (palette sémantique, typographie Dynamic Type, mouvement,
  haptiques), `GlassSurface` comme point unique de Liquid Glass, service de permissions,
  stockage fichier atomique, `AppEnvironment` et routage.
- Écran de disponibilité : permissions, espace libre, nuits enregistrées, calibration.

### Corrigé
- Les cibles de test désactivent l'isolation MainActor par défaut : `XCTestCase` déclare ses
  initialiseurs et ses hooks de cycle de vie comme `nonisolated`, ce qui rendait toute
  sous-classe non compilable.
- L'espace libre était interrogé sur un dossier absent au premier lancement : une installation
  neuve aurait refusé d'enregistrer faute d'espace apparent.
- Les blocs `#Preview` sont encadrés en `#if DEBUG` : compilés en Release, ils atteignaient du
  code de preview volontairement absent des builds de production.

### Validé
- Chaîne complète Windows → runner macOS → IPA non signé, vérifiée sur un run réel
  (Xcode 26.6, SDK iOS 26.5). 55 tests au vert.

### Modifié
- L'isolation par défaut reste `nonisolated` au lieu de `MainActor` : le domaine, les
  repositories et les moteurs vivent hors du main actor et échangent des types valeur.
- `@unchecked Sendable` remplacé par `Mutex` là où il avait été introduit.

### Décisions verrouillées
- Cible iOS 26.0, iPhone uniquement, portrait.
- Audio AAC-LC 16 kHz mono 32 kbps, segments de 10 minutes.
- Classification par SoundAnalysis (classifieur embarqué Apple), sans modèle Core ML propriétaire en v0.1.
- Résumé généré localement par templates, protocole prêt pour un LLM embarqué en v0.2.
- Projet Xcode généré par XcodeGen, jamais versionné.
- IPA non signé, signature déléguée à AltStore côté utilisateur.
- Aucun accès réseau.

### Exclu de la v0.1
- Détection de mouvement par accéléromètre, HealthKit, Apple Watch, widgets,
  synchronisation iCloud, achats intégrés réels, transcription des paroles nocturnes.
