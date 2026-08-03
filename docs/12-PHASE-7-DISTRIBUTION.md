# Somna v0.1 — Phase 7 : Distribution

> Statut : **préparée, rien publié** — répétition à vide validée sur le run `30777655030`.
> Il ne manque qu'un tag git, et c'est une décision qui t'appartient.

---

## 1. Ce qui existe maintenant

| Élément | Rôle |
|---|---|
| `.github/workflows/release.yml` | Build, tests, archive, IPA, Release GitHub, mise à jour du feed |
| `altstore/apps.json` | La source AltStore, actuellement à zéro version |
| `scripts/ci/update-altstore-source.py` | Ajoute une version au feed, sans écraser les précédentes |
| `scripts/make-app-icon.py` | Génère les trois variantes d'icône iOS 26 |
| `Somna/Resources/PrivacyInfo.xcprivacy` | Manifeste de confidentialité |
| `docs/INSTALLATION.md` | Guide destiné aux testeurs |

---

## 2. Publier reste un geste délibéré

Le workflow ne se déclenche **que sur un tag**. Aucun push sur `main` ne peut publier quoi que ce soit, quelle qu'en soit la taille.

Il expose aussi une **répétition à vide** (`workflow_dispatch`, `dry_run: true`) : toute la chaîne tourne, l'IPA est produit et vérifié, et les deux étapes de publication sont sautées. C'est ce qui a validé cette phase sans rien rendre public.

Le workflow refuse également de publier si un test échoue. Une release qui embarque des tests rouges est pire que pas de release : un testeur ne peut alors pas distinguer un bug connu d'un bug neuf.

---

## 3. L'icône est générée, pas dessinée

Deux raisons, dans cet ordre :

1. **Elle peut être produite depuis Windows**, où aucun éditeur d'image ne fait partie de la chaîne d'outils.
2. **Une modification du signe devient un diff relisible** au lieu d'un binaire que personne ne peut relire.

Le signe : un croissant de lune avec trois arcs quittant son bord ouvert. La lune dit la nuit, les arcs disent le son. Pas d'étoiles — toutes les apps de sommeil en ont —, pas de texte, et aucun dégradé assez fin pour disparaître à 40 points.

**La première version débordait du cadre.** Les arcs sortaient de la zone que le masque squircle d'iOS conserve, et auraient été rognés sur l'écran d'accueil. Les proportions ont été refaites pour que l'ensemble — lune plus arc le plus large — tienne dans 0,17…0,83 du canevas.

---

## 4. Le feed est servi depuis raw.githubusercontent

```
https://raw.githubusercontent.com/LeVraiLunatix/somna/main/altstore/apps.json
```

Pas de GitHub Pages, pas de branche `gh-pages`. **Une pièce mobile de moins**, et une de moins à pouvoir être mal configurée sans que personne s'en aperçoive avant qu'une installation échoue.

Les anciennes versions sont **conservées** plutôt que remplacées : AltStore permet d'installer une version antérieure, ce qui compte pour une bêta où une release peut se révéler pire que la précédente.

Le script est **idempotent** : relancer une release ne crée pas d'entrée en double. Les workflows se relancent, et un feed contenant deux fois la même version perturbe AltStore.

---

## 5. Le manifeste de confidentialité est court, et vérifié

Aucune collecte, aucun suivi, aucun domaine. Seulement trois API système avec leur code de motif : préférences utilisateur, horodatage de fichiers dans le conteneur de l'app, et espace disque.

**La CI vérifie qu'il est réellement dans le bundle**, pas seulement dans le dépôt. Une ressource qui échoue à être copiée reste invisible jusqu'à ce que quelqu'un inspecte un build livré — c'est-à-dire trop tard.

Si ce fichier acquiert un jour une entrée `NSPrivacyCollectedDataTypes`, quelque chose a changé dans la nature de l'app.

---

## 6. Le guide d'installation commence par les contraintes

`docs/INSTALLATION.md` ouvre sur ce à quoi un testeur s'engage, avant toute instruction :

- l'app expire au bout de **7 jours** ;
- **3 apps sideloadées** maximum ;
- l'Apple ID est saisi dans AltStore — avec la recommandation d'un **mot de passe d'application** plutôt que le vrai mot de passe ;
- **une expiration non rattrapée efface les nuits**, parce qu'une réinstallation recrée le conteneur.

Ce dernier point est le plus dur, et le plus facile à découvrir trop tard. Il est écrit en toutes lettres.

Le guide recommande **SideStore plutôt qu'AltStore Classic** : le rafraîchissement se fait depuis l'iPhone seul, sans ressortir un ordinateur toutes les semaines. C'est la friction qui fait abandonner les bêtas.

---

## 7. Ce que la répétition à vide a prouvé

| Étape | Résultat |
|---|---|
| SDK iOS 26 | présent |
| Projet généré, traductions vérifiées | OK |
| 259 tests | au vert |
| Archive appareil non signée | OK |
| IPA | `Somna-0.1.0.ipa`, 1 040 369 octets |
| `Info.plist` empaqueté | background mode, description micro, versions |
| Manifeste de confidentialité dans le bundle | présent |
| Publication de la Release | **sautée** |
| Mise à jour du feed | **sautée** |

Aucune release n'existe. Le feed contient toujours zéro version.

---

## 8. Pour publier, le jour venu

```bash
git tag v0.1.0
git push origin v0.1.0
```

Le workflow s'occupe du reste : build, tests, IPA, Release en pré-release, et commit du feed sur `main`.

Ce qu'il faut vérifier après : la Release apparaît, le feed contient une version, et l'URL de la source répond en JSON.

---

## 9. Ce qui reste hors de portée

- **Aucune signature.** L'IPA est non signé et le restera : AltStore le signe sur l'appareil avec le compte du testeur. C'est le seul modèle possible sans abonnement développeur.
- **Aucune capture d'écran dans le feed.** Elles demandent un appareil ou un simulateur lancé à la main ; à ajouter après la première vraie nuit, quand il y aura quelque chose de réel à montrer.
- **TestFlight n'est pas une option**, et ne le sera pas sans compte payant.

---

## 10. Checklist

- [x] Workflow de release déclenché uniquement par tag
- [x] Répétition à vide disponible et validée
- [x] Refus de publier si un test échoue
- [x] IPA non signé, conforme à ce qu'attend AltStore
- [x] Feed AltStore versionné, idempotent, sans GitHub Pages
- [x] Icône générée, trois variantes iOS 26, dans la zone sûre
- [x] Manifeste de confidentialité, présence vérifiée dans le bundle
- [x] Guide d'installation ouvrant sur les contraintes réelles
- [ ] **Release publiée** — en attente d'une décision
- [ ] Captures d'écran — après la première vraie nuit

---

**Prochaine étape : Phase 8** — validation accessibilité, Dynamic Type, VoiceOver, performances, et revue finale.
