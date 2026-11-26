#!/usr/bin/env python3
"""Generate every Popkino brand image from branding/ (provisional logo, task T7).

Sources (see branding/README.md):
  branding/brand.json   name, backgroundColor, markColor, bannerText
  branding/mark.svg     the mark: one <path> on a 1024x1024 canvas, geometry only
  branding/banner.svg, background.svg, monochrome.svg   optional overrides (final logo)

Outputs (same paths as the upstream files they replace): assets/plezy.{png,svg},
assets/plezy_adaptive_foreground.svg, Android launcher/banner/notification resources,
the iOS/macOS .icon bundles, the tvOS image stacks and top shelf images, and the Windows .ico.

The mark is rasterised with Pillow only (the path is flattened to polygons and
supersampled), so no librsvg or ImageMagick is needed unless banner.svg or
background.svg exist (then `rsvg-convert` renders them).

Usage, from the repository root:
    python3 -I scripts/fork/generate_brand_assets.py          # write
    python3 -I scripts/fork/generate_brand_assets.py --check  # compare, write nothing
"""

from __future__ import annotations

import io
import json
import re
import shutil
import struct
import subprocess
import sys
from pathlib import Path

try:
    from PIL import Image, ImageDraw, ImageFont
except ImportError:  # pragma: no cover
    sys.exit("Pillow is required: python3 -m pip install pillow (preferably in a local venv)")

ROOT = Path(__file__).resolve().parents[2]
BRANDING = ROOT / "branding"
RES = ROOT / "android/app/src/main/res"
FONT = ROOT / "assets/go-noto-current-regular.ttf"
TVOS = ROOT / "tvos/Runner/Assets.xcassets/AppIcon.brandassets"

CANVAS = 1024
# Mark scale (relative to the 1024 canvas) for icons that are not adaptive: the mark
# is only ~49% of the canvas, so full-bleed icons enlarge it.
FILL = 1.2
# Wide tvOS / Android TV tiles scale the canvas to this multiple of the tile height.
WIDE = 1.25


# ---------------------------------------------------------------- colours


def hex_rgb(value: str) -> tuple[int, int, int]:
    value = value.lstrip("#")
    return int(value[0:2], 16), int(value[2:4], 16), int(value[4:6], 16)


def load_brand() -> dict:
    brand = json.loads((BRANDING / "brand.json").read_text(encoding="utf-8"))
    brand["bg"] = hex_rgb(brand["backgroundColor"])
    brand["fg"] = hex_rgb(brand["markColor"])
    return brand


# ---------------------------------------------------------------- SVG path


def read_path_data(svg: Path) -> str:
    text = svg.read_text(encoding="utf-8")
    paths = re.findall(r'<path\b[^>]*?\bd="([^"]+)"', text)
    if len(paths) != 1:
        sys.exit(f"{svg}: exactly one <path d=...> expected, found {len(paths)}")
    return " ".join(paths[0].split())


_TOKEN = re.compile(r"([MmLlHhVvCcSsQqZz])|(-?(?:\d+\.?\d*|\.\d+)(?:[eE][-+]?\d+)?)")


def flatten(d: str, steps: int = 32) -> list[list[tuple[float, float]]]:
    """Flatten an SVG path (no arcs) into polygons, one per subpath."""
    tokens = [(m.group(1), m.group(2)) for m in _TOKEN.finditer(d)]
    polys: list[list[tuple[float, float]]] = []
    cur: list[tuple[float, float]] = []
    x = y = sx = sy = 0.0
    last_ctrl: tuple[float, float] | None = None
    i = 0
    cmd = ""

    def num() -> float:
        nonlocal i
        c, n = tokens[i]
        if n is None:
            raise ValueError(f"number expected in path near token {i}")
        i += 1
        return float(n)

    def cubic(p0, p1, p2, p3):
        for k in range(1, steps + 1):
            t = k / steps
            u = 1 - t
            cur.append(
                (
                    u**3 * p0[0] + 3 * u * u * t * p1[0] + 3 * u * t * t * p2[0] + t**3 * p3[0],
                    u**3 * p0[1] + 3 * u * u * t * p1[1] + 3 * u * t * t * p2[1] + t**3 * p3[1],
                )
            )

    while i < len(tokens):
        if tokens[i][0] is not None:
            cmd = tokens[i][0]
            i += 1
            if cmd in "Zz":
                if cur:
                    polys.append(cur)
                cur = []
                x, y = sx, sy
                last_ctrl = None
                continue
        rel = cmd.islower()
        c = cmd.upper()
        ox, oy = (x, y) if rel else (0.0, 0.0)
        if c == "M":
            if cur:
                polys.append(cur)
            x, y = num() + ox, num() + oy
            sx, sy = x, y
            cur = [(x, y)]
            cmd = "l" if rel else "L"  # implicit lineto after the first pair
            last_ctrl = None
        elif c == "L":
            x, y = num() + ox, num() + oy
            cur.append((x, y))
            last_ctrl = None
        elif c == "H":
            x = num() + ox
            cur.append((x, y))
            last_ctrl = None
        elif c == "V":
            y = num() + oy
            cur.append((x, y))
            last_ctrl = None
        elif c == "C":
            p1 = (num() + ox, num() + oy)
            p2 = (num() + ox, num() + oy)
            p3 = (num() + ox, num() + oy)
            cubic((x, y), p1, p2, p3)
            x, y = p3
            last_ctrl = p2
        elif c == "S":
            p1 = (2 * x - last_ctrl[0], 2 * y - last_ctrl[1]) if last_ctrl else (x, y)
            p2 = (num() + ox, num() + oy)
            p3 = (num() + ox, num() + oy)
            cubic((x, y), p1, p2, p3)
            x, y = p3
            last_ctrl = p2
        elif c == "Q":
            q = (num() + ox, num() + oy)
            p3 = (num() + ox, num() + oy)
            p1 = (x + 2 / 3 * (q[0] - x), y + 2 / 3 * (q[1] - y))
            p2 = (p3[0] + 2 / 3 * (q[0] - p3[0]), p3[1] + 2 / 3 * (q[1] - p3[1]))
            cubic((x, y), p1, p2, p3)
            x, y = p3
            last_ctrl = None
        else:
            raise ValueError(f"unsupported path command {cmd!r} (arcs must be converted to curves)")
    if cur:
        polys.append(cur)
    return polys


def signed_area(poly) -> float:
    return sum(
        poly[k][0] * poly[(k + 1) % len(poly)][1] - poly[(k + 1) % len(poly)][0] * poly[k][1]
        for k in range(len(poly))
    )


class Mark:
    """The mark as polygons on the 1024 canvas, rasterised to an L mask on demand."""

    def __init__(self, d: str):
        self.d = d
        self.polys = flatten(d)
        xs = [p[0] for poly in self.polys for p in poly]
        ys = [p[1] for poly in self.polys for p in poly]
        self.bbox = (min(xs), min(ys), max(xs), max(ys))
        self._cache: dict[int, Image.Image] = {}

    def mask(self, size: int) -> Image.Image:
        """Mask of the whole 1024 canvas rendered at `size` x `size` px."""
        if size in self._cache:
            return self._cache[size]
        ss = 4 if size <= 1200 else 2
        big = size * ss
        k = big / CANVAS
        m = Image.new("L", (big, big), 0)
        draw = ImageDraw.Draw(m)
        ref = signed_area(self.polys[0])
        for poly in self.polys:
            fill = 255 if (signed_area(poly) >= 0) == (ref >= 0) else 0
            draw.polygon([(px * k, py * k) for px, py in poly], fill=fill)
        m = m.resize((size, size), Image.LANCZOS)
        self._cache[size] = m
        return m

    def cropped_mask(self, height: int) -> tuple[Image.Image, int]:
        """Mask of the mark bbox only, scaled so the bbox is `height` px tall."""
        x0, y0, x1, y1 = self.bbox
        scale = height / (y1 - y0)
        size = round(CANVAS * scale)
        full = self.mask(size)
        box = (round(x0 * scale), round(y0 * scale), round(x1 * scale), round(y1 * scale))
        return full.crop(box), size


# ---------------------------------------------------------------- drawing helpers


def paste_mask(dest: Image.Image, color, mask: Image.Image, left: int, top: int) -> None:
    """Paste `color` through `mask` at (left, top), clipping to dest."""
    x0, y0 = max(left, 0), max(top, 0)
    x1, y1 = min(left + mask.width, dest.width), min(top + mask.height, dest.height)
    if x1 <= x0 or y1 <= y0:
        return
    part = mask.crop((x0 - left, y0 - top, x1 - left, y1 - top))
    dest.paste(color, (x0, y0, x1, y1), part)


def solid(size: tuple[int, int], rgb) -> Image.Image:
    return Image.new("RGB", size, rgb)


def mark_layer(size: tuple[int, int], mark: Mark, tile: int, rgb) -> Image.Image:
    """Transparent RGBA canvas with the mark centred, canvas scaled to `tile` px."""
    w, h = size
    alpha = Image.new("L", size, 0)
    paste_mask_alpha(alpha, mark.mask(tile), (w - tile) // 2, (h - tile) // 2)
    img = Image.new("RGBA", size, rgb + (0,))
    img.putalpha(alpha)
    return img


def paste_mask_alpha(alpha: Image.Image, mask: Image.Image, left: int, top: int) -> None:
    x0, y0 = max(left, 0), max(top, 0)
    x1, y1 = min(left + mask.width, alpha.width), min(top + mask.height, alpha.height)
    if x1 <= x0 or y1 <= y0:
        return
    alpha.paste(mask.crop((x0 - left, y0 - top, x1 - left, y1 - top)), (x0, y0))


def icon_on(bg: Image.Image, mark: Mark, tile: int, rgb) -> Image.Image:
    out = bg.convert("RGB")
    left, top = (out.width - tile) // 2, (out.height - tile) // 2
    paste_mask(out, rgb, mark.mask(tile), left, top)
    return out


def rounded_square(size: int, mark: Mark, brand: dict, radius: float = 0.22) -> Image.Image:
    ss = 4
    corner = Image.new("L", (size * ss, size * ss), 0)
    ImageDraw.Draw(corner).rounded_rectangle(
        (0, 0, size * ss - 1, size * ss - 1), radius=int(size * ss * radius), fill=255
    )
    corner = corner.resize((size, size), Image.LANCZOS)
    img = icon_on(solid((size, size), brand["bg"]), mark, round(size * FILL), brand["fg"]).convert("RGBA")
    img.putalpha(corner)
    return img


def rsvg(svg: Path, width: int, height: int) -> Image.Image:
    tool = shutil.which("rsvg-convert")
    if not tool:
        sys.exit(f"{svg.name} exists but rsvg-convert is missing: brew install librsvg (or remove the file)")
    out = subprocess.run(
        [tool, "-w", str(width), "-h", str(height), "-f", "png", str(svg)],
        check=True,
        capture_output=True,
    ).stdout
    return Image.open(io.BytesIO(out)).convert("RGBA")


def background(size: tuple[int, int], brand: dict) -> Image.Image:
    """Plain brand background, or a centred cover crop of branding/background.svg."""
    svg = BRANDING / "background.svg"
    if not svg.exists():
        return solid(size, brand["bg"])
    w, h = size
    side = max(w, h)
    img = rsvg(svg, side, side)
    left, top = (side - w) // 2, (side - h) // 2
    flat = Image.new("RGB", (w, h), brand["bg"])
    flat.paste(img.crop((left, top, left + w, top + h)), (0, 0), img.crop((left, top, left + w, top + h)))
    return flat


def banner(width: int, height: int, mark: Mark, brand: dict) -> Image.Image:
    svg = BRANDING / "banner.svg"
    if svg.exists():
        flat = solid((width, height), brand["bg"])
        img = rsvg(svg, width, height)
        flat.paste(img, (0, 0), img)
        return flat
    img = background((width, height), brand)
    f = height / 360
    mark_h = round(190 * f)
    mask, tile = mark.cropped_mask(mark_h)
    font = ImageFont.truetype(str(FONT), round(92 * f))
    text = brand["bannerText"]
    text_w = font.getlength(text)
    gap = 36 * f
    total = mask.width + gap + text_w
    left = round((width - total) / 2)
    top = round((height - mask.height) / 2)
    paste_mask(img, brand["fg"], mask, left, top)
    cap = -font.getbbox("P", anchor="ls")[1]
    draw = ImageDraw.Draw(img)
    draw.text((left + mask.width + gap, height / 2 + cap / 2), text, font=font, fill=brand["fg"], anchor="ls")
    return img


def notification(size: int, mark: Mark) -> Image.Image:
    pad = max(1, round(size / 12))
    mask, _ = mark.cropped_mask(size - 2 * pad)
    alpha = Image.new("L", (size, size), 0)
    paste_mask_alpha(alpha, mask, (size - mask.width) // 2, (size - mask.height) // 2)
    img = Image.new("RGBA", (size, size), (255, 255, 255, 0))
    img.putalpha(alpha)
    return img


# ---------------------------------------------------------------- text outputs


def vector_drawable(d: str, fill: str) -> str:
    return f"""<?xml version="1.0" encoding="UTF-8"?>
<vector xmlns:android="http://schemas.android.com/apk/res/android"
    android:height="108dp"
    android:width="108dp"
    android:viewportHeight="{CANVAS}"
    android:viewportWidth="{CANVAS}">
    <path
        android:fillColor="{fill}"
        android:pathData="{d}" />
</vector>
"""


def flat_svg(d: str, brand: dict, with_background: bool) -> str:
    rect = (
        f'<rect width="{CANVAS}" height="{CANVAS}" fill="{brand["backgroundColor"]}"/>' if with_background else ""
    )
    return (
        f'<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 {CANVAS} {CANVAS}">{rect}'
        f'<path fill="{brand["markColor"]}" d="{d}"/></svg>\n'
    )


def apple_layer_svg(mark: Mark, d: str, brand: dict) -> str:
    # Cropped to the mark bbox at half scale (the .icon layer is placed with scale 2).
    x0, y0, x1, y1 = mark.bbox
    w, h = (x1 - x0) / 2, (y1 - y0) / 2
    return (
        f'<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 {w:g} {h:g}">'
        f'<path fill="{brand["markColor"]}" transform="scale(0.5) translate({-x0:g} {-y0:g})" d="{d}"/></svg>\n'
    )


def apple_fill(brand: dict) -> str:
    r, g, b = (c / 255 for c in brand["bg"])
    return f"srgb:{r:.5f},{g:.5f},{b:.5f},1.00000"


# ---------------------------------------------------------------- binary helpers


def png_bytes(img: Image.Image) -> bytes:
    buf = io.BytesIO()
    img.save(buf, "PNG")
    return buf.getvalue()


def ico_bytes(images: list[Image.Image]) -> bytes:
    blobs = [png_bytes(im) for im in images]
    head = struct.pack("<HHH", 0, 1, len(images))
    offset = 6 + 16 * len(images)
    entries = b""
    for im, blob in zip(images, blobs):
        w = 0 if im.width >= 256 else im.width
        h = 0 if im.height >= 256 else im.height
        entries += struct.pack("<BBBBHHII", w, h, 0, 0, 1, 32, len(blob), offset)
        offset += len(blob)
    return head + entries + b"".join(blobs)


# ---------------------------------------------------------------- outputs


def outputs(brand: dict, mark: Mark, d: str, mono_d: str, mono: Mark):
    """Yield (relative path, Image | str | bytes)."""
    bg, fg = brand["bg"], brand["fg"]

    # Flutter assets.
    master = icon_on(background((CANVAS, CANVAS), brand), mark, round(CANVAS * FILL), fg)
    yield "assets/plezy.png", master.convert("RGBA")
    yield "assets/plezy.svg", flat_svg(d, brand, True)
    yield "assets/plezy_adaptive_foreground.svg", flat_svg(d, brand, False)

    # Android.
    yield "android/app/src/main/res/drawable/ic_launcher_foreground.xml", vector_drawable(d, "#FFFFFFFF")
    yield "android/app/src/main/res/drawable/ic_launcher_monochrome.xml", vector_drawable(mono_d, "#FFFFFFFF")
    for dens, px in (("mdpi", 48), ("hdpi", 72), ("xhdpi", 96), ("xxhdpi", 144), ("xxxhdpi", 192)):
        # Legacy (API 25) launcher icons; only xxxhdpi is in the plan, see compte rendu.
        yield f"android/app/src/main/res/mipmap-{dens}/ic_launcher.png", rounded_square(px, mark, brand)
    for dens, px in (("mdpi", 24), ("hdpi", 36), ("xhdpi", 48), ("xxhdpi", 72), ("xxxhdpi", 96)):
        yield f"android/app/src/main/res/drawable-{dens}/ic_stat_notification.png", notification(px, mono)
    for dens, (w, h) in (("xhdpi", (320, 180)), ("xxhdpi", (480, 270)), ("xxxhdpi", (640, 360))):
        yield f"android/app/src/main/res/drawable-{dens}/tv_banner.png", banner(w, h, mark, brand)

    # iOS and macOS Icon Composer bundles.
    layer = apple_layer_svg(mark, d, brand)
    for plat in ("ios", "macos"):
        base = f"{plat}/plezy.icon"
        yield f"{base}/Assets/plezy-cropped.svg", layer
        icon_json = (ROOT / base / "icon.json").read_text(encoding="utf-8")
        new = re.sub(r'("solid"\s*:\s*)"[^"]*"', lambda m: f'{m.group(1)}"{apple_fill(brand)}"', icon_json, count=1)
        yield f"{base}/icon.json", new

    # tvOS image stacks and top shelf.
    stacks = (
        ("App Icon.imagestack", "", ((400, 240), 1), ((800, 480), 2)),
        ("App Icon - App Store.imagestack", "", ((1280, 768), 1),),
    )
    for stack, _, *variants in stacks:
        for (size, scale) in variants:
            suffix = "" if scale == 1 else f"@{scale}x"
            tile = round(size[1] * WIDE)
            for name, img in (
                ("Back", background(size, brand)),
                ("Middle", Image.new("RGBA", size, (0, 0, 0, 0))),
                ("Front", mark_layer(size, mark, tile, fg)),
            ):
                yield f"tvos/Runner/Assets.xcassets/AppIcon.brandassets/{stack}/{name}.imagestacklayer/Content.imageset/{name}{suffix}.png", img
    for rel, size, mode in (
        ("Top Shelf Image.imageset/top-shelf.png", (1920, 720), "RGBA"),
        ("Top Shelf Image Wide.imageset/top-shelf-wide.png", (2320, 720), "RGB"),
        ("Top Shelf Image Wide.imageset/top-shelf-wide@2x.png", (4640, 1440), "RGB"),
    ):
        img = icon_on(background(size, brand), mark, round(size[1] * WIDE), fg)
        yield f"tvos/Runner/Assets.xcassets/AppIcon.brandassets/{rel}", img.convert(mode)

    # Windows.
    sizes = (16, 24, 32, 48, 64, 128, 256)
    yield "windows/runner/resources/app_icon.ico", ico_bytes([rounded_square(s, mark, brand) for s in sizes])


# ---------------------------------------------------------------- main


def encode(payload) -> bytes:
    if isinstance(payload, str):
        return payload.encode("utf-8")
    if isinstance(payload, bytes):
        return payload
    return png_bytes(payload)


def same(rel: str, path: Path, payload) -> bool:
    if not path.exists():
        return False
    new = encode(payload)
    old = path.read_bytes()
    if old == new:
        return True
    # PNG encoders differ across Pillow versions: compare decoded pixels instead.
    if isinstance(payload, Image.Image) and rel.endswith(".png"):
        try:
            cur = Image.open(io.BytesIO(old))
            return cur.size == payload.size and cur.convert("RGBA").tobytes() == payload.convert("RGBA").tobytes()
        except OSError:
            return False
    return False


def main(argv: list[str]) -> int:
    check = "--check" in argv
    unknown = [a for a in argv if a != "--check"]
    if unknown:
        print(__doc__)
        return 2
    if not FONT.exists():
        sys.exit(f"missing font {FONT}")
    brand = load_brand()
    d = read_path_data(BRANDING / "mark.svg")
    mark = Mark(d)
    mono_svg = BRANDING / "monochrome.svg"
    mono_d = read_path_data(mono_svg) if mono_svg.exists() else d
    mono = Mark(mono_d) if mono_svg.exists() else mark

    changed = []
    count = 0
    for rel, payload in outputs(brand, mark, d, mono_d, mono):
        count += 1
        path = ROOT / rel
        if same(rel, path, payload):
            continue
        changed.append(rel)
        if not check:
            path.parent.mkdir(parents=True, exist_ok=True)
            path.write_bytes(encode(payload))
    verb = "differ" if check else "written"
    print(f"{count} outputs, {len(changed)} {verb}")
    for rel in changed:
        print(f"  {rel}")
    return 1 if (check and changed) else 0


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))
