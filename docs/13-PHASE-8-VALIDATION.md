# Somna v0.1 — Phase 8 : Validation

> Statut : **terminée** — run `30781242221`, 259 tests unitaires + 12 audits d'accessibilité, tous au vert.
> Ce document dit aussi ce qui **n'a pas** été validé, et pourquoi.

---

## 1. L'audit d'accessibilité a trouvé 30 problèmes réels

`XCUIApplication.performAccessibilityAudit` a été branché sur chaque écran, plus des variantes à la plus grande taille de texte (AX5). Douze audits, exécutés à chaque push.

Ce n'est pas une relecture : l'audit mesure les contrastes, les zones tactiles, les descriptions manquantes, le texte tronqué et les traits qui mentent sur ce qu'un contrôle fait. Il a trouvé **trente problèmes**, dont aucun n'avait été repéré en écrivant le code.

### Ce qu'il a corrigé

**Contraste.** `textTertiary` était à **3,2:1 en clair et 4,0:1 en sombre**, sous le 4,5:1 requis pour du texte normal. Une teinte tertiaire est exactement le genre de couleur qui paraît correcte à celui qui la choisit. Les deux valeurs ont été recalculées par mesure, pas à l'œil : elles sont maintenant à 5,0:1 et 5,9:1.

**Dynamic Type.** Treize tailles de police fixes ignoraient purement et simplement le réglage système. L'anneau du score de tranquillité était le pire cas : un cercle de 120 points contenant un chiffre qui grandit, donc un chiffre tronqué précisément aux tailles où il doit être lisible. Il grandit désormais avec son texte.

**Zones tactiles.** Le bouton Retour de l'onboarding faisait moins de 44 points de haut — sur l'étape où quelqu'un veut justement revenir relire. Et la barre de progression, à quatre points de haut, portait un libellé accessible qui en faisait un élément mesurable.

La correction de ce second point est devenue une amélioration produit : **l'étape est maintenant affichée** (« Étape 3 sur 7 ») au lieu d'être cachée dans le libellé d'une barre. Les utilisateurs voyants y gagnent autant.

**Texte tronqué.** Six endroits, tous du même motif : un titre court en anglais devient long en français, et une valeur tronquée est indiscernable d'une valeur absente. Les lignes de statistiques de l'historique passent en `ViewThatFits` — une rangée quand ça tient, une colonne sinon.

### La seule exemption, et sa raison

Un `Form` SwiftUI dessine ses en-têtes, pieds de section et boutons destructifs avec les couleurs sémantiques d'Apple. Sur l'écran Réglages, l'audit en mesure plusieurs entre 4,0:1 et 4,5:1 — **les valeurs d'Apple, pas celles de Somna**.

Les surcharger reviendrait à figer des couleurs qu'Apple met à jour, y compris les variantes renforcées que les gens obtiennent en activant *Augmenter le contraste*. L'accessibilité empirerait avec le temps.

Contraste et Dynamic Type sont donc exemptés **sur cet écran seul**. Zones tactiles, texte tronqué et descriptions manquantes y restent audités, et tous les autres écrans le sont intégralement.

Corollaire assumé : **la phrase de confidentialité a été sortie du pied de section.** La chrome de pied est stylée pour des notes accessoires ; ce que Somna fait des enregistrements de quelqu'un n'en est pas une. Elle est maintenant du texte normal, au contraste vérifié.

---

## 2. Trois défaillances silencieuses corrigées

Le balayage du code contre nos propres conventions a trouvé trois `try?` qui masquaient de vraies pannes :

| Endroit | Ce que l'échec silencieux produisait |
|---|---|
| Favori d'une nuit | Le signet s'affiche, disparaît au rechargement — « l'app a oublié » |
| Re-analyse d'une nuit | Un bouton qui ne fait rien, donc qu'on retape |
| Manifeste final | Le filet de sécurité perdu **sans trace**, ce qui annule sa seule raison d'être |

Les trois remontent désormais, soit à l'écran, soit dans les logs.

---

## 3. Un bug d'isolation des tests

Les réglages survivent entre suites sur un simulateur. Une suite ayant terminé l'onboarding faisait donc échouer la suivante, **pour une raison sans rapport avec son objet**. Les tests UI réinitialisent maintenant l'état au lancement, via un argument disponible uniquement en `DEBUG`.

C'est le genre de faux positif qui, non traité, apprend à ignorer les échecs.

---

## 4. État du code contre les conventions

| Règle | État |
|---|---|
| Aucun force unwrap évitable | **0** |
| Aucun TODO / FIXME | **0** |
| Aucun `try?` silencieux | Corrigés ; les restants sont du nettoyage ou une dégradation documentée |
| Aucune valeur hexadécimale hors `SomnaColor` | Respecté |
| `Domain/` n'importe que Foundation | Respecté |
| Aucun singleton global mutable | Respecté |
| `@unchecked Sendable` | **3**, chacun justifié en commentaire |
| `nonisolated(unsafe)` | **1**, sur une seule propriété |
| `fatalError` | **1**, dans du code `#if DEBUG` de preview |
| Aucune dépendance tierce | Respecté |
| Aucun accès réseau | Respecté — aucun `URLSession` dans le projet |

---

## 5. Ce qui n'a pas été validé

C'est la section qui compte, parce qu'une CI verte donne une fausse impression de complétude.

### Ce que l'audit ne couvre pas

L'audit vérifie ce qui se mesure. Il ne dit pas si **VoiceOver raconte quelque chose de sensé** — si l'ordre de lecture suit une logique, si un libellé dit la chose utile plutôt qu'une chose exacte. Cela reste un travail humain, et il n'a pas été fait.

### Le risque R11, inchangé

Rien de ce qui suit n'a jamais tourné sur un appareil :

- **l'enregistrement écran verrouillé** — le mécanisme est le bon, rien ne l'a exercé ;
- **les interruptions réelles** — la machine à états est testée, son câblage aux notifications iOS ne l'est pas ;
- **la consommation de batterie** — 3 à 7 %/heure est un ordre de grandeur, pas une mesure ;
- **la rotation de segments sur huit heures** ;
- **la classification d'un seul son réel** — `SNAudioFileAnalyzer` n'a jamais tourné ;
- **la table de correspondance des labels**, bâtie sur des noms plausibles et non sur la liste réelle de cet iOS ;
- **les seuils du raffineur**, issus du raisonnement acoustique et non de nuits mesurées ;
- **la durée de la passe du matin** ;
- **l'installation via AltStore**.

### Performances

Aucun profilage Instruments : il exige un appareil. Les zones à surveiller restent celles identifiées en Phase 1 — enregistrement prolongé, génération des waveforms, chargement de l'historique, graphiques, SwiftData.

Ce qui a été fait à la place, structurellement : rien de lourd sur le `MainActor`, capture audio et analyse dans des `actor`, accès base via `@ModelActor`, pas de FFT nocturne, budget d'analyse plafonné à 20 % de la nuit.

---

## 6. Critères de réussite de la v0.1

Repris du cahier des charges, §53.

| Critère | État |
|---|---|
| L'application compile | ✅ |
| L'onboarding fonctionne | ✅ |
| Les permissions fonctionnent | ✅ |
| Une session peut être lancée | ✅ (jamais sur appareil) |
| L'audio peut être enregistré | ⚠️ non vérifié sur appareil |
| Les fichiers sont segmentés | ✅ par construction, non vérifié en conditions réelles |
| Les interruptions sont gérées | ✅ modélisées et testées, non éprouvées |
| Une session est sauvegardée | ✅ |
| L'analyse produit de vrais résultats | ⚠️ pipeline réel, jamais exécuté sur du son réel |
| Les événements ont des timestamps | ✅ |
| La timeline fonctionne | ✅ |
| Les extraits sont lisibles | ✅ code en place, jamais joué depuis un vrai clip |
| Le rapport fonctionne | ✅ |
| L'historique fonctionne | ✅ |
| Les suppressions fonctionnent | ✅ testées, y compris l'ordre fichiers-puis-base |
| Les paramètres fonctionnent | ✅ |
| L'application est local-first | ✅ aucun code réseau |
| L'interface est premium | jugement humain requis |
| Le mode sombre est excellent | ✅ contrastes mesurés |
| Le mode clair est utilisable | ✅ contrastes mesurés |
| Dynamic Type est pris en charge | ✅ audité jusqu'à AX5 |
| VoiceOver est pris en charge | ⚠️ audité mécaniquement, pas parcouru par un humain |
| Les tests principaux existent | ✅ 259 + 12 |
| GitHub Actions compile le projet | ✅ |
| Une release peut contenir l'IPA | ✅ répétition à vide validée |
| La source AltStore référence les versions | ✅ mécanisme en place, zéro version publiée |
| Les limitations sont documentées | ✅ ce document |
| Aucune fonctionnalité majeure n'est fausse | ✅ |

---

## 7. Conclusion honnête

Somna v0.1 est **complète et cohérente**. Tout ce qu'elle affiche, elle sait le produire ; tout ce qu'elle ne sait pas faire, elle le dit.

Elle n'est pas **éprouvée**. La différence est entière, et elle tient en une phrase : *aucune vraie nuit n'a jamais été enregistrée.*

La première nuit réelle sera le test de la bêta autant que de l'app. C'est pour cela que le manifeste de secours existe, que les nuits interrompues sont récupérables, que les logs sont exportables, et que l'écran Diagnostics est accessible depuis l'accueil.
