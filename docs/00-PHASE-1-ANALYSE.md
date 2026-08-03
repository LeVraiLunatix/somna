# Somna v0.1 — Phase 1 : Analyse et faisabilité

> Document de référence. Toute décision prise ici fait autorité pour les phases suivantes.
> Statut : **validé pour exécution** — Phase 2 (arborescence) à suivre.
> Date : 2026-08-02

---

## 1. Vision finale de Somna v0.1

Somna est un **journal nocturne sonore**, pas un tracker de sommeil.

La promesse tient en une phrase : *tu poses ton iPhone sur la table de nuit, et au réveil tu sais ce qui s'est passé pendant que tu dormais.* Pas un score de sommeil profond inventé, pas un diagnostic d'apnée : une **chronologie honnête d'événements sonores réellement détectés**, chacun écoutable en un tap.

Ce qui différencie Somna des applications existantes :

- **Preuve audio systématique.** Chaque événement de la timeline est adossé à un extrait réel réécoutable. Rien n'est affirmé sans pouvoir être vérifié par l'oreille de l'utilisateur.
- **Honnêteté du vocabulaire.** Trois niveaux de langage selon la confiance du classifieur : « Toux détectée » / « Toux probable » / « Son ressemblant à une toux ». Jamais de certitude fabriquée.
- **Local-first strict.** Aucun octet ne quitte l'appareil en v0.1. Pas de compte, pas de serveur, pas d'analytics.
- **Zéro prétention médicale.** Le score s'appelle *Score de tranquillité*, jamais *Sleep Score*. Aucune mention d'apnée, de phases de sommeil, ou de qualité de sommeil.

L'expérience cible est celle d'une app Apple de première partie : sobre, rapide, mode sombre impeccable, Liquid Glass utilisé avec parcimonie sur quelques surfaces seulement.

---

## 2. Périmètre précis de la bêta privée

### 2.1 Inclus dans la v0.1 (engagement ferme)

| Domaine | Contenu |
|---|---|
| Onboarding | 7 écrans, permissions micro + notifications, calibration 15 s |
| Session | Préparation (checklist pré-vol), enregistrement nocturne, écran veille, arrêt |
| Audio | AVAudioEngine, segments AAC 10 min, écriture atomique, reprise après incident |
| Analyse | Passe temps réel légère (DSP) + passe post-nuit (SoundAnalysis + DSP) |
| Rapport | En-tête, résumé généré, statistiques, qualité d'enregistrement, moments clés |
| Timeline | Événements groupés, filtres, confiance, mini-waveform, correction utilisateur |
| Lecteur | Panneau Liquid Glass persistant, ±5 s, vitesse, navigation événement suivant/précédent |
| Historique | Liste + calendrier, recherche structurée, suppression unitaire et globale |
| Tendances | 5 graphiques Swift Charts, honnêtes, avec explication textuelle de chacun |
| Réglages | 7 sections complètes, toutes fonctionnelles |
| Stockage | Politiques de rétention 7/30/90/illimité, purge audio brut, calcul d'espace réel |
| Notifications | Rappel du soir, rapport prêt, résumé du matin, alerte espace faible |
| Accessibilité | VoiceOver, Dynamic Type jusqu'à AX5, Reduce Motion/Transparency, Increased Contrast |
| Localisation | FR + EN via String Catalogs, zéro chaîne en dur |
| Export | JSON nuit, CSV événements, partage texte, export de clips sélectionnés |
| Premium | Écran vitrine, non achetable, mention explicite « Bientôt disponible » |
| Distribution | GitHub Actions → IPA non signé → GitHub Release → source AltStore auto-mise à jour |
| Tests | Unitaires (score, groupement, résumé, rétention, mapping), intégration (session simulée), UI (parcours critiques) |

### 2.2 Explicitement reporté (et pourquoi)

| Fonctionnalité | Raison du report |
|---|---|
| Détection de mouvement corporel | Accéléromètre inutilisable depuis une table de nuit. Voir §5. |
| Apple Watch / HealthKit | HealthKit exige une *entitlement* → compte développeur payant. Incompatible sideloading gratuit. |
| Widgets & Live Activities | Nécessitent une App Extension : un binaire séparé, avec son propre bundle ID et son propre profil. Un compte gratuit ne peut activer que **3 apps *et extensions*** à la fois, et AltStore en occupe déjà une — Somna en prendrait deux des trois. Coût/bénéfice défavorable en v0.1. |
| Sync iCloud | Exige l'entitlement CloudKit → compte payant. |
| Achats intégrés réels | StoreKit exige App Store Connect. L'écran Premium est une vitrine désactivée. |
| Transcription des paroles nocturnes | Techniquement possible (SpeechAnalyzer, iOS 26) mais **volontairement exclu** : transcrire ce que quelqu'un dit en dormant est une violation de vie privée majeure, y compris pour les tiers présents dans la pièce. Somna détecte *qu'il y a eu parole*, jamais *ce qui a été dit*. |
| Résumé par LLM distant | Aucune dépendance réseau en v0.1. L'abstraction est prête (§7.5). |
| Alarme intelligente | AlarmKit (iOS 26) est utilisable, mais réveiller quelqu'un est une responsabilité produit qui mérite sa propre version. |

---

## 3. Contraintes iOS de l'enregistrement nocturne

C'est le cœur du risque technique. Voici ce qui est **réellement possible**, vérifié contre les règles d'Apple.

### 3.1 Ce qui fonctionne (garanti par la plateforme)

- **Enregistrement écran verrouillé et app en arrière-plan : OUI.** C'est l'usage légitime prévu par le background mode `audio` déclaré dans `UIBackgroundModes`. Une app d'enregistrement dont la session `AVAudioSession` est active en catégorie `.record` (ou `.playAndRecord`) n'est pas suspendue par iOS. C'est exactement le mécanisme qu'utilisent Dictaphone et les apps d'enregistrement tierces.
- **Aucune entitlement requise.** `UIBackgroundModes` est une clé `Info.plist`, pas une entitlement signée. Elle fonctionne donc **avec un compte Apple gratuit et en sideloading**. C'est le point le plus important de tout le projet, et il est favorable.
- **Notifications locales : OUI**, sans compte payant (contrairement aux notifications *push* distantes).
- **Durée illimitée.** Tant que la session audio reste active, il n'y a pas de minuteur de 30 secondes ni de 10 minutes comme pour les tâches d'arrière-plan classiques.

### 3.2 Ce qui casse une session (à gérer, pas à masquer)

| Événement | Comportement iOS | Stratégie Somna |
|---|---|---|
| Appel entrant / FaceTime | `AVAudioSession.interruptionNotification` `.began`, moteur arrêté | Fermeture propre du segment courant, attente de `.ended`, redémarrage du moteur, insertion d'un événement `sessionGap` dans la timeline |
| Siri, alarme de l'app Horloge | Interruption courte | Idem, reprise quasi immédiate |
| L'utilisateur balaie l'app hors du multitâche | **Terminaison définitive. iOS ne relancera jamais l'app.** | Impossible à contourner. Prévenu explicitement dans l'onboarding et l'écran de session : « Ne ferme pas Somna depuis le sélecteur d'apps. » Les segments déjà écrits sont conservés et analysables. |
| Crash / kill mémoire | Segments déjà écrits intacts | Détection d'une session `.interrupted` au lancement suivant, proposition « Analyser la nuit incomplète » |
| `mediaServicesWereReset` | Le démon audio a redémarré, tous les objets audio sont invalides | Reconstruction complète de `AVAudioEngine` et réouverture d'un nouveau segment |
| Route audio changée (AirPods qui se connectent) | `routeChangeNotification` | Réévaluation de l'entrée, retour au micro intégré, événement de qualité journalisé |
| Batterie critique | iOS peut fermer l'app | Avertissement bloquant sous 30 %, recommandation de charge, arrêt propre à 3 % |
| Mode économie d'énergie | Pas d'arrêt, mais throttling | Analyse post-nuit différée jusqu'à sortie du mode ou branchement |

### 3.3 Ce qu'on ne fera pas

- Aucun contournement : pas de lecture d'un fichier silencieux en boucle pour maintenir la session, pas d'abus du background mode `location`, pas de `beginBackgroundTask` détourné. Ces techniques sont des motifs de rejet App Store et créent une instabilité réelle.
- Aucune promesse de « redémarrage automatique après fermeture ». iOS ne le permet pas. On le dit.

### 3.4 Coût énergétique — estimation honnête

Micro actif + encodage AAC + DSP léger : ordre de grandeur **3 à 7 % de batterie par heure** selon le modèle d'iPhone et le mode économie d'énergie. Sur 8 heures, une session non branchée viderait l'appareil. **La recommandation de charge n'est pas cosmétique, elle est structurelle** : elle sera présente dans l'onboarding, dans la checklist de préparation, et en avertissement si l'iPhone n'est pas branché au lancement. Les chiffres définitifs devront être mesurés sur appareil physique avec Instruments (Energy Log) — ils ne sont pas mesurables en simulateur.

---

## 4. Capacités réalistes du microphone

### 4.1 Ce que le micro d'un iPhone sur table de nuit capte réellement

À 30–100 cm du dormeur, en pièce calme (25–35 dB SPL de bruit de fond), le micro capte sans difficulté :

- **Ronflement** — 45 à 75 dB SPL, énergie concentrée sous 1 kHz, très périodique. Cible facile, taux de détection élevé.
- **Toux, éternuement** — transitoires larges bandes, 60–90 dB. Cible facile.
- **Parole nocturne** — détectable comme *présence de voix*, souvent à faible intelligibilité. Cible moyenne.
- **Respiration audible** — seulement si la respiration est sonore (nez bouché, bouche ouverte). Cible difficile, confiance systématiquement basse.
- **Bruits environnants** (porte, alarme, circulation, pluie, animal, télévision) — cible facile, ce sont des classes fortes du classifieur Apple.
- **Froissement de draps, changement de position** — transitoires courts, large bande, faible énergie. Détectables comme *activité sonore*, **jamais** comme « tu t'es retourné ». Cible difficile, vocabulaire prudent obligatoire.

### 4.2 Facteurs dégradants à surveiller et à signaler

- Distance supérieure à ~1,5 m → chute du rapport signal/bruit, beaucoup de faux négatifs.
- iPhone posé face contre le matelas, sous un oreiller, ou dans un tiroir → micro obstrué.
- Ventilateur, climatisation, purificateur d'air → plancher de bruit élevé, masquage des événements faibles.
- Télévision ou musique laissée allumée → saturation du classifieur en fausses détections de parole.
- Deux dormeurs → **impossible d'attribuer un ronflement à une personne.** Somna dira « ronflement détecté », jamais « tu as ronflé ». Ce point est traité dans l'onboarding et dans la formulation des résumés.
- Coque épaisse couvrant le micro inférieur.

C'est précisément le rôle de la **calibration** (§13 du cahier des charges) : mesurer le plancher de bruit ambiant sur 15 secondes, estimer la qualité du placement, et donner un verdict *excellent / correct / à améliorer* avec un conseil actionnable. Et le rôle de la section **Qualité de l'enregistrement** du rapport : si la nuit était inexploitable, on le dit au lieu d'inventer des événements.

### 4.3 Limites assumées

- Somna ne mesure **pas** un niveau sonore absolu en dB SPL. Le micro d'un iPhone n'est pas calibré en usine pour la mesure acoustique absolue et le gain varie selon le modèle. Tous les niveaux affichés sont **relatifs** (dBFS normalisés par rapport au plancher mesuré lors de la calibration). Aucun chiffre en « décibels » ne sera présenté comme une mesure physique.
- Somna ne distingue pas deux personnes.
- Somna ne détecte pas les événements silencieux. Un réveil sans bruit est invisible.

---

## 5. Limitations concernant les mouvements

**Décision : la détection de mouvement par accéléromètre est retirée de la v0.1.**

Justification technique :

- Un iPhone posé sur une table de nuit est **mécaniquement découplé** du lit. L'accéléromètre y mesure les vibrations du meuble, pas celles du dormeur. Le rapport signal/bruit est proche de zéro.
- La seule configuration où l'accéléromètre serait exploitable est « iPhone posé sur le matelas », ce qui est déconseillé (surchauffe pendant la charge, micro obstrué, risque de chute).
- Core Motion en arrière-plan prolongé n'a pas de mode dédié comparable au background mode `audio`. `CMSensorRecorder` permet un enregistrement différé, mais sur des données que nous venons d'établir comme non pertinentes ici.

**Ce qui est fait à la place :** le mouvement est inféré **acoustiquement**, et étiqueté avec un vocabulaire strictement prudent, imposé au niveau du modèle de données (pas laissé à l'appréciation de l'UI) :

- `movementNoise` → « Mouvement audible probable »
- `beddingNoise` → « Bruit de draps détecté »
- jamais « Tu t'es retourné », jamais un compteur de « changements de position »

Un `NightEventType` ne peut pas produire un libellé affirmant un mouvement corporel : la table de correspondance type → libellé est unique et testée.

---

## 6. Architecture recommandée

### 6.1 Vue d'ensemble

Architecture **feature-based**, en couches, avec injection de dépendances par protocoles. Pattern de présentation : **MVVM avec `@Observable`** (framework Observation), un *store* par feature.

```
        ┌──────────────────────────────────────────┐
        │  Features (SwiftUI Views + @Observable)   │
        └───────────────┬──────────────────────────┘
                        │ protocoles uniquement
        ┌───────────────▼──────────────────────────┐
        │  Domain (modèles purs, use cases, ports)  │
        └───────────────┬──────────────────────────┘
                        │
        ┌───────────────▼──────────────────────────┐
        │  Data (SwiftData, repositories, mappers)  │
        │  Services (Audio, Analysis, Files, Notif) │
        └──────────────────────────────────────────┘
```

**Règles non négociables :**

1. Les vues ne connaissent **que** des protocoles, jamais une implémentation concrète ni `ModelContext` directement.
2. Le `Domain` est en Swift pur : pas d'import SwiftUI, pas d'import SwiftData, pas d'import AVFoundation. C'est ce qui rend le score, le groupement et le résumé testables sans simulateur.
3. Un seul point d'injection : `AppEnvironment`, une struct de services typés par protocole, propagée via `.environment(...)`. **Aucun singleton global mutable.**
4. Le traitement audio vit dans un `actor` dédié, hors `MainActor`. Aucune écriture disque et aucune FFT sur le thread principal.
5. Aucune vue au-delà de ~150 lignes : au-delà, on extrait un sous-composant dans `DesignSystem` ou dans le dossier de la feature.

### 6.2 Choix structurants et compromis

| Décision | Alternative écartée | Pourquoi |
|---|---|---|
| **Un seul target app + targets de test**, modules = dossiers | Packages SPM locaux par module | Les vrais modules SPM donneraient des frontières compilées. Mais ils compliquent la génération de projet sur CI et allongent le build. Compromis : discipline par protocoles maintenant, extraction en packages en v0.2 si le besoin apparaît. La structure de dossiers est déjà celle d'un découpage en packages. |
| **`.xcodeproj` généré par XcodeGen** depuis `project.yml` | `.pbxproj` versionné à la main | Le développement se fait sous Windows, sans Xcode. Éditer un `.pbxproj` à la main est ingérable et source de corruption. `project.yml` est lisible, diffable, et le projet est régénéré sur le runner. **C'est ce qui rend ce projet réalisable depuis Windows.** |
| **MVVM + Observation** | TCA / Redux | TCA est excellent mais ajoute une dépendance externe lourde, contraire à la règle « aucun framework tiers si une API Apple convient ». |
| **SwiftData** | Core Data brut, GRDB | Imposé par le cahier des charges, et adapté. Risque connu (voir §10) mitigé par des repositories : si SwiftData pose problème, on remplace l'implémentation sans toucher aux features. |
| **Audio hors SwiftData** | Blobs en base | Les fichiers audio restent sur le système de fichiers, la base ne stocke que des chemins relatifs + métadonnées. Évite de faire exploser le store et permet la purge indépendante. |

### 6.3 Concurrence

- `@MainActor` sur tous les stores de features.
- `actor AudioRecordingEngine` : capture, rotation de segments, métriques temps réel.
- `actor NightAnalysisEngine` : analyse post-nuit.
- `@ModelActor NightSessionRepository` : accès SwiftData hors thread principal.
- Strict concurrency activé. Objectif : zéro `@unchecked Sendable`.

---

## 7. Stratégie locale d'analyse audio

C'est le point où la plupart des projets mentent. Voici ce qui est **réel**.

### 7.1 Le socle : SoundAnalysis, pas un modèle inventé

Apple fournit depuis iOS 15 un classifieur sonore embarqué (`SNClassifySoundRequest(classifierIdentifier: .version1)`) couvrant **plusieurs centaines de classes**, dont, pertinentes ici : ronflement, toux, éternuement, respiration, parole, chuchotement, porte, coup frappé, réveil/alarme, pluie, vent, circulation, chien, chat, télévision, musique, applaudissement, verre brisé.

Conséquences majeures :

- **Aucun modèle Core ML à entraîner ni à embarquer pour la v0.1.** Le pipeline ML est réel dès le jour 1.
- Le modèle renvoie une **confiance par classe** — exactement ce dont le vocabulaire à trois niveaux a besoin.
- Il tourne sur le Neural Engine, entièrement hors ligne.

**Mise en œuvre prudente :** la liste exacte des identifiants de classes varie selon la version d'iOS. On ne codera donc pas en dur une liste supposée : au premier lancement, on interroge `request.knownClassifications`, on la confronte à notre table de correspondance `String → NightEventType`, et on journalise les classes attendues absentes. Une classe non reconnue tombe sur `.unknown` au lieu de faire échouer l'analyse.

### 7.2 Pipeline hybride en deux passes

**Passe A — pendant la nuit (légère, sur le tap AVAudioEngine) :**

Sur chaque buffer (~100 ms), avec Accelerate/vDSP :
- RMS et crête (dBFS)
- Zero-crossing rate
- Centroïde spectral et énergie par bandes (FFT 1024 points)
- Détection de dépassement de seuil adaptatif (plancher de calibration + hystérésis)

Sortie : un flux compact de « fenêtres candidates » (horodatage, énergie, caractéristiques) écrit en JSONL à côté de chaque segment. Coût CPU : quelques pourcents. **Aucune inférence ML pendant la nuit** — c'est le choix qui protège la batterie.

**Passe B — au matin (lourde, sur fichiers) :**

1. Sélection des zones candidates issues de la passe A (typiquement 5–15 % de la nuit).
2. `SNAudioFileAnalyzer` sur ces zones uniquement → classification + confiance. L'analyse fichier tourne bien plus vite que le temps réel.
3. **Fusion règles + ML** : le ML propose une classe, les règles DSP arbitrent. Exemple : une classe « snoring » à 0,6 de confiance mais sans périodicité 0,2–0,5 Hz sur 20 s est rétrogradée. À l'inverse, un transitoire large bande court sans classe ML forte devient `movementNoise` en confiance basse.
4. **Groupement temporel** : des événements de même type séparés de moins de 90 s fusionnent en un épisode (« 12 épisodes de ronflement entre 2 h 10 et 2 h 37 »).
5. **Extraction des clips** : ±3 s autour de chaque événement représentatif, ré-encodés en fichiers courts.
6. Statistiques, score de tranquillité, résumé.

Progression affichée, annulable, reprenable. Sur une nuit de 8 h, cible : **moins de 3 minutes** sur un iPhone récent, à valider sur appareil.

### 7.3 Niveaux de confiance

| Confiance | Seuil indicatif | Formulation |
|---|---|---|
| Élevée | ≥ 0,80 | « Toux détectée » |
| Moyenne | 0,55 – 0,79 | « Toux probable » |
| Faible | 0,35 – 0,54 | « Son ressemblant à une toux » |
| Rejeté | < 0,35 | non affiché (comptabilisé en interne uniquement) |

Les seuils sont par classe, versionnés dans `AnalysisConfiguration`, et une classe jugée trop peu fiable peut être désactivée sans recompiler l'UI.

### 7.4 Format d'enregistrement — décision et justification

| Paramètre | Choix | Justification |
|---|---|---|
| Codec | AAC-LC (`.m4a`) | Encodage matériel, faible coût CPU/énergie. Le PCM 16 kHz mono consommerait ~920 Mo pour 8 h : inacceptable. |
| Fréquence | **16 kHz** | Ronflement, toux et voix ont leur énergie utile sous 8 kHz. 16 kHz respecte Nyquist pour cette bande, et c'est une fréquence sûre pour SoundAnalysis. Passer à 44,1 kHz triplerait le coût sans gain de classification. |
| Canaux | **1 (mono)** | Le micro utilisé est unique ; la stéréo doublerait la taille sans information ajoutée. |
| Débit | **32 kbps** par défaut, 64 kbps en mode « qualité élevée » | ≈ **14 Mo/heure**, soit **~115 Mo pour 8 h**. Compromis validé pour la classification. |
| Segment | **10 minutes** | ~2,4 Mo par fichier. Un crash coûte au pire 10 minutes, jamais la nuit. |
| Écriture | Fichier temporaire `.part` puis renommage atomique + écriture des métadonnées | Un `.part` orphelin au lancement suivant = segment incomplet, tronqué ou supprimé proprement. |
| Protection fichier | `.completeUnlessOpen` | L'écriture doit continuer écran verrouillé, mais les fichiers restent chiffrés au repos hors usage. |

**Limite connue et assumée :** l'AAC à 32 kbps introduit des artefacts spectraux légers. Impact négligeable sur des classes larges (ronflement, toux, porte), potentiellement mesurable sur des sons ténus (respiration faible). Un test comparatif 32 vs 64 kbps sur nuits réelles est prévu en Phase 8 ; si l'écart est significatif, le défaut passera à 48 kbps.

### 7.5 Résumé automatique

**v0.1 : génération locale par templates paramétrés.** Un moteur de règles sélectionne parmi des patrons de phrases selon la durée, la densité d'événements, leur répartition, leur confiance, les périodes calmes, et la comparaison avec la moyenne des 7 nuits précédentes. Variation naturelle par sélection pondérée de tournures, sans jamais introduire un événement absent des données (invariant testé unitairement : *toute entité citée dans le résumé doit exister dans le jeu d'événements*).

**Préparation pour un LLM :** le protocole `SummaryGenerating` est l'unique point d'entrée. Une implémentation alternative basée sur **Foundation Models** (le LLM embarqué d'iOS 26, gratuit et hors ligne) est prévue en v0.2, avec repli automatique sur les templates si `SystemLanguageModel.default.availability` n'est pas `.available` — ce qui sera le cas sur les iPhone antérieurs au 15 Pro. Aucune API distante, aucun coût.

### 7.6 Endormissement et réveil

Estimés acoustiquement : début du premier segment calme durable après le lancement, fin de la dernière période calme avant l'arrêt. Toujours étiquetés « probable ». Si l'estimation est trop incertaine (nuit bruyante, session trop courte), **l'événement n'est pas affiché du tout** plutôt qu'affiché à tort.

---

## 8. Stratégie de stockage

### 8.1 Organisation disque

```
Application Support/Somna/
  Nights/<sessionUUID>/
    segments/    seg-000.m4a … + seg-000.features.jsonl
    clips/       evt-<uuid>.m4a
    manifest.json          ← source de vérité de secours, réécrit après chaque segment
  Models/
  Exports/
```

`manifest.json` est délibérément redondant avec SwiftData : si la base est corrompue ou si une migration échoue, une nuit reste reconstructible depuis le disque. Coût : quelques kilo-octets. Bénéfice : aucune nuit perdue.

Exclusion de la sauvegarde iCloud pour l'audio brut (`isExcludedFromBackup`) : une bêta ne doit pas remplir le stockage iCloud de ses utilisateurs.

### 8.2 Budget

| Élément | Taille |
|---|---|
| Nuit de 8 h, audio brut 32 kbps | ~115 Mo |
| Métriques (JSONL) | ~2 Mo |
| Clips d'événements | 2–10 Mo |
| **Après purge de l'audio brut** | **~10 Mo par nuit** |

Par défaut : **conserver l'audio brut 7 jours, puis ne garder que les clips**. 30 nuits ≈ 1,1 Go avec le défaut, contre 3,4 Go en conservation totale.

### 8.3 Règles

- Vérification de l'espace libre avant chaque session ; refus de démarrer sous **1,5 Go** avec message actionnable.
- Estimation d'occupation affichée sur l'écran de préparation.
- Toute suppression est précédée d'un écran indiquant précisément ce qui part, et suivie d'une vérification qu'aucune référence orpheline ne subsiste (fichiers puis base, dans cet ordre, avec balayage des orphelins au lancement).
- Purge automatique au lancement : segments `.part`, dossiers de sessions absentes de la base, clips sans événement.

---

## 9. Stratégie GitHub Actions et AltStore

### 9.1 Chaîne de build

```
Windows (code, git push)
      ↓
GitHub Actions — runner macOS + Xcode 26
      ↓  brew install xcodegen && xcodegen generate
      ↓  xcodebuild archive -destination generic/platform=iOS
      ↓         CODE_SIGNING_ALLOWED=NO
      ↓  Payload/Somna.app → zip → Somna-x.y.z.ipa
      ↓
GitHub Release (tag vX.Y.Z) + upload de l'IPA
      ↓
Étape de mise à jour du feed → apps.json publié sur GitHub Pages
      ↓
AltStore / SideStore sur l'iPhone : télécharge, signe avec l'Apple ID de l'utilisateur, installe
```

**Points clés :**

- **L'IPA est non signé, et c'est volontaire.** Un IPA signé avec un Personal Team ne s'installerait sur aucun autre appareil que ceux du certificat. AltStore signe l'app à l'installation avec le compte Apple du bêta-testeur. C'est le seul modèle qui fonctionne sans abonnement développeur.
- `MARKETING_VERSION` depuis le tag git, `CURRENT_PROJECT_VERSION` depuis `github.run_number` → build strictement croissant, jamais de collision.
- Un job de vérification rapide (build + tests unitaires) sur chaque push ; l'archive et la release uniquement sur tag.
- Point de vigilance à valider en Phase 7 : la version d'Xcode disponible sur les images de runner. Une étape de diagnostic listera `/Applications/Xcode*` au premier run pour épingler explicitement la bonne version plutôt que de dépendre du défaut de l'image.

### 9.2 Limites du sideloading avec un compte Apple gratuit — à documenter sans détour

| Limite | Conséquence pour les bêta-testeurs |
|---|---|
| Profil valide **7 jours** | L'app doit être « rafraîchie » chaque semaine via AltStore/SideStore, sinon elle refuse de s'ouvrir |
| **3 apps et extensions** actives simultanément | Limite d'*installation*, permanente. Une extension compte pour un emplacement au même titre qu'une app — d'où le refus des widgets en §3.4. Somna en consomme un seul. |
| **10 App IDs par 7 jours** | Limite de *création*, glissante. Elle borne l'enregistrement de nouveaux identifiants, pas l'usage : elle gêne le développement, pas les testeurs. À ne pas confondre avec la précédente. |
| Pas d'App Groups, iCloud, HealthKit, push distant | Confirme le périmètre défini en §2.2 |
| AltStore nécessite un ordinateur (AltServer) sur le même réseau, ou SideStore avec un VPN de boucle locale | Friction réelle à documenter pas à pas dans le guide d'installation |
| Le testeur saisit son Apple ID dans AltStore | Doit être expliqué honnêtement, y compris la recommandation d'un mot de passe d'application |

**Ce qui n'est pas fait :** aucun contournement de la signature Apple, aucun certificat d'entreprise, aucun service de signature tiers.

### 9.3 Source AltStore

Un fichier `apps.json` (format AltStore v2 : `name`, `identifier`, `apps[].versions[]`, `appPermissions`, `news`) hébergé sur GitHub Pages. Une étape de workflow y **préfixe** la nouvelle version dans le tableau `versions` (l'historique est conservé — AltStore permet le retour à une version antérieure), en renseignant taille réelle de l'IPA, date, `minOSVersion`, et notes de version extraites du CHANGELOG. `appPermissions` déclare l'usage du micro et des notifications, ce qui rend les permissions visibles avant installation.

---

## 10. Risques principaux

| # | Risque | Gravité | Mitigation |
|---|---|---|---|
| R1 | Un testeur balaie l'app hors du multitâche et perd sa nuit | Élevée | Non contournable. Prévention par l'onboarding, la checklist de préparation, et la notification du soir. Les segments déjà écrits restent exploitables. |
| R2 | Reprise après interruption longue (appel de 20 min) qui échoue silencieusement | Élevée | Machine à états explicite, tentatives de reprise espacées, événement `sessionGap` visible dans la timeline, section « Qualité » du rapport qui signale les coupures. Jamais de gap masqué. |
| R3 | Trop de faux positifs → perte de confiance des bêta-testeurs | Élevée | Seuils volontairement conservateurs au départ, rejet sous 0,35, correction utilisateur en un tap, vocabulaire prudent. Mieux vaut manquer un événement que d'en inventer un. |
| R4 | Batterie vidée sur une session non branchée | Moyenne | Avertissement sous 30 %, recommandation systématique, arrêt propre à 3 %. |
| R5 | SwiftData : migrations et performances sur historiques longs | Moyenne | `VersionedSchema` + `MigrationPlan` dès la v0.1 (même avec un seul schéma), accès via repositories remplaçables, pagination de l'historique, `manifest.json` en filet de sécurité. |
| R6 | Xcode 26 / iOS 26 indisponible ou différent sur le runner GitHub | Moyenne | Job de diagnostic, version épinglée, `IPHONEOS_DEPLOYMENT_TARGET` piloté depuis `project.yml`. |
| R7 | Friction d'installation AltStore décourage les testeurs | Moyenne | Guide d'installation pas à pas avec captures, et rappel du rafraîchissement à 7 jours. |
| R8 | Durée de l'analyse post-nuit jugée trop longue | Moyenne | Analyse sur zones candidates uniquement, progression visible, annulable et reprenable, lancement automatique dès l'arrêt de la session. |
| R9 | `mediaServicesWereReset` non géré → moteur mort silencieusement | Moyenne | Observation de la notification, reconstruction complète du moteur, test d'intégration dédié. |
| R10 | Liquid Glass sur-utilisé → illisible la nuit | Faible | Usage limité à 6 surfaces identifiées, respect de `Reduce Transparency`, contrôle des contrastes en Phase 8. |
| R11 | Impossibilité de tester sur appareil physique depuis Windows avant la première release | Élevée (organisationnelle) | Le simulateur ne reproduit ni le micro réel, ni l'arrière-plan, ni la batterie. **Conséquence acceptée : la première nuit réelle sera un test de la bêta elle-même.** D'où l'importance du manifeste de secours et des logs structurés exportables. |

---

## 11. Fonctionnalités à ne jamais promettre

Liste de blocage, applicable au code comme aux textes de l'interface :

1. Phases de sommeil (léger / profond / paradoxal) — aucune donnée ne les supporte.
2. Apnée du sommeil, diagnostic ou dépistage, sous quelque formulation que ce soit.
3. « Sleep Score », « qualité du sommeil », « efficacité du sommeil ».
4. Fréquence cardiaque, respiratoire mesurée, SpO₂.
5. Détection de mouvement corporel par accéléromètre.
6. Attribution d'un ronflement à une personne identifiée.
7. Transcription de ce qui est dit pendant le sommeil.
8. Niveau sonore en dB SPL absolus.
9. Reprise automatique après fermeture manuelle de l'app.
10. Sauvegarde cloud, synchronisation multi-appareils, compte utilisateur.
11. Intégration Apple Watch ou HealthKit.
12. Conseils de santé personnalisés (« tu devrais consulter », « dors mieux en… »).
13. Achats intégrés fonctionnels.
14. Conversation libre avec un assistant IA.

Un avertissement non médical figure dans l'onboarding, dans les réglages, dans le README et dans les notes de version.

---

## 12. Plan de développement détaillé

| Phase | Contenu | Livrables | Statut |
|---|---|---|---|
| **1** | Analyse et faisabilité | Ce document | ✅ Terminée |
| **2** | Arborescence complète, rôle de chaque module, `project.yml`, conventions | Structure du dépôt, README initial | ⏭️ Suivante |
| **3** | Fondations : point d'entrée, `AppEnvironment`, routage, design system (tokens, typographie, composants, haptiques), modèles SwiftData + schéma versionné, repositories, erreurs, logs, permissions | Le projet compile et lance un écran d'accueil vide mais navigable | À faire |
| **4** | Interface complète sur données injectées : onboarding, accueil, préparation, session, rapport, timeline, lecteur, historique, tendances, réglages | Tous les écrans navigables, aucun bouton mort | À faire |
| **5** | Audio réel : `AVAudioSession`, `AVAudioEngine`, segmentation, interruptions, reprise, métriques temps réel, écriture atomique | Une vraie nuit peut être enregistrée | À faire |
| **6** | Analyse : extraction de caractéristiques, SoundAnalysis, fusion, confiance, groupement, clips, statistiques, score, résumé | Une vraie nuit produit un vrai rapport | À faire |
| **7** | Distribution : GitHub Actions, versioning, IPA, Release, feed AltStore, documentation complète | Une release installable existe | À faire |
| **8** | Validation : compilation sans avertissement, accessibilité, Dynamic Type AX5, VoiceOver, contraste, performance, tests, revue des limitations | Bêta privée diffusable | À faire |

**Ordre imposé par les dépendances :** la Phase 4 précède la Phase 5 pour que l'audio arrive dans une coquille déjà navigable et testable ; les phases 5 et 6 injectent du réel dans des interfaces déjà validées. La Phase 7 est indépendante et pourrait être avancée si l'on souhaite valider la chaîne de build tôt — **recommandation : exécuter une version minimale de la Phase 7 juste après la Phase 3**, pour vérifier que le runner compile réellement le projet avant d'avoir écrit 15 000 lignes.

---

## Décisions verrouillées

À reprendre telles quelles dans toutes les phases suivantes :

- Cible **iOS 26.0**, iPhone uniquement, orientation portrait.
- Bundle identifier : `com.somna.app` (modifiable en Phase 2).
- Audio : **AAC-LC, 16 kHz, mono, 32 kbps, segments de 10 minutes**.
- ML : **SoundAnalysis version1** + règles DSP. Aucun modèle Core ML embarqué en v0.1.
- Résumé : **templates locaux**, protocole prêt pour Foundation Models.
- Persistance : **SwiftData** derrière des repositories, audio sur le système de fichiers, `manifest.json` en secours.
- Projet Xcode **généré par XcodeGen** depuis `project.yml`.
- IPA **non signé**, signature déléguée à AltStore côté utilisateur.
- Score nommé **« Score de tranquillité »**, 0–100, jamais « Sleep Score ».
- **Zéro réseau** en v0.1.
