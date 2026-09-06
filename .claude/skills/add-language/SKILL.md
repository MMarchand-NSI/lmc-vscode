---
name: add-language
description: Ajouter une langue d'interface à l'extension LMC (panneau de l'émulateur, réglage lmc.locale, phrases de l'hôte). À utiliser quand on demande de traduire l'extension dans une nouvelle langue, ou après qu'une langue est apparue dans lmc_lsp. Ne couvre pas la traduction des diagnostics, qui vit dans lmc_lsp.
---

# Ajouter une langue

Huit points, dont quatre que le compilateur ou un contrôle réclamera de
lui-même. Suivre l'ordre : le premier point est un prérequis, pas une étape.

Dans ce qui suit, `xx` est l'étiquette BCP 47 primaire (`it`, `de`, `pt`…).

## 0. Prérequis : le serveur doit connaître la langue

`webview/text/locale.gleam` **ne définit pas** le type `Locale`, il importe
celui de `lmc_lsp` (`lmc/text/locale`). Tant que ce dépôt-là ne connaît pas
`xx` :

- `from_tag("xx")` rend la langue par défaut, donc le réglage ne fait rien ;
- aucun bras `server.Xx` ne peut être écrit ici, le type n'a pas la variante.

Vérifier :

```sh
grep '"xx" ->' build/packages/lmc_lsp/src/lmc/text/locale.gleam
```

Si rien ne sort, **s'arrêter** : la langue s'ajoute d'abord dans `lmc_lsp`
(une variante, un bras dans `render`, un bras dans `from_tag`, un fichier
`xx.gleam`), puis une release, puis le `ref` de `gleam.toml` ici. Ne pas
contourner en dupliquant un type `Locale` local : le panneau et les
diagnostics répondraient différemment au même réglage.

## 1. Le fichier de langue du panneau

Copier `src/webview/text/english.gleam` vers `src/webview/text/xx.gleam` et
traduire. Deux fonctions publiques, `render(Text)` et `label(Label)`, rien
d'autre.

**Ce qui ne se traduit pas**, et que la copie ne doit pas toucher :

- les mnémoniques et les noms de registres (`LDA`, `ACC`, `SI`…) ;
- `Fetch`, `Decode`, `Execute` — les termes du cours, tels quels partout ;
- les jetons d'état (`empty`, `running`, `waiting_input`, `halted`,
  `error`) : `app_ffi.mjs` teste `state.status === "running"`, les traduire
  casse les boutons. Les infobulles les **citent**, elles ne les traduisent
  pas ;
- `message.shortcut` et `message.three_cells` : des faits (mots machine,
  adresses), écrits une seule fois dans `message.gleam` pour que deux langues
  ne divergent pas dessus. Les appeler, ne pas les recopier.

**Le vocabulaire suit celui du serveur.** Le lire, ne pas l'inventer :

```sh
grep -oE '"[^"]{8,}"' build/packages/lmc_lsp/src/lmc/text/xx.gleam | head -40
```

Deux traductions du même terme feraient lire deux machines différentes à un
élève.

## 2. La répartition

`src/webview/text/locale.gleam` : un bras dans `render`, un dans `label`, un
dans `phase_label`, un dans `tag`. Le compilateur les réclame tous les
quatre, c'est tout l'intérêt du découpage.

## 3. Les phrases que l'hôte prononce lui-même

`vscode-extension/webviewPanel.ts`, table `hostText` : trois entrées, le
titre de l'onglet, la notification d'assemblage, l'avertissement « ouvre
d'abord un fichier .lmc ». Elles ne peuvent pas venir du catalogue Gleam (une
notification VS Code et un titre d'onglet ne passent pas par le rendu du
webview).

Citer la commande sous son nom réel, `LMC: Open Emulator`, dans toutes les
langues : les chaînes du manifeste ne suivent pas `lmc.locale` et sont en
anglais pour cette raison. Traduire la citation enverrait chercher une entrée
qui n'existe pas.

Cet oubli est déjà arrivé : l'espagnol est arrivé, la table est restée à deux
langues, et un réglage `es` donnait un panneau espagnol avec un titre
d'onglet français. D'où le contrôle du point 6.

## 4. Le réglage

`vscode-extension/package.json`, `contributes.configuration` : ajouter `xx`
à `enum` **et** sa description à `enumDescriptions` (même ordre, `auto` reste
en dernier). Sans ça, la langue existe mais personne ne peut la choisir.

## 5. Les tests

`test/webview_text_test.gleam` : ajouter `server.Xx` à la liste `languages`.
Les trois tests qui bouclent dessus couvrent alors la nouvelle langue sans
être touchés — chaque message se rend non vide, chaque étiquette est
remplie, chaque langue a son étiquette BCP 47 distincte.

`scripts/smoke-webview.mjs`, section « La langue du panneau » : au moins une
vérification dans le DOM, sur le modèle de celles de l'espagnol, du japonais
et du coréen.

## 6. Vérifier, en exécutant

```sh
gleam format src test && gleam test          # dont les tests par langue
node scripts/check-manifest.mjs              # réglage et hostText contre le serveur
node scripts/build-webview.mjs && node scripts/smoke-webview.mjs
```

`check-manifest.mjs` est celui qui attrape les oublis des points 3 et 4 : il
lit les étiquettes que `from_tag` reconnaît **dans `locale.gleam` du
serveur** et exige que le réglage et `hostText` couvrent exactement
celles-là.

Puis **casser pour vérifier le filet**, comme partout ici : retirer la langue
de `hostText`, constater l'échec et le code de sortie 1, remettre.

## 7. Ne pas confondre défaut et repli

`webview/text/locale.gleam` expose les deux, et ils ne coïncident pas :

- `default_locale` (français) est ce que le panneau peint à sa toute première
  image, avant que l'hôte n'ait parlé, parce que c'est ce que `lmc.locale`
  enverra une milliseconde plus tard ;
- `fallback_locale` (anglais, celui du serveur) répond « je ne parle pas ce
  que tu demandes ».

Ajouter une langue ne change ni l'un ni l'autre.

## 8. Dire ce qui reste

Deux choses ne suivent pas le réglage, et il vaut mieux l'écrire que le
laisser découvrir :

- **les chaînes du manifeste** — nom de l'extension, description, titre de la
  commande, description du réglage. VS Code ne localise `package.json` que
  par `package.nls.json`, indexé sur *sa* langue d'affichage, ce que
  `lmc.locale` sert justement à ne plus suivre. Ne pouvant être que d'une
  seule langue, elles sont en **anglais** : une chaîne qui ne peut pas suivre
  son lecteur doit porter le plus loin. Ne pas les traduire en ajoutant une
  langue ;
- **les 26 exemples et la référence du langage**, en français.

Si personne qui lise `xx` n'a relu la traduction, le dire dans l'en-tête du
fichier `xx.gleam`, dans le commit, et sur la page Marketplace. Le critère
n'est pas qui a écrit la traduction — tout a été écrit ici — mais **qui peut
repérer une faute** : une tournure bancale en français ou en anglais se
corrige dans le flux de travail, la même en japonais n'est vue par personne.
Pour un support de cours, ça compte.
