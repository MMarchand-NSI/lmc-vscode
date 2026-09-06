#!/usr/bin/env python3
"""Fabrique l'icone du Marketplace, vscode-extension/icon.png (128x128).

L'icone n'est pas un dessin arbitraire : c'est la grille memoire du panneau,
avec les deux couleurs que le panneau utilise reellement, teal pour une case
lue et rose pour une case ecrite (voir webview/style.css, @keyframes
mailbox-read et mailbox-written). Elle est produite par ce script et non
dessinee a la main pour que ces couleurs restent celles du produit : si la
palette change la, elle change ici.

Pas de texte : a 42 px, la taille d'une vignette dans la liste des extensions,
trois lettres deviennent une tache. Une grille avec deux cases allumees reste
lisible a cette taille et ne ressemble a aucune autre icone.

    python3 scripts/build-icon.py

Depend de Pillow (`pip install pillow`), et de rien d'autre. Le PNG produit est
commite : personne n'a besoin de ce script pour construire l'extension, il
n'existe que pour refaire l'icone.
"""

from PIL import Image, ImageDraw

SIZE = 128
SS = 8  # supersampling, pour des bords lisses sans dependance de plus
S = SIZE * SS

GROUND = (18, 18, 26, 255)  # #12121a, le fond de la grille du panneau
CELL = (58, 58, 74, 255)  # une case au repos
TEAL = (0, 176, 176, 255)  # une case lue
PINK = (255, 92, 168, 255)  # une case ecrite

GRID = 4  # 4 x 4 cases
MARGIN = 14 * SS
GAP = 7 * SS


def rounded(draw, box, radius, fill):
    draw.rounded_rectangle(box, radius=radius, fill=fill)


def main():
    img = Image.new("RGBA", (S, S), (0, 0, 0, 0))
    d = ImageDraw.Draw(img)

    rounded(d, (0, 0, S - 1, S - 1), radius=24 * SS, fill=GROUND)

    span = S - 2 * MARGIN
    cell = (span - (GRID - 1) * GAP) / GRID
    # Une lecture puis une ecriture, placees en diagonale : c'est ce que fait
    # une instruction (lire une case, ecrire dans une autre), et la diagonale
    # se voit encore quand l'icone est minuscule.
    lit = {(1, 1): TEAL, (2, 2): PINK}

    for row in range(GRID):
        for col in range(GRID):
            x = MARGIN + col * (cell + GAP)
            y = MARGIN + row * (cell + GAP)
            fill = lit.get((row, col), CELL)
            rounded(
                d,
                (x, y, x + cell, y + cell),
                radius=int(cell * 0.22),
                fill=fill,
            )

    img = img.resize((SIZE, SIZE), Image.LANCZOS)
    out = "vscode-extension/icon.png"
    img.save(out)
    print(f"ecrit {out} ({SIZE}x{SIZE})")


if __name__ == "__main__":
    main()
