#!/usr/bin/env python3
"""Generates the placeholder isometric sprites used by the demo.

Run from the repo root:  python3 tools/make_sprites.py
Writes PNGs to assets/sprites/ and scripts/sprite_data.gd (anchor points).
Needs Pillow. Replace any PNG with real art of the same name and anchor and the game will use it.
"""
import math
import os

from PIL import Image, ImageDraw

LA, LB = 0.28, 0.14          # iso scale at logical resolution (final = x2 -> 0.56 / 0.28, matches main.gd)
SCALE = 2
OUT = "assets/sprites"
CX, CY = 220.0, 300.0        # footprint-centre position on the scratch canvas
CW, CH = 440, 400
OUTLINE = (27, 22, 32, 255)
anchors = {}


def sh(c, f):
    return (max(0, min(255, int(c[0] * f))), max(0, min(255, int(c[1] * f))), max(0, min(255, int(c[2] * f))), 255)


def P(x, y, z=0.0):
    return (CX + (x - y) * LA, CY + (x + y) * LB - z)


def new_canvas():
    img = Image.new("RGBA", (CW, CH), (0, 0, 0, 0))
    return img, ImageDraw.Draw(img)


def line3(d, a, b, col):
    d.line([P(*a), P(*b)], fill=col, width=1)


def box(d, cx, cy, w, dp, z0, z1, col, tex="plain", outline=True, top_col=None):
    x0, x1, y0, y1 = cx - w / 2, cx + w / 2, cy - dp / 2, cy + dp / 2
    south = sh(col, 0.78)
    east = sh(col, 0.55)
    top = top_col or col
    ol = lambda c: sh(c, 0.45) if outline else None
    d.polygon([P(x0, y1, z1), P(x1, y1, z1), P(x1, y1, z0), P(x0, y1, z0)], fill=south, outline=ol(south))
    d.polygon([P(x1, y1, z1), P(x1, y0, z1), P(x1, y0, z0), P(x1, y1, z0)], fill=east, outline=ol(east))
    d.polygon([P(x0, y0, z1), P(x1, y0, z1), P(x1, y1, z1), P(x0, y1, z1)], fill=top, outline=ol(top))
    if tex == "wood":
        t = sh(top, 0.82)
        yy = y0 + 8
        while yy < y1 - 1:
            line3(d, (x0, yy, z1), (x1, yy, z1), t)
            yy += 8
        zz = z0 + 7
        while zz < z1 - 1:
            line3(d, (x0, y1, zz), (x1, y1, zz), sh(south, 0.82))
            line3(d, (x1, y1, zz), (x1, y0, zz), sh(east, 0.82))
            zz += 7
    elif tex == "stone":
        zz, r = z0, 0
        while zz < z1 - 1:
            line3(d, (x0, y1, zz), (x1, y1, zz), sh(south, 0.8))
            xx = x0 + (r % 2) * 7 + 7
            while xx < x1:
                line3(d, (xx, y1, zz), (xx, y1, min(zz + 8, z1)), sh(south, 0.8))
                xx += 14
            yy = y0 + (r % 2) * 7 + 7
            line3(d, (x1, y1, zz), (x1, y0, zz), sh(east, 0.8))
            while yy < y1:
                line3(d, (x1, yy, zz), (x1, yy, min(zz + 8, z1)), sh(east, 0.8))
                yy += 14
            zz += 8
            r += 1


def ellipse(d, c, rx, ry, fill, outline=None):
    d.ellipse([c[0] - rx, c[1] - ry, c[0] + rx, c[1] + ry], fill=fill, outline=outline)


def cylinder(d, cx, cy, r, z0, z1, col, top_col=None, hoops=(), hoop_col=(70, 70, 78, 255)):
    c = P(cx, cy, 0)
    rx, ry = r * 1.414 * LA, r * 1.414 * LB
    u = -rx
    while u <= rx:
        f = 1.12 - 0.62 * ((u + rx) / (2 * rx))
        k = math.sqrt(max(0.0, 1 - (u / rx) ** 2))
        d.line([(c[0] + u, c[1] - z1), (c[0] + u, c[1] - z0 + ry * k)], fill=sh(col, f))
        for hz in hoops:
            d.point((c[0] + u, c[1] - hz + ry * k), fill=hoop_col)
        u += 0.5
    d.arc([c[0] - rx, c[1] - z0 - ry, c[0] + rx, c[1] - z0 + ry], 0, 180, fill=sh(col, 0.4))
    ellipse(d, (c[0], c[1] - z1), rx, ry, top_col or sh(col, 1.15), sh(col, 0.4))


def finish(name, img, anchor=None):
    """Crop to content, remember the footprint-centre anchor, upscale x2 and save."""
    bbox = img.getbbox()
    crop = img.crop((bbox[0] - 1, bbox[1] - 1, bbox[2] + 1, bbox[3] + 1))
    ax, ay = (CX, CY) if anchor is None else anchor
    ax, ay = (ax - (bbox[0] - 1)), (ay - (bbox[1] - 1))
    crop = crop.resize((crop.width * SCALE, crop.height * SCALE), Image.NEAREST)
    crop.save(os.path.join(OUT, name + ".png"))
    anchors[name] = (round(ax * SCALE), round(ay * SCALE))


WOOD = (150, 100, 55, 255)
DWOOD = (110, 70, 38, 255)

# ------------------------------------------------------------------ furniture
def pot_full():
    img, d = new_canvas()
    cylinder(d, 0, 0, 11, 0, 4, (150, 84, 52, 255))
    cylinder(d, 0, 0, 17, 4, 15, (176, 100, 60, 255))
    cylinder(d, 0, 0, 13, 15, 19, (176, 100, 60, 255))
    cylinder(d, 0, 0, 15, 19, 22, (190, 112, 70, 255), top_col=(58, 34, 24, 255))
    finish("pot_full", img)


def pot_broken():
    img, d = new_canvas()
    cylinder(d, 0, 0, 15, 0, 6, (150, 84, 52, 255), top_col=(58, 34, 24, 255))
    for (x, y, z) in [(-18, 10, 0), (16, 14, 0), (4, 22, 0), (-8, -14, 0)]:
        box(d, x, y, 7, 6, 0, 4 + (x % 3), (176, 100, 60, 255))
    finish("pot_broken", img)


def chest_closed():
    img, d = new_canvas()
    box(d, 0, 0, 56, 36, 0, 8, (140, 92, 46, 255), "wood")
    box(d, 0, 0, 56, 36, 8, 12, (160, 108, 54, 255), "wood")
    gold = (232, 190, 60, 255)
    line3(d, (0, -18, 12), (0, 18, 12), gold)
    line3(d, (-1, 18, 12), (-1, 18, 0), gold)
    line3(d, (1, 18, 12), (1, 18, 0), gold)
    box(d, 0, 17, 6, 3, 5, 9, gold, outline=False)
    finish("chest_closed", img)


def chest_open():
    img, d = new_canvas()
    box(d, 0, -17, 56, 4, 8, 24, (160, 108, 54, 255), "wood")       # raised lid at the back
    box(d, 0, 0, 56, 36, 0, 8, (140, 92, 46, 255), "wood")
    inner = [P(-24, -14, 8), P(24, -14, 8), P(24, 14, 8), P(-24, 14, 8)]
    d.polygon(inner, fill=(38, 24, 16, 255))
    finish("chest_open", img)


def barrel():
    img, d = new_canvas()
    cylinder(d, 0, 0, 18, 0, 30, (150, 100, 52, 255), top_col=(120, 78, 40, 255), hoops=(5, 24))
    finish("barrel", img)


def table():
    img, d = new_canvas()
    for (x, y) in [(-27, -17), (27, -17), (-27, 17), (27, 17)]:
        box(d, x, y, 5, 5, 0, 11, DWOOD)
    box(d, 0, 0, 68, 44, 11, 14, (160, 108, 56, 255), "wood")
    finish("table", img)


def board(note):
    img, d = new_canvas()
    for y in (-30, 30):
        box(d, 0, y, 5, 5, 0, 38, DWOOD)
    box(d, 0, 0, 5, 68, 16, 44, (128, 90, 52, 255), "wood")
    if note:
        paper = (244, 238, 214, 255)
        d.polygon([P(2.6, -14, 40), P(2.6, 14, 40), P(2.6, 14, 21), P(2.6, -14, 21)], fill=paper, outline=(150, 140, 110, 255))
        for zz in (36, 32, 28, 24):
            line3(d, (2.6, -10, zz), (2.6, 10, zz), (120, 110, 90, 255))
        d.point(P(2.6, 0, 42), fill=(200, 50, 50, 255))
    finish("board_note" if note else "board_empty", img)


def cart():
    img, d = new_canvas()
    box(d, 0, 0, 60, 36, 4, 15, (110, 124, 140, 255), "wood")
    d.polygon([P(-26, -14, 15), P(26, -14, 15), P(26, 14, 15), P(-26, 14, 15)], fill=(40, 46, 56, 255))
    for x in (-18, 18):
        ellipse(d, P(x, 18, 4), 3.4, 3.4, (40, 40, 46, 255), (20, 20, 24, 255))
    line3(d, (-30, -10, 13), (-44, -10, 24), (90, 90, 100, 255))
    line3(d, (-30, 10, 13), (-44, 10, 24), (90, 90, 100, 255))
    finish("cart", img)


def block_counter():
    img, d = new_canvas()
    box(d, 0, 0, 56, 36, 0, 12, (112, 112, 122, 255), "stone")
    box(d, 0, 0, 56, 36, 12, 15, (176, 176, 186, 255))
    finish("block_counter", img)


def block_bar():
    img, d = new_canvas()
    box(d, 0, 0, 56, 48, 0, 12, (130, 84, 44, 255), "wood")
    box(d, 0, 0, 56, 48, 12, 15, (92, 58, 30, 255))
    box(d, 10, 6, 6, 6, 15, 21, (230, 200, 120, 255), outline=True)   # mug
    finish("block_bar", img)


def block_ktable():
    img, d = new_canvas()
    box(d, 0, 0, 56, 84, 0, 12, (120, 84, 50, 255), "wood")
    top = [P(-28, -42, 12), P(28, -42, 12), P(28, 42, 12), P(-28, 42, 12)]
    d.polygon(top, fill=(214, 214, 224, 255))
    for yy in range(-36, 42, 12):
        d.polygon([P(-28, yy, 12), P(28, yy, 12), P(28, yy + 6, 12), P(-28, yy + 6, 12)], fill=(196, 70, 70, 255))
    finish("block_ktable", img)


def block_stove():
    img, d = new_canvas()
    box(d, 0, -14, 20, 20, 24, 46, (62, 62, 68, 255), "stone")      # chimney
    box(d, 0, 0, 56, 56, 0, 24, (72, 72, 80, 255), "stone")
    d.polygon([P(-16, 28.1, 17), P(16, 28.1, 17), P(16, 28.1, 4), P(-16, 28.1, 4)], fill=(30, 20, 20, 255))
    d.polygon([P(-11, 28.2, 14), P(11, 28.2, 14), P(11, 28.2, 6), P(-11, 28.2, 6)], fill=(238, 130, 34, 255))
    finish("block_stove", img)


# ------------------------------------------------------------------ village props
def crate_full():
    img, d = new_canvas()
    box(d, 0, 0, 30, 30, 0, 20, (168, 124, 66, 255), "wood")
    line3(d, (-15, 15, 10), (15, 15, 10), (110, 76, 40, 255))
    line3(d, (15, 15, 10), (15, -15, 10), (90, 62, 32, 255))
    finish("crate_full", img)


def crate_broken():
    img, d = new_canvas()
    for (x, y, w, h) in [(-8, 4, 14, 5), (7, 8, 12, 4), (-2, -8, 16, 4), (10, -6, 5, 12)]:
        box(d, x, y, w, h, 0, 3, (150, 108, 56, 255))
    box(d, -6, 12, 10, 4, 0, 6, (120, 84, 44, 255))
    finish("crate_broken", img)


def tree():
    img, d = new_canvas()
    cylinder(d, 0, 0, 5, 0, 26, (110, 76, 42, 255))
    for (dx, dy, r) in [(-11, 30, 10), (10, 31, 10), (0, 42, 12), (-4, 53, 10), (7, 49, 10)]:
        ellipse(d, (CX + dx, CY - dy), r, r * 0.9, (60, 130, 56, 255), (40, 90, 40, 255))
    ellipse(d, (CX - 3, CY - 44), 7, 6, (84, 160, 70, 255))
    finish("tree", img)


def well():
    img, d = new_canvas()
    cylinder(d, 0, 0, 22, 0, 16, (140, 140, 150, 255), top_col=(30, 50, 80, 255))
    box(d, -20, -2, 4, 4, 16, 46, (110, 76, 42, 255))
    box(d, 20, -2, 4, 4, 16, 46, (110, 76, 42, 255))
    box(d, 0, -2, 50, 8, 44, 49, (150, 70, 60, 255))
    finish("well", img)


def block_stall():
    img, d = new_canvas()
    box(d, 0, -14, 4, 4, 0, 40, DWOOD)
    box(d, 0, 0, 56, 40, 0, 13, (150, 100, 55, 255), "wood")
    box(d, 0, 0, 56, 40, 13, 16, (120, 80, 44, 255))
    for x in (-26, 26):
        box(d, x, 16, 4, 4, 16, 40, DWOOD)
    box(d, 0, 0, 56, 44, 40, 44, (205, 70, 60, 255))
    for xx in range(-24, 28, 16):
        box(d, xx, 0, 8, 44, 40, 44, (240, 232, 220, 255), outline=False)
    finish("block_stall", img)


def block_smithy():
    img, d = new_canvas()
    box(d, 0, 0, 56, 56, 0, 14, (86, 86, 94, 255), "stone")
    box(d, -6, 0, 30, 10, 14, 20, (50, 50, 56, 255))        # anvil
    box(d, -20, 0, 10, 8, 14, 17, (50, 50, 56, 255))
    d.polygon([P(8, -14, 14), P(24, -14, 14), P(24, 14, 14), P(8, 14, 14)], fill=(230, 110, 30, 255))   # glowing coals
    finish("block_smithy", img)


# ------------------------------------------------------------------ ascii sprites
PAL = {
    "k": (27, 22, 32), "s": (241, 201, 160), "S": (214, 160, 120), "h": (90, 58, 34), "H": (62, 40, 24),
    "y": (232, 192, 74), "b": (63, 116, 196), "B": (40, 74, 133), "w": (242, 239, 230), "g": (154, 160, 170),
    "G": (100, 106, 118), "r": (196, 58, 58), "R": (138, 36, 36), "n": (138, 90, 42), "N": (90, 58, 26),
    "Y": (224, 176, 48), "p": (78, 168, 58), "P": (46, 106, 36), "e": (30, 24, 34), "o": (240, 140, 40),
    "m": (200, 100, 100), "l": (200, 220, 255), "t": (222, 190, 130), "T": (176, 140, 84), "q": (250, 170, 190),
}


def ascii_sprite(name, rows, anchor_x=None):
    w = max(len(r) for r in rows)
    img = Image.new("RGBA", (w, len(rows)), (0, 0, 0, 0))
    for y, row in enumerate(rows):
        for x, ch in enumerate(row):
            if ch != "." and ch in PAL:
                img.putpixel((x, y), PAL[ch] + (255,))
    big = img.resize((w * SCALE, len(rows) * SCALE), Image.NEAREST)
    big.save(os.path.join(OUT, name + ".png"))
    anchors[name] = (round((anchor_x if anchor_x is not None else w / 2) * SCALE), len(rows) * SCALE)


PELL = [
    "....kkkkkk....",
    "...khhhhhhk...",
    "..khhhhhhhhk..",
    "..khssssssk...",
    "..ksseessek...",
    "..kssssssssk..",
    "...kssmmssk...",
    "....kssssk..Y.",
    "...kbbbbbbk.nY",
    "..kbbbbbbbbknY",
    ".ksbbnbbbbbskn",
    ".ksbbbnbbbbsNn",
    ".kssbbbbbbbsNk",
    "..kkbbbbbbbkNk",
    "...kBBBBBBBkN.",
    "...kBBBBBBBkN.",
    "...kBBkkBBBkN.",
    "...kkk..kkkkN.",
    "...kNNk.kNNk..",
    "..kNNNk.kNNNk.",
    "..kkkkk.kkkkk.",
]

HERO = [
    ".....kkkkkk.....",
    "....kyyyyyyk....",
    "...kyyyyyyyyk...",
    "..kyyssssssyyk..",
    "..kyseessseyyk..",
    "...kssssssssk...",
    "....ksssmssk....",
    ".kk.kkssssk.....",
    "kRRkkgggggkkl...",
    "kRRkgggwgggkkl..",
    "kRRRkgggggggkl..",
    "kRRRkgwgggwgkl..",
    ".kRRkgggggggkl..",
    ".kRRkkggggkkgl..",
    "..kRkgggggggNk..",
    "..kkkGGGGGGGkk..",
    "....kGGkkGGGk...",
    "....kGGk.kGGk...",
    "....kNNk.kNNk...",
    "...kNNNk.kNNNk..",
    "...kkkkk.kkkkk..",
]

INNKEEPER = [
    "....kkkk....",
    "...khhhhk...",
    "..khhhhhhk..",
    "..khssssshk.",
    "..ksessess..",
    "...kssmssk..",
    "....ksssk...",
    "...krrrrrk..",
    "..krrwwwrrk.",
    ".ksrrwwwrrsk",
    ".ksrwwwwwrsk",
    "..krwwwwwrk.",
    "..krwwwwwrk.",
    "..kkrrrrrkk.",
]

GRUB_OK = [
    "kk........kk",
    "kpk.kkkk.kpk",
    ".kpkpppppkpk",
    "..kpppppppk.",
    "..kpeepeepk.",
    "..kppppppPk.",
    "..kpkwwkpPk.",
    "..kppppppPk.",
    "...kpPPPPk..",
    "...kpk.kpk..",
    "...kkk.kkk..",
]

GRUB_OUT = [
    "............",
    "............",
    "kk........kk",
    "kpk.kkkk.kpk",
    ".kpkpppppkpk",
    "..kpppppppk.",
    "..kpxppxppk.",
    "..kppppppPk.",
    ".kppkwwkpPPk",
    ".kkpPPPPPkk.",
    "..kkkkkkkk..",
]
PAL["x"] = (20, 40, 16)

ITEMS = {
    "item_coin": [
        "..kkkk..", ".kYYYYk.", "kYYyyYYk", "kYyYYyYk", "kYyYYyYk", "kYYyyYYk", ".kYYYYk.", "..kkkk..",
    ],
    "item_sword": [
        "......kk", ".....kgk", "....kgwk", "...kgwk.", "..kgwk..", "kkgwk...", "kNkk....", "kNk.....", ".kk.....",
    ],
    "item_bread": [
        "..kkkkk..", ".kttTttk.", "ktTtttTtk", "kttTttttk", ".kkkkkkk.",
    ],
    "item_potion": [
        "..kk..", "..kw..", "..kk..", ".krrk.", "krrlrk", "krrrrk", ".kkkk.",
    ],
    "item_letter": [
        "kkkkkkkk", "kwwwwwwk", "kwwrrwwk", "kwwrrwwk", "kwwwwwwk", "kkkkkkkk",
    ],
    "item_cloth": [
        "..kkkk..", ".kggggk.", "kgGgggGk", "kgggGggk", ".kkkkkk.",
    ],
    "item_sack": [
        "..kkk...", ".kTTk...", "kTTTTk..", "kTTTTTk.", "kTTNTTk.", ".kkkkk..",
    ],
    "item_gift": [
        "..kqqk..", ".kqkkqk.", "kqqqqqqk", "kqqrrqqk", "krrrrrrk", "kqqrrqqk", "kkkkkkkk",
    ],
}


def write_data():
    lines = ["# Generated by tools/make_sprites.py - do not edit by hand.", "extends RefCounted", "", "const ANCHORS := {"]
    for k in sorted(anchors):
        lines.append('\t"%s": Vector2(%d, %d),' % (k, anchors[k][0], anchors[k][1]))
    lines.append("}")
    open("scripts/sprite_data.gd", "w").write("\n".join(lines) + "\n")


def main():
    os.makedirs(OUT, exist_ok=True)
    for fn in (pot_full, pot_broken, chest_closed, chest_open, barrel, table, cart,
               block_counter, block_bar, block_ktable, block_stove):
        fn()
    board(False)
    board(True)
    ascii_sprite("pell", PELL, 6)
    ascii_sprite("hero", HERO, 7)
    ascii_sprite("innkeeper", INNKEEPER)
    ascii_sprite("grub_ok", GRUB_OK)
    ascii_sprite("grub_out", GRUB_OUT)
    for k, rows in ITEMS.items():
        ascii_sprite(k, rows)
    for fn in (crate_full, crate_broken, tree, well, block_stall, block_smithy):
        fn()
    for name, mapping in {
        "tilly": {"r": "p", "h": "y"},
        "mara": {"r": "n", "w": "T", "h": "H"},
        "mayor": {"r": "B", "w": "Y", "h": "g"},
        "wenna": {"r": "G", "w": "g", "h": "g"},
    }.items():
        ascii_sprite(name, ["".join(mapping.get(c, c) for c in row) for row in INNKEEPER])
    write_data()
    print("wrote", len(anchors), "sprites")


if __name__ == "__main__":
    main()
