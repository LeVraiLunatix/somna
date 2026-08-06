# Somna — Retours de la bêta v0.1

> Issus du premier test réel sur appareil. Rangés par ce qu'ils coûtent à un utilisateur, pas par ordre d'arrivée.
>
> **Tous traités.** CI verte au run `30848478604` — 267 tests unitaires et 12 audits d'accessibilité. Rien n'est publié.

---

## Bugs

### 1. ✅ Le thème clair ne s'applique pas

**Symptôme.** Choisir « Clair » dans les Réglages ne change rien : l'app reste en sombre.

**Cause, confirmée dans le code.** `RootView.colorScheme` lit le thème ainsi :

```swift
private var colorScheme: ColorScheme? {
    switch environment.settings.load().theme { … }
}
```

`environment.settings.load()` est un simple appel de fonction. Il ne crée **aucune dépendance observable** : quand `SettingsStore` écrit le nouveau thème dans `UserDefaults`, rien ne dit à SwiftUI que `RootView` doit être réévalué. L'écran de réglages se met à jour, la racine non.

**Portée réelle.** Le problème n'est pas limité au thème. Toute la lecture des réglages hors de l'écran Réglages a le même défaut : `RootView` lit aussi `hasCompletedOnboarding` de cette façon, et la sensibilité d'analyse est relue à chaque session sans que rien n'observe son changement. Le thème est simplement le seul endroit où ça se voit.

**Correction.** Un store de réglages `@Observable` unique, tenu à la racine et injecté, remplaçant les appels dispersés à `settings.load()`. Le repository reste la couche de persistance ; ce qui manque est la couche observable au-dessus.

---

### 2. ✅ La calibration est impossible à refaire

**Symptôme.** Aucune entrée dans les Réglages pour lancer ou relancer la calibration.

**Ce qui aggrave le cas.** L'onboarding dit, en toutes lettres :

> « La calibration a besoin du micro. Tu pourras la faire plus tard depuis les Réglages. »

Ce n'est donc pas une fonctionnalité manquante, c'est **une promesse que l'app ne tient pas**. Quelqu'un qui saute la calibration au premier lancement — ce que l'onboarding l'encourage à faire s'il est dans une pièce bruyante — n'a plus aucun moyen de la faire.

Et sans calibration, il n'y a pas de plancher de bruit de référence : les seuils de détection tombent sur des valeurs par défaut qui ne correspondent à aucune chambre en particulier. La qualité de détection en dépend directement.

**Correction.** Une section Calibration dans les Réglages : état actuel (faite / jamais faite / ancienne), date, verdict, et un bouton pour (re)mesurer. Le service et l'évaluateur existent déjà — c'est l'écran qui manque, pas le mécanisme. `CalibrationProfile.isStale(now:)` est déjà écrit et n'est appelé nulle part.

---

## Demandes

### 3. ✅ Section Personnalisation

Variantes de logo, thèmes alternatifs, nouveaux logos, versions Liquid Glass.

**Ce qui est facile.** Les couleurs sont déjà des tokens sémantiques centralisés dans un seul fichier. Ajouter des palettes revient à faire de `SomnaColor` un sélecteur entre plusieurs jeux de valeurs — précisément ce que cette centralisation rendait possible. Aucun écran ne change.

**Ce qui est faisable mais mérite d'être su.** Les icônes alternatives passent par `setAlternateIconName` et une déclaration `CFBundleAlternateIcons`. Ça fonctionne en sideloading, sans entitlement. Chaque variante est un jeu de trois PNG, et le générateur d'icône existant peut les produire à partir de paramètres.

**Ce qui n'est pas possible tel quel.** iOS n'applique pas de matériau à une icône d'app : une icône « Liquid Glass » doit avoir cet aspect **peint dans l'image**. On peut le simuler de façon convaincante — reflets, réfraction, bord lumineux — mais c'est du rendu figé, pas l'effet système. À dire dans l'interface plutôt qu'à laisser croire.

En revanche, le vrai Liquid Glass peut être étendu **dans** l'app : c'est là qu'il est réel, et `GlassSurface` est déjà le point d'entrée unique.

---

### 4. ✅ Animation de lancement

**Ce qui est demandé.** Un « S » apparaît, puis « omna » sort du S en glissant vers la droite. Le mot devient ensuite la barre de chargement : il se remplit du bleu de l'app avec de petites vagues animées. Le chargement terminé, zoom au milieu du mot et fondu vers l'app.

**Contrainte technique à connaître.** L'écran de lancement d'iOS (`UILaunchScreen`) est **statique** — aucune animation n'y est possible. Cette séquence doit donc jouer *après* le lancement, en SwiftUI, dans le premier écran de l'app.

**Le vrai piège.** Le cahier des charges dit : *« L'application doit démarrer rapidement. Ne bloque pas le lancement. »* Une barre de chargement qui ne suit pas un chargement réel est une mise en scène — et c'est exactement le genre de théâtre que cette app refuse partout ailleurs.

La séquence doit donc être **adossée au travail réel du démarrage** : ouverture du conteneur SwiftData, récupération des nuits interrompues, nettoyage des orphelins. Si ce travail finit avant l'animation, l'animation s'écourte au lieu d'être rallongée. Sur un appareil rapide avec peu de nuits, elle durera une fraction de seconde — et c'est le bon comportement.

**Notes de réalisation.**
- Remplissage : une forme d'onde animée, masquée par le mot (`.mask(Text("Somna"))`). Deux sinusoïdes déphasées lues comme des vagues.
- Le glissement de « omna » hors du S : `matchedGeometryEffect` ou un simple décalage animé, l'un et l'autre suffisent.
- **Reduce Motion doit court-circuiter toute la séquence** vers un fondu simple. Une animation d'ouverture est exactement ce que ce réglage existe pour supprimer.
- Le zoom final ne doit pas retarder l'interactivité : l'app est utilisable dès la fin du fondu.

### 3. ✅ Notification mensongère : « ta nuit est prête » sans nuit

**Symptôme.** Notification reçue à 8 h annonçant que le rapport de la nuit était prêt, alors qu'aucune session n'avait été lancée.

**Cause, confirmée dans le code.** Le « résumé du matin » est programmé comme une **notification calendaire répétitive quotidienne à 8 h**, sans aucune condition :

```swift
if settings.morningSummaryEnabled {
    await schedule(
        identifier: Identifier.morningSummary,
        title: "Your night is ready to read",
        body: "Somna has finished going over what it heard.",
        at: DateComponents(hour: 8, minute: 0)
    )
}
```

Elle se déclenche tous les matins, qu'une nuit existe ou non.

**Pourquoi c'est le pire bug du projet.** Toute l'identité de Somna tient dans le refus d'affirmer plus que les données ne soutiennent — vocabulaire nuancé, score absent quand l'audio est inexploitable, résumé structurellement incapable d'inventer un événement. Et l'app **ment à quelqu'un tous les matins à 8 h**. Aucun autre défaut de cette liste ne contredit le produit à ce point.

**Deuxième constat.** La méthode qui ferait les choses correctement existe déjà — `notifyReportReady(sessionID:)` — et **n'est appelée nulle part**. Elle a été écrite, testée à la compilation, et jamais branchée.

**Troisième constat.** L'heure est codée en dur. Seul le rappel du soir est réglable ; le résumé du matin est figé à 8 h et le rapport hebdomadaire au dimanche 9 h.

**Correction.** Supprimer la notification calendaire répétitive. Le résumé du matin doit être **déclenché par la fin d'une analyse**, via `notifyReportReady`, c'est-à-dire seulement quand un rapport existe réellement. Et l'heure doit être réglable partout où une heure est proposée.

---

### 4. ✅ Arrêter la nuit sans avoir à ouvrir l'app

**Ce qui existe.** Le bouton « Terminer la nuit » sur l'écran de session. Il faut donc déverrouiller, ouvrir Somna, et le trouver.

**Ce qui manque.** Pouvoir arrêter au moment où on se lève, sans cette manipulation.

**Pistes, avec leur coût réel.**

- ~~**Live Activity avec un bouton d'arrêt**~~ — **tranché : non.** Coût : une extension widget, donc un binaire séparé avec son propre bundle ID. Un compte gratuit n'active que trois apps *et extensions* à la fois, et AltStore en occupe déjà une : Somna prendrait deux emplacements sur trois, et chaque testeur devrait désinstaller quelque chose pour l'installer.
- ~~**Now Playing (`MPRemoteCommandCenter`)**~~ — **tranché : non.** Poserait un bouton d'arrêt sans aucune extension, mais seulement pour l'app qu'iOS considère comme *celle* qui joue. La session est déjà `.playAndRecord` ; ce qui bloque, c'est `.mixWithOthers` — précisément le drapeau qui laisse la musique de quelqu'un continuer pendant que Somna écoute. Prendre le créneau Now Playing suppose de l'abandonner, donc de capter le bouton play/pause des écouteurs et de déplacer ce sur quoi l'utilisateur s'est endormi : exactement la plainte qui a rendu `.mixWithOthers` nécessaire.
- **Fait : une notification avec une action.** Posée au démarrage de la nuit, retirée à sa fin, portant « Arrêter la nuit ». Sans `.foreground` ni `.authenticationRequired`, donc traitée en arrière-plan sans déverrouillage. Aucun App ID, aucun effet sur la session audio. Moins joli qu'une Live Activity, et honnête sur ce que c'est.
- **Bouton d'arrêt dans la notification** de session en cours : plus léger, pas d'extension, mais suppose une notification persistante.
- **Arrêt automatique par l'alarme** — voir le point suivant. C'est probablement le plus élégant : on se réveille, l'alarme sonne, la nuit se termine.

---

### 5. ✅ Un vrai réveil dans l'app

**Ce qui est demandé.** Régler une heure de réveil dans Somna, qui sonne vraiment, et qui termine la nuit.

**La distinction qui compte.** Une `UNNotification` **n'est pas un réveil**. Elle est silencée par le mode Concentration, par l'interrupteur silencieux, et peut être manquée. Promettre « un vrai réveil » avec des notifications serait exactement le genre de sur-promesse que cette app refuse partout ailleurs — et le bug ci-dessus montre que ce risque n'est pas théorique.

**La vraie réponse : AlarmKit (iOS 26).** C'est le framework prévu pour ça, introduit précisément pour permettre à une app tierce de sonner comme l'app Horloge — au travers du mode silencieux et des Concentrations. Il apporte aussi sa propre présentation sur l'écran verrouillé, ce qui pourrait offrir le bouton d'arrêt du point 4 **sans extension widget**.

**Vérifié : aucun compte développeur payant n'est nécessaire.** AlarmKit demande uniquement :

- la clé `NSAlarmKitUsageDescription` dans l'`Info.plist` ;
- une autorisation obtenue à l'exécution.

**Aucune *entitlement* signée.** Le point mérite d'être écrit noir sur blanc parce qu'il circule une fausse information : `com.apple.developer.alarmkit` **n'existe pas**. Un ingénieur Apple l'a confirmé sur les forums, dans un fil ouvert par un développeur dont le build échouait à cause de cette clé — inventée par un LLM. Sa réponse mérite d'être citée ici, parce qu'elle vise exactement le risque que court ce projet :

> « Nous constatons une augmentation des LLM qui inventent des entitlements inexistants… Les LLM ne semblent pas comprendre la différence entre les entitlements déclarés, ceux qu'il faut demander, et les entrées d'Info.plist — ils appellent tout “entitlement”. »

Source : [forums.developer.apple.com/forums/thread/797950](https://developer.apple.com/forums/thread/797950)

**Conséquence pour Somna.** AlarmKit est compatible avec le sideloading sur compte gratuit. C'est donc la bonne réponse au réveil, et probablement aussi à l'arrêt de la nuit.

**Vérifié aussi : pas d'extension widget pour un réveil à heure fixe.**

La session WWDC25 « Wake up to the AlarmKit API » est explicite : *« To use countdown functionality, you're required to provide a live activity for it. »* L'obligation est **bornée au décompte**. Pour une alarme `Alarm.Schedule.fixed(date)` qui ne fait que sonner, le système fournit lui-même l'interface : titre, nom de l'app, bouton d'arrêt, et bouton de report optionnel.

Sources : [WWDCNotes — session 230](https://wwdcnotes.com/documentation/wwdc25-230-wake-up-to-the-alarmkit-api/) · [Apple — Wake up to the AlarmKit API](https://developer.apple.com/videos/play/wwdc2025/230/)

**Conséquence pour Somna.** Le réveil ne coûte **aucun App ID supplémentaire**. L'app reste à un seul emplacement sur le quota de trois d'un compte gratuit. C'est ce qui rend la fonctionnalité non seulement possible mais bon marché.

**Un point encore ouvert, et il est important.** Le bouton d'arrêt de l'interface système est exactement ce qu'il faut pour terminer la nuit sans déverrouiller — à condition que l'app soit *prévenue* quand l'utilisateur l'actionne. Il faut confirmer que `AlarmManager` expose bien ces changements d'état à l'app (un flux d'`alertingAlarms` ou équivalent), et surtout **que l'app est réveillée pour les recevoir** alors qu'elle tourne en arrière-plan avec le mode audio actif.

Si ce lien existe, les points 4 et 5 se résolvent ensemble : le réveil sonne, l'utilisateur appuie sur Arrêter, la session se termine proprement. Sinon, l'alarme reste un réveil et l'arrêt de la nuit demande autre chose.

C'est le genre de détail qui ne se tranche que sur un appareil. À mettre en tête de la liste des choses à éprouver lors du premier vrai test.

---

## Ordre proposé

1. **Notification mensongère** — l'app contredit tous les jours ce qu'elle prétend être. Rien ne devrait passer devant.
2. **Thème** — bug visible, et sa correction assainit toute la lecture des réglages.
3. **Calibration dans les Réglages** — l'onboarding promet quelque chose qui n'existe pas, et la qualité de détection en dépend.
4. **Réveil + arrêt de la nuit** — à instruire ensemble : si AlarmKit est utilisable en sideloading, il résout les deux d'un coup.
5. **Animation de lancement** — forte valeur perçue, isolée, ne touche à rien d'autre.
6. **Personnalisation** — la plus grosse, et celle qui gagne le plus à être faite après un thème qui fonctionne.

---

## Question ouverte

Le retour porte sur l'interface. **Rien n'est encore su de l'enregistrement lui-même** : écran verrouillé, interruptions, batterie sur une nuit entière, et surtout ce que la classification donne sur de vrais sons.

C'est le risque R11 de la Phase 1, et il reste le seul écart entre « l'app est complète » et « l'app fonctionne ».


---

## Ce qui a été livré

| Point | Ce qui a changé |
|---|---|
| Notification mensongère | Envoyée par le pipeline d'analyse quand un rapport existe, plus par une minuterie. Le rapport hebdomadaire n'est programmé que s'il existe une nuit. |
| Thème | `AppSettings`, store observable unique à la racine. Corrige aussi `hasCompletedOnboarding` et la lecture de la sensibilité. |
| Calibration | Écran dédié, atteignable depuis Réglages › Enregistrement, avec l'état, la date et un avertissement au-delà d'un mois. |
| Réveil | AlarmKit, sonne à travers le mode silencieux et les Concentrations. **L'arrêt de la nuit ne dépend pas de lui** : un minuteur interne termine la session au même instant. |
| Animation de lancement | Le S, puis le mot, puis le remplissage — adossé au travail réel du démarrage, jamais rallongé. Reduce Motion la supprime. |
| Personnalisation | Quatre accents et autant d'icônes. Seuls les accents varient : les contrastes mesurés restent intacts. |

## Ce qui reste vrai

**Aucune vraie nuit n'a encore été enregistrée.** Enregistrement écran verrouillé, interruptions réelles, batterie sur huit heures, classification de sons réels, et maintenant le comportement d'AlarmKit en arrière-plan : rien de tout cela n'a tourné sur un appareil.

C'est toujours le seul écart entre « l'app est complète » et « l'app fonctionne ».
