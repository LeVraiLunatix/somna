# Somna — Phase 7 (minimale) : validation de la chaîne de build

> Objectif : prouver que la chaîne **Windows → runner macOS → IPA installable** fonctionne, **avant** d'écrire 15 000 lignes.
> Répond au risque **R6** identifié en Phase 1 (Xcode 26 / iOS 26 indisponible ou différent sur le runner).
> La Phase 7 complète (GitHub Release + feed AltStore) viendra après la Phase 6.

---

## 1. Pourquoi maintenant

Une erreur de toolchain découverte après la Phase 6 coûte une réécriture de configuration sur un projet volumineux, avec des dizaines de fichiers déjà écrits contre des API supposées disponibles. Découverte maintenant, elle coûte un `IPHONEOS_DEPLOYMENT_TARGET` à changer dans un fichier de 180 lignes.

Le workflow valide **huit maillons** en une seule exécution :

1. Le runner possède bien Xcode 26 / le SDK iOS 26
2. XcodeGen s'installe et génère un `.xcodeproj` exploitable
3. `project.yml` produit trois cibles reliées correctement
4. Le code Swift 6 compile avec l'isolation MainActor par défaut
5. Les tests unitaires (Swift Testing) s'exécutent sur simulateur
6. Les tests UI (XCTest) lancent réellement l'app
7. L'archive **non signée** pour appareil réussit
8. L'IPA se package et contient un `Info.plist` correct

---

## 2. Code minimal ajouté

Le linker exige un `@main` : impossible de valider la chaîne sur un projet vide. Le strict minimum a donc été écrit, **explicitement marqué comme temporaire** et remplacé en Phase 3.

| Fichier | Rôle | Devenir |
|---|---|---|
| `Somna/App/SomnaApp.swift` | Point d'entrée `@main` | Enrichi en Phase 3 (container SwiftData, `AppEnvironment`) |
| `Somna/App/RootView.swift` | Écran témoin affichant nom, tagline et version | Remplacé en Phase 3 par le routeur réel |
| `Somna/Core/Extensions/Bundle+Version.swift` | Lecture de la version et du build | **Définitif** — utilisé par Réglages › À propos et l'export de diagnostic |
| `Somna/Resources/Assets.xcassets` | `AppIcon` (3 apparences iOS 26), `AccentColor`, `LaunchBackground` | Icône réelle en Phase 4, palette complète en Phase 3 |
| `SomnaTests/Unit/BundleVersionTests.swift` | 5 tests de non-régression | **Définitifs** |
| `SomnaUITests/LaunchSmokeTests.swift` | Lancement réel de l'app | **Définitif** |

### Pourquoi ces tests-là et pas des tests jetables

`BundleVersionTests` vérifie que le bundle **déclare exactement `["audio"]`** comme background mode et possède une description d'usage du micro. Ce ne sont pas des tests de façade :

- Si `UIBackgroundModes` disparaît lors d'un refactor de `project.yml`, l'app **cesse silencieusement d'enregistrer la nuit**. Aucune erreur, aucun crash : les testeurs découvrent le problème au réveil, avec une nuit perdue.
- Si un jour un second background mode est ajouté par inadvertance, le test échoue — la contrainte « un seul mode » de la Phase 1 devient exécutable.
- Si la CI cesse de propager `MARKETING_VERSION`, le feed AltStore publierait une version que l'app ne sait pas identifier.

`LaunchSmokeTests` couvre ce qu'une compilation ne prouve pas : un `UILaunchScreen` mal configuré, une couleur d'asset manquante ou une clé `Info.plist` invalide n'échouent **qu'à l'exécution**.

---

## 3. Le workflow

`.github/workflows/ci.yml`, un seul job, 16 étapes.

### Décisions notables

**Sélection dynamique d'Xcode.** `sudo xcode-select -s "$(ls -d /Applications/Xcode*.app | sort -V | tail -1)"` plutôt qu'une version épinglée. Épingler `Xcode_26.0.app` casse le jour où GitHub retire cette image ; prendre la plus récente survit aux rotations d'image.

**Garde explicite sur le SDK.** Si le SDK iOS le plus récent est inférieur à 26, le job échoue avec un message actionnable plutôt qu'avec 200 lignes d'erreurs de compilation incompréhensibles :

> `Somna targets iOS 26 but the newest iOS SDK on this runner is '18.5'. Pin a runner image that ships Xcode 26, or lower IPHONEOS_DEPLOYMENT_TARGET in project.yml.`

**Sélection dynamique du simulateur.** `scripts/ci/select-simulator.sh` interroge `simctl` et retient le plus récent iPhone disponible. Coder en dur `name=iPhone 17 Pro` est la façon classique dont une CI casse silencieusement.

**Pas de `xcodebuild -exportArchive`.** L'export exige une identité de signature et un profil de provisioning, que nous n'avons délibérément pas. `scripts/ci/make-ipa.sh` construit l'IPA directement — un `.ipa` n'est qu'une archive zip contenant `Payload/Somna.app`. **C'est le format qu'AltStore attend** : il re-signe l'app sur l'appareil avec le compte Apple du testeur. Un IPA signé par un Personal Team ne s'installerait sur aucun autre appareil.

**Vérification du `Info.plist` empaqueté.** Après l'archive, `plutil` vérifie dans le binaire final la présence du background mode `audio`, de la description micro, et la correspondance exacte des numéros de version. C'est la dernière barrière avant qu'un IPA cassé n'atteigne un testeur.

**Versionnement.** `MARKETING_VERSION` vient du tag git (`v0.1.0` → `0.1.0`), `CURRENT_PROJECT_VERSION` du `run_number` GitHub — strictement croissant, jamais de collision, y compris entre deux builds de la même version.

---

## 4. Validation possible depuis Windows

```bash
python scripts/validate-project.py
```

15 vérifications sans Xcode : YAML valide, cible iOS 26.0, trois cibles présentes, bundle identifier, **`audio` comme unique background mode**, description micro, portrait uniquement, conformité export, iPhone uniquement, Swift 6, versionnement pilotable, schéma présent, et existence réelle de chaque racine de sources.

Ce script tourne aussi en CI, avant `xcodegen generate` : il échoue en 2 secondes plutôt qu'après 4 minutes de build.

État actuel : **15/15**.

---

## 5. Comment lancer la validation

Le dépôt n'a pas encore de remote. Une fois créé sur GitHub :

```bash
git remote add origin https://github.com/<utilisateur>/somna.git
git push -u origin main
```

Le workflow se déclenche sur `push` vers `main`, sur toute pull request, et manuellement via **Actions › CI › Run workflow**.

Résultat attendu : un artefact `Somna-unsigned-ipa` téléchargeable, d'environ 1 à 3 Mo à ce stade.

---

## 5 bis. Résultats du premier run réel

Dépôt : **https://github.com/LeVraiLunatix/somna** (public — voir §5 ter).

### Toolchain constaté sur `macos-latest`

| Élément | Valeur |
|---|---|
| Xcode | **26.6** (build 17F113) |
| SDK iOS | **26.5** |
| Simulateur retenu | **iPhone Air** (iOS 26.5) |

**Le risque R6 est levé.** Le SDK iOS 26 est bien disponible, et la garde n'a pas eu à se déclencher.

La sélection dynamique du simulateur a démontré son utilité immédiatement : le runner a retenu
un **iPhone Air**, appareil qu'aucune valeur codée en dur n'aurait devinée. Un
`name=iPhone 17 Pro` en dur aurait fait échouer le run.

### Le seul échec, et ce qu'il nous a appris

Le premier run a échoué à l'étape de tests :

```
LaunchSmokeTests.swift:6:42: error: main actor-isolated initializer 'init()'
  has different actor isolation from nonisolated overridden declaration
LaunchSmokeTests.swift:8:19: error: main actor-isolated instance method 'setUp()'
  has different actor isolation from nonisolated overridden declaration
```

Cause directe de la décision de Phase 2 `SWIFT_DEFAULT_ACTOR_ISOLATION: MainActor` : elle isole
implicitement toute classe au MainActor, y compris les sous-classes de `XCTestCase`, dont les
initialiseurs et les hooks de cycle de vie sont `nonisolated`.

**Correction retenue :** désactiver l'isolation par défaut sur les deux cibles de test plutôt que
d'annoter chaque classe. La première approche règle le problème une fois pour toutes ; la seconde
l'aurait fait réapparaître à chaque nouvelle classe de test des phases 4 à 8.

C'est exactement le genre de découverte qui justifiait d'avancer cette phase : ce défaut aurait
sinon surgi en Phase 8, sur des dizaines de fichiers de test déjà écrits.

### Run vert — chaîne complète validée

Second run : **succès en 5 min 11 s**, les 16 étapes passées.

| Vérification | Résultat |
|---|---|
| Tests unitaires (Swift Testing) | 5/5 |
| Test UI (lancement réel sur simulateur) | 1/1, en 22,6 s |
| Archive appareil non signée | OK |
| IPA produit | `Somna-0.1.0-2-unsigned.ipa`, 12 190 octets |
| `plutil` sur le bundle empaqueté | OK |

**Inspection de l'IPA téléchargé** (les 12 Ko méritaient un contrôle plutôt qu'une supposition) :

```
Payload/Somna.app/Somna         79 160 octets   Mach-O 64-bit / arm64
Payload/Somna.app/Assets.car    19 160 octets
Payload/Somna.app/Info.plist     1 233 octets
Payload/Somna.app/PkgInfo             8 octets
```

| Clé du bundle final | Valeur |
|---|---|
| `CFBundleIdentifier` | `com.somna.app` |
| `CFBundleShortVersionString` | `0.1.0` |
| `CFBundleVersion` | `2` (numéro de run) |
| `MinimumOSVersion` | **26.0** |
| `UIBackgroundModes` | `['audio']` |
| `UIRequiredDeviceCapabilities` | `['arm64', 'microphone']` |
| `DTPlatformVersion` / `DTXcode` | 26.5 / 2660 |

Un binaire de 79 Ko est normal et non suspect : depuis iOS 12.2, la bibliothèque d'exécution
Swift et SwiftUI sont fournies par le système et liées dynamiquement — rien n'est embarqué dans
l'app. Avec l'optimisation whole-module et le dead-code stripping en Release, un écran témoin
tient dans cette taille.

Absence attendue et correcte : ni `_CodeSignature`, ni `embedded.mobileprovision`. C'est
exactement l'état qu'AltStore attend pour re-signer avec le compte du testeur.

### Nettoyage annexe

`actions/checkout` et `actions/upload-artifact` passés de `v4` à `v5` — GitHub force désormais
les actions Node 20 sur Node 24 en émettant un avertissement de dépréciation.

Résultat partiel : `checkout@v5` a bien fait disparaître l'avertissement, **`upload-artifact@v5`
non** — cette version cible toujours Node 20. Il n'y a rien à corriger de notre côté ; l'action
fonctionne, et l'avertissement disparaîtra quand GitHub publiera une version compilée pour
Node 24.

## 5 ter. Le dépôt doit être public

Contrainte découverte lors de la création du dépôt, non anticipée en Phase 1.

« Bêta privée » qualifie le **cercle de testeurs**, pas la visibilité du dépôt. La chaîne AltStore
impose deux accès publics non négociables :

- l'URL de l'IPA référencée dans le feed doit être téléchargeable **sans authentification** — les
  assets de release d'un dépôt privé exigent un token qu'AltStore ne sait pas fournir ;
- le feed `apps.json` doit être servi par GitHub Pages, indisponible sur dépôt privé avec un
  compte gratuit.

**Conséquence de sécurité :** aucun secret, aucune clé, aucun chemin personnel ne doit entrer dans
ce dépôt — y compris dans les exports de diagnostic prévus en Phase 7. La règle « aucun secret en
dur » passe du statut de bonne pratique à celui de contrainte réelle.

Effet de bord favorable : les minutes GitHub Actions sont illimitées sur les dépôts publics, donc
le quota de 2000 min/mois n'est pas consommé.

## 6. Ce que cette phase ne prouve pas

À dire clairement, pour ne pas confondre « la CI est verte » avec « ça marche » :

- **Rien sur le comportement réel de l'audio.** Aucun test automatisé ne peut valider l'enregistrement écran verrouillé, la gestion des interruptions, ou la consommation batterie. Cela reste le risque R11, et sera vérifié sur appareil physique après la Phase 5.
- **Rien sur la qualité de la classification.** Elle exige de vraies nuits enregistrées.
- **Rien sur le sideloading.** L'installation via AltStore ne sera validée qu'à la première release réelle.
- L'IPA produit est fonctionnel mais **ne contient pour l'instant qu'un écran témoin**.

---

## 7. Checklist de validation

- [x] Code minimal compilable (`@main`, vue racine, assets)
- [x] Tests unitaires portant sur des invariants réels, pas des tests de façade
- [x] Test UI de lancement
- [x] Workflow CI complet : diagnostic, garde SDK, génération, tests, archive, IPA, vérification, artefacts
- [x] Sélection dynamique d'Xcode et du simulateur — résistante aux rotations d'image
- [x] Packaging IPA sans signature, conforme à ce qu'attend AltStore
- [x] Versionnement piloté par tag et par numéro de run
- [x] `ci.yml` syntaxiquement valide (16 étapes vérifiées par parsing)
- [x] Python embarqué dans `select-simulator.sh` validé par `ast.parse`
- [x] `scripts/validate-project.py` : 15/15 depuis Windows
- [x] **Workflow réellement exécuté sur un runner** — run `30760902298`, vert en 5 min 11 s
- [x] Toolchain confirmé : Xcode 26.6, SDK iOS 26.5 — **risque R6 levé**
- [x] IPA téléchargé et inspecté : Mach-O arm64, `MinimumOSVersion` 26.0, background mode `audio`
- [x] Résistance aux rotations d'image démontrée : le runner a retenu un *iPhone Air*

---

**Prochaine étape : Phase 3 — Fondations.**
