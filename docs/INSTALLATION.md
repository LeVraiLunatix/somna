# Installer Somna

> Bêta privée. Somna n'est pas sur l'App Store et ne le sera pas pendant la bêta.

---

## Ce dans quoi tu t'engages

À lire avant de commencer, parce que ces contraintes viennent d'Apple et qu'aucune n'est contournable.

| Contrainte | Ce que ça veut dire concrètement |
|---|---|
| **L'app expire au bout de 7 jours** | Il faut la « rafraîchir » chaque semaine, sinon elle refuse de s'ouvrir. Tes nuits ne sont pas perdues, l'app redevient utilisable après le rafraîchissement. |
| **3 apps sideloadées maximum** | Somna occupe un des trois emplacements de ton compte Apple. |
| **10 identifiants d'app par semaine** | Limite les réinstallations répétées. |
| **Tu saisis ton Apple ID dans AltStore** | Nécessaire pour signer l'app. Utilise un **mot de passe d'application** plutôt que ton vrai mot de passe : [appleid.apple.com](https://appleid.apple.com) → Connexion et sécurité → Mots de passe d'application. |
| **Pas de notifications distantes** | Somna n'en utilise pas — toutes ses notifications sont locales, donc rien ne manque. |

Si ces contraintes ne te conviennent pas, mieux vaut ne pas commencer. Elles ne s'allègeront pas.

---

## Choisir entre AltStore et SideStore

| | AltStore Classic | SideStore |
|---|---|---|
| Rafraîchissement | Nécessite un ordinateur sur le même Wi-Fi | Se fait depuis l'iPhone seul |
| Installation initiale | Un ordinateur | Un ordinateur, une seule fois |
| Recommandé si | Tu as un Mac ou un PC allumé souvent | Tu veux oublier ton ordinateur ensuite |

**Recommandation :** SideStore, si tu ne veux pas ressortir ton PC toutes les semaines.

*(AltStore PAL, la version distribuée officiellement en Europe, ne convient pas ici : elle ne prend pas les sources tierces de ce type.)*

---

## Installation

### 1. Installer AltStore ou SideStore

Suis le guide officiel de l'outil choisi :
- AltStore : <https://altstore.io>
- SideStore : <https://sidestore.io>

Cette étape se fait une seule fois, depuis un ordinateur.

### 2. Ajouter la source Somna

Dans AltStore/SideStore, onglet **Sources** → **+** → colle cette adresse :

```
https://raw.githubusercontent.com/LeVraiLunatix/somna/main/altstore/apps.json
```

### 3. Installer Somna

Onglet **Browse** → Somna → **INSTALL** (ou **FREE**).

Le téléchargement est petit (quelques mégaoctets). La signature sur l'appareil prend une minute.

### 4. Faire confiance au certificat

Au premier lancement, iOS refusera d'ouvrir l'app.

**Réglages → Général → VPN et gestion de l'appareil → ton Apple ID → Faire confiance.**

### 5. Premier lancement

Somna te fera passer par sept écrans d'explication, te demandera l'accès au micro, puis proposera de mesurer ta chambre pendant quinze secondes.

**Fais la calibration.** Sans elle, Somna n'a aucune référence de ce qu'est le silence chez toi, et la détection est nettement moins fiable.

---

## Avant ta première nuit

- **Branche ton iPhone.** L'enregistrement consomme de l'ordre de 3 à 7 % par heure ; une nuit complète sur batterie ne tiendra pas.
- **Pose-le à moins d'un mètre du lit**, sur une surface stable, micro dégagé (pas sous un oreiller, pas face contre le matelas).
- **Ne balaie pas Somna hors du sélecteur d'apps.** iOS mettrait alors définitivement fin à l'enregistrement, et rien ne peut le relancer. C'est la seule chose contre laquelle l'app ne peut pas te protéger.
- Le mode Ne pas déranger est recommandé, mais pas obligatoire.

Une alarme, un appel, Siri : Somna gère et reprend. L'interruption apparaîtra explicitement dans ta chronologie plutôt que d'être masquée.

---

## Rafraîchir chaque semaine

Ouvre AltStore/SideStore et appuie sur **Refresh All**. Fais-le avant l'expiration : une fois expirée, l'app doit être réinstallée, et **tes nuits sont alors effacées** (iOS supprime le conteneur de l'app).

C'est la limite la plus pénible du sideloading avec un compte gratuit. Mets-toi un rappel hebdomadaire.

---

## Mettre à jour

Une nouvelle version apparaît dans l'onglet **Browse** ou **My Apps**. La mise à jour conserve tes nuits.

---

## Si ça ne marche pas

| Symptôme | Cause probable |
|---|---|
| « Impossible de vérifier l'app » | Certificat pas encore approuvé — étape 4 |
| L'app se ferme au lancement | Profil expiré — rafraîchis |
| « Unable to install » dans AltStore | Trois apps ou extensions déjà actives (AltStore compte dedans), ou 10 App IDs créés dans les 7 derniers jours |
| « The data couldn't be read because it isn't in the correct format » | **Ce n'est pas Somna.** Voir ci-dessous — ça touche toutes les apps installées via AltStore |
| Aucun son détecté après une nuit | Micro obstrué ou trop loin — la section **Qualité d'enregistrement** du rapport le dira |
| L'enregistrement s'est arrêté seul | Batterie vide, ou app balayée hors du multitâche |

### L'erreur 3840, en détail

Le message complet dit « Encountered unknown tag html on line 1 », domaine `NSCocoaErrorDomain`, code 3840. Il décrit l'échec d'un parseur, pas la cause.

Ce qui se passe : AltStore te connecte à Apple via `gsa.apple.com/grandslam/GsService2`. Apple répond **401 Unauthorized** sous forme de page HTML ; AltStore attend un plist et essaie de parser cette page. La connexion à Apple a donc échoué **avant** que l'app n'entre en jeu — c'est pourquoi toutes les apps échouent, pas seulement Somna.

C'est un [bug connu d'AltStore](https://github.com/altstoreio/AltStore/issues/1698), ouvert depuis janvier 2026 et [toujours sans réponse](https://github.com/altstoreio/AltStore/issues/1747). **Aucun correctif officiel n'existe.** Ce qui suit traite le refus d'authentification, pas le bug d'affichage :

1. **Déconnecte puis reconnecte ton Apple ID dans AltStore.** Un jeton expiré produit exactement ce 401.
2. **Utilise un mot de passe pour application** (généré sur [account.apple.com](https://account.apple.com) → Connexion et sécurité) plutôt que ton mot de passe principal.
3. **Attends une heure.** Apple limite les tentatives de connexion, et chaque échec aggrave la suivante — tant que la limite tient, les deux étapes précédentes resteront sans effet.
4. **Passe en Wi-Fi.** AltStore Classic a besoin d'AltServer joignable sur le même réseau.

---

Pour tout le reste : ouvre une [issue](https://github.com/LeVraiLunatix/somna/issues) avec la version indiquée dans **Réglages → À propos**, et une capture de l'écran **Diagnostics** (icône stéthoscope, en haut de l'accueil).

---

## Ce que Somna fait de tes données

Rien ne sort de ton iPhone. Pas de compte, pas de serveur, pas d'analytics, aucun accès réseau — l'app ne contient littéralement aucun code réseau.

L'audio brut est supprimé au bout de sept jours par défaut, seuls les extraits courts de chaque événement sont conservés. Tu peux tout effacer d'un geste dans **Réglages → Confidentialité**.

Somna ne transcrit jamais ce qui est dit pendant la nuit — ni le tien, ni celui des autres personnes présentes.

---

## Avertissement

**Somna n'est pas un dispositif médical.** Elle ne pose aucun diagnostic, ne détecte pas l'apnée du sommeil, ne mesure pas les phases de sommeil, et son « score de tranquillité » décrit le calme sonore de l'enregistrement — pas la qualité de ton sommeil.

Si ton sommeil t'inquiète, parles-en à un médecin.
