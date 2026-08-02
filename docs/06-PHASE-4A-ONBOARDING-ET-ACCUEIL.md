# Somna v0.1 — Phase 4A : Onboarding, accueil et localisation

> Première tranche de l'interface. Suite de [05-PHASE-3B-DESIGN-ET-SERVICES.md](05-PHASE-3B-DESIGN-ET-SERVICES.md).
> Statut : **livrée, CI verte** — run `30767435499`, 102 tests, IPA `0.1.0 (13)`.

---

## 1. Écart assumé par rapport au découpage annoncé

J'avais annoncé « barre d'onglets réelle » en 4A. Retiré : Historique, Tendances et Réglages arrivent en 4C, la barre aurait donc eu trois onglets vides — exactement les impasses que la Phase 3B s'était interdites. La 4A garde une pile de navigation unique. La barre arrivera avec les écrans qui la remplissent.

---

## 2. La calibration est réelle

Le cahier des charges interdit de simuler une fonctionnalité. La calibration mesure donc vraiment la pièce, via `AVAudioEngine`.

**`AVAudioSession` en mode `.measurement`.** C'est le détail qui décide si la mesure vaut quelque chose : ce mode désactive la chaîne de traitement d'entrée d'iOS — gain automatique, réduction de bruit. Avec l'AGC actif, une pièce silencieuse et une pièce bruyante se mesurent toutes deux « moyennes », le plancher de bruit devient arbitraire, et **tous les niveaux qui en dérivent deviennent une fiction**.

**Capture et jugement sont séparés.** `CalibrationService` capture ; `PlacementQualityEvaluator` est pur et juge. Conséquence pratique : la logique se teste exhaustivement sans micro, ce qui compte parce que le runner CI n'a aucune entrée audio.

**Bénéfice secondaire :** c'est la première brique audio du projet, et elle exerce exactement ce dont la Phase 5 dépendra — catégorie de session, tap d'entrée, calcul de niveau vDSP — sur une tâche de quinze secondes plutôt que sur une de huit heures. Un micro qui refuse de s'ouvrir coûte beaucoup moins cher à découvrir ici.

### Le silence total n'est pas l'excellence

Le mode de défaillance le plus dangereux de cet évaluateur, et le test qui le verrouille :

> Un micro couvert, ou une entrée qui ne délivre rien, mesure un **silence parfait**. Le noter « excellent » enverrait quelqu'un se coucher rassuré, pour se réveiller devant une timeline vide — qui ressemble exactement à une nuit calme.

`peak < 0,001` sur toute la fenêtre est donc rapporté comme `.noInput`, jamais comme une chambre remarquablement silencieuse.

**Médiane plutôt que moyenne**, et **écart interquartile plutôt qu'écart-type** : une porte qui claque une fois pendant la calibration ne doit pas condamner une bonne chambre.

---

## 3. L'onboarding

Sept étapes. Deux choix de séquence qui ne sont pas cosmétiques :

**Les explications précèdent la demande de permission.** iOS n'accorde qu'une invite par permission et par installation. La dépenser avant que quelqu'un comprenne ce que fait Somna, c'est ainsi que les apps d'enregistrement finissent définitivement refusées par des gens qui auraient dit oui.

**Un refus ne bloque pas.** Seule l'étape micro peut retenir, et seulement tant que la réponse est inconnue. Refuser laisse continuer : Somna explique ce qui ne fonctionnera pas et reste utilisable pour relire d'anciennes nuits. Enfermer quelqu'un dans l'onboarding à cause d'une permission qu'il a déclinée est hostile.

L'étape 3, « ce que Somna peut et ne peut pas faire », arrive **avant** la demande de micro. C'est délibéré : toute affirmation ultérieure de l'app n'est crédible que si les limites ont été posées d'abord, et il faut pouvoir décliner en connaissance de cause. Elle contient aussi la mise en garde la plus importante du produit :

> « Si tu partages ta chambre, Somna ne peut pas savoir qui a fait un son. Elle dira “ronflement détecté”, jamais “tu as ronflé”. »

La calibration est **sautable**. Quelqu'un qui ouvre Somna dans un salon bruyant doit pouvoir atteindre l'app ; la mesure se refait depuis les Réglages.

---

## 4. L'accueil

Trois présentations choisies par **ce qui s'est passé**, pas par un mode que l'utilisateur devrait comprendre : première nuit, nuit récente (fenêtre de 18 h), ou repos avec la dernière nuit en rappel.

Les nuits interrompues sont remontées **en premier** : leur audio est encore sur le disque, et ne rien en dire le perdrait silencieusement.

Le bouton d'enregistrement n'existe pas encore — la Phase 5 le fournira. À la place, une carte dit franchement que le moteur audio arrive à la version suivante. Un bouton qui ne fait rien en silence est pire qu'un bouton qui explique pourquoi.

---

## 5. Localisation : 168 clés, deux langues

Deux sources, chacune faisant autorité sur une seule chose :

- **L'anglais vient du code source.** Chaque `String(localized:defaultValue:)` porte son texte, donc le code ne peut pas diverger du catalogue.
- **Le français vient de `scripts/i18n/fr.json`.**

`scripts/generate-strings.py` fusionne les deux et **échoue si une clé n'a pas de traduction française**. La CI l'exécute en mode `--check` : un écran ajouté sans traduction fait échouer le build au lieu d'être découvert par un testeur.

Trois familles de clés sont construites à l'exécution — phrasing d'événement, conseil de calibration, salutation selon l'heure — et ne peuvent pas être extraites par Xcode. Elles passent par `String.localized(dynamicKey:fallback:)` et sont déclarées explicitement dans le JSON.

### La lacune de la Phase 3A est comblée

`VocabularyTests` ne couvrait que l'anglais, faute de français existant. **Une promesse tenue dans une langue et pas dans l'autre n'est pas une promesse** — et la plupart des testeurs liront le français.

`LocalizationTests` vérifie désormais que :

- `fr.lproj` est réellement présent dans le bundle compilé (sinon la version partirait en anglais seul, en silence) ;
- aucun libellé français n'emploie de vocabulaire clinique ;
- les étiquettes de mouvement restent nuancées en français — « Mouvement audible probable » est la limite, « tu as bougé » est ce qu'elles ne doivent jamais devenir ;
- les trois niveaux de confiance se lisent différemment en français aussi.

---

## 6. Un point de friction rencontré

`String(localized:defaultValue:)` exige une clé `StaticString`, pour que Xcode puisse l'extraire à la compilation. Les trois endroits où la clé est calculée à l'exécution ne compilaient donc pas. Ils passent maintenant par un helper unique, `String.localized(dynamicKey:fallback:)`, documenté avec son compromis : l'extraction ne les voit pas, donc leurs entrées sont générées depuis les mêmes tables sources.

---

## 7. Fichiers livrés

```
Somna/Domain/Analysis/      PlacementQualityEvaluator.swift
Somna/Services/Calibration/ CalibrationService.swift
Somna/Core/Errors/          AudioError.swift
Somna/Core/Extensions/      String+Localization.swift

Somna/Features/Onboarding/  Stores/OnboardingStore.swift
                            Views/OnboardingView.swift, OnboardingSteps.swift
Somna/Features/Home/        HomeStore.swift, HomeView.swift
Somna/App/                  RootView.swift (branchement onboarding)

Somna/Resources/            Localizable.xcstrings (généré, 168 clés)
scripts/                    generate-strings.py, i18n/fr.json

SomnaTests/Unit/            CalibrationTests.swift, LocalizationTests.swift
SomnaUITests/               LaunchSmokeTests.swift (parcours d'onboarding)
```

---

## 8. Checklist de validation

- [x] Calibration réelle, non simulée, en mode `.measurement`
- [x] Logique d'évaluation pure et testée sans micro
- [x] Silence total rapporté comme absence de signal, jamais comme excellence
- [x] Permission demandée après les explications
- [x] Un refus ne bloque jamais l'onboarding
- [x] Calibration sautable, refaisable depuis les Réglages
- [x] Accueil contextuel, trois présentations
- [x] Nuits interrompues remontées en priorité
- [x] Aucun bouton mort — l'absence d'enregistrement est expliquée
- [x] 168 clés localisées FR/EN, complétude vérifiée en CI
- [x] `fr.lproj` réellement présent dans le bundle, vérifié par test
- [x] Invariant de vocabulaire étendu au français
- [x] 102 tests au vert, IPA produit
- [ ] Dynamic Type AX5 et VoiceOver — vérifiés en Phase 8, pas encore audités écran par écran

---

**Prochaine étape : Phase 5 — moteur audio**, ou **Phase 4B** (rapport, timeline, lecteur). La 4B n'a rien de réel à afficher tant qu'aucune nuit n'existe ; la 5 produit ces nuits. L'ordre 5 puis 4B est probablement le bon.
