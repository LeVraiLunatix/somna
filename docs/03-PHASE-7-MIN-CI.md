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
- [ ] **Workflow réellement exécuté sur un runner** — nécessite un dépôt GitHub distant

Le dernier point est le seul qui compte vraiment, et il est entre tes mains : il faut un remote.

---

**Prochaine étape : Phase 3 — Fondations.**
