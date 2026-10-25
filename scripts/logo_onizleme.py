#!/usr/bin/env python3
"""Kodmoz Picture — logo önizlemesi (Swift'teki çizimin birebir vektörel eşi).

Swift tarafı (LogoRenderer.swift) aynı geometriyi NSBezierPath ile çizer;
bu betik yalnızca README/önizleme için PNG üretir.
"""
import os
import sys

from PIL import Image, ImageDraw

S = 4              # supersampling
BASE = 1024
W = BASE * S

YESIL_ACIK = (74, 222, 128)
YESIL_KOYU = (21, 128, 61)


def grad_dikey(boyut, ust, alt):
    im = Image.new('RGB', (1, boyut))
    for y in range(boyut):
        t = y / max(1, boyut - 1)
        im.putpixel((0, y), tuple(int(ust[i] + (alt[i] - ust[i]) * t) for i in range(3)))
    return im.resize((boyut, boyut), Image.BILINEAR)


def ciz(boyut=1024, seffaf=False):
    W = boyut * S
    tuval = Image.new('RGBA', (W, W), (0, 0, 0, 0))
    # --- squircle zemin + gradyan
    zemin = Image.new('RGBA', (W, W), (0, 0, 0, 0))
    g = grad_dikey(W, YESIL_ACIK, YESIL_KOYU).convert('RGBA')
    maske = Image.new('L', (W, W), 0)
    md = ImageDraw.Draw(maske)
    m = int(W * 0.02)
    md.rounded_rectangle([m, m, W - m, W - m], radius=int(W * 0.225), fill=255)
    zemin.paste(g, (0, 0), maske)
    # üst ışık bandı
    bant = Image.new('RGBA', (W, W), (0, 0, 0, 0))
    bd = ImageDraw.Draw(bant)
    bd.rectangle([0, 0, W, W // 2], fill=(255, 255, 255, 26))
    zemin = Image.alpha_composite(zemin, Image.composite(bant, Image.new('RGBA', (W, W), (0, 0, 0, 0)), maske))
    tuval = Image.alpha_composite(tuval, zemin)

    d = ImageDraw.Draw(tuval)
    inset = 0.20 * W
    cerceve = [inset, inset, W - inset, W - inset]
    lw = int(max(2, 0.045 * W))
    kol = (cerceve[2] - cerceve[0]) * 0.30

    def cizgi(p1, p2):
        d.line([p1, p2], fill=(255, 255, 255, 255), width=lw, joint='curve')

    # vizör köşeleri
    cizgi((cerceve[0], cerceve[1] + kol), (cerceve[0], cerceve[1]))
    cizgi((cerceve[0], cerceve[1]), (cerceve[0] + kol, cerceve[1]))
    cizgi((cerceve[2] - kol, cerceve[1]), (cerceve[2], cerceve[1]))
    cizgi((cerceve[2], cerceve[1]), (cerceve[2], cerceve[1] + kol))
    cizgi((cerceve[2], cerceve[3] - kol), (cerceve[2], cerceve[3]))
    cizgi((cerceve[2], cerceve[3]), (cerceve[2] - kol, cerceve[3]))
    cizgi((cerceve[0] + kol, cerceve[3]), (cerceve[0], cerceve[3]))
    cizgi((cerceve[0], cerceve[3]), (cerceve[0], cerceve[3] - kol))

    # lens
    cx, cy = W // 2, W // 2
    r = 0.175 * W
    d.ellipse([cx - r, cy - r, cx + r, cy + r], fill=(255, 255, 255, 255))
    r2 = r * 0.62
    d.ellipse([cx - r2, cy - r2, cx + r2, cy + r2], fill=YESIL_KOYU + (235,))
    rr = r * 0.20
    hx, hy = cx - r * 0.42, cy + r * 0.30
    d.ellipse([hx - rr, hy - rr, hx + rr, hy + rr], fill=(255, 255, 255, 220))

    return tuval.resize((boyut, boyut), Image.LANCZOS)


def menu_simge(boyut=64):
    """Menü çubuğu simgesi (template): siyah + alfa."""
    W = boyut * S
    im = Image.new('RGBA', (W, W), (0, 0, 0, 0))
    d = ImageDraw.Draw(im)
    s = W
    lw = int(max(1.4 * S, s * 0.085))
    inset = s * 0.14
    x0, y0 = inset, inset * 1.15
    x1, y1 = s - inset, s - inset * 1.15
    kol = (x1 - x0) * 0.34
    S_ = (0, 0, 0, 255)
    for (p1, p2) in [((x0, y1 - kol), (x0, y1)), ((x0, y1), (x0 + kol, y1)),
                     ((x1 - kol, y1), (x1, y1)), ((x1, y1), (x1, y1 - kol)),
                     ((x1, y0 + kol), (x1, y0)), ((x1, y0), (x1 - kol, y0)),
                     ((x0 + kol, y0), (x0, y0)), ((x0, y0), (x0, y0 + kol))]:
        d.line([p1, p2], fill=S_, width=lw, joint='curve')
    cx = cy = s / 2
    r = s * 0.20
    d.ellipse([cx - r, cy - r, cx + r, cy + r], fill=S_)
    hole = r * 0.44
    d.ellipse([cx - hole, cy - hole, cx + hole, cy + hole], fill=(0, 0, 0, 0))
    return im.resize((boyut, boyut), Image.LANCZOS)


def main():
    cikti = sys.argv[1] if len(sys.argv) > 1 else '.'
    os.makedirs(cikti, exist_ok=True)
    ciz(1024).save(os.path.join(cikti, 'logo-1024.png'))
    ciz(512).save(os.path.join(cikti, 'logo-512.png'))
    ciz(128).save(os.path.join(cikti, 'logo-128.png'))
    # menü çubuğu simgesi: koyu ve açık zemin üzerinde önizleme
    m = menu_simge(64)
    oniz = Image.new('RGB', (300, 140), (28, 28, 30))
    oniz.paste(m, (40, 38), m)
    acik = Image.new('RGB', (300, 140), (242, 242, 245))
    acik.paste(m, (40, 38), m)
    birlesik = Image.new('RGB', (600, 140))
    birlesik.paste(oniz, (0, 0))
    birlesik.paste(acik, (300, 0))
    birlesik.save(os.path.join(cikti, 'menubar-onizleme.png'))
    menu_simge(18).save(os.path.join(cikti, 'menubar.png'))
    menu_simge(36).save(os.path.join(cikti, 'menubar@2x.png'))
    print('OK: logo-1024.png, logo-512.png, logo-128.png, menubar-onizleme.png')


if __name__ == '__main__':
    main()
