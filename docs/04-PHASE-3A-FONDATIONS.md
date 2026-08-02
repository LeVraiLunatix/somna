# Somna v0.1 — Phase 3A : Domaine et persistance

> Première moitié de la Phase 3. La 3B couvrira le design system, les services et l'environnement d'injection.
> Statut : **livrée, CI verte** — run `30762301747`, 55 tests au vert.

---

## 1. Périmètre

| Couche | Contenu |
|---|---|
| `Core` | Logs structurés, erreurs racine, horloge injectable, formatage de durées, constantes audio et d'analyse |
| `Domain` | Modèles purs, vocabulaire prudent, port de persistance |
| `Data` | Schéma SwiftData versionné, repository `@ModelActor`, mappers, réglages |
| `Tests` | 55 tests : invariants de vocabulaire, modèles, rétention, persistance réelle |

Aucune interface. C'était l'intention : ce qui est ici se teste en 1,4 seconde sans simulateur, et devra encore tenir quand l'UI arrivera.

---

## 2. Décisions structurantes

### 2.1 Le vocabulaire prudent est un test, pas une consigne

`NightEventPhrasing` centralise les 51 formulations (17 types × 3 niveaux de confiance). Aucune vue ne construit sa propre phrase.

`VocabularyTests` fait échouer le build si :

- un libellé contient du vocabulaire clinique (`apnea`, `diagnos`, `sleep score`, `sleep stage`, `respiratory rate`, `heart rate`…) ;
- une étiquette de mouvement affirme un mouvement corporel sans nuance ;
- deux niveaux de confiance se lisent à l'identique ;
- un type n'a pas d'entrée explicite dans la table.

**Pourquoi un test et pas une revue :** tout le reste de cette app est rattrapable. Dire à quelqu'un qu'il fait de l'apnée, ou qu'il s'est retourné quatre fois, ne l'est pas — c'est une affirmation que le micro ne peut pas soutenir, et une fois faite, toutes les autres lectures deviennent suspectes. Une consigne s'érode en six mois au détour d'une retouche de copie ; un test rouge, non.

### 2.2 La confiance module les mots, pas seulement une icône

| Confiance | Formulation |
|---|---|
| Élevée | « Cough detected » |
| Moyenne | « Likely cough » |
| Faible | « Cough-like sound » |
| < 0,35 | non affiché du tout |

Une icône ou une couleur ne suffit pas : les utilisateurs VoiceOver entendent le libellé, et les autres le lisent plus vite qu'ils n'interprètent un badge.

Le seuil de rejet est dans `EventConfidence`, pas dans le moteur : c'est une décision produit sur le degré d'assurance que l'app s'autorise, pas une constante de réglage.

### 2.3 Correction utilisateur : elle gagne, sans écraser le modèle

`NightEvent` porte `type` (ce que le modèle a conclu) **et** `userCorrectedType`. `effectiveType` privilégie l'humain, et un événement corrigé passe en confiance haute — il n'y a plus rien à nuancer.

Le couple *(supposition du modèle, réponse humaine)* est exactement le signal qu'un futur modèle devrait apprendre. L'écraser détruirait la seule donnée d'entraînement que la bêta produit gratuitement.

### 2.4 Distinguer le temps écoulé du temps enregistré

`NightSession` sépare `wallClockDuration` de `recordedDuration`, et expose `captureCoverage`.

Une session interrompue affiche 8 h au réveil mais n'a peut-être capté que 6 h. Présenter l'un pour l'autre gonflerait chaque statistique dérivée et masquerait précisément les coupures que l'utilisateur doit voir.

Corollaire : `interrupted` est un état de premier rang, distinct de `failed`. iOS peut arrêter un enregistrement sans que l'utilisateur l'ait choisi, et ces nuits contiennent des segments exploitables. Les traiter comme des échecs jetterait des données réelles et apprendrait aux gens que Somna perd des nuits.

### 2.5 Le domaine ne voit jamais SwiftData

Les modèles de persistance sont préfixés `SD`, les mappers traduisent dans les deux sens, et seuls des types valeur franchissent la frontière de l'acteur. Coût : du code de conversion. Bénéfice : le risque R5 devient un détail d'implémentation remplaçable.

Deux règles dans les mappers :

- **Les enums sont stockés en chaînes brutes.** SwiftData sait persister des enums `Codable`, mais renommer un cas casse alors le décodage des lignes existantes. Une chaîne plus un mapper tolérant dégrade vers un cas connu au lieu de perdre une nuit.
- **Aucun chemin absolu.** iOS relocalise le conteneur applicatif lors d'une restauration ; tout `URL` absolu stocké devient invalide. Seuls les noms de fichiers sont persistés.

### 2.6 Les formes d'onde en octets, pas en `Float`

Une enveloppe n'est jamais dessinée qu'en hauteur de barre : 8 bits sont indiscernables à l'écran et pèsent le quart. Sur une nuit à 300 événements, environ un mégaoctet économisé — chaque nuit, indéfiniment.

### 2.7 Rétention : le défaut n'est pas « tout garder »

Une nuit pèse ~115 Mo bruts et ~10 Mo une fois réduite à ses extraits. Le défaut à 7 jours protège le stockage de gens qui ne réécouteront jamais l'audio brut. Les deux consentements (cloud, analytics) sont à `false` et le restent en v0.1 — ils existent pour que le choix soit enregistré comme opt-in dès l'origine.

---

## 3. Deux décisions inversées, avec leurs raisons

### `SWIFT_DEFAULT_ACTOR_ISOLATION: MainActor` → `nonisolated`

Décidée en Phase 2 pour l'ergonomie de l'UI. Retirée en 3A :

1. `XCTestCase` déclare ses initialiseurs `nonisolated` — toute sous-classe devenait incompilable (constaté sur le run réel, pas anticipé).
2. Somna n'est pas dominée par l'UI. Domaine, repositories et moteurs vivent hors du main actor et échangent des types valeur ; isoler ces types au MainActor les rendait inconstructibles depuis les acteurs qui les produisent.

`@MainActor` s'écrira donc explicitement sur les stores en Phase 3B.

### `@unchecked Sendable` → `Mutex`

`InMemorySettingsRepository` utilisait un `NSLock` derrière `@unchecked Sendable`, ce qui violait notre propre règle « zéro `@unchecked` ». Remplacé par `Mutex` (module `Synchronization`) : le compilateur vérifie l'isolation au lieu qu'un commentaire la promette. Effet de bord : `Mutex` étant non-copiable, le type devient une `final class`.

Il reste **un** `nonisolated(unsafe)`, sur la propriété `defaults` de `SettingsRepository` : `UserDefaults` est thread-safe d'après Apple mais n'est pas annoté `Sendable`. L'annotation porte sur cette seule propriété, ce qui est plus étroit que `@unchecked Sendable` sur le type — lequel masquerait aussi les ajouts futurs réellement dangereux.

---

## 4. Ce que le premier run a révélé

Le build a passé, deux tests ont échoué. **Les deux étaient des trouvailles, pas des bugs de test.**

**Score infini.** Mon test attendait qu'un score `.infinity` produise une confiance haute ; l'implémentation le rejetait. L'implémentation avait raison : un score infini signale un bug en amont, pas une certitude maximale, et la réponse sûre est d'abandonner la détection plutôt que de la promouvoir au libellé le plus affirmatif de l'app. C'est le test qui a été corrigé.

**Confiance sur les non-classifications.** La règle « deux niveaux ne se lisent jamais pareil » ne peut pas s'appliquer à `.unknown` : « confidemment non identifié » n'a pas de sens. L'exemption est maintenant explicite — et elle-même testée, avec une exception à l'exception : un son faible non identifié reste distingué d'un son clair non identifié, parce que quelqu'un qui décide s'il vaut la peine d'écouter a besoin de savoir s'il y a quelque chose à entendre.

---

## 5. Fichiers livrés

```
Somna/Core/
  Logging/LogCategory.swift, Log.swift
  Errors/SomnaError.swift
  Utilities/Clock.swift
  Extensions/TimeInterval+Duration.swift
  Constants/AudioConstants.swift, AnalysisConstants.swift

Somna/Domain/
  Models/EventConfidence.swift, NightEventType.swift, NightEventPhrasing.swift,
         NightEvent.swift, NightSession.swift, AudioSegment.swift,
         RecordingQuality.swift, CalibrationProfile.swift, UserSettings.swift
  Protocols/NightSessionRepositing.swift

Somna/Data/
  Persistence/SDModels.swift, SomnaSchema.swift
  Mappers/NightMappers.swift
  Repositories/NightSessionRepository.swift, SettingsRepository.swift

SomnaTests/
  Unit/VocabularyTests.swift, DomainModelTests.swift
  Integration/PersistenceTests.swift
```

---

## 6. Checklist de validation

- [x] Le domaine n'importe que `Foundation` — aucun SwiftUI, SwiftData ni AVFoundation
- [x] Schéma versionné et plan de migration en place dès la v1
- [x] Accès à la base hors du thread principal (`@ModelActor`)
- [x] Aucun `PersistentModel` ne franchit la frontière de l'acteur
- [x] Mappers tolérants : une valeur inconnue dégrade, elle ne fait pas échouer une nuit
- [x] Cascade de suppression vérifiée par test (aucun orphelin)
- [x] Zéro `@unchecked Sendable` ; un seul `nonisolated(unsafe)`, justifié
- [x] Zéro `try?` silencieux
- [x] 55 tests au vert, dont la persistance réelle sur conteneur en mémoire
- [x] Build et IPA produits par la CI
- [ ] Chaînes localisées — les défauts anglais sont la source de vérité ; le catalogue FR arrive en Phase 4

---

**Prochaine étape : Phase 3B.** Design system (tokens, typographie, mouvement, haptiques, `GlassSurface`), service de permissions, stockage fichier, `AppEnvironment` et routage. Objectif de sortie : une app navigable, injectée, prête à recevoir les écrans de la Phase 4.
