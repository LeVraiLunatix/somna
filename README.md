# Somna

**Every Night Tells a Story.**

Somna est un journal nocturne pour iPhone. Il écoute les sons de la nuit, détecte des événements sonores probables, et construit au réveil une chronologie claire de ce qui s'est passé — chaque événement étant réécoutable.

> **Avertissement — Somna n'est pas un dispositif médical.**
> Somna ne pose aucun diagnostic, ne détecte pas l'apnée du sommeil, ne mesure pas les phases de sommeil et ne remplace pas un avis médical. C'est une application de bien-être et d'observation. Le « score de tranquillité » est un indicateur interne de calme sonore, pas une mesure de la qualité du sommeil.

---

## Statut

**v0.1 — bêta privée, en développement.**

| Phase | Contenu | Statut |
|---|---|---|
| 1 | Analyse et faisabilité | ✅ [Terminée](docs/00-PHASE-1-ANALYSE.md) |
| 2 | Arborescence et conventions | ✅ [Terminée](docs/01-PHASE-2-ARBORESCENCE.md) |
| 7-min | Validation de la chaîne de build | ✅ [Terminée](docs/03-PHASE-7-MIN-CI.md) — CI verte, IPA produit |
| 3A | Fondations : domaine et persistance | ✅ [Terminée](docs/04-PHASE-3A-FONDATIONS.md) |
| 3B | Fondations : design system, services, environnement | ✅ [Terminée](docs/05-PHASE-3B-DESIGN-ET-SERVICES.md) |
| 4A | Onboarding, accueil, localisation FR/EN | ✅ [Terminée](docs/06-PHASE-4A-ONBOARDING-ET-ACCUEIL.md) |
| 5 | Moteur audio | ✅ [Terminée](docs/07-PHASE-5-MOTEUR-AUDIO.md) — non vérifiée sur appareil |
| 4B / 4C | Rapport, timeline, lecteur, historique, réglages | ⏸️ |
| 6 | Moteur d'analyse | ⏳ En cours |
| 7 | Distribution (Release + AltStore) | ⏸️ |
| 8 | Validation | ⏸️ |

---

## Ce que Somna fait

- Enregistre l'audio de la nuit, écran verrouillé, en segments de 10 minutes
- Détecte des événements : ronflement, toux, parole, respiration, porte, alarme, pluie, circulation, animal, télévision, bruit inconnu
- Qualifie chaque événement par un niveau de confiance, avec un vocabulaire prudent
- Construit une timeline groupée, avec un extrait audio réécoutable par événement
- Génère un résumé en langage naturel à partir des seules données détectées
- Calcule un score de tranquillité 0–100
- Conserve l'historique, les tendances, la recherche
- **Fonctionne entièrement hors ligne. Aucune donnée ne quitte l'appareil.**

## Ce que Somna ne fait pas

Phases de sommeil · apnée · fréquence cardiaque ou respiratoire · détection de mouvement corporel · transcription des paroles nocturnes · attribution d'un ronflement à une personne · mesure en dB SPL absolus · synchronisation cloud · Apple Watch · conseils de santé.

Le détail et les raisons : [docs/00-PHASE-1-ANALYSE.md](docs/00-PHASE-1-ANALYSE.md) §11.

---

## Contraintes techniques importantes

- **Ne ferme pas Somna depuis le sélecteur d'apps pendant une session.** iOS termine alors l'app définitivement et ne la relancera pas. Les segments déjà enregistrés restent exploitables, mais la nuit s'arrête là.
- **Branche ton iPhone.** L'enregistrement consomme de l'ordre de 3 à 7 % de batterie par heure.
- Les interruptions (appel, Siri, alarme) sont gérées et apparaissent explicitement dans la timeline.

---

## Développement

Le projet est développé **depuis Windows** et compilé sur un runner macOS via GitHub Actions. Il n'y a donc aucun `.xcodeproj` dans le dépôt : il est généré depuis `project.yml`.

```bash
# Sur macOS
brew install xcodegen
xcodegen generate
open Somna.xcodeproj
```

```bash
# Depuis Windows — valider la configuration du projet (15 vérifications)
python scripts/validate-project.py
```

La compilation est faite par GitHub Actions sur un runner macOS : génération XcodeGen,
tests sur simulateur, archive non signée et packaging IPA. Voir
[docs/03-PHASE-7-MIN-CI.md](docs/03-PHASE-7-MIN-CI.md).

| Élément | Valeur |
|---|---|
| Cible | iOS 26.0, iPhone, portrait |
| Langage | Swift 6, SwiftUI, SwiftData |
| Audio | AAC-LC 16 kHz mono 32 kbps, segments de 10 min (~14 Mo/h) |
| Analyse | SoundAnalysis (classifieur embarqué Apple) + règles DSP via Accelerate |
| Bundle ID | `com.somna.app` |

---

## Documentation

| Document | Contenu |
|---|---|
| [00 — Analyse](docs/00-PHASE-1-ANALYSE.md) | Faisabilité, contraintes iOS, stratégies audio/ML/stockage/distribution, risques |
| [01 — Arborescence](docs/01-PHASE-2-ARBORESCENCE.md) | Structure du projet, rôle de chaque module |
| [02 — Conventions](docs/02-CONVENTIONS.md) | Code, nommage, accessibilité, vocabulaire produit, git |
| [03 — Chaîne de build](docs/03-PHASE-7-MIN-CI.md) | CI, runner macOS, packaging IPA, contraintes AltStore |
| [04 — Domaine et persistance](docs/04-PHASE-3A-FONDATIONS.md) | Modèles, vocabulaire prudent, SwiftData, décisions inversées |
| [05 — Design system et services](docs/05-PHASE-3B-DESIGN-ET-SERVICES.md) | Palette, Liquid Glass, permissions, stockage, injection |
| [06 — Onboarding et accueil](docs/06-PHASE-4A-ONBOARDING-ET-ACCUEIL.md) | Sept étapes, calibration réelle, localisation FR/EN |
| [07 — Moteur audio](docs/07-PHASE-5-MOTEUR-AUDIO.md) | Segmentation, interruptions, récupération, limites non vérifiées |
| [CHANGELOG](CHANGELOG.md) | Journal de version |

---

## Installation (bêta privée)

La distribution passe par **AltStore / SideStore**, via un IPA non signé publié en GitHub Release et signé sur l'appareil avec le compte Apple du testeur.

Limites d'un compte Apple gratuit, à connaître avant de s'inscrire à la bêta :

- l'app doit être **rafraîchie tous les 7 jours**, sinon elle refuse de s'ouvrir
- **3 apps sideloadées** maximum simultanément
- AltStore nécessite un ordinateur sur le même réseau (ou SideStore)

Le guide détaillé arrivera en Phase 7.

---

## Confidentialité

Somna est strictement local-first. Aucun compte, aucun serveur, aucun analytics, aucun réseau. L'audio est stocké dans le conteneur de l'application, protégé par le chiffrement iOS, exclu de la sauvegarde iCloud, et supprimable à tout moment depuis les réglages.

Somna ne transcrit jamais les paroles nocturnes — ni les tiennes, ni celles des personnes présentes dans la pièce.

---

## Licence

À déterminer avant la première release publique.
