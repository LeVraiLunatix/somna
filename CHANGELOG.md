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

- Phase 4A — Onboarding en sept étapes, calibration réelle du micro, accueil contextuel,
  catalogue de localisation FR/EN (168 clés) généré et vérifié en CI.
- L'invariant de vocabulaire prudent couvre désormais le français : aucun libellé ne peut
  employer de langage clinique ni affirmer un mouvement corporel, dans l'une ou l'autre langue.

- Phase 5 — Moteur d'enregistrement : segments de dix minutes publiés atomiquement, gestion des
  interruptions et des réinitialisations du démon média, manifeste de secours réécrit après chaque
  segment, récupération au lancement des nuits inachevées et des fichiers orphelins.
- Écran de préparation distinguant ce qui bloque un enregistrement de ce qui le dégrade, et écran
  de session sobre pensé pour être regardé dans le noir.

- Phase 6A — Groupement des événements, score de tranquillité, statistiques, estimation de la
  fenêtre de sommeil, évaluation de la qualité d'enregistrement, et résumé structurellement
  incapable de citer un événement inexistant.
- Le résumé est stocké sous forme d'énoncés et rendu à l'affichage : changer la langue du
  téléphone relit correctement toutes les nuits passées.
- Le catalogue de localisation gère les pluriels.

- Phase 6B — Classification par le modèle sonore embarqué d'Apple, sélection des zones
  candidates depuis les métriques nocturnes, arbitrage par règles, extraction des extraits
  audio, et analyse déclenchée juste après la nuit.

- Phase 4B — Rapport de nuit, chronologie filtrable avec correction des événements, et lecteur
  d'extraits persistant entre les écrans.
- Le rapport masque ses statistiques quand l'audio est inexploitable, et place la qualité
  d'enregistrement avant les chiffres.

- Phase 4C — Réglages complets avec suppression des données et rétention, historique filtrable,
  tendances refusant de s'afficher sans données suffisantes, export local, vitrine Premium
  non achetable, et barre d'onglets.

- Phase 7 — Chaîne de publication complète : workflow de release déclenché par tag, source
  AltStore versionnée, icône d'application générée, manifeste de confidentialité, et guide
  d'installation. Rien n'est encore publié.

- Phase 8 — Audit d'accessibilité système sur chaque écran, y compris à la plus grande taille de
  texte, exécuté à chaque push. Trente problèmes trouvés et corrigés.

### Corrigé
- Contraste : `textTertiary` était sous le seuil de 4,5:1 dans les deux modes.
- Treize tailles de police fixes ignoraient Dynamic Type.
- Le bouton Retour de l'onboarding et la barre de progression avaient des zones tactiles trop
  petites ; l'étape est désormais affichée plutôt que cachée dans un libellé.
- Six textes se faisaient tronquer aux grandes tailles.
- Trois `try?` masquaient de vraies défaillances : favori non enregistré, re-analyse muette,
  manifeste de secours perdu sans trace.
- Les tests UI n'étaient pas isolés : les réglages survivaient d'une suite à l'autre.
- Les cibles de test désactivent l'isolation MainActor par défaut : `XCTestCase` déclare ses
  initialiseurs et ses hooks de cycle de vie comme `nonisolated`, ce qui rendait toute
  sous-classe non compilable.
- La mesure de périodicité rapportait un son parfaitement stable comme fortement rythmique :
  le bruit d'arrondi restant après soustraction de la moyenne s'autocorrèle presque
  parfaitement. Un ventilateur aurait donc été rapporté comme un ronflement.
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
