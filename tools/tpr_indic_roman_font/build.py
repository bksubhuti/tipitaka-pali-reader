"""Build TPR Indic Roman: a calligraphic Latin font for Pāḷi and Sanskrit in the
head-bar style. Every outline is drawn here by a simulated broad pen moving
along the curves below; nothing is traced from another font.

    python build.py TPRIndicRoman-Regular.ttf
    python build.py --noline TPRIndicRomanNoline-Regular.ttf   (no head bar)

Needs: pip install fonttools shapely
"""
import math, sys
from shapely.geometry import Polygon, box
from shapely.ops import unary_union
from shapely.affinity import translate, scale
from shapely.geometry.polygon import orient
from fontTools.fontBuilder import FontBuilder
from fontTools.pens.ttGlyphPen import TTGlyphPen

UPM = 1000
BAR_TOP, BAR_BOT = 715, 640     # head bar
XH = BAR_BOT                    # letters hang from the bar
ASC = 900
NIB_W, NIB_T, NIB_A = 142, 8, math.radians(30)
TAPER = (0.08, 0.12), 0.32       # pen width at start/end, share of stroke spent swelling
LIGHT = 112                     # pen width for diagonals (v, k, w, x, z)
SX = 1.14                       # widen letters after drawing
NOLINE = '--noline' in sys.argv  # the same letters without the head bar
TRACK = 20 if NOLINE else -30   # extra room between letters (bar still joins)   # broad pen: width, thickness, angle


def cubic(p0, p1, p2, p3, n=48):
    pts = []
    for i in range(n + 1):
        t = i / n
        a, b, c, d = (1 - t) ** 3, 3 * t * (1 - t) ** 2, 3 * t * t * (1 - t), t ** 3
        pts.append((a * p0[0] + b * p1[0] + c * p2[0] + d * p3[0],
                    a * p0[1] + b * p1[1] + c * p2[1] + d * p3[1]))
    return pts


def line(p, q, n=12):
    return [(p[0] + (q[0] - p[0]) * i / n, p[1] + (q[1] - p[1]) * i / n) for i in range(n + 1)]


def path(*segs):
    pts = []
    for s in segs:
        pts += s if not pts else s[1:]
    return pts


def nib(p, w=NIB_W):
    dx, dy = math.cos(NIB_A) * w / 2, math.sin(NIB_A) * w / 2
    tx, ty = -math.sin(NIB_A) * NIB_T / 2, math.cos(NIB_A) * NIB_T / 2
    x, y = p
    return [(x - dx - tx, y - dy - ty), (x + dx - tx, y + dy - ty),
            (x + dx + tx, y + dy + ty), (x - dx + tx, y - dy + ty)]


def pressure(t, ends=TAPER[0], ramp=TAPER[1]):
    """Pen pressure along a stroke: light at entry and exit, full in the middle."""
    if t < ramp:
        u = t / ramp
        return ends[0] + (1 - ends[0]) * math.sin(u * math.pi / 2)
    if t > 1 - ramp:
        u = (1 - t) / ramp
        return ends[1] + (1 - ends[1]) * math.sin(u * math.pi / 2)
    return 1.0


def stroke(pts, w=NIB_W, ends=TAPER[0]):
    """Sweep the broad nib along pts with calligraphic pressure."""
    # parametrise by length so the swell does not depend on point spacing
    d = [0.0]
    for a, b in zip(pts, pts[1:]):
        d.append(d[-1] + math.dist(a, b))
    L = d[-1] or 1.0
    ramp = min(TAPER[1], 160 / L) if L > 0 else TAPER[1]
    polys = []
    for i in range(len(pts) - 1):
        wa, wb = (w * pressure(d[j] / L, ends, ramp) for j in (i, i + 1))
        polys.append(Polygon(nib(pts[i], wa) + nib(pts[i + 1], wb)).convex_hull)
    return unary_union(polys)


NO_BAR = False


def bar(adv):
    return Polygon() if NO_BAR or NOLINE else box(-6, BAR_BOT, adv + 6, BAR_TOP)


def wedge(x, top):
    """Leaning wedge cap for a tall stem."""
    h = NIB_W / 2
    return Polygon([(x - h, top - 90), (x - h + 10, top - 20), (x + h + 45, top + 45), (x + h, top - 90)])


def stem(x, top, bottom=0, foot=True):
    """Vertical stem; foot flicks right at the baseline."""
    if top > BAR_TOP:
        lead = stroke(path(cubic((x + 40, top + 20), (x + 10, top - 20), (x, top - 80), (x, top - 150)),
                           line((x, top - 150), (x, BAR_BOT))), ends=(0.15, 1))
        return unary_union([lead, stem(x, BAR_BOT, bottom, foot)])
    if foot:
        return stroke(path(line((x, top), (x, bottom + 90)),
                           cubic((x, bottom + 90), (x, bottom), (x + 60, bottom - 15), (x + 135, bottom + 75))),
                      ends=(1, 0.05))
    return stroke(line((x, top), (x, bottom)), ends=(1, 0.85))


def short_stem(x, foot=True, top=500):
    """Stem that starts below the bar with a pen lead-in, so n m r are not read as h."""
    lead = stroke(path(cubic((x - 60, top - 30), (x - 30, top + 5), (x, top + 10), (x, top - 70))), ends=(0.3, 1))
    return unary_union([lead, stem(x, top - 60, foot=foot)])


def dot_above(cx):
    return Polygon([(cx, 745), (cx + 78, 820), (cx, 895), (cx - 78, 820)])


def macron_above(cx, half=95, y=758):
    half += 20
    return box(cx - half, y, cx + half, y + 80)


def acute_above(cx):
    return stroke(line((cx - 40, 765), (cx + 70, 895)), w=100, ends=(0.4, 1))


# --- glyphs: name -> (advance, geometry) ---------------------------------------
G = {}


def g_i():
    adv = 250
    return adv, unary_union([bar(adv), stem(110, XH)])


def g_t():
    adv = 340
    tall = stroke(path(line((150, 780), (150, 160)),
                       cubic((150, 160), (150, -20), (290, -30), (320, 90))))
    return adv, unary_union([bar(adv), tall, box(40, 470, 290, 520)])


def g_u():
    adv = 620
    left = stroke(path(line((110, XH), (110, 260)),
                       cubic((110, 260), (105, 40), (250, -10), (350, 20)),
                       cubic((350, 20), (430, 45), (465, 130), (470, 220))))
    return adv, unary_union([bar(adv), left, stem(470, XH)])


def g_b():
    adv = 620
    bowl = stroke(path(cubic((120, 400), (230, 500), (480, 480), (480, 250)),
                       cubic((480, 250), (480, 40), (280, -30), (120, 50))))
    return adv, unary_union([bar(adv), stem(120, ASC, foot=False), bowl])


def g_h():
    adv = 620
    arch = stroke(path(cubic((120, 400), (230, 500), (470, 490), (475, 300)),
                       line((475, 300), (475, 70)),
                       cubic((475, 70), (475, 10), (505, -4), (560, 30))))
    return adv, unary_union([bar(adv), stem(120, ASC, foot=False), arch])


def g_s():
    adv = 580
    spine = stroke(path(cubic((450, XH), (450, 540), (360, 520), (270, 515)),
                        cubic((270, 515), (110, 505), (80, 430), (130, 370)),
                        cubic((130, 370), (190, 300), (470, 320), (470, 170)),
                        cubic((470, 170), (470, 30), (300, -20), (110, 60))))
    return adv, unary_union([bar(adv), spine])


def a_bowl(x):
    """Bowl on the left of a right-hand stem at x (a, d, g)."""
    return stroke(path(cubic((x, 340), (330, 410), (105, 360), (110, 190)),
                       cubic((110, 190), (115, 20), (320, -10), (x, 110))))


def g_a():
    adv = 580
    # two-storey a: hook over the top, clear of the bar, so it is never read as d
    body = stroke(path(cubic((120, 450), (160, 540), (300, 560), (380, 530)),
                       cubic((380, 530), (430, 505), (440, 450), (440, 380)),
                       line((440, 380), (440, 70)),
                       cubic((440, 70), (440, 10), (470, -4), (525, 30))))
    bowl = stroke(path(cubic((440, 320), (300, 350), (100, 330), (105, 160)),
                       cubic((105, 160), (110, 0), (330, -15), (440, 100))))
    return adv, unary_union([bar(adv), body, bowl])


def g_d():
    adv = 580
    bowl = stroke(path(cubic((440, 450), (320, 530), (100, 470), (105, 240)),
                       cubic((105, 240), (110, 10), (330, -20), (440, 110))))
    return adv, unary_union([bar(adv), stem(440, ASC), bowl])


def g_g():
    adv = 580
    tail = stroke(path(line((440, XH), (440, -60)),
                       cubic((440, -60), (440, -210), (220, -250), (110, -150))))
    return adv, unary_union([bar(adv), tail, a_bowl(440)])


def g_e():
    adv = 560
    eye = stroke(path(line((125, 290), (445, 290)),
                      cubic((445, 290), (450, 500), (130, 510), (115, 290)),
                      cubic((115, 290), (100, 50), (330, -25), (455, 95))))
    return adv, unary_union([bar(adv), eye, box(120, 268, 450, 308)])


def g_j():
    adv = 300
    hook = stroke(path(line((190, XH), (190, -60)),
                       cubic((190, -60), (190, -200), (80, -230), (10, -160))))
    return adv, unary_union([bar(adv), hook, dot_above(190)])


def g_k():
    adv = 580
    arm = stroke(line((440, XH), (150, 300)), w=LIGHT, ends=(1, 0.6))
    leg = stroke(path(cubic((210, 340), (330, 280), (380, 70), (530, 30))), w=LIGHT + 15)
    return adv, unary_union([bar(adv), stem(120, ASC, foot=False), arm, leg])


def arch(x0, x1, foot=True):
    pts = [cubic((x0, 400), (x0 + 80, 490), (x1 - 20, 480), (x1, 300)), line((x1, 300), (x1, 70))]
    if foot:
        pts.append(cubic((x1, 70), (x1, 10), (x1 + 30, -4), (x1 + 85, 30)))
    else:
        pts.append(line((x1, 70), (x1, 0)))
    return stroke(path(*pts))


def g_m():
    adv = 860
    return adv, unary_union([bar(adv), short_stem(110, foot=False), arch(110, 400, foot=False), arch(400, 690)])


def g_n():
    adv = 600
    return adv, unary_union([bar(adv), short_stem(110, foot=False), arch(110, 450)])


def g_p():
    adv = 600
    bowl = stroke(path(cubic((120, 400), (230, 500), (470, 480), (470, 250)),
                       cubic((470, 250), (470, 40), (280, -30), (120, 50))))
    return adv, unary_union([bar(adv), stem(120, XH, -250, foot=False), bowl])


def g_r():
    adv = 420
    arm = stroke(cubic((110, 400), (170, 480), (280, 490), (340, 430)))
    return adv, unary_union([bar(adv), short_stem(110), arm])


def g_v():
    adv = 560
    v = stroke(path(line((100, XH), (280, 10)),
                    cubic((280, 10), (380, 180), (450, 380), (450, XH))), w=LIGHT, ends=(1, 1))
    return adv, unary_union([bar(adv), v])


def g_y():
    adv = 600
    left = stroke(path(line((110, XH), (110, 260)),
                       cubic((110, 260), (105, 40), (250, -10), (350, 20)),
                       cubic((350, 20), (430, 45), (460, 130), (465, 220))))
    right = stroke(path(line((465, XH), (465, -60)),
                        cubic((465, -60), (465, -210), (240, -250), (120, -150))))
    return adv, unary_union([bar(adv), left, right])


def g_l():
    adv = 260
    return adv, unary_union([bar(adv), stem(120, ASC + 20, foot=False)])


def g_c():
    adv = 540
    c = stroke(path(cubic((445, 400), (390, 500), (110, 500), (110, 250)),
                    cubic((110, 250), (110, 20), (350, -20), (460, 90))))
    return adv, unary_union([bar(adv), c])


def g_o():
    adv = 580
    o = stroke(path(cubic((290, 480), (140, 480), (105, 340), (105, 240)),
                    cubic((105, 240), (105, 100), (170, 0), (290, 0)),
                    cubic((290, 0), (420, 0), (470, 120), (470, 240)),
                    cubic((470, 240), (470, 380), (420, 480), (290, 480)),
                    cubic((290, 480), (240, 480), (200, 470), (180, 455))), ends=(1, 1))
    return adv, unary_union([bar(adv), o])


def g_f():
    adv = 380
    top = stroke(path(cubic((340, ASC - 30), (280, ASC + 20), (150, ASC + 10), (140, ASC - 160)),
                      line((140, ASC - 160), (140, 0))), ends=(0.2, 0.85))
    return adv, unary_union([bar(adv), top, box(40, 470, 290, 520)])


def g_q():
    adv = 600
    bowl = stroke(path(cubic((440, 450), (320, 530), (100, 470), (105, 240)),
                       cubic((105, 240), (110, 10), (330, -20), (440, 110))))
    return adv, unary_union([bar(adv), stem(440, XH, -250, foot=False), bowl])


def g_w():
    adv = 760
    w = stroke(path(line((90, XH), (240, 10)),
                    cubic((240, 10), (300, 120), (360, 260), (380, 380)),
                    line((380, 380), (520, 10)),
                    cubic((520, 10), (600, 180), (660, 380), (660, XH))), w=LIGHT, ends=(1, 1))
    return adv, unary_union([bar(adv), w])


def g_x():
    adv = 560
    a = stroke(path(line((100, XH), (130, 520)), cubic((130, 520), (200, 300), (330, 100), (470, 20))), w=LIGHT, ends=(1, 0.4))
    b = stroke(line((450, XH), (90, 10)), w=LIGHT, ends=(1, 0.5))
    return adv, unary_union([bar(adv), a, b])


def g_z():
    adv = 540
    z = stroke(line((440, 470), (110, 40)), w=LIGHT + 45, ends=(1, 1))
    return adv, unary_union([bar(adv), z, box(100, 430, 455, 500), box(100, 0, 485, 70)])


def tilde_above(cx):
    return stroke(cubic((cx - 120, 765), (cx - 50, 870), (cx + 50, 730), (cx + 120, 835)), w=105, ends=(0.5, 0.5))


def dot_below(cx, y=-150):
    return Polygon([(cx, y - 75), (cx + 78, y), (cx, y + 75), (cx - 78, y)])


LETTERS = [('i', g_i), ('t', g_t), ('u', g_u), ('b', g_b), ('h', g_h), ('s', g_s),
                 ('a', g_a), ('d', g_d), ('e', g_e), ('g', g_g), ('j', g_j), ('k', g_k),
                 ('m', g_m), ('n', g_n), ('p', g_p), ('r', g_r), ('v', g_v), ('y', g_y), ('l', g_l),
                 ('c', g_c), ('o', g_o), ('f', g_f), ('q', g_q), ('w', g_w), ('x', g_x), ('z', g_z)]
for name, fn in LETTERS:
    G[name] = fn()
G['dotlessi'] = G['i']

# Capitals: the lowercase form, wider, and (if it has no ascender) taller so it rises through the bar.
CAP_SX, CAP_SY = 1.08, 1.25
ASCENDERS = set('bdfhklt')
NO_BAR = True
for name, fn in LETTERS:
    adv, geo = fn()
    if name not in ASCENDERS:
        geo = geo.difference(box(-200, 740, 1200, 1200))      # drop dots (j)
    geo = scale(geo, CAP_SX, 1.0 if name in ASCENDERS else CAP_SY, origin=(0, 0))
    adv = round(adv * CAP_SX)
    G[name.upper()] = (adv, geo if NOLINE else unary_union([geo, box(-6, BAR_BOT, adv + 6, BAR_TOP)]))
NO_BAR = False


def up(mark, base):
    """Raise an above-mark for a capital (above any stem poking through the bar)."""
    return translate(mark, 0, 0 if base.lower() in ASCENDERS else 150)


def add(name, base, *marks):
    adv, geo = G[base]
    G[name] = (adv, unary_union([geo, *marks]))


add('i', 'dotlessi', dot_above(110))
add('imacron', 'dotlessi', macron_above(110, 85))
add('umacron', 'u', macron_above(290))
add('amacron', 'a', macron_above(290))
add('mdotbelow', 'm', dot_below(400))
add('ndotbelow', 'n', dot_below(280))
add('ddotbelow', 'd', dot_below(280))
add('ldotbelow', 'l', dot_below(150))
add('tdotbelow', 't', dot_below(150))
add('ndotaccent', 'n', dot_above(280))
add('ntilde', 'n', tilde_above(280))
# Sanskrit (IAST / ISO 15919)
add('rdotbelow', 'r', dot_below(110))
add('rdotbelowmacron', 'rdotbelow', macron_above(200, 110))
add('ldotbelowmacron', 'ldotbelow', macron_above(150, 95, y=965))
add('sacute', 's', acute_above(290))
add('sdotbelow', 's', dot_below(280))
add('hdotbelow', 'h', dot_below(300))
add('mdotaccent', 'm', dot_above(400))
add('emacron', 'e', macron_above(285))
add('omacron', 'o', macron_above(290))
X = CAP_SX
for name, base, mark in [
        ('Amacron', 'A', up(macron_above(290 * X), 'A')), ('Imacron', 'I', up(macron_above(110 * X, 85), 'I')),
        ('Umacron', 'U', up(macron_above(290 * X), 'U')), ('Ndotaccent', 'N', up(dot_above(280 * X), 'N')),
        ('Ntilde', 'N', up(tilde_above(280 * X), 'N')), ('Tdotbelow', 'T', dot_below(150 * X)),
        ('Ddotbelow', 'D', dot_below(280 * X)), ('Ndotbelow', 'N', dot_below(280 * X)),
        ('Ldotbelow', 'L', dot_below(150 * X)), ('Mdotbelow', 'M', dot_below(400 * X)),
        ('Rdotbelow', 'R', dot_below(110 * X)), ('Sacute', 'S', up(acute_above(290 * X), 'S')),
        ('Sdotbelow', 'S', dot_below(280 * X)), ('Hdotbelow', 'H', dot_below(300 * X)),
        ('Mdotaccent', 'M', up(dot_above(400 * X), 'M')), ('Emacron', 'E', up(macron_above(285 * X), 'E')),
        ('Omacron', 'O', up(macron_above(290 * X), 'O'))]:
    add(name, base, mark)
add('Rdotbelowmacron', 'Rdotbelow', up(macron_above(200 * X, 110), 'R'))
add('Ldotbelowmacron', 'Ldotbelow', macron_above(150 * X, 95, y=965))

# punctuation
DOT = lambda x, y: Polygon([(x, y - 62), (x + 62, y), (x, y + 62), (x - 62, y)])
G['colon'] = (240, unary_union([DOT(120, 50), DOT(120, 400)]))
G['semicolon'] = (240, unary_union([DOT(120, 400), stroke(cubic((130, 60), (150, 20), (130, -60), (80, -110)), w=70)]))
G['hyphen'] = (360, box(50, 280, 310, 340))
G['endash'] = (520, box(30, 290, 490, 340))
G['quoteright'] = (220, stroke(cubic((130, 900), (150, 860), (130, 780), (80, 730)), w=70))
G['quoteleft'] = (220, stroke(cubic((100, 730), (80, 770), (100, 850), (150, 900)), w=70))
G['quotedblright'] = (360, unary_union([G['quoteright'][1], translate(G['quoteright'][1], 130, 0)]))
G['quotedblleft'] = (360, unary_union([G['quoteleft'][1], translate(G['quoteleft'][1], 130, 0)]))
G['exclam'] = (240, unary_union([stroke(line((120, 880), (120, 200)), ends=(1, 0.3), w=100), DOT(120, 50)]))
G['question'] = (460, unary_union([stroke(path(cubic((80, 780), (120, 920), (400, 920), (390, 720)),
                                               cubic((390, 720), (380, 560), (220, 520), (220, 220))), w=90, ends=(0.4, 0.4)),
                                   DOT(220, 50)]))
G['parenleft'] = (300, stroke(cubic((240, 920), (60, 760), (60, 60), (240, -120)), w=70, ends=(0.6, 0.6)))
# digits: no head bar
def oval(cx, cy, rx, ry):
    return path(cubic((cx, cy + ry), (cx - rx * 0.55, cy + ry), (cx - rx, cy + ry * 0.55), (cx - rx, cy)),
                cubic((cx - rx, cy), (cx - rx, cy - ry * 0.55), (cx - rx * 0.55, cy - ry), (cx, cy - ry)),
                cubic((cx, cy - ry), (cx + rx * 0.55, cy - ry), (cx + rx, cy - ry * 0.55), (cx + rx, cy)),
                cubic((cx + rx, cy), (cx + rx, cy + ry * 0.55), (cx + rx * 0.55, cy + ry), (cx, cy + ry)),
                cubic((cx, cy + ry), (cx - 40, cy + ry), (cx - 70, cy + ry - 5), (cx - 90, cy + ry - 15)))
DW = 560
G['zero'] = (DW, stroke(oval(280, 330, 180, 320), ends=(1, 1)))
G['one'] = (DW, unary_union([stroke(path(line((150, 520), (300, 660)), line((300, 660), (300, 0))), ends=(0.3, 1)),
                             box(170, 0, 430, 50)]))
G['two'] = (DW, unary_union([stroke(path(cubic((100, 500), (130, 700), (450, 700), (440, 480)),
                                         cubic((440, 480), (430, 320), (200, 200), (110, 30))), ends=(0.3, 1)),
                             box(100, 0, 470, 60)]))
G['three'] = (DW, stroke(path(cubic((110, 560), (180, 690), (440, 690), (430, 520)),
                              cubic((430, 520), (420, 400), (300, 370), (230, 370)),
                              cubic((230, 370), (380, 370), (460, 300), (450, 180)),
                              cubic((450, 180), (430, -20), (160, -30), (90, 100))), ends=(0.3, 0.3)))
G['four'] = (DW, unary_union([stroke(line((360, 660), (80, 180)), w=LIGHT), box(80, 160, 490, 215),
                              stroke(line((380, 450), (380, 0)), ends=(1, 1))]))
G['five'] = (DW, unary_union([box(160, 600, 450, 660), stroke(line((170, 640), (150, 370)), w=LIGHT + 20, ends=(1, 1)),
                              stroke(path(cubic((150, 370), (260, 430), (460, 410), (460, 220)),
                                          cubic((460, 220), (460, -20), (170, -30), (90, 100))), ends=(1, 0.3))]))
G['six'] = (DW, stroke(path(cubic((420, 640), (200, 600), (100, 450), (100, 250)),
                            cubic((100, 250), (100, 60), (200, 0), (290, 0)),
                            cubic((290, 0), (400, 0), (460, 90), (460, 200)),
                            cubic((460, 200), (460, 330), (370, 390), (280, 390)),
                            cubic((280, 390), (200, 390), (130, 340), (105, 280))), ends=(0.3, 1)))
G['seven'] = (DW, unary_union([box(90, 600, 470, 660), stroke(cubic((460, 640), (330, 450), (230, 250), (200, 0)), ends=(1, 0.6))]))
G['eight'] = (DW, unary_union([stroke(oval(280, 500, 150, 145), ends=(1, 1)), stroke(oval(280, 180, 180, 180), ends=(1, 1))]))
G['nine'] = (DW, stroke(path(cubic((450, 450), (420, 580), (360, 650), (270, 650)),
                             cubic((270, 650), (160, 650), (100, 560), (100, 450)),
                             cubic((100, 450), (100, 320), (190, 260), (280, 260)),
                             cubic((280, 260), (360, 260), (440, 320), (455, 400)),
                             cubic((455, 400), (460, 200), (380, 40), (140, 0))), ends=(1, 0.3)))
G['parenright'] = (300, stroke(cubic((60, 920), (240, 760), (240, 60), (60, -120)), w=70, ends=(0.6, 0.6)))
G['space'] = (280, None)
G['period'] = (220, Polygon([(110, 0), (160, 50), (110, 100), (60, 50)]))
G['comma'] = (220, stroke(cubic((120, 60), (140, 20), (120, -60), (70, -110)), w=70))
G['emdash'] = (700, box(-6, 300, 706, 350))

CMAP = {ord(c): c for c in 'abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ'}
CMAP.update({0x30 + i: d for i, d in enumerate(['zero', 'one', 'two', 'three', 'four', 'five', 'six', 'seven', 'eight', 'nine'])})
CMAP.update({0x0304: 'macroncomb', 0x0323: 'dotbelowcomb', 0x0307: 'dotaccentcomb', 0x0303: 'tildecomb', 0x0301: 'acutecomb',
             0x200B: 'uni200B', 0x200C: 'uni200C', 0x200D: 'uni200D', 0xFEFF: 'uniFEFF', 0x00AD: 'uni00AD',
             0x0D: 'CR', 0x0A: 'LF', 0xA0: 'nbspace', 0x09: 'tab', 0x2010: 'hyphen', 0x2011: 'hyphen'})
CMAP.update({ord(':'): 'colon', ord(';'): 'semicolon', ord('-'): 'hyphen', 0x2013: 'endash', ord("'"): 'quoteright',
             0x2019: 'quoteright', 0x2018: 'quoteleft', 0x201C: 'quotedblleft', 0x201D: 'quotedblright', ord('"'): 'quotedblright',
             ord('!'): 'exclam', ord('?'): 'question', ord('('): 'parenleft', ord(')'): 'parenright',
             0x0100: 'Amacron', 0x012A: 'Imacron', 0x016A: 'Umacron', 0x1E44: 'Ndotaccent', 0x00D1: 'Ntilde',
             0x1E6C: 'Tdotbelow', 0x1E0C: 'Ddotbelow', 0x1E46: 'Ndotbelow', 0x1E36: 'Ldotbelow', 0x1E42: 'Mdotbelow',
             0x1E5A: 'Rdotbelow', 0x1E5C: 'Rdotbelowmacron', 0x1E38: 'Ldotbelowmacron', 0x015A: 'Sacute',
             0x1E62: 'Sdotbelow', 0x1E24: 'Hdotbelow', 0x1E40: 'Mdotaccent', 0x0112: 'Emacron', 0x014C: 'Omacron'})
CMAP.update({0x0131: 'dotlessi', 0x012B: 'imacron', 0x016B: 'umacron', 0x0101: 'amacron',
             0x1E43: 'mdotbelow', 0x1E47: 'ndotbelow', 0x1E0D: 'ddotbelow', 0x1E37: 'ldotbelow', 0x1E6D: 'tdotbelow',
             0x1E5B: 'rdotbelow', 0x1E5D: 'rdotbelowmacron', 0x1E39: 'ldotbelowmacron', 0x015B: 'sacute',
             0x1E63: 'sdotbelow', 0x1E25: 'hdotbelow', 0x1E41: 'mdotaccent', 0x0113: 'emacron', 0x014D: 'omacron', 0x1E45: 'ndotaccent', 0x00F1: 'ntilde',
             0x20: 'space', ord('.'): 'period', ord(','): 'comma', 0x2014: 'emdash'})


DIGITS = ['zero', 'one', 'two', 'three', 'four', 'five', 'six', 'seven', 'eight', 'nine']
# combining marks (for text typed as letter + accent); drawn left of the origin, zero width
CENTRE = -300
G['macroncomb'] = (0, macron_above(CENTRE, 85))
G['dotbelowcomb'] = (0, dot_below(CENTRE))
G['dotaccentcomb'] = (0, dot_above(CENTRE))
G['tildecomb'] = (0, tilde_above(CENTRE))
G['acutecomb'] = (0, acute_above(CENTRE))
for k in ('uni200B', 'uni200C', 'uni200D', 'uniFEFF', 'uni00AD', 'CR', 'LF'):
    G[k] = (0, None)
G['nbspace'] = G['space']
G['tab'] = (G['space'][0] * 4, None)
PUNCT = set(DIGITS) | {'macroncomb', 'dotbelowcomb', 'dotaccentcomb', 'tildecomb', 'acutecomb'} | {'period', 'comma', 'emdash', 'colon', 'semicolon', 'hyphen', 'endash', 'quoteright', 'quoteleft',
         'quotedblright', 'quotedblleft', 'exclam', 'question', 'parenleft', 'parenright'}


def to_glyph(geo):
    pen = TTGlyphPen(None)
    if geo is not None:
        geo = geo.simplify(1.5)
        polys = [geo] if geo.geom_type == 'Polygon' else list(geo.geoms)
        for poly in polys:
            poly = orient(poly, sign=-1.0)        # outer clockwise for TrueType
            for ring in [poly.exterior] + list(poly.interiors):
                pts = [(round(x), round(y)) for x, y in ring.coords[:-1]]
                pen.moveTo(pts[0])
                for p in pts[1:]:
                    pen.lineTo(p)
                pen.closePath()
    return pen.glyph()


def build(out, family='TPR Indic Roman'):
    order = ['.notdef'] + sorted(k for k in G)
    fb = FontBuilder(UPM, isTTF=True)
    fb.setupGlyphOrder(order)
    fb.setupCharacterMap(CMAP)
    glyphs = {'.notdef': to_glyph(box(50, 0, 450, 700).difference(box(100, 50, 400, 650)))}
    metrics = {'.notdef': (500, 50)}
    for k, (adv, geo) in list(G.items()):
        if geo is not None and k not in PUNCT:
            geo = scale(geo, SX, 1, origin=(0, 0))
            adv = round(adv * SX)
            geo = translate(geo, TRACK / 2)
            if not NOLINE:
                geo = unary_union([geo, box(-6, BAR_BOT, adv + TRACK + 6, BAR_TOP)])
            adv += TRACK
            G[k] = (adv, geo)
        glyphs[k] = to_glyph(geo)
        metrics[k] = (adv, 0)
    fb.setupGlyf(glyphs)
    metrics = {k: (G[k][0] if k in G else adv, glyphs[k].xMin if hasattr(glyphs[k], 'xMin') else 0)
               for k, (adv, _) in metrics.items()}
    fb.setupHorizontalMetrics(metrics)
    import unicodedata
    from fontTools.feaLib.builder import addOpenTypeFeaturesFromString
    names = {cp: g for cp, g in CMAP.items()}
    rules = []
    for cp, g in CMAP.items():
        dec = unicodedata.normalize('NFD', chr(cp))
        if len(dec) > 1 and all(ord(c) in names for c in dec):
            rules.append('    sub %s by %s;' % (' '.join(names[ord(c)] for c in dec), g))
    rules.sort(key=lambda r: -r.count(' '))     # longest sequences first
    fea = 'languagesystem DFLT dflt;\nlanguagesystem latn dflt;\nfeature ccmp {\n' + '\n'.join(rules) + '\n} ccmp;\n'
    addOpenTypeFeaturesFromString(fb.font, fea)
    fb.setupHorizontalHeader(ascent=950, descent=-250)
    ps = family.replace(' ', '') + '-Regular'
    fb.setupNameTable({'familyName': family, 'styleName': 'Regular',
                       'uniqueFontIdentifier': '1.000;UKWN;' + ps, 'fullName': family + ' Regular',
                       'psName': ps, 'version': 'Version 1.000',
                       'copyright': 'Copyright 2026 Path Nirvana Foundation',
                       'licenseDescription': 'This Font Software is licensed under the SIL Open Font License, Version 1.1.',
                       'licenseInfoURL': 'https://openfontlicense.org'})
    fb.setupOS2(sTypoAscender=950, sTypoDescender=-250, sTypoLineGap=0, usWinAscent=1060, usWinDescent=300,
                usWeightClass=400, fsSelection=0x40, achVendID='UKWN',     # 0x40 = REGULAR
                ulCodePageRange1=0b1 | 0b10)                                 # Latin 1, Latin 2
    fb.font['OS/2'].recalcUnicodeRanges(fb.font)
    fb.setupPost()
    fb.save(out)


if __name__ == '__main__':
    args = [a for a in sys.argv[1:] if a != '--noline']
    build(args[0] if args else 'TPRIndicRoman-Regular.ttf',
          'TPR Indic Roman Noline' if NOLINE else 'TPR Indic Roman')
