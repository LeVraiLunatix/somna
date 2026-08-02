# Somna v0.1 — Phase 6A : Algorithmes d'analyse

> Statut : **livrée, CI verte** — run `30772807900`, 201 tests, IPA `0.1.0 (20)`.
> Première moitié de la Phase 6 : tout ce qui est pur et vérifiable en CI. La 6B branche SoundAnalysis et l'extraction d'extraits.

---

## 1. Le résumé ne peut pas inventer

C'est la pièce centrale. Le résumé est le seul endroit de Somna qui produit de la prose sur la nuit de quelqu'un ; c'est donc le seul endroit qui pourrait en inventer une.

**Mécanisme.** `TemplateSummaryGenerator` ne reçoit que `SummaryFacts` — pas les événements, pas la session. Il ne peut pas écrire une phrase : il ne peut que choisir un cas de `SummaryStatement` et le remplir avec des valeurs prises dans ces faits. **Il n'existe aucun chemin de code entre le générateur et du texte libre.**

Ajouter une affirmation que les données ne soutiennent pas exigerait d'ajouter un cas d'enum : un changement visible en revue, pas une dérive de formulation.

Le test correspondant relit les nombres des énoncés produits et les compare aux faits d'entrée. Un `coughs(count:)` qui ne correspondrait pas à `facts.statistics.coughCount` fait échouer le build.

### Deux refus honnêtes

Un enregistrement inexploitable et une session trop courte **terminent** le résumé au lieu de le préfacer :

> « L'enregistrement est trop dégradé pour en tirer quoi que ce soit. Cela ne dit rien de ta nuit — seulement de l'audio. »

Cette distinction est testée explicitement. Sans elle, un micro sous un oreiller se lit comme une mauvaise nuit.

Et une interruption n'est **jamais** omise : sans elle, chaque compte au-dessus devient silencieusement un sous-compte.

---

## 2. Des énoncés, pas de la prose

`NightSession` stocke `[SummaryStatement]`, plus une chaîne.

Stocker du texte rendu figerait la langue dans laquelle la nuit a été enregistrée. Les mots sont produits à l'affichage par `SummaryRenderer`, donc passer le téléphone en anglais relit correctement toutes les nuits passées.

Effet de bord utile : le domaine reste sans `Bundle`, donc testable sans lui.

Changement de schéma effectué sans plan de migration — **justifié uniquement parce que rien n'est encore publié.** Ce sera la dernière fois : dès la première release, toute évolution passera par une étape de migration.

---

## 3. Pluriels

Le générateur de catalogue gère maintenant les variations CLDR. Sans cela, Somna afficherait « 1 toux ont été détectées » — faux exactement les nuits où le compte est le plus petit, et donc le plus lu attentivement.

Quatre clés en bénéficient : `summary.coughs`, `summary.interrupted`, `summary.overallActive`, `status.hours`.

---

## 4. Le score de tranquillité

Formule volontairement simple et inspectable. Un score issu d'un modèle opaque serait impossible à expliquer à quelqu'un qui le conteste, et « pourquoi 61 ? » est une question à laquelle cette app doit pouvoir répondre.

Chaque facteur est **plafonné** : une nuit de ronflements intenses mais sans rien d'autre ne doit pas tomber à zéro, et un seul bruit fort ne doit pas effacer une nuit paisible. Le ronflement est compté à la durée, pas au nombre d'épisodes — dix ronflements brefs ne font pas une nuit bruyante — et il n'est pas compté deux fois dans la densité.

**Un audio inexploitable ne reçoit aucun score**, pas un score bas. Un chiffre lui donnerait une précision qu'il n'a pas, et un score bas se lirait « mauvaise nuit » au lieu de « mauvais enregistrement ».

---

## 5. Ce que la qualité d'enregistrement sépare

Un micro sous un oreiller et une chambre réellement silencieuse **se mesurent pareil en moyenne**. Ce qui les distingue, ce sont les **pics** : une vraie pièce en a — une voiture dehors, un craquement. Une nuit sans aucun pic n'était pas calme, elle était sourde.

L'assesseur peut opposer son veto au rapport entier. C'est délibéré : un rapport plein de statistiques tirées d'un audio inexploitable est la chose la plus dommageable que Somna puisse produire.

---

## 6. Ce que le run a révélé

Une trouvaille, encore une fois du côté du test et non du code.

Mon test d'estimation du réveil décrivait une nuit se terminant en silence et attendait une heure de réveil. L'estimateur refusait. **Il avait raison :** se réveiller sans bruit et attraper son téléphone ne laisse aucune trace acoustique. Donner l'instant où l'utilisateur a appuyé sur stop reviendrait à lui renvoyer son propre geste comme s'il s'agissait d'une découverte.

Le test décrit maintenant une vraie nuit — installation, long calme, activité matinale — et le cas du réveil silencieux est testé pour lui-même.

---

## 7. Autres invariants encodés

| Règle | Raison |
|---|---|
| Les trous de session ne se groupent jamais | Fusionner deux interruptions cacherait qu'il y en a eu deux |
| Un groupe prend la confiance de son membre le plus fort | Si un ronflement de la série était indubitable, la série était un ronflement |
| Un groupe garde l'extrait de son membre le plus fort | C'est celui qu'on veut écouter pour vérifier la classification |
| Une correction utilisateur regroupe l'événement avec ce qu'il a dit | La correction est la vérité, pas une annotation |
| Les trous de session ne comptent pas comme événements | Une nuit interrompue paraîtrait plus agitée qu'elle ne l'était |
| Un écart court n'est pas une période calme | Deux minutes entre deux ronflements ne sont pas du calme |
| Les égalités d'heure la plus active se résolvent de façon déterministe | Une statistique qui bouge entre deux exécutions n'est pas une statistique |
| Une fenêtre de ronflement n'est nommée que si elle est concentrée | « Entre 23 h 10 et 6 h 40 » est vrai et totalement inutile |

---

## 8. Fichiers livrés

```
Somna/Domain/Models/       NightStatistics.swift
Somna/Domain/Analysis/     EventGrouper.swift, CalmnessScoreCalculator.swift,
                           StatisticsCalculator.swift (+ SleepWindowEstimator),
                           RecordingQualityAssessor.swift
Somna/Domain/Analysis/Summary/  SummaryStatement.swift (+ SummaryFacts),
                                TemplateSummaryGenerator.swift
Somna/Features/NightReport/     SummaryRenderer.swift

SomnaTests/Unit/           AnalysisTests.swift, SummaryTests.swift
```

---

## 9. Checklist

- [x] Résumé structurellement incapable d'inventer un événement, testé
- [x] Refus honnêtes sur audio inexploitable et session trop courte
- [x] Interruptions jamais omises
- [x] Énoncés stockés, rendus à l'affichage, donc traduisibles rétroactivement
- [x] Pluriels FR/EN corrects
- [x] Score plafonné, déterministe, absent quand l'audio ne le supporte pas
- [x] Qualité distinguant chambre silencieuse et micro sourd
- [x] Groupement, statistiques, fenêtre de sommeil : invariants testés
- [x] 201 tests au vert
- [ ] Classification réelle — Phase 6B

---

**Prochaine étape : Phase 6B** — sélection des zones candidates depuis les métriques nocturnes, classification par SoundAnalysis, extraction des extraits, orchestration, et branchement de l'analyse après une session.
