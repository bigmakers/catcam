#!/usr/bin/env python3
"""CATcam の App Store 用マーケティングスクショを生成する。
猫写真(NEWMOON 枠付き)を内側でクロップし、CATcam のレトロ配色背景 +
アプリの焼き込み風オーバーレイ(肉球の頭数バッジ・地名・日時)+ 機能見出しを合成。
出力: 1284x2778(iPhone 6.5インチ)。"""
from PIL import Image, ImageDraw, ImageFont
import os

W, H = 1284, 2778
OUT = "/Users/harasakidaisaku/catcam/store/screenshots/out-65"
os.makedirs(OUT, exist_ok=True)

FONT = "/System/Library/Fonts/Hiragino Sans GB.ttc"
def f(sz): return ImageFont.truetype(FONT, sz)

def lerp(a, b, t): return tuple(int(a[i] + (b[i]-a[i])*t) for i in range(3))

def gradient(draw):
    top, mid, bot = (0xF4,0xE6,0xCB), (0xE3,0xBE,0x88), (0x8A,0x5C,0x34)
    for y in range(H):
        t = y / H
        c = lerp(top, mid, t*2) if t < 0.5 else lerp(mid, bot, (t-0.5)*2)
        draw.line([(0,y),(W,y)], fill=c)

def rounded(draw, box, r, fill):
    draw.rounded_rectangle(box, radius=r, fill=fill)

def paw(draw, cx, cy, s, color):
    # 肉球: 主パッド + 指4つ
    draw.ellipse([cx-s*0.55, cy-s*0.15, cx+s*0.55, cy+s*0.75], fill=color)
    for dx, dy, rx in [(-0.55,-0.55,0.22),(-0.18,-0.78,0.22),(0.18,-0.78,0.22),(0.55,-0.55,0.22)]:
        draw.ellipse([cx+dx*s-rx*s, cy+dy*s-rx*s, cx+dx*s+rx*s, cy+dy*s+rx*s], fill=color)

def text_shadow(img, draw, pos, s, font, fill=(255,255,255), sh=(0,0,0,150)):
    x, y = pos
    # 影
    shadow = Image.new("RGBA", img.size, (0,0,0,0))
    sd = ImageDraw.Draw(shadow)
    sd.text((x+2, y+3), s, font=font, fill=sh)
    img.alpha_composite(shadow.filter.__self__ if False else shadow)
    draw.text((x, y), s, font=font, fill=fill)

def crop_inner(path):
    im = Image.open(path).convert("RGB")
    w, h = im.size
    # NEWMOON 枠を除いて内側の写真だけにする(下を多めに削る)
    box = (int(w*0.055), int(h*0.05), int(w*0.945), int(h*0.87))
    im = im.crop(box)
    # 中央正方形
    cw, ch = im.size; side = min(cw, ch)
    im = im.crop(((cw-side)//2, (ch-side)//2, (cw-side)//2+side, (ch-side)//2+side))
    return im

SHOTS = [
    dict(src="IMG_7474.JPG", head=["猫を、自動で", "数える。"],
         sub="Vision が猫を検出して頭数を記録", count="1匹"),
    dict(src="IMG_7475.JPG", head=["複数の猫も、", "まとめて。"],
         sub="何匹いても自動でカウント", count="3匹"),
    dict(src="IMG_7476.JPG", head=["向いた瞬間、", "自動シャッター。"],
         sub="鳴き声ボタンで振り向かせて", count="1匹"),
]
DL = "/Users/harasakidaisaku/Downloads"

for i, sh in enumerate(SHOTS, 1):
    base = Image.new("RGBA", (W, H), (0,0,0,255))
    d = ImageDraw.Draw(base)
    gradient(d)

    # 見出し
    ink = (74,46,24); sub_c = (104,70,40)
    hy = 150
    for line in sh["head"]:
        d.text((96, hy), line, font=f(82), fill=ink, stroke_width=1, stroke_fill=ink)
        hy += 104
    d.text((100, hy+8), sh["sub"], font=f(38), fill=sub_c)

    # 写真カード(ポラロイド風)
    cat = crop_inner(os.path.join(DL, sh["src"]))
    photo = 980
    card_x, card_y = (W-photo-40)//2, 700
    card = [card_x, card_y, card_x+photo+40, card_y+photo+220]
    rounded(d, card, 28, (252,247,238,255))
    cat = cat.resize((photo, photo), Image.LANCZOS)
    px, py = card_x+20, card_y+20
    base.paste(cat, (px, py))

    # オーバーレイ(写真の上、白文字+影)
    ov = Image.new("RGBA", (W, H), (0,0,0,0))
    od = ImageDraw.Draw(ov)
    # 頭数バッジ(左上、半透明黒カプセル + 肉球 + N匹)
    bx, by = px+28, py+28
    cnt = sh["count"]
    bw = 70 + od.textlength(cnt, font=f(46))
    od.rounded_rectangle([bx, by, bx+bw, by+76], radius=38, fill=(0,0,0,135))
    paw(od, bx+38, by+40, 26, (255,255,255,255))
    od.text((bx+66, by+14), cnt, font=f(46), fill=(255,255,255,255))
    # 地名・日時(写真左下)
    loc_y = py+photo-92
    od.text((px+30, loc_y), "Kagoshima, Japan", font=f(40), fill=(255,255,255,235),
            stroke_width=2, stroke_fill=(0,0,0,140))
    od.text((px+30, loc_y+48), "2026/06/12  31.60°N, 130.56°E", font=f(28),
            fill=(255,255,255,220), stroke_width=2, stroke_fill=(0,0,0,140))
    base.alpha_composite(ov)

    # カード下帯キャプション(肉球は描画)
    cap_y = card_y+photo+44
    paw(d, card_x+58, cap_y+28, 22, (90,60,34))
    d.text((card_x+92, cap_y), "この場所で " + sh["count"] + " を記録", font=f(40), fill=(60,40,22))

    # 下部ブランド: アイコン + アプリ名
    try:
        icon = Image.open("/Users/harasakidaisaku/catcam/CATcam/Assets.xcassets/AppIcon.appiconset/icon1024.png").convert("RGBA")
        icon = icon.resize((150,150), Image.LANCZOS)
        # 角丸マスク
        mask = Image.new("L", (150,150), 0); ImageDraw.Draw(mask).rounded_rectangle([0,0,150,150], radius=34, fill=255)
        base.paste(icon, ((W-150)//2, 2360), mask)
    except Exception:
        pass
    name = "CATcam"
    d.text(((W-d.textlength(name, font=f(56)))//2, 2540), name, font=f(56), fill=(74,46,24), stroke_width=1, stroke_fill=(74,46,24))

    out = os.path.join(OUT, f"catcam_{i}.png")
    base.convert("RGB").save(out, "PNG")
    print("✓", out, base.size)
print("done")
