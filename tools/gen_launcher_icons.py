#!/usr/bin/env python3
"""Legado MD3 应用图标生成器。

设计：钢蓝渐变圆角底 + 白色打开的书 + 琥珀书签（扁平风，与 App 主题一致）。
绘制 1024 母图后输出全部 Android 启动图标资源：

  assets/icon/icon.png              1024 完整图标（圆角已烘焙，传统图标用）
  assets/icon/icon_bg.png           1024 全出血渐变底（备用）
  assets/icon/icon_foreground.png   1024 透明底图形（自适应 foreground，安全区内）
  assets/icon/icon_monochrome.png   1024 单色剪影（Android 13+ themed 图标）
  assets/icon/icon_512.png          512  Play Store 用

  android/app/src/main/res/mipmap-<dpi>/ic_launcher.png | ic_launcher_round.png
      传统图标（API < 26 回退）：48/72/96/144/192 px
  android/app/src/main/res/drawable-<dpi>/ic_launcher_foreground.png | ic_launcher_monochrome.png
      自适应图层（108dp）：108/162/216/324/432 px
  android/app/src/main/res/drawable/ic_launcher_background.xml
      自适应背景：竖向渐变
  android/app/src/main/res/mipmap-anydpi-v26/ic_launcher.xml | ic_launcher_round.xml
      自适应图标声明（含 monochrome，API 33+ 生效，旧系统自动忽略）

用法：python3 tools/gen_launcher_icons.py
依赖：Pillow（pip install pillow）
"""
import os
from PIL import Image, ImageDraw, ImageFilter

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
ICON_DIR = os.path.join(ROOT, "assets", "icon")
RES_DIR = os.path.join(ROOT, "android", "app", "src", "main", "res")

SIZE = 1024

# ---------- 调色板（与 lib/constant/app_theme.dart 钢蓝主题一致） ----------
BG_TOP = (0x55, 0x70, 0x8C)      # 渐变顶
BG_BOTTOM = (0x2C, 0x42, 0x56)   # 渐变底
PAPER = (0xFF, 0xFF, 0xFF)       # 书页白
PAPER_LINE = (0xB9, 0xC9, 0xD8)  # 页面文字线
SPINE = (0xD8, 0xE2, 0xEA)       # 书脊亮线
RIBBON = (0xE8, 0xA3, 0x3D)      # 琥珀书签

# 传统图标密度 -> 像素（48dp 基准）
LEGACY_DENSITIES = {"mdpi": 48, "hdpi": 72, "xhdpi": 96, "xxhdpi": 144, "xxxhdpi": 192}
# 自适应图层密度 -> 像素（108dp 基准）
ADAPTIVE_DENSITIES = {"mdpi": 108, "hdpi": 162, "xhdpi": 216, "xxhdpi": 324, "xxxhdpi": 432}


def lerp(a, b, t):
    return tuple(int(a[i] + (b[i] - a[i]) * t) for i in range(3))


def gradient(size, corner_radius=None, highlight=True):
    """竖向渐变底；corner_radius 非空则裁圆角；highlight 叠加左上柔光。"""
    img = Image.new("RGBA", (size, size))
    px = img.load()
    for y in range(size):
        c = lerp(BG_TOP, BG_BOTTOM, y / (size - 1))
        for x in range(size):
            px[x, y] = c + (255,)
    if highlight:
        glow = Image.new("L", (size, size), 0)
        ImageDraw.Draw(glow).ellipse(
            [size * 0.08, size * 0.02, size * 0.85, size * 0.72], fill=46)
        glow = glow.filter(ImageFilter.GaussianBlur(size * 0.10))
        white = Image.new("RGBA", (size, size), (255, 255, 255, 255))
        img = Image.composite(white, img, glow.point(lambda v: int(v * 0.5)))
    if corner_radius:
        mask = Image.new("L", (size, size), 0)
        ImageDraw.Draw(mask).rounded_rectangle(
            [0, 0, size - 1, size - 1], radius=corner_radius, fill=255)
        img.putalpha(mask)
    return img


def cubic(p0, p1, p2, p3, n=40):
    """采样三次贝塞尔曲线点列。"""
    pts = []
    for i in range(n + 1):
        t = i / n
        mt = 1 - t
        pts.append((
            mt**3 * p0[0] + 3 * mt**2 * t * p1[0] + 3 * mt * t**2 * p2[0] + t**3 * p3[0],
            mt**3 * p0[1] + 3 * mt**2 * t * p1[1] + 3 * mt * t**2 * p2[1] + t**3 * p3[1],
        ))
    return pts


def draw_book(draw, scale=1.0, ox=0.0, oy=0.0, ink=PAPER):
    """绘制打开的书：左右两页 + 书脊 + 文字线 + 琥珀书签。ink 可整体换色（单色剪影用）。"""
    def T(p):
        return (ox + p[0] * scale, oy + p[1] * scale)

    line = ink if ink == (0, 0, 0) else PAPER_LINE  # 单色模式下文字线并入剪影
    spine_ink = ink if ink == (0, 0, 0) else SPINE

    # 左页：顶弧（外缘上扬）-> 左缘外凸 -> 底弧（下垂）-> 书脊直边
    left = cubic((512, 402), (430, 380), (360, 366), (296, 372))
    left += cubic((296, 372), (284, 470), (292, 560), (308, 636))
    left += cubic((308, 636), (380, 662), (450, 654), (512, 624))
    left += [(512, 402)]
    draw.polygon([T(p) for p in left], fill=ink + (255,))

    # 右页（镜像）
    right = cubic((512, 402), (594, 380), (664, 366), (728, 372))
    right += cubic((728, 372), (740, 470), (732, 560), (716, 636))
    right += cubic((716, 636), (644, 662), (574, 654), (512, 624))
    right += [(512, 402)]
    draw.polygon([T(p) for p in right], fill=ink + (255,))

    # 书脊中线 + 两侧内缘线（页面厚度）
    draw.line([T((512, 404)), T((512, 623))], fill=spine_ink + (255,),
              width=max(1, int(9 * scale)))
    draw.line([T((526, 412)), T((526, 616))], fill=spine_ink + (255,),
              width=max(1, int(5 * scale)))
    draw.line([T((498, 412)), T((498, 616))], fill=spine_ink + (255,),
              width=max(1, int(5 * scale)))

    # 页面文字线：每页 3 条圆角短线，长度错落
    for (x0, widths) in ((340, (128, 108, 84)), (560, (128, 108, 84))):
        for i, w in enumerate(widths):
            y = 452 + i * 46
            draw.rounded_rectangle([T((x0, y)), T((x0 + w, y + 15))],
                                   radius=7 * scale, fill=line + (255,))

    # 琥珀书签：从书芯顶部垂下的缎带（底部 V 型缺口）；单色模式随剪影
    ribbon = [(552, 328), (598, 328), (598, 408), (575, 430), (552, 408)]
    draw.polygon([T(p) for p in ribbon],
                 fill=(ink if ink == (0, 0, 0) else RIBBON) + (255,))


def make_master():
    """完整图标：圆角渐变底 + 图形（书本原始包围盒中心约 (512,495)，放大 1.08 并对齐画布中心）。"""
    img = gradient(SIZE, corner_radius=int(SIZE * 0.225))
    draw = ImageDraw.Draw(img)
    s = 1.08
    draw_book(draw, scale=s, ox=512 - 512 * s, oy=510 - 495 * s)
    return img


def make_layer(scale_ratio, ink=None):
    """透明底图形层：scale_ratio 控制图形占画布比例（自适应安全区）。"""
    img = Image.new("RGBA", (SIZE, SIZE), (0, 0, 0, 0))
    draw = ImageDraw.Draw(img)
    s = scale_ratio
    ox = (1 - s) / 2 * SIZE
    draw_book(draw, scale=s, ox=ox, oy=ox, ink=ink or PAPER)
    return img


def circular(img):
    """圆形裁切（传统 round 图标用）。"""
    mask = Image.new("L", img.size, 0)
    ImageDraw.Draw(mask).ellipse([0, 0, img.size[0] - 1, img.size[1] - 1], fill=255)
    out = img.copy()
    out.putalpha(mask)
    return out


def save_resized(img, path, size):
    os.makedirs(os.path.dirname(path), exist_ok=True)
    img.resize((size, size), Image.LANCZOS).save(path)


def write_xml(path, content):
    os.makedirs(os.path.dirname(path), exist_ok=True)
    with open(path, "w", encoding="utf-8") as f:
        f.write(content)


ADAPTIVE_ICON_XML = """<?xml version="1.0" encoding="utf-8"?>
<adaptive-icon xmlns:android="http://schemas.android.com/apk/res/android">
    <background android:drawable="@drawable/ic_launcher_background" />
    <foreground android:drawable="@drawable/ic_launcher_foreground" />
    <monochrome android:drawable="@drawable/ic_launcher_monochrome" />
</adaptive-icon>
"""

BACKGROUND_XML = """<?xml version="1.0" encoding="utf-8"?>
<shape xmlns:android="http://schemas.android.com/apk/res/android" android:shape="rectangle">
    <gradient
        android:angle="270"
        android:startColor="#FF55708C"
        android:endColor="#FF2C4256"
        android:type="linear" />
</shape>
"""


def main():
    master = make_master()
    foreground = make_layer(0.62)
    monochrome = make_layer(0.62, ink=(0, 0, 0))

    # ---- 母图（存档 + Play Store） ----
    os.makedirs(ICON_DIR, exist_ok=True)
    master.save(os.path.join(ICON_DIR, "icon.png"))
    gradient(SIZE).save(os.path.join(ICON_DIR, "icon_bg.png"))
    foreground.save(os.path.join(ICON_DIR, "icon_foreground.png"))
    monochrome.save(os.path.join(ICON_DIR, "icon_monochrome.png"))
    save_resized(master, os.path.join(ICON_DIR, "icon_512.png"), 512)

    # ---- 传统图标（API < 26 回退） ----
    for dpi, px in LEGACY_DENSITIES.items():
        save_resized(master, os.path.join(RES_DIR, f"mipmap-{dpi}", "ic_launcher.png"), px)
        save_resized(circular(master), os.path.join(RES_DIR, f"mipmap-{dpi}", "ic_launcher_round.png"), px)

    # ---- 自适应图层（108dp） ----
    for dpi, px in ADAPTIVE_DENSITIES.items():
        save_resized(foreground, os.path.join(RES_DIR, f"drawable-{dpi}", "ic_launcher_foreground.png"), px)
        save_resized(monochrome, os.path.join(RES_DIR, f"drawable-{dpi}", "ic_launcher_monochrome.png"), px)

    # ---- 自适应背景与声明 ----
    write_xml(os.path.join(RES_DIR, "drawable", "ic_launcher_background.xml"), BACKGROUND_XML)
    write_xml(os.path.join(RES_DIR, "mipmap-anydpi-v26", "ic_launcher.xml"), ADAPTIVE_ICON_XML)
    write_xml(os.path.join(RES_DIR, "mipmap-anydpi-v26", "ic_launcher_round.xml"), ADAPTIVE_ICON_XML)
    print("launcher icons generated OK")


if __name__ == "__main__":
    main()
