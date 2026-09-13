#!/usr/bin/env python3
"""Fabrique les icones de fichier .lmc et .lmcobj, et celle de l'onglet de
l'emulateur (vscode-extension/icons/).

VS Code les montre dans l'explorateur et les onglets quand le theme d'icones
n'a rien pour ces fichiers, ce qui est le cas du theme par defaut, Seti
(contributes.languages[].icon). Il les affiche a 16 px (background-size: 16px
dans iconlabel.css de VS Code) : le PNG fait 32 px pour rester net sur un ecran
HiDPI.

Deux dessins, un par etape de la chaine, lisibles a 16 px :
- .lmc, le source : trois lignes de texte, comme du code.
- .lmcobj, le fichier objet : une grille de cases, les mots tels qu'ils
  arrivent en memoire.
- l'onglet de l'emulateur : une grille 3 x 3 de cases, une lue (teal) et une
  ecrite (rose), le reste en gris ; c'est la grille memoire du panneau, et la
  distinction qu'il enseigne. Posee par webviewPanel.ts (panel.iconPath).
Les teintes sont celles de l'icone de l'extension (scripts/build-icon.py) :
teal pour le source, rose pour l'objet. Chacune a une variante plus sombre pour
les themes clairs, ou la teinte d'origine manque de contraste sur fond blanc.

    python3 scripts/build-file-icons.py

Depend de Pillow. Les PNG produits sont commites.
"""

from PIL import Image, ImageDraw

SIZE = 32
SS = 8  # supersampling
S = SIZE * SS

TEAL = {"dark": (0, 176, 176, 255), "light": (0, 128, 128, 255)}
PINK = {"dark": (255, 92, 168, 255), "light": (196, 38, 118, 255)}
OUT = "vscode-extension/icons"


def canvas():
    img = Image.new("RGBA", (S, S), (0, 0, 0, 0))
    return img, ImageDraw.Draw(img)


def save(img, name):
    img.resize((SIZE, SIZE), Image.LANCZOS).save(f"{OUT}/{name}.png")
    print(f"ecrit {OUT}/{name}.png")


def source(variant):
    """Trois lignes de longueurs differentes, alignees a gauche."""
    img, d = canvas()
    colour = TEAL[variant]
    bar = 6 * SS  # pair : 3 px nets une fois reduit a 16
    left = 4 * SS
    for top, length in [(6, 24), (14, 16), (22, 20)]:
        y = top * SS
        d.rounded_rectangle(
            (left, y, left + length * SS, y + bar), radius=2 * SS, fill=colour
        )
    return img


def object_file(variant):
    """Une grille 2 x 2 de cases arrondies."""
    img, d = canvas()
    colour = PINK[variant]
    cell = 12 * SS
    gap = 4 * SS
    origin = 2 * SS
    for row in range(2):
        for col in range(2):
            x = origin + col * (cell + gap)
            y = origin + row * (cell + gap)
            d.rounded_rectangle(
                (x, y, x + cell, y + cell), radius=3 * SS, fill=colour
            )
    return img


GREY = {"dark": (120, 120, 132, 255), "light": (150, 150, 160, 255)}


def emulator(variant):
    """Grille 3 x 3 : une case lue, une case ecrite, les autres au repos."""
    img, d = canvas()
    cell = 8 * SS
    gap = 2 * SS  # pair : 1 px net une fois reduit a 16
    origin = 2 * SS  # 3 cases + 2 gouttieres = 28 px, centre dans 32
    lit = {(0, 0): TEAL[variant], (1, 1): PINK[variant]}
    for row in range(3):
        for col in range(3):
            x = origin + col * (cell + gap)
            y = origin + row * (cell + gap)
            d.rounded_rectangle(
                (x, y, x + cell, y + cell),
                radius=2 * SS,
                fill=lit.get((row, col), GREY[variant]),
            )
    return img


def main():
    import os

    os.makedirs(OUT, exist_ok=True)
    for variant in ["dark", "light"]:
        save(source(variant), f"lmc-{variant}")
        save(object_file(variant), f"lmcobj-{variant}")
        save(emulator(variant), f"emulator-{variant}")


if __name__ == "__main__":
    main()
