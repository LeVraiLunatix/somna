# Somna v0.1 — Phase 3B : Design system, services et injection

> Seconde moitié de la Phase 3. Suite de [04-PHASE-3A-FONDATIONS.md](04-PHASE-3A-FONDATIONS.md).
> Statut : **livrée, CI verte** — run `30765235135`, 71 tests, IPA `0.1.0 (10)`.

---

## 1. Décisions structurantes

### 1.1 La palette est en Swift, pas en catalogue d'assets

Somna a besoin de **quatre variantes de chaque couleur** : clair, sombre, et la version contraste élevé de chacune. En catalogue d'assets, cela fait une trentaine de fichiers JSON dont les relations sont invisibles en revue — rien n'empêche `surface` de devenir plus clair que `surfaceElevated` en mode sombre uniquement.

Un seul fichier lisible, où les variantes de contraste sont écrites à côté des couleurs qu'elles renforcent. C'est le seul endroit du projet autorisé à contenir un hexadécimal, et l'un des deux seuls autorisés à importer UIKit — SwiftUI n'a pas d'équivalent réagissant à `accessibilityContrast`.

Chaque token porte un nom de **rôle**, jamais d'apparence. Pas de `darkGray` : le jour où il faut l'éclaircir, le nom ment.

### 1.2 `GlassSurface` est l'unique point d'application de Liquid Glass

Deux problèmes réglés par un seul modificateur :

- **L'accessibilité ne peut plus être oubliée.** `Reduce Transparency` et `Increased Contrast` sont traités une fois. Un écran écrit dans six mois hérite du comportement au lieu de devoir y penser.
- **La sur-utilisation devient visible.** Compter les appels d'un modificateur est une revue que n'importe qui peut faire ; repérer des `.glassEffect` éparpillés, non. C'est la mise en œuvre du garde-fou contre le risque R10.

Le repli est une surface **opaque**, pas un matériau translucide : quelqu'un qui a désactivé la transparence a demandé de l'opacité, et l'honorer à moitié est pire que l'ignorer.

### 1.3 Reduce Motion passe par un `ViewModifier`, pas par une convention

`somnaAnimation(_:value:)` lit `accessibilityReduceMotion` depuis l'environnement — impossible depuis une fonction libre. Router chaque animation par là signifie qu'un écran ne *peut pas* oublier le réglage.

Reduce Motion supprime l'animation, pas le changement d'état : l'interface se met toujours à jour, elle arrive au lieu de voyager.

### 1.4 Les haptiques sont un vocabulaire d'événements

`HapticEvent.sessionStarted`, pas `impact(.soft)`. Les appelants disent *ce qui s'est passé*, jamais *ce que ça doit produire*. Retoucher le langage physique de l'app devient une édition unique.

`play` est `nonisolated` et saute vers le MainActor : un retour haptique ne vaut jamais de faire attendre un moteur audio.

### 1.5 L'environnement par défaut échoue au lieu de mentir

`AppEnvironment.unconfigured` est la valeur que SwiftUI utilise avant l'injection à la racine. Son repository **lève une erreur** au lieu de renvoyer une liste vide.

Un historique vide est une réponse plausible. Une vue mal placée qui affiche « aucune nuit pour l'instant » masquerait l'injection manquante jusqu'à ce que quelqu'un se demande où sont passées ses données. Une erreur la révèle immédiatement, dans l'état d'erreur que l'écran doit de toute façon gérer, sans planter.

### 1.6 Le lancement dégradé plutôt que le crash

Si le `ModelContainer` refuse de s'ouvrir, `SomnaApp` démarre en mode dégradé et affiche l'erreur. Un bêta-testeur dont la base est corrompue a encore besoin d'un écran Réglages fonctionnel pour effacer ses données et continuer ; un crash au lancement ne lui laisse rien.

### 1.7 `permanentlyDenied` est distinct de `denied`

iOS n'accorde qu'une invite par permission et par installation. Les deux états appellent des interfaces différentes : l'un se résout par un bouton dans l'app, l'autre uniquement dans les Réglages iOS. Les confondre produit l'impasse classique — un bouton qui redemande une permission qu'iOS ne redemandera jamais.

`canPrompt` rend la distinction explicite et testée.

### 1.8 L'écran de disponibilité n'est pas un placeholder

`SystemStatusView` gagne sa place deux fois : il prouve aujourd'hui que le graphe de dépendances est câblé de bout en bout, et il deviendra **Réglages › Diagnostics** en Phase 4 — la première chose à demander en capture d'écran à un bêta-testeur qui signale un problème.

Pas de barre d'onglets avec trois onglets vides : ce serait mettre des impasses devant un testeur dès le premier jour. La barre arrive en Phase 4 avec les écrans qui la remplissent.

---

## 2. Le bug que la CI n'a pas attrapé, et que les logs ont révélé

Le run était **vert côté tests UI**. En lisant les journaux, une anomalie CoreData m'a fait relire `NightFileStore.availableCapacity()` :

> La capacité libre était interrogée sur le dossier de Somna, **qui n'existe pas au premier lancement**. La requête ne renvoyait rien, `availableCapacity` valait 0, et l'écran de disponibilité l'aurait lu comme « plus d'espace » — une installation neuve aurait refusé d'enregistrer.

Invisible en test pour une raison précise : sur simulateur neuf, le micro est toujours indéterminé, et `blockingIssue` vérifie le micro **avant** le stockage. Le test acceptait donc l'écran « micro bloqué » et passait au vert sans jamais atteindre la branche fautive.

Correction : la capacité est une propriété du volume, donc interrogée sur un chemin qui existe toujours. Test de non-régression ajouté, qui vérifie la capacité **avant** toute création de dossier.

**Leçon retenue :** un run vert n'est pas une preuve d'absence de bug quand une garde en masque une autre. Les journaux d'un run réussi méritent d'être lus.

---

## 3. Le second échec : l'archive Release

Les 71 tests passaient, mais l'archive échouait :

```
RootView.swift:43: error: type 'AppEnvironment' has no member 'preview'
```

Les blocs `#Preview` sont compilés **en Release aussi**, alors que `AppEnvironment.preview()` est volontairement sous `#if DEBUG` — le décor de preview n'a pas à partir dans une bêta. Les previews sont désormais encadrées.

C'est l'étape d'archive qui l'a attrapé, pas les tests. Argument supplémentaire en faveur d'avoir avancé la Phase 7 : sans elle, ce défaut n'aurait été découvert qu'à la première tentative de release.

---

## 4. Fichiers livrés

```
Somna/DesignSystem/
  Foundation/  SomnaColor.swift, SomnaTypography.swift, SomnaMotion.swift
  Effects/     GlassSurface.swift
  Haptics/     HapticFeedback.swift, LiveHapticFeedback.swift
  Components/  Cards/SomnaCard.swift, States/StateViews.swift

Somna/Domain/Protocols/  PermissionRequesting.swift
Somna/Services/Permissions/  PermissionService.swift
Somna/Data/FileSystem/   NightFileStore.swift
Somna/Core/Utilities/    ByteFormatting.swift

Somna/App/  AppEnvironment.swift, AppEnvironment+Preview.swift,
            AppRouter.swift, RootView.swift, SomnaApp.swift
Somna/Features/Home/  SystemStatusStore.swift, SystemStatusView.swift

SomnaTests/Unit/  FileStoreTests.swift (stockage, formatage, permissions, routage)
SomnaUITests/     LaunchSmokeTests.swift (mis à jour)
```

---

## 5. Checklist de validation

- [x] Palette sémantique avec variantes clair / sombre / contraste élevé
- [x] Aucun hexadécimal hors `SomnaColor`
- [x] UIKit confiné à deux fichiers (couleurs, haptiques), justifié dans chacun
- [x] Liquid Glass appliqué depuis un point unique, repli opaque
- [x] Reduce Motion impossible à oublier (modificateur obligatoire)
- [x] Injection unique, aucun singleton mutable
- [x] Environnement par défaut qui échoue plutôt que de simuler des données vides
- [x] Lancement dégradé si la base refuse de s'ouvrir
- [x] `permanentlyDenied` distinct, aucun bouton sans effet
- [x] Écritures fichier atomiques, `.part` détectables après crash
- [x] Audio exclu de la sauvegarde iCloud
- [x] Aucun onglet ni écran vide
- [x] 71 tests au vert, IPA produit
- [ ] Chaînes localisées — défauts anglais en place, catalogue FR en Phase 4

---

**Prochaine étape : Phase 4 — Interface.** Onboarding, accueil, préparation, session, rapport, timeline, lecteur, historique, tendances, réglages, et le catalogue de localisation FR/EN généré depuis la table de phrasing.
