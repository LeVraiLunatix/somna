# Somna v0.1 — Phase 5 : Moteur audio

> Statut : **livrée, CI verte** — run `30771586880`, 146 tests, IPA `0.1.0 (17)`.
> **Aucune de ses promesses centrales n'est vérifiée sur appareil.** Voir §7.

---

## 1. Ce que la phase ajoute

Une nuit peut être enregistrée : préparation, capture segmentée, gestion des interruptions, arrêt, et récupération au lancement suivant si l'app est morte en route.

Ce qui n'existe toujours pas : l'analyse. Une nuit produit de l'audio et des métriques, pas encore d'événements. C'est la Phase 6.

---

## 2. La machine à états, extraite en fonction pure

Aucun runner CI ne produit d'appel entrant, d'activation Siri ni de crash du démon média, et aucun simulateur ne reproduit huit heures en arrière-plan. La gestion des interruptions est pourtant la partie de Somna la plus susceptible de faire perdre une nuit.

Les règles ont donc été sorties du moteur, dans `RecordingStateMachine`, qui ne touche ni AVFoundation ni disque. Résultat : les scénarios impossibles à provoquer sont testés quand même — 20 tests couvrant interruption pendant le démarrage, reprise échouée puis réussie, réinitialisation du démon média pendant une reprise, notifications dupliquées, double arrêt.

### Trois décisions qu'elle encode

**Une reprise est tentée même quand iOS omet `shouldResume`.** Cet indice est routinièrement absent après les interruptions longues — un appel typiquement — alors même que la reprise fonctionnerait. Le respecter à la lettre abandonnerait des nuits récupérables. Le pire cas d'une tentative est un redémarrage qui échoue, ce qui est rattrapable.

**L'instant d'interruption est porté à travers l'état `resuming`.** Une reprise ratée retombe donc sur le trou d'origine plutôt que d'en inventer un nouveau. Un appel de vingt minutes affiché comme un instant ferait passer une nuit cassée pour intacte — exactement le malentendu que la timeline doit empêcher.

**Seul un arrêt volontaire produit une nuit prête à analyser.** Tout le reste devient `interrupted`, ce qui conserve l'audio et laisse le choix, plutôt que `failed` qui se lit « ta nuit est perdue ».

**Un événement inattendu est ignoré, pas traité comme une erreur.** Les notifications audio arrivent dans le désordre et en double ; échouer sur chacune terminerait des nuits qui allaient bien.

---

## 3. Écart assumé : pas de FFT nocturne

La Phase 1 prévoyait un centroïde spectral dans la passe temps réel. Retiré.

Une FFT par buffer pendant huit heures est la chose la plus coûteuse que cette app puisse faire la nuit, et la passe du matin dispose de l'audio complet — y calculer les spectres ne coûte rien de plus, pendant que le téléphone est réveillé et en charge. La passe nocturne garde RMS, crête et taux de passage par zéro : assez pour repérer les zones candidates, ce qui est tout ce qu'elle a à faire.

C'est cohérent avec la priorité que la Phase 1 énonçait elle-même — traitement nocturne léger, batterie préservée.

---

## 4. Ce qui protège une nuit

| Mécanisme | Ce qu'il empêche |
|---|---|
| Segments de 10 min, publiés par renommage atomique | Un crash coûte au pire 10 minutes, jamais la nuit |
| `.part` pendant l'écriture | Un fichier tronqué est détectable au lancement au lieu d'être analysé comme s'il était entier |
| `manifest.json` réécrit **après chaque segment** | Les situations à récupérer sont précisément celles où la fin n'arrive jamais |
| Ligne en base écrite **avant** le démarrage du moteur | Si l'app meurt entre les deux, on trouve une session sans audio, pas de l'audio sans session |
| Segment fermé dès l'interruption | Une interruption qui ne finit jamais laisse quand même un fichier lisible |
| Récupération au lancement | Une ligne bloquée en `recording` ressemble à une nuit encore en cours, indéfiniment |

---

## 5. Conversion de format

Le micro délivre ce que le matériel utilise — typiquement 48 kHz, souvent plusieurs canaux. Somna stocke 16 kHz mono. Sans conversion, `AVAudioFile.write(from:)` rejette le buffer et **la nuit n'enregistre rien**. `AudioFormatConverter` s'en charge, avec un point de vigilance encodé dans le code : le buffer d'entrée n'est offert qu'une seule fois au convertisseur, sinon l'audio serait dupliqué.

Le buffer traverse aussi une frontière d'isolation. Swift 6 refuse à juste titre qu'un `AVAudioPCMBuffer` le fasse. L'exception est encadrée au seul endroit où l'argument de propriété tient : une copie profonde créée dans le callback du tap et jamais réutilisée par lui, donc la propriété se déplace vraiment au lieu d'être partagée.

---

## 6. Préparation : ce qui bloque et ce qui conseille

Seuls **le micro et l'espace disque** bloquent. Batterie, mode économie d'énergie, calibration absente et placement **avertissent**.

Quelqu'un qui fait une sieste à 40 % de batterie fait un choix raisonnable ; refuser serait paternaliste. En revanche, sous 30 % débranché, un enregistrement de huit heures meurt vers 4 h du matin — assez tard pour qu'on croie la nuit enregistrée, assez tôt pour qu'elle ne le soit pas. C'est cette combinaison-là que l'avertissement vise.

L'écran de session dit aussi la seule chose contre laquelle iOS ne protège pas : **balayer Somna hors du sélecteur d'apps met définitivement fin à l'enregistrement.** C'est écrit là où la décision se prend, pas enterré dans les Réglages.

---

## 7. Ce que cette phase ne prouve pas

À dire franchement, parce que la CI verte peut donner une fausse impression :

- **L'enregistrement écran verrouillé n'a jamais tourné.** Le background mode `audio` est déclaré et le mécanisme est le bon, mais rien ne l'a exercé.
- **Aucune interruption réelle n'a eu lieu.** La machine à états est testée ; le câblage entre les notifications iOS et elle ne l'est pas.
- **La consommation de batterie est une estimation.** Les 3 à 7 %/heure viennent d'un ordre de grandeur, pas d'une mesure.
- **La rotation de segments sur huit heures n'a jamais tourné.** Elle est testée à l'unité, pas dans la durée.
- **Aucun fichier AAC produit par ce code n'a été relu.** L'encodage est configuré correctement sur le papier.

C'est le risque **R11** de la Phase 1, inchangé et désormais dominant : tout le reste du projet est vérifiable en CI, celui-ci ne l'est pas. **La première vraie nuit sera le test.**

---

## 8. Fichiers livrés

```
Somna/Services/Audio/Session/     AudioSessionController.swift
Somna/Services/Audio/Recording/   RecordingStateMachine.swift, RealtimeMetrics.swift,
                                  SegmentWriter.swift, AudioRecordingEngine.swift,
                                  StubAudioRecorder.swift
Somna/Services/Storage/           DevicePowerMonitor.swift
Somna/Data/FileSystem/            NightManifest.swift
Somna/Domain/Protocols/           AudioRecording.swift
Somna/Domain/UseCases/            NightSessionUseCases.swift
Somna/Features/Session/           Stores/SessionStore.swift, Views/SessionView.swift

SomnaTests/Unit/                  RecordingStateMachineTests.swift, ManifestTests.swift
SomnaTests/Integration/           SessionLifecycleTests.swift
```

---

## 9. Checklist

- [x] `AVAudioSession` configurée, background mode `audio` déclaré, aucun contournement
- [x] Segmentation 10 min, écriture atomique, `.part` détectable
- [x] Interruptions, reprise, réinitialisation du démon média : modélisées et testées
- [x] Manifeste réécrit après chaque segment
- [x] Récupération au lancement : nuits inachevées, orphelins, fichiers tronqués
- [x] Conversion de format vers 16 kHz mono
- [x] Métriques temps réel légères, sans FFT
- [x] Préparation distinguant blocage et conseil
- [x] 200 clés localisées FR/EN
- [x] 146 tests au vert
- [ ] **Enregistrement réel sur appareil physique** — non vérifiable en CI

---

**Prochaine étape : Phase 6 — moteur d'analyse**, ou un test sur appareil avant d'aller plus loin.
