# Somna v0.1 — Phase 4C : Historique, tendances, réglages

> Statut : **livrée, CI verte** — run `30776584319`, 259 tests, IPA `0.1.0 (28)`.
> **L'interface de la v0.1 est complète.** Il ne reste que la distribution et la validation.

---

## 1. L'ordre de suppression est toute la conception

Les fichiers d'abord, la base ensuite. Toujours, partout — `StorageService`, `HistoryStore`, `DeleteNightUseCase`.

L'ordre inverse laisserait de l'audio que **rien ne référence** : de l'espace consommé, inaccessible depuis tous les écrans, introuvable pour l'utilisateur et invisible dans les réglages. Un échec à mi-chemin dans le bon ordre laisse des orphelins que la récupération au lancement nettoie ; à mi-chemin dans l'ordre inverse, plus rien ne pourrait les retrouver.

C'est le seul domaine de l'app où un bug est **irrattrapable pour l'utilisateur**, d'où huit tests qui vérifient deux propriétés : rien ne survit qui ne devrait pas, rien n'est orphelin sans pouvoir être retrouvé.

### Deux règles de rétention

**Une nuit non analysée n'est jamais purgée.** Jeter l'audio brut d'une nuit que personne n'a encore regardée détruirait la seule copie de quelque chose que l'utilisateur n'a pas vu.

**Les extraits survivent toujours à la rétention.** Ce sont eux qui rendent chaque détection vérifiable ; les perdre transformerait un rapport contrôlable en rapport à croire sur parole.

---

## 2. Le consentement cloud est affiché mais non commutable

Il apparaît dans Confidentialité avec la mention « Pas dans cette version ».

La v0.1 n'a **aucun code réseau**. Offrir l'interrupteur serait mentir sur ce que l'app peut faire. Le laisser visible enregistre en revanche le choix comme opt-in dès la première version, plutôt que de le rétro-ajouter le jour où il servirait — moment où l'ajout ressemblerait à un changement de politique.

---

## 3. Les tendances refusent de s'afficher sous cinq nuits

Tracer une ligne entre deux points et l'appeler une direction est **la façon la plus courante dont une app de bien-être induit en erreur**. Somna refuse et explique pourquoi, dans le vide même :

> « Une ligne entre deux points n'est pas une tendance, et la tracer dirait plus que les données ne permettent. »

Trois autres décisions :

- **Seules les nuits complètes sont tracées.** Une nuit interrompue a des chiffres partiels ; à côté de nuits complètes, elle montrerait un creux qui parle de l'enregistrement, pas de la nuit.
- **La moyenne est dessinée, pas seulement énoncée.** Une nuit inhabituelle est alors visiblement une aberration au lieu de ressembler à un changement.
- **Chaque graphique explique ce qu'il représente.** Un graphique que personne ne peut interpréter est de la décoration, et de la décoration sur la santé de quelqu'un est pire que rien.

Le graphique de couverture existe pour la même raison que la section qualité du rapport : une baisse y signale des interruptions, et rend les autres chiffres de cette nuit moins fiables.

---

## 4. La barre d'onglets, enfin

Elle arrive maintenant que ses quatre sections existent. La liste est **énumérée à la main** plutôt que dérivée de `allCases`, et un test vérifie que chaque entrée a un écran derrière elle.

La raison : le tab bar est le seul endroit d'une app où une impasse est **visible en permanence**. Un écran vide au fond d'une pile se rencontre rarement ; un onglet vide se regarde toute la journée.

---

## 5. L'export ne partage jamais un enregistrement entier

Diffuser huit heures d'une chambre engage aussi **les autres personnes présentes**. Ce n'est pas une décision à prendre à la légère depuis une feuille de partage. Sont exportables : le rapport, les données d'événements, et les extraits choisis un par un.

L'export JSON embarque **la supposition du modèle à côté de la valeur corrigée** : qui analyse un export mérite de voir où l'app s'est trompée.

L'avertissement non médical **voyage avec le texte exporté**. Un résumé sorti de l'app perd tout le contexte que le rapport lui donnait, et « ronflements détectés pendant 40 minutes » lu à froid dans un message invite exactement la lecture médicale que Somna refuse de soutenir.

---

## 6. L'écran Premium n'affiche ni prix ni bouton

Un tunnel d'achat désactivé qui a l'air réel est un dark pattern ; un faux prix est une promesse. L'écran dit ce qui pourrait venir, demande aux testeurs ce qu'ils utiliseraient vraiment, et pose une limite explicite :

> « L'enregistrement, l'analyse, les rapports et la suppression resteront gratuits. Rien de ce qui fonctionne aujourd'hui ne passera derrière un paiement. »

---

## 7. Fichiers livrés

```
Somna/Services/Storage/       StorageService.swift
Somna/Services/Notifications/ NotificationService.swift
Somna/Services/Export/        ExportService.swift
Somna/Features/Settings/      SettingsStore.swift, SettingsView.swift
Somna/Features/History/       HistoryView.swift (+ HistoryStore, HistoryRow)
Somna/Features/Trends/        TrendsView.swift (+ TrendsStore)
Somna/Features/Premium/       PremiumView.swift
Somna/App/                    RootView.swift (barre d'onglets), AppRouter.swift

SomnaTests/Integration/       StorageTests.swift
```

393 clés localisées FR/EN.

---

## 8. Checklist

- [x] Sept sections de réglages, toutes fonctionnelles
- [x] Suppression totale et suppression de l'audio brut, avec confirmation nommant ce qui part
- [x] Rétention 7/30/90/illimité/extraits seuls, applicable immédiatement
- [x] Une nuit non analysée n'est jamais purgée
- [x] Notifications locales, ton non culpabilisant, aucun son le soir
- [x] Historique avec recherche structurée, favoris, suppression
- [x] Tendances refusant de s'afficher sans données suffisantes
- [x] Export JSON / CSV / texte, jamais l'enregistrement entier
- [x] Premium en vitrine, sans achat possible
- [x] Barre d'onglets sans impasse, vérifiée par test
- [x] 259 tests au vert
- [ ] Vue calendrier de l'historique — reportée, la liste filtrable couvre le besoin en v0.1

---

**Prochaine étape : Phase 7** — GitHub Release, IPA publié, source AltStore, guide d'installation. Puis Phase 8, validation.
