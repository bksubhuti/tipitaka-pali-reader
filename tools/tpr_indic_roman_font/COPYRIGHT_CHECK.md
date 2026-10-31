# TPR Indic Roman: originality check

TPR Indic Roman is in the same broad style as Samarkan (Titivillus Foundry, 1993):
Latin letters hanging from a head bar, in the manner of Devanagari. A style is
not owned. The outlines are not copied: `build.py` draws every letter from
scratch with a simulated broad pen along curves written in the script. No
outline, point or measurement was taken from another font.

## Measured overlap (2026-10-31)

`compare.py` removes the head bar, scales each letter a–z to the same box and
measures shared ink as IoU (0 = nothing in common, 1 = identical).

| Pair | Mean IoU a–z | What the pair is |
|---|---|---|
| Arial vs Helvetica | 0.90 | Arial is a well-known near-copy of Helvetica |
| Arial vs Verdana | 0.82 | two plain sans-serifs |
| Arial vs Georgia | 0.49 | unrelated designs (sans vs serif) |
| **TPR Indic Roman vs Samarkan** | **0.36** | |

TPR Indic Roman shares less with Samarkan than Arial shares with Georgia. By this
measure the two are independent designs.

Per letter (TPR Indic Roman vs Samarkan):
a 0.46, b 0.17, c 0.46, d 0.32, e 0.34, f 0.44, g 0.18, h 0.18, i 0.29,
j 0.41, k 0.20, l 0.32, m 0.42, n 0.42, o 0.47, p 0.42, q 0.45, r 0.30,
s 0.27, t 0.24, u 0.46, v 0.61, w 0.30, x 0.49, y 0.42, z 0.41

The highest letter, v (0.61), is close to the Arial–Georgia level. Any two
v shapes overlap this much, because a v is two diagonals.

To repeat the check:

    python compare.py ../../assets/fonts/TPRIndicRoman-Regular.ttf SAMAN___.TTF abcdefghijklmnopqrstuvwxyz

This is a technical comparison, not legal advice.
