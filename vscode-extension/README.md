> **In English:** this is a teaching extension for **LMC**, an assembly language used in French
> high-school computer science (NSI). Everything it says — diagnostics, hover, the emulator panel,
> the example programs — is in French, on purpose. The language reference is
> [LANGAGE.md](https://github.com/MMarchand-NSI/lmc_lsp/blob/master/LANGAGE.md).

# LMC — assembleur pédagogique

Le langage d'assemblage **LMC** dans VS Code : de quoi écrire, comprendre et exécuter des programmes
pour une machine à cent cases mémoire, en cours.

Ce n'est pas le LMC d'origine. Le mot machine fait quatre chiffres, il y a cinq registres (`ACC`,
`SI`, `LR`, `SP`, `PC`) et dix-sept mnémoniques, dont `MOV`, les sous-programmes (`JSR`/`RET`), une
pile (`PSH`/`POP`) et un écran (`PLT`). Un programme écrit pour un émulateur LMC classique ne tourne
pas ici, et l'inverse est vrai aussi. La référence du langage est
[LANGAGE.md](https://github.com/MMarchand-NSI/lmc_lsp/blob/master/LANGAGE.md).

## Ce que l'extension apporte

- **Des diagnostics qui expliquent** plutôt que de constater : une étiquette non définie, un `HLT`
  manquant, un programme qui déborde des cent cases, une adresse hors de 0-99 — celle-ci parce
  qu'écrite telle quelle elle déborderait sur le chiffre de mode et assemblerait *une autre
  instruction valide*, en silence.
- **Survol, aller à la définition, références, complétion** sur les étiquettes et les mnémoniques.
- **Formatage** du document entier, sur une forme canonique.
- **Un émulateur pas à pas**, commande « LMC : ouvrir l'émulateur ». C'est la pièce centrale.

## La langue

Diagnostics, survols et complétion sont en **français** par défaut. Le réglage `lmc.locale` permet
`fr`, `en`, ou `auto` pour suivre la langue d'affichage de VS Code. `auto` n'est délibérément pas le
défaut : cette langue reste l'anglais chez la plupart des gens quel que soit leur pays, parce qu'on
ne la change pas — la prendre pour la langue de la classe rendrait des diagnostics anglais à un
cours français. Le serveur redémarre quand le réglage change, la langue étant annoncée à son
démarrage.

Le panneau de l'émulateur et les exemples restent français quoi qu'il arrive.

## L'émulateur

Une grille de cent cases, les cinq registres, les files d'entrée et de sortie, et le cycle
**Fetch / Decode / Execute** déplié à chaque pas — y compris l'incrément du compteur ordinal pendant
la lecture, qui est ce qui explique qu'une machine arrêtée affiche un `PC` d'un cran au-delà de
l'instruction qui l'a arrêtée.

Le panneau et l'éditeur sont synchronisés dans les deux sens : déplacer le curseur souligne la case
correspondante, cliquer une case révèle sa ligne source. C'est la raison d'être de ce panneau plutôt
que d'un simulateur LMC en ligne.

La grille distingue quatre choses : la pile au-dessus de `SP`, les cases réservées par un `DAT`, le
milieu inutilisé, et le code. Ce marquage dit **ce que l'auteur a écrit**, pas ce que la machine
fait : rien ne distingue une case de code d'une case de données, et un `STA` qui écrit dans du code
ne change pas la couleur. Cet écart est la leçon, pas un défaut.

**Assembler**, **Charger** et **Exécuter** sont trois actes séparés, avec trois boutons. « Assembler »
écrit un `.lmcobj` à côté du source : quatre chiffres par ligne, une ligne par case, sans mnémonique
ni étiquette, parce que c'est tout ce que le processeur reçoit. « Charger » relit ce fichier sur le
disque. Charger avant d'avoir assemblé échoue, et modifier le source sans réassembler charge
l'ancien programme : c'est ainsi que se comporte une vraie chaîne d'outils.

## Un écran

`PLT` allume un point sur un écran de 32 × 32 en huit couleurs. La couleur 0 est le fond, donc
allumer un point en 0 l'efface. Un point hors de l'écran ou hors de la palette n'est pas dessiné, et
le panneau du cycle le dit au lieu de laisser un blanc.

## Le code

Développé pour l'enseignement de NSI. Le serveur de langage vit dans un dépôt séparé,
[lmc_lsp](https://github.com/MMarchand-NSI/lmc_lsp), pour rester indépendant de l'éditeur ;
l'extension elle-même est dans [lmc-vscode](https://github.com/MMarchand-NSI/lmc-vscode).
