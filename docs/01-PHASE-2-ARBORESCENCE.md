# Somna v0.1 — Phase 2 : Arborescence et rôle des modules

> Suite de [00-PHASE-1-ANALYSE.md](00-PHASE-1-ANALYSE.md). Les décisions verrouillées en Phase 1 sont reprises telles quelles.
> Statut : **structure créée sur disque**. Les fichiers Swift listés ci-dessous sont le plan des phases 3 à 6, pas des fichiers déjà écrits.

---

## 1. Vue d'ensemble

```
somna/
├── project.yml                  # Définition XcodeGen — source de vérité du projet Xcode
├── README.md
├── CHANGELOG.md
├── .gitignore
├── .github/workflows/           # Phase 7 — CI, archive, release, feed AltStore
├── altstore/                    # Phase 7 — apps.json + assets de la source
├── scripts/                     # Phase 7 — outils Python/shell exécutables depuis Windows
├── docs/                        # Documentation (ce dossier)
├── Somna/                       # Cible applicative
└── SomnaTests/ + SomnaUITests/  # Cibles de test
```

**Le projet Xcode n'est pas versionné.** Il est régénéré depuis `project.yml` par XcodeGen, sur le runner macOS comme en local. C'est ce qui rend le développement possible depuis Windows.

---

## 2. Arborescence détaillée de la cible applicative

Légende : `▸` = fichier planifié, avec la phase où il est écrit.

### 2.1 `Somna/App/` — amorçage et composition

Le seul endroit du projet qui a le droit de connaître les implémentations concrètes. C'est ici que les protocoles sont câblés à leurs implémentations réelles.

```
App/
├── SomnaApp.swift              ▸P3  @main, ModelContainer, injection de l'environnement
├── AppEnvironment.swift        ▸P3  Conteneur de services typés par protocole
├── AppEnvironment+Live.swift   ▸P3  Câblage des implémentations réelles
├── AppEnvironment+Preview.swift ▸P3 Doublures pour previews et tests
├── AppRouter.swift             ▸P3  Destinations, NavigationPath, deep links
├── RootView.swift              ▸P3  Aiguillage onboarding / app principale
└── AppLifecycle.swift          ▸P5  scenePhase, reprise de session interrompue
```

`AppEnvironment` est le **point d'injection unique**. Aucun `.shared` mutable ailleurs dans le projet.

### 2.2 `Somna/Core/` — utilitaires transverses, sans logique métier

```
Core/
├── Extensions/
│   ├── Date+Night.swift        ▸P3  Nuit civile, bornes, comparaisons
│   ├── TimeInterval+Format.swift ▸P3 Durées localisées (testé unitairement)
│   ├── Collection+Safe.swift   ▸P3
│   └── URL+Somna.swift         ▸P3  Racines de dossiers, chemins relatifs
├── Utilities/
│   ├── Clock.swift             ▸P3  Protocole horloge injectable (tests déterministes)
│   ├── Debouncer.swift         ▸P4
│   └── ByteFormatter.swift     ▸P3  Tailles de fichiers localisées
├── Logging/
│   ├── Log.swift               ▸P3  Façade os.Logger, catégories typées
│   ├── LogCategory.swift       ▸P3  app, audio, analysis, persistence, …
│   └── DiagnosticExporter.swift ▸P7 Export de logs anonymisés
├── Errors/
│   ├── SomnaError.swift        ▸P3  Erreur racine, LocalizedError
│   ├── AudioError.swift        ▸P5
│   ├── AnalysisError.swift     ▸P6
│   └── StorageError.swift      ▸P3
└── Constants/
    ├── AudioConstants.swift    ▸P5  16 kHz, mono, 32 kbps, segments 10 min
    └── AnalysisConstants.swift ▸P6  Seuils de confiance, fenêtres de groupement
```

**Règle de journalisation :** `Log` interdit structurellement l'écriture de contenu sensible. Les chemins de fichiers audio sont journalisés sous forme d'identifiant tronqué, jamais en clair.

### 2.3 `Somna/DesignSystem/` — langage visuel, réutilisable, sans dépendance métier

```
DesignSystem/
├── Foundation/
│   ├── SomnaColor.swift        ▸P3  Tokens sémantiques uniquement
│   ├── SomnaTypography.swift   ▸P3  Styles Dynamic Type
│   ├── SomnaSpacing.swift      ▸P3  Échelle 4/8/12/16/24/32
│   ├── SomnaRadius.swift       ▸P3
│   └── SomnaMotion.swift       ▸P3  Durées, courbes, respect de Reduce Motion
├── Components/
│   ├── Cards/       SomnaCard, StatCard, NightSummaryCard, EventCard       ▸P4
│   ├── Buttons/     PrimaryButton, GlassActionButton, DestructiveButton    ▸P4
│   ├── Charts/      TrendChart, DistributionChart, ChartLegend             ▸P4
│   ├── Waveform/    WaveformView, MiniWaveform, WaveformRenderer           ▸P4
│   └── States/      EmptyStateView, ErrorStateView, LoadingStateView       ▸P4
├── Effects/
│   ├── GlassSurface.swift      ▸P4  Enveloppe unique de Liquid Glass
│   └── NightGradient.swift     ▸P4  Fond nocturne discret
├── Haptics/
│   ├── HapticFeedback.swift    ▸P3  Protocole
│   └── LiveHapticFeedback.swift ▸P3 Implémentation CoreHaptics/UIFeedback
└── Accessibility/
    ├── AccessibilityFlags.swift ▸P3 Lecture des réglages système
    └── View+Accessible.swift    ▸P3 Modificateurs partagés
```

**Deux invariants :**
1. Aucune valeur hexadécimale hors de `SomnaColor` et du catalogue d'assets.
2. `GlassSurface` est le **seul** point du projet appelant l'effet Liquid Glass. Il gère `Reduce Transparency` et `Increased Contrast` en un endroit unique, ce qui rend impossible d'oublier l'accessibilité dans un écran isolé. C'est aussi le garde-fou contre la sur-utilisation identifiée en risque R10.

### 2.4 `Somna/Domain/` — le cœur, en Swift pur

**Aucun `import SwiftUI`, `import SwiftData`, `import AVFoundation` dans ce dossier.** C'est ce qui rend le score, le groupement et le résumé testables sans simulateur, en quelques millisecondes.

```
Domain/
├── Models/
│   ├── NightSession.swift      ▸P3  Struct de domaine (≠ modèle SwiftData)
│   ├── NightEvent.swift        ▸P3
│   ├── NightEventType.swift    ▸P3  Enum extensible + libellés prudents
│   ├── EventConfidence.swift   ▸P3  high / medium / low, avec formulation
│   ├── AudioSegment.swift      ▸P3
│   ├── CalibrationProfile.swift ▸P3
│   ├── UserSettings.swift      ▸P3
│   ├── RecordingQuality.swift  ▸P3  excellent / correct / faible / inexploitable
│   ├── NightStatistics.swift   ▸P3
│   └── DemoData.swift          ▸P4  Jeux d'essai pour previews UNIQUEMENT
├── Protocols/                      # Les « ports » — ce que le domaine attend du monde
│   ├── NightSessionRepositing.swift    ▸P3
│   ├── AudioRecording.swift            ▸P3
│   ├── AudioPlaying.swift              ▸P3
│   ├── NightAnalyzing.swift            ▸P3
│   ├── SoundClassifying.swift          ▸P3
│   ├── SummaryGenerating.swift         ▸P3  ← futur point d'entrée LLM
│   ├── PermissionRequesting.swift      ▸P3
│   ├── NotificationScheduling.swift    ▸P3
│   ├── FileStoring.swift               ▸P3
│   └── HapticFeedbacking.swift         ▸P3
├── Analysis/                       # Algorithmes purs, 100 % testables
│   ├── CalmnessScoreCalculator.swift   ▸P6
│   ├── EventGrouper.swift              ▸P6  Fusion des événements < 90 s
│   ├── SleepWindowEstimator.swift      ▸P6  Endormissement / réveil « probables »
│   ├── StatisticsCalculator.swift      ▸P6
│   ├── RecordingQualityAssessor.swift  ▸P6
│   └── Summary/
│       ├── TemplateSummaryGenerator.swift  ▸P6
│       ├── SummaryTemplates.swift          ▸P6
│       └── SummaryFacts.swift              ▸P6  Faits extraits — rien d'autre n'est citable
└── UseCases/
    ├── StartNightSessionUseCase.swift  ▸P5
    ├── StopNightSessionUseCase.swift   ▸P5
    ├── AnalyzeNightUseCase.swift       ▸P6
    ├── DeleteNightUseCase.swift        ▸P4
    ├── ApplyRetentionPolicyUseCase.swift ▸P4
    └── SearchNightsUseCase.swift       ▸P4
```

**`SummaryFacts` est le garde-fou anti-hallucination.** Le générateur de résumé ne reçoit que cette structure, extraite des événements réels. Il lui est structurellement impossible de citer un événement inexistant, et un test unitaire vérifie que toute entité mentionnée dans le texte figure dans les faits.

### 2.5 `Somna/Data/` — persistance

```
Data/
├── Persistence/
│   ├── SomnaSchemaV1.swift         ▸P3  VersionedSchema
│   ├── SomnaMigrationPlan.swift    ▸P3  Vide mais présent dès le jour 1
│   ├── SDNightSession.swift        ▸P3  @Model
│   ├── SDNightEvent.swift          ▸P3
│   ├── SDAudioSegment.swift        ▸P3
│   ├── SDCalibrationProfile.swift  ▸P3
│   └── ModelContainerFactory.swift ▸P3
├── Repositories/
│   ├── NightSessionRepository.swift ▸P3  @ModelActor
│   ├── SettingsRepository.swift     ▸P3  UserDefaults, pas SwiftData
│   └── CalibrationRepository.swift  ▸P3
├── Mappers/
│   ├── NightSessionMapper.swift     ▸P3  @Model ⇄ struct de domaine
│   └── NightEventMapper.swift       ▸P3
└── FileSystem/
    ├── NightFileStore.swift         ▸P3  Arborescence disque, écriture atomique
    ├── NightManifest.swift          ▸P3  manifest.json, filet de sécurité
    ├── StorageCalculator.swift      ▸P3  Espace utilisé / disponible réel
    └── OrphanCleaner.swift          ▸P3  Purge au lancement
```

**Le domaine ne voit jamais un `@Model`.** Les mappers traduisent dans les deux sens. Coût : du code de conversion. Bénéfice : le risque R5 (SwiftData) devient un problème d'implémentation remplaçable, pas une contamination de tout le projet.

### 2.6 `Somna/Services/` — adaptateurs vers les frameworks Apple

```
Services/
├── Audio/
│   ├── Session/
│   │   ├── AudioSessionController.swift    ▸P5  AVAudioSession, catégorie, activation
│   │   ├── InterruptionHandler.swift       ▸P5  Interruptions + mediaServicesWereReset
│   │   └── RouteChangeHandler.swift        ▸P5
│   ├── Recording/
│   │   ├── AudioRecordingEngine.swift      ▸P5  actor — AVAudioEngine + tap
│   │   ├── SegmentWriter.swift             ▸P5  Rotation 10 min, .part → atomique
│   │   ├── RealtimeMetricsExtractor.swift  ▸P5  vDSP : RMS, crête, ZCR, centroïde
│   │   ├── MetricsWriter.swift             ▸P5  JSONL par segment
│   │   └── RecordingStateMachine.swift     ▸P5  États explicites, testable
│   └── Playback/
│       ├── ClipPlayer.swift                ▸P4  actor — AVAudioPlayer
│       └── NowPlayingCoordinator.swift     ▸P4  Lecteur persistant inter-écrans
├── Analysis/
│   ├── NightAnalysisEngine.swift           ▸P6  actor — orchestration passe B
│   ├── CandidateSelector.swift             ▸P6  Zones à analyser (5–15 % de la nuit)
│   ├── SoundAnalysisClassifier.swift       ▸P6  SNAudioFileAnalyzer
│   ├── ClassificationMapping.swift         ▸P6  Label Apple → NightEventType
│   ├── RuleBasedRefiner.swift              ▸P6  Fusion règles DSP + ML
│   ├── FeatureExtractor.swift              ▸P6  Accelerate
│   ├── ClipExtractor.swift                 ▸P6  Extraits ±3 s
│   └── AnalysisProgress.swift              ▸P6
├── Calibration/
│   ├── CalibrationService.swift            ▸P5
│   └── PlacementQualityEvaluator.swift     ▸P5
├── Notifications/
│   ├── NotificationService.swift           ▸P4
│   └── NotificationContentBuilder.swift    ▸P4  Textes non culpabilisants
├── Permissions/
│   └── PermissionService.swift             ▸P3  Micro + notifications, états complets
├── Storage/
│   ├── RetentionService.swift              ▸P4
│   └── DiskSpaceMonitor.swift              ▸P4
├── Export/
│   ├── JSONExporter.swift                  ▸P4
│   ├── CSVExporter.swift                   ▸P4
│   └── ClipExporter.swift                  ▸P4
└── Privacy/
    └── DataEraser.swift                    ▸P4  Suppression totale, sans orphelin
```

**Ordre de suppression imposé** dans `DataEraser` : fichiers d'abord, base ensuite, puis balayage des orphelins. L'ordre inverse laisserait des fichiers non référencés et donc invisibles, mais occupant l'espace.

### 2.7 `Somna/Features/` — un dossier par écran

Chaque feature suit le même patron : `XxxView.swift` (SwiftUI, ≤ 150 lignes) + `XxxStore.swift` (`@Observable`, `@MainActor`, la logique de présentation) + sous-vues.

```
Features/
├── Onboarding/       7 étapes, permissions, calibration              ▸P4
├── Home/             Accueil contextuel (3 états)                    ▸P4
├── Session/          Préparation (checklist pré-vol) + session active ▸P4/P5
├── NightReport/      Rapport complet                                  ▸P4
├── Timeline/         Timeline, groupes, filtres, correction           ▸P4
├── AudioPlayer/      Panneau lecteur Liquid Glass persistant          ▸P4
├── History/          Liste + calendrier                               ▸P4
├── Trends/           5 graphiques Swift Charts                        ▸P4
├── Search/           Recherche structurée locale                      ▸P4
├── AskSomna/         Moteur d'intentions prédéfinies                  ▸P4
├── Settings/         7 sections                                       ▸P4
└── Premium/          Vitrine désactivée                               ▸P4
```

### 2.8 `Somna/Resources/`

```
Resources/
├── Assets.xcassets              ▸P3  Couleurs sémantiques, AppIcon, symboles
├── Localizable.xcstrings        ▸P3  FR + EN, zéro chaîne en dur
├── InfoPlist.xcstrings          ▸P3  Descriptions de permissions localisées
├── PrivacyInfo.xcprivacy        ▸P3  Manifeste de confidentialité
└── Info.plist                   (généré par XcodeGen — non versionné)
```

---

## 3. Tests

```
SomnaTests/
├── Unit/
│   ├── CalmnessScoreTests.swift          ▸P6
│   ├── EventGrouperTests.swift           ▸P6
│   ├── SummaryGeneratorTests.swift       ▸P6  dont l'invariant anti-hallucination
│   ├── SleepWindowEstimatorTests.swift    ▸P6
│   ├── RetentionPolicyTests.swift        ▸P4
│   ├── DurationFormattingTests.swift     ▸P3
│   ├── StatisticsCalculatorTests.swift   ▸P6
│   ├── MapperTests.swift                 ▸P3
│   ├── SearchFilterTests.swift           ▸P4
│   ├── ConfidenceLabelTests.swift        ▸P3  Vérifie l'absence de vocabulaire interdit
│   └── ClassificationMappingTests.swift  ▸P6
├── Integration/
│   ├── RecordingSessionTests.swift       ▸P5  Session simulée complète
│   ├── SegmentationTests.swift           ▸P5
│   ├── InterruptionRecoveryTests.swift   ▸P5
│   ├── AnalysisPipelineTests.swift       ▸P6  Fichier réel → timeline
│   ├── PersistenceTests.swift            ▸P3  Container en mémoire
│   └── DeletionIntegrityTests.swift      ▸P4  Zéro orphelin après suppression
└── Support/
    ├── Fixtures.swift                    ▸P3
    ├── FakeClock.swift                   ▸P3
    ├── SpyRepositories.swift             ▸P3
    └── AudioFixtureGenerator.swift       ▸P5  Génère des WAV synthétiques

SomnaUITests/
├── OnboardingFlowTests.swift             ▸P4
├── PermissionDeniedTests.swift           ▸P4
├── NightReportTests.swift                ▸P4
├── DeletionFlowTests.swift               ▸P4
└── DynamicTypeTests.swift                ▸P8  Jusqu'à AX5
```

`ConfidenceLabelTests` mérite une mention : il vérifie qu'aucun libellé produit par le domaine ne contient de vocabulaire médical ou d'affirmation de mouvement corporel. C'est la liste de blocage de la Phase 1 §11 transformée en test automatique.

---

## 4. Écarts par rapport à la structure suggérée dans le cahier des charges

| Écart | Justification |
|---|---|
| `Domain/Analysis/` ajouté | Sépare les **algorithmes purs** (score, groupement, résumé) des **adaptateurs de framework** (`Services/Analysis`). Ce sont les algorithmes qu'on veut tester, et ils ne doivent rien importer. |
| `Recording` fusionné dans `Features/Session` | Préparation et session active sont un seul parcours continu. Deux dossiers auraient dupliqué le store. |
| `Features/Search` et `Features/AskSomna` ajoutés | Explicitement demandés aux §28–29 mais absents de l'arborescence suggérée. |
| `Data/FileSystem/` ajouté | Le stockage fichier est une responsabilité distincte de la base. Le manifeste de secours a besoin de son propre foyer. |
| `Services/Calibration/` ajouté | La calibration est un service à part entière, utilisé par l'onboarding **et** par les réglages (recalibration). |
| `Tests/` remplacé par `SomnaTests/` + `SomnaUITests/` | Contrainte Xcode : deux types de bundles différents, donc deux cibles, donc deux racines. |
| Pas de packages SPM locaux | Voir Phase 1 §6.2. Compromis assumé, extraction possible en v0.2 sans déplacer un fichier. |

---

## 5. Fichiers créés en Phase 2

| Fichier | Rôle |
|---|---|
| `project.yml` | Définition XcodeGen complète : cibles, réglages, Info.plist, schéma |
| `.gitignore` | Exclut le projet Xcode généré, les artefacts de build, l'Info.plist généré |
| `README.md` | Entrée du dépôt : ce qu'est Somna, statut, démarrage, avertissement non médical |
| `CHANGELOG.md` | Journal de version, alimente les notes de release AltStore |
| `docs/01-PHASE-2-ARBORESCENCE.md` | Ce document |
| `docs/02-CONVENTIONS.md` | Conventions de code, nommage, git, revue |
| Structure de dossiers | 66 dossiers avec `.gitkeep` |

---

## 6. Commandes

Depuis Windows, aucune compilation n'est possible — seule la génération est validable sur macOS ou en CI.

```bash
# Sur macOS ou sur le runner GitHub Actions
brew install xcodegen
xcodegen generate
open Somna.xcodeproj
```

```bash
# Depuis Windows : vérifier que project.yml est du YAML valide
python -c "import yaml,sys; yaml.safe_load(open('project.yml')); print('project.yml OK')"
```

---

## 7. Checklist de validation — Phase 2

- [x] Arborescence créée sur disque (66 dossiers)
- [x] `project.yml` complet : 3 cibles, 2 configurations, 1 schéma
- [x] Cible iOS 26.0, iPhone uniquement, portrait
- [x] `UIBackgroundModes: [audio]` déclaré — seul mode utilisé
- [x] `NSMicrophoneUsageDescription` rédigé et explicite sur le local-first
- [x] Versioning piloté par `MARKETING_VERSION` / `CURRENT_PROJECT_VERSION`, pilotables par la CI
- [x] Signature laissée aux défauts Xcode, `CODE_SIGNING_ALLOWED=NO` réservé à la CI
- [x] Swift 6 avec isolation MainActor par défaut
- [x] Projet Xcode et Info.plist exclus du versionnement
- [x] YAML syntaxiquement valide
- [x] Rôle de chaque module documenté, écarts justifiés
- [ ] `xcodegen generate` exécuté sur macOS — **non validable depuis Windows, sera vérifié au premier run CI**

---

**Prochaine étape : Phase 3 — Fondations.** Point d'entrée, `AppEnvironment`, routage, design system, modèles de domaine, schéma SwiftData versionné, repositories, erreurs, logs, permissions. Objectif de sortie : le projet compile et lance un écran navigable.
