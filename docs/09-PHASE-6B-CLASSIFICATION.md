# Somna v0.1 — Phase 6B : Classification et passe du matin

> Statut : **livrée, CI verte** — run `30773984615`, 227 tests, IPA `0.1.0 (23)`.
> La boucle est fermée : enregistrer une nuit produit un rapport.

---

## 1. Aucun modèle propriétaire

Somna n'embarque pas de modèle. `SNClassifySoundRequest(.version1)` couvre plusieurs centaines de classes — ronflement, toux, parole, portes, pluie, animaux —, tourne sur le Neural Engine, et ne quitte jamais l'appareil.

Entraîner un classifieur moins bon pour se l'approprier aurait été de la vanité. Le travail utile est ailleurs : décider **quoi** lui donner à écouter, et **quand le contredire**.

---

## 2. Le mapping des labels se fait par sous-chaîne

Le jeu de labels d'Apple **n'est pas un contrat publié**. Les noms diffèrent entre versions d'iOS : `door` ici, `door_open_or_close` là.

Une correspondance exacte ferait qu'une mise à jour mineure d'iOS **arrêterait silencieusement de détecter les portes** — une régression que personne ne verrait avant qu'un utilisateur demande pourquoi sa porte n'apparaît plus.

Trois protections :

- correspondance par sous-chaîne, règles ordonnées du spécifique au général (`alarm_clock` avant `clock`, `snoring` avant `breathing`) ;
- tout label non reconnu devient `.unknown`, jamais une supposition ;
- au démarrage de l'analyse, la liste réelle du classifieur est confrontée à ce dont Somna dépend, et **les classes manquantes sont journalisées**. Une classe disparue est ainsi découverte explicitement, au lieu d'être déduite d'une nuit qui n'a mystérieusement trouvé aucun ronflement.

Les labels non mappés mais détectés avec confiance sont journalisés, pour enrichir la table depuis de vraies nuits plutôt que depuis des suppositions.

---

## 3. Le raffineur n'invente jamais

Le classifieur propose, les règles arbitrent. **Chaque règle ne peut que baisser la confiance ou rendre un libellé plus vague.** Aucune ne crée une détection que le modèle n'a pas faite — c'est un invariant testé sur tous les cas de règle.

La règle qui compte le plus :

> Un ronflement **sans rythme respiratoire** redevient un bruit constant.

Un classifieur généraliste, entraîné sur de l'audio diurne, étiquette volontiers un ventilateur comme un ronflement. Sans cette règle, Somna rapporterait le ventilateur de quelqu'un comme un ronflement **toutes les nuits**, et ce serait le genre d'erreur qui détruit la confiance dans tout le reste du rapport.

La périodicité se mesure par autocorrélation de l'enveloppe RMS **déjà écrite pendant la nuit** — donc sans FFT, cohérent avec l'écart assumé en Phase 5.

Deux autres : une salve trop brève pour être de la parole devient un bruit de draps ; un transitoire court, clair et faible non classifié devient un « mouvement audible probable », avec la formulation nuancée que la table de phrasing impose de toute façon.

---

## 4. Le silence n'a pas besoin de classifieur

Une nuit calme est surtout du silence. Faire tourner un classifieur sur huit heures de silence dépenserait plusieurs minutes du matin de quelqu'un pour conclure qu'il ne s'est rien passé.

`CandidateSelector` lit les métriques nocturnes et ne retient que les quelques pourcents où quelque chose s'est produit. **Les segments sans aucune zone candidate ne sont pas classifiés du tout.**

Deux garde-fous :

- **Seuil adaptatif** — multiplicatif sur le plancher mesuré, donc une pièce bruyante exige un saut plus grand, une pièce silencieuse moins.
- **Budget plafonné à 20 % de la nuit.** Sans lui, une nuit avec un ventilateur marquerait tout comme candidat et la passe du matin durerait aussi longtemps que la nuit. Au-delà du budget, les zones les plus fortes gagnent — ce sont celles qu'un humain aurait remarquées aussi.

Le plancher de bruit est estimé par un **percentile bas**, pas une moyenne : une moyenne serait tirée vers le haut par les événements mêmes qu'elle doit rendre détectables, donc une nuit bruyante relèverait son propre seuil et cacherait ce qui s'y est passé.

---

## 5. Le bug que le test a trouvé

Le test « un bourdonnement stable n'a pas de rythme » a échoué avec un score de **0,95**.

Cause : un son parfaitement stable ne laisse que du **bruit d'arrondi** après soustraction de la moyenne — et le bruit d'arrondi s'autocorrèle presque parfaitement.

La mesure rapportait donc un ventilateur comme **fortement rythmique**. Exactement l'inverse de ce que cette fonction existe pour faire, puisque le raffineur s'en sert pour distinguer un ventilateur d'un ronflement. Sans ce test, la règle de §3 aurait été inopérante précisément dans le cas qu'elle vise.

Correction : un rythme exige que le niveau varie vraiment — plancher d'amplitude absolu et relatif avant tout calcul.

---

## 6. Dégradation plutôt qu'échec

| Situation | Conséquence |
|---|---|
| Un segment illisible | Ce segment est sauté, les autres sont analysés |
| Le classifieur ne se charge pas | La classification est perdue, l'enregistrement est conservé |
| Un extrait n'a pas pu être coupé | Cette ligne perd son audio, la nuit est intacte |
| L'analyse échoue entièrement | La nuit repasse en `awaitingAnalysis`, **jamais** en `failed` |

Ce dernier point est délibéré : `failed` se lirait « cette nuit est perdue » pour une nuit qui ne l'est pas. L'audio est intact et l'analyse est rejouable.

Une nuit trop courte n'est pas une erreur non plus : trois minutes sont une chose légitime à avoir enregistrée. Elles ne peuvent simplement pas soutenir un rapport, et le dire est le résultat honnête.

---

## 7. Quand l'analyse tourne

**Immédiatement après la nuit**, pas plus tard. Le téléphone est réveillé et généralement en charge à cet instant précis — c'est le moment le moins cher où ce travail pourra jamais être fait.

L'écran de session affiche la progression, puis le résumé.

---

## 8. Fichiers livrés

```
Somna/Services/Analysis/  CandidateSelector.swift (+ EnvelopePeriodicity),
                          ClassificationMapping.swift, RuleBasedRefiner.swift,
                          SoundAnalysisClassifier.swift, ClipExtractor.swift,
                          NightAnalysisEngine.swift
Somna/Core/Errors/        AnalysisError.swift
Somna/Domain/UseCases/    AnalyzeNightUseCase.swift

SomnaTests/Unit/          ClassificationTests.swift
```

---

## 9. Ce que cette phase ne prouve pas

- **Aucun son réel n'a été classifié.** Les tests utilisent un classifieur scripté ; `SNAudioFileAnalyzer` n'a jamais tourné.
- **La table de mapping est bâtie sur des noms de classes plausibles**, pas sur la liste réelle de cet iOS. C'est exactement pourquoi le mapping est tolérant et pourquoi les classes manquantes sont journalisées.
- **Les seuils du raffineur ne sont calibrés sur rien.** Ils viennent du raisonnement acoustique, pas de nuits mesurées. Ils bougeront.
- **La durée réelle de la passe du matin est inconnue.** L'objectif de moins de trois minutes pour huit heures reste une estimation.

Le risque **R11** reste dominant, et il est maintenant le seul qui sépare Somna d'une bêta.

---

## 10. Checklist

- [x] Classification par le modèle embarqué d'Apple, hors ligne
- [x] Mapping tolérant aux variations de nommage, classes manquantes signalées
- [x] Aucune règle ne peut créer une détection — invariant testé
- [x] Ronflement sans rythme rétrogradé
- [x] Segments silencieux non classifiés, budget d'analyse plafonné
- [x] Plancher de bruit par percentile, pas par moyenne
- [x] Extraits audio adossés à chaque événement
- [x] Dégradation à chaque étape, jamais d'abandon de nuit
- [x] Analyse déclenchée juste après la session, avec progression
- [x] 227 tests au vert
- [ ] **Un seul son réel classifié** — appareil physique requis

---

**Prochaine étape : Phase 4B** — rapport de nuit, timeline et lecteur audio, pour afficher ce que cette phase produit.
