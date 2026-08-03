# Retour du test sur appareil — enregistrement d'écran du 3 août 2026

> 109 s d'interface sur iPhone, analysée image par image.
> Méthode réutilisable : `ffmpeg -ss <t> -i video -frames:v 1 -vf scale=560:-1 out.jpg`, puis lecture de l'image. Une planche-contact (`fps=1/3` + filtre `tile=6x6`) donne la vue d'ensemble en une seule lecture.

---

## Corrigé

### 1. Écran noir sur Calibration — corrigé

Signalé à 1:02. Le détail décisif n'était pas le noir mais **l'absence de titre de navigation** : une destination qui n'a rien poussé, pas un écran au contenu vide.

Deux causes empilées :

- `case .calibration` manquait dans le routeur.
- **Plus grave :** `SettingsView` déclarait son propre `navigationDestination(for: AppDestination.self)` ne gérant que `.premium`. Plus proche dans la hiérarchie, il masquait celui de la racine et poussait une vue vide pour tout le reste. Il avalait silencieusement **n'importe quelle** destination poussée depuis les Réglages.

La correction qui compte est structurelle : une seule registration pour ce type dans toute l'app, et le `switch` est devenu exhaustif. Le `default:` rendait une destination sans écran invisible — elle affichait un écran plausible mais faux au lieu d'empêcher la compilation.

### 2. Autorisations système en anglais — corrigé

Les deux invites, micro et AlarmKit, affichaient la description d'usage **en anglais** dans une invite système française — au moment précis où l'app demande qu'on lui confie un micro pendant la nuit.

Cause : les descriptions de l'`Info.plist` n'étaient pas localisées. `InfoPlist.xcstrings` était mentionné dans la doc de Phase 2 mais n'avait jamais été créé. Le générateur le produit maintenant, et la CI le vérifie comme l'autre catalogue.

---

## À trancher

### 3. « Commencer la nuit » paraît désactivé

Sur les dernières images (103 s, 107 s, 108 s), le bouton est **gris avec un libellé estompé** — l'apparence d'un bouton désactivé — alors que toutes les vérifications sont au vert :

| Vérification | État |
|---|---|
| Micro | Autorisé ✓ |
| Espace libre | 7,48 Go ✓ |
| Alimentation | En charge ✓ |
| Calibration de la pièce | Faite ✓ |
| Placement | ⚠ (consultatif, non bloquant) |

**Le code dit qu'il devrait être actif.** `canStart` vaut `!checks.contains { $0.severity == .blocking } && phase == .preparing` ; aucune des vérifications affichées n'est bloquante, et `phase` vaut `.preparing` par défaut. Seuls le micro et l'espace disque peuvent bloquer, et les deux sont satisfaits.

L'accent n'explique rien non plus : « Marée » en mode sombre est `0x4FBEC6`, un turquoise vif, pas du gris.

**Deux hypothèses restantes**, et une question à l'utilisateur les départage :

- le bouton a été capté **pendant un appui** (la vidéo s'arrête à 109,3 s, soit une seconde après) — auquel cas il n'y a pas de bug ;
- il est réellement désactivé pour une raison d'état que l'analyse statique ne montre pas.

**Question : appuyer dessus déclenche-t-il quelque chose ?** Si rien ne se passe, c'est le bug le plus grave du projet — l'app ne peut pas faire ce pour quoi elle existe.

---

## Vu fonctionnant

Thème clair · changement d'icône avec confirmation système · quatre accents (Minuit, Aube, Marée, Encre) · **calibration rendant un vrai verdict** (« Emplacement à améliorer — Le signal est très faible ») · rapport hebdomadaire réglable au dimanche 12:00 · écran Somna Plus · portail de bêta · animation de lancement · onboarding en sept étapes avec compteur d'étape visible.

Autrement dit : les corrections v0.2 tiennent sur un vrai appareil.

---

## Toujours pas su

**Aucune nuit n'a été enregistrée.** Le test portait sur l'interface. Écran verrouillé, interruptions, batterie sur huit heures, comportement d'AlarmKit en arrière-plan, et ce que la classification donne sur de vrais sons : tout cela reste le risque R11.
