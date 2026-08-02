# Somna — Conventions de code et de contribution

> Ces règles sont appliquées dans toutes les phases. Un écart doit être justifié dans le commit.

---

## 1. Langue

| Élément | Langue |
|---|---|
| Code, noms, commentaires, documentation technique intégrée, noms de tests, messages d'erreur internes | **Anglais** |
| Documentation du dépôt (`docs/`, README), messages de commit, échanges, textes affichés à l'utilisateur français | **Français** |

Les textes de l'interface ne sont jamais écrits dans le code : ils vivent dans `Localizable.xcstrings` (FR + EN).

---

## 2. Nommage

| Type | Convention | Exemple |
|---|---|---|
| Protocole de capacité | Participe présent | `AudioRecording`, `SummaryGenerating`, `NightAnalyzing` |
| Implémentation réelle | Préfixe `Live` ou nom explicite | `LiveHapticFeedback`, `SoundAnalysisClassifier` |
| Doublure de test | Préfixe `Fake` / `Spy` | `FakeClock`, `SpyNightSessionRepository` |
| Modèle SwiftData | Préfixe `SD` | `SDNightSession` |
| Modèle de domaine | Nom nu | `NightSession` |
| Store de feature | Suffixe `Store` | `HomeStore`, `TimelineStore` |
| Vue | Suffixe `View` | `NightReportView` |
| Use case | Suffixe `UseCase` | `AnalyzeNightUseCase` |
| Fichier d'extension | `Type+Sujet.swift` | `Date+Night.swift` |

Le préfixe `SD` sur les modèles de persistance rend visible dans le diff toute fuite de SwiftData vers une couche qui ne devrait pas le connaître.

---

## 3. Architecture — règles vérifiables en revue

1. **`Domain/` n'importe que `Foundation`.** Pas de SwiftUI, SwiftData, AVFoundation, UIKit.
2. **Une vue ne connaît qu'un store et des protocoles.** Aucun `ModelContext`, aucun service concret dans une vue.
3. **Aucun singleton global mutable.** Tout passe par `AppEnvironment`.
4. **Vue ≤ 150 lignes.** Au-delà, extraire un composant.
5. **Aucun `try?` silencieux.** Une erreur est gérée, journalisée, ou propagée — jamais avalée.
6. **Aucun force unwrap évitable.** Les rares cas légitimes portent un commentaire justifiant l'invariant.
7. **Rien de lourd sur le `MainActor`.** FFT, écritures disque et classification vivent dans des `actor`.
8. **Aucune dépendance tierce** tant qu'une API Apple couvre le besoin.
9. **Aucun secret dans le code.**

---

## 4. Concurrence

- Swift 6, isolation `MainActor` par défaut (`SWIFT_DEFAULT_ACTOR_ISOLATION`).
- Les stores de features sont `@MainActor @Observable`.
- Les moteurs audio et d'analyse sont des `actor` explicitement `nonisolated` du MainActor.
- L'accès SwiftData passe par un `@ModelActor`.
- **Objectif : zéro `@unchecked Sendable`.** Toute occurrence doit être justifiée en commentaire.

### Isolation par défaut : `nonisolated`

Le projet **n'utilise pas** `SWIFT_DEFAULT_ACTOR_ISOLATION: MainActor`. Décision initialement
prise en Phase 2 puis **inversée en Phase 3A**, pour deux raisons découvertes à l'usage :

1. **XCTest est antérieur à la concurrence Swift.** `XCTestCase` déclare ses initialiseurs et
   ses hooks de cycle de vie comme `nonisolated` ; hériter d'une isolation MainActor fait
   échouer la compilation de toute sous-classe.
2. **Somna n'est pas une app dominée par l'UI.** Le domaine, les repositories et les moteurs
   audio et d'analyse vivent hors du main actor et échangent des types valeur. Isoler ces
   types au MainActor les aurait rendus inconstructibles depuis les acteurs qui les produisent —
   exactement l'inverse du besoin.

Conséquence : `@MainActor` s'écrit explicitement sur les stores. Les vues SwiftUI l'obtiennent
déjà du protocole `View`. Plus verbeux, mais l'isolation se lit au lieu de s'hériter en silence.

### Import explicite des modules

`SWIFT_UPCOMING_FEATURE_MEMBER_IMPORT_VISIBILITY` est actif : un fichier doit importer le module
définissant les membres qu'il utilise. Concrètement, tout fichier qui journalise doit
`import OSLog`, même si `Log` est défini ailleurs dans le module.

C'est délibéré. `Log` expose `Logger` plutôt qu'une façade prenant des chaînes, parce que
l'interpolation native d'`os_log` porte les annotations de confidentialité
(`\(value, privacy: .private)`) — une façade à base de `String` les perdrait, et la
journalisation est ici une surface de confidentialité, pas un confort de débogage.

---

## 5. Confidentialité dans le code

Interdits absolus, y compris en `#if DEBUG` :

- Journaliser le contenu audio, un chemin de fichier audio complet, ou une transcription.
- Envoyer quoi que ce soit sur le réseau en v0.1. **Aucun import de `URLSession` n'est justifié dans cette version.**
- Écrire une donnée utilisateur dans un rapport de diagnostic non anonymisé.

Les identifiants de session sont journalisés tronqués (8 premiers caractères).

---

## 6. Vocabulaire produit — liste de blocage

Ces termes ne doivent apparaître ni dans le code, ni dans les chaînes localisées, ni dans la documentation destinée à l'utilisateur :

`apnée` · `apnea` · `diagnostic` · `sleep score` · `qualité du sommeil` · `sleep quality` · `sommeil profond` · `deep sleep` · `REM` · `phases de sommeil` · `sleep stage` · `tu t'es retourné` · `mouvement corporel` · `body movement` · `fréquence respiratoire` · `respiratory rate`

Un test unitaire (`ConfidenceLabelTests`) vérifie l'absence de ces termes dans les libellés produits par le domaine.

Formulations imposées pour la confiance :

| Confiance | Français | Anglais |
|---|---|---|
| Élevée | « Toux détectée » | "Cough detected" |
| Moyenne | « Toux probable » | "Likely cough" |
| Faible | « Son ressemblant à une toux » | "Cough-like sound" |

---

## 7. Accessibilité — non négociable dès l'écriture, pas en fin de projet

- Tout élément interactif ≥ 44×44 pt.
- Tout élément non textuel porte un `accessibilityLabel`.
- Toute animation respecte `Reduce Motion` via `SomnaMotion`.
- Tout effet de verre passe par `GlassSurface`, qui gère `Reduce Transparency`.
- Tout graphique expose `accessibilityChartDescriptor` ou un résumé textuel équivalent.
- Aucune information portée uniquement par la couleur (`Differentiate Without Color`).
- Les cartes doivent rester utilisables jusqu'à la taille AX5.

---

## 8. Tests

- Le `Domain` vise une couverture élevée : c'est du code pur, il n'y a pas d'excuse.
- Un test par règle métier énoncée dans la documentation.
- Aucun test ne dépend de l'horloge système : `Clock` est injecté.
- Swift Testing pour les nouveaux tests unitaires, XCTest pour les tests UI.

---

## 9. Git

Format de commit : `type(portée): sujet en français`

Types : `feat` · `fix` · `refactor` · `docs` · `test` · `chore` · `ci`

```
feat(timeline): regroupement des événements consécutifs
fix(audio): reprise après interruption longue
docs(phase-2): arborescence et conventions
```

- Branche `main` = état diffusable.
- Un tag `vX.Y.Z` déclenche l'archive et la release (Phase 7).
- Le projet Xcode généré n'est **jamais** commité.

---

## 10. Definition of Done d'un écran

Un écran n'est terminé que si :

- [ ] aucun bouton sans action, aucun lien mort, aucune navigation en cul-de-sac
- [ ] états vide, chargement et erreur traités
- [ ] toutes les chaînes localisées FR + EN
- [ ] VoiceOver traverse l'écran dans un ordre cohérent
- [ ] lisible à la taille AX5
- [ ] correct en mode clair et en mode sombre
- [ ] correct avec Reduce Transparency et Increased Contrast
- [ ] aucune logique métier dans la vue
- [ ] preview SwiftUI fonctionnelle avec `AppEnvironment.preview`
