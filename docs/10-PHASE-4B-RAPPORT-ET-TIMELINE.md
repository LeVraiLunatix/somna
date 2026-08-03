# Somna v0.1 — Phase 4B : Rapport, timeline et lecteur

> Statut : **livrée, CI verte** — run `30774617511`, 241 tests.
> Somna sait maintenant montrer ce qu'elle a trouvé.

---

## 1. Le lecteur est la pièce qui rend l'app vérifiable

Une ligne disant « toux probable » est une **affirmation**. L'extrait est la **preuve**. Tout le reste du produit repose sur cette possibilité de vérifier à l'oreille — sans elle, Somna demanderait une confiance qu'elle n'a pas gagnée.

**Il vit au niveau racine, pas par écran.** Comparer trois événements ne doit pas obliger à relancer l'audio à chaque défilement.

Détail assumé : `ClipPlayer` est tenu comme type concret et non derrière un protocole. Observation ne se propage pas à travers un existentiel, donc un protocole ici signifierait que le panneau ne se redessine jamais pendant la lecture. Son accès aux fichiers, lui, passe bien par `NightFileStoring`.

Les vitesses proposées sont **0,5× · 0,75× · 1×** — uniquement en dessous ou à la normale. Ralentir est ce qui rend un son faible identifiable ; c'est la seule raison d'offrir des vitesses ici, pas le survol.

`.playback` en catégorie de session, donc audible même en mode silencieux. Justifié parce que la lecture est toujours un geste délibéré : Somna ne joue jamais rien d'elle-même.

---

## 2. Le rapport place la qualité avant les chiffres

Si l'audio était mauvais, c'est **la première chose dont le lecteur a besoin**, parce que cela change la lecture de tout ce qui suit.

Et quand l'audio est **inexploitable, les statistiques ne sont pas affichées du tout**. Des nombres tirés d'un audio inexploitable sont pires qu'aucun nombre : ils ressemblent à des résultats.

Le score de tranquillité porte son avertissement **dans le composant lui-même**, pas dans l'écran qui l'utilise. Un nombre aussi visible sera lu comme un verdict si les mots à côté ne disent pas le contraire, et ces mots ne doivent pas pouvoir être oubliés par un futur appelant.

Les estimations d'endormissement et de réveil n'apparaissent que si l'estimateur en a produit — c'est-à-dire seulement quand les preuves acoustiques existaient.

---

## 3. Trois refus dans la timeline

**Les filtres qui ne renverraient rien ne sont pas proposés.** Une puce donnant une liste vide laisse croire que Somna a cherché des toux et n'en a pas trouvé, alors qu'elle n'a peut-être jamais cherché.

**Un événement sans extrait le dit** au lieu de le cacher. C'est un événement que l'utilisateur ne peut pas vérifier, et cela change la confiance à lui accorder.

**Une nuit sans rien détecté est un résultat, pas une absence** — et le texte dit qu'elle est ambiguë, plutôt que de féliciter quelqu'un pour une nuit calme qui était peut-être un micro sourd.

---

## 4. Les corrections

Une correction conserve la supposition du modèle, et la ligne est **marquée comme corrigée**. Deux raisons : l'utilisateur voit ce qu'il a changé, et une correction ne se fait jamais passer pour un modèle qui avait vu juste.

Elle ne recalcule pas les statistiques dans la foulée. Les chiffres bougeraient sous l'utilisateur sans explication ; ils seront recalculés à la prochaine analyse.

---

## 5. Liquid Glass, deuxième usage

Le panneau de lecture est la deuxième des six surfaces prévues. Il flotte au-dessus d'un contenu qui défile, c'est la seule chose à l'écran qui n'est pas la liste, et le matériau le dit. `somnaGlass` gère `Reduce Transparency`, donc le choix se dégrade au lieu de casser.

---

## 6. Fichiers livrés

```
Somna/Services/Audio/Playback/   ClipPlayer.swift
Somna/DesignSystem/Components/Waveform/  MiniWaveform.swift (+ CalmnessRing)
Somna/Features/AudioPlayer/      PlaybackPanel.swift
Somna/Features/Timeline/         TimelineStore.swift, TimelineView.swift (+ EventRow)
Somna/Features/NightReport/      NightReportView.swift (+ NightReportStore)

SomnaTests/Unit/                 TimelineTests.swift
```

270 clés localisées FR/EN.

---

## 7. Checklist

- [x] Lecture persistante entre les écrans
- [x] Extrait adossé à chaque événement, absence signalée
- [x] Vitesses de lecture pensées pour écouter de plus près
- [x] Qualité d'enregistrement avant les statistiques
- [x] Statistiques masquées quand l'audio est inexploitable
- [x] Avertissement du score porté par le composant
- [x] Filtres vides non proposés
- [x] Corrections conservant la supposition du modèle et marquées
- [x] Liquid Glass limité au panneau flottant, dégradant proprement
- [x] Cibles tactiles ≥ 44 pt, libellés VoiceOver sur tous les contrôles
- [x] 241 tests au vert
- [ ] Dynamic Type AX5 et VoiceOver audités écran par écran — Phase 8

---

**Prochaine étape : Phase 4C** — historique, tendances, réglages, et la barre d'onglets qui les relie.
