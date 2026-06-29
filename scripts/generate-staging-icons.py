from __future__ import annotations

import json
from pathlib import Path

from PIL import Image, ImageDraw, ImageFont


ROOT = Path(__file__).resolve().parents[1]
SOURCE_DIR = ROOT / "assets" / "icon" / "source"
STAGING_DIR = ROOT / "assets" / "icon" / "staging"
ANDROID_STAGING_RES = ROOT / "android" / "app" / "src" / "staging" / "res"
FONT_PATH = ROOT / "fonts" / "SF-Pro-Display-Bold.otf"

BANNER_FILL = (239, 68, 68, 232)
BANNER_STROKE = (255, 255, 255, 230)
TEXT_FILL = (255, 255, 255, 255)
TEXT_SHADOW = (17, 24, 39, 160)
ANDROID_BACKGROUND = "#081B5A"


IOS_ICON_FILES: dict[str, int] = {
    "Icon-App-20x20@1x.png": 20,
    "Icon-App-20x20@2x.png": 40,
    "Icon-App-20x20@3x.png": 60,
    "Icon-App-29x29@1x.png": 29,
    "Icon-App-29x29@2x.png": 58,
    "Icon-App-29x29@3x.png": 87,
    "Icon-App-40x40@1x.png": 40,
    "Icon-App-40x40@2x.png": 80,
    "Icon-App-40x40@3x.png": 120,
    "Icon-App-50x50@1x.png": 50,
    "Icon-App-50x50@2x.png": 100,
    "Icon-App-57x57@1x.png": 57,
    "Icon-App-57x57@2x.png": 114,
    "Icon-App-60x60@2x.png": 120,
    "Icon-App-60x60@3x.png": 180,
    "Icon-App-72x72@1x.png": 72,
    "Icon-App-72x72@2x.png": 144,
    "Icon-App-76x76@1x.png": 76,
    "Icon-App-76x76@2x.png": 152,
    "Icon-App-83.5x83.5@2x.png": 167,
    "Icon-App-1024x1024@1x.png": 1024,
}

MACOS_ICON_FILES: dict[str, int] = {
    "app_icon_16.png": 16,
    "app_icon_32.png": 32,
    "app_icon_64.png": 64,
    "app_icon_128.png": 128,
    "app_icon_256.png": 256,
    "app_icon_512.png": 512,
    "app_icon_1024.png": 1024,
}

WINDOWS_ICON_FILES: dict[str, int] = {
    "app_icon_16.png": 16,
    "app_icon_32.png": 32,
    "app_icon_48.png": 48,
    "app_icon_64.png": 64,
    "app_icon_128.png": 128,
    "app_icon_256.png": 256,
}

ANDROID_MIPMAP_FILES: dict[str, int] = {
    "mipmap-mdpi": 48,
    "mipmap-hdpi": 72,
    "mipmap-xhdpi": 96,
    "mipmap-xxhdpi": 144,
    "mipmap-xxxhdpi": 192,
}

ANDROID_FOREGROUND_FILES: dict[str, int] = {
    "drawable-mdpi": 108,
    "drawable-hdpi": 162,
    "drawable-xhdpi": 216,
    "drawable-xxhdpi": 324,
    "drawable-xxxhdpi": 432,
}


def open_source(name: str) -> Image.Image:
    return Image.open(SOURCE_DIR / name).convert("RGBA")


def fit_square(image: Image.Image, size: int, *, remove_alpha: bool = False) -> Image.Image:
    resample = Image.Resampling.LANCZOS
    image = image.resize((size, size), resample)
    if remove_alpha:
        background = Image.new("RGBA", (size, size), (8, 27, 90, 255))
        background.alpha_composite(image)
        image = background
    return image.convert("RGB") if remove_alpha else image


def text_bbox(draw: ImageDraw.ImageDraw, text: str, font: ImageFont.FreeTypeFont) -> tuple[int, int]:
    left, top, right, bottom = draw.textbbox((0, 0), text, font=font)
    return right - left, bottom - top


def draw_staging_banner(base: Image.Image, *, text: str = "STAGING") -> Image.Image:
    size = base.width
    scale = 3
    work = base.resize((size * scale, size * scale), Image.Resampling.LANCZOS).convert("RGBA")
    overlay = Image.new("RGBA", work.size, (0, 0, 0, 0))
    draw = ImageDraw.Draw(overlay)

    w = work.width
    badge_x = int(w * 0.075)
    badge_y = int(w * 0.09)
    badge_w = int(w * 0.44)
    badge_h = int(w * 0.12)
    radius = int(badge_h * 0.34)
    stroke = max(4, int(w * 0.007))

    shadow_offset = max(3, int(w * 0.006))
    draw.rounded_rectangle(
        [badge_x + shadow_offset, badge_y + shadow_offset, badge_x + badge_w + shadow_offset, badge_y + badge_h + shadow_offset],
        radius=radius,
        fill=(15, 23, 42, 90),
    )
    draw.rounded_rectangle(
        [badge_x, badge_y, badge_x + badge_w, badge_y + badge_h],
        radius=radius,
        fill=BANNER_FILL,
    )
    draw.rounded_rectangle(
        [badge_x, badge_y, badge_x + badge_w, badge_y + badge_h],
        radius=radius,
        outline=BANNER_STROKE,
        width=stroke,
    )
    draw.line(
        [(badge_x + stroke * 2, badge_y + badge_h - stroke * 2), (badge_x + badge_w - stroke * 2, badge_y + badge_h - stroke * 2)],
        fill=BANNER_STROKE,
        width=max(2, stroke // 2),
    )

    font_size = int(w * 0.064)
    font = ImageFont.truetype(str(FONT_PATH), font_size)
    tracking = int(font_size * 0.055)

    total_w = sum(text_bbox(draw, ch, font)[0] for ch in text) + tracking * (len(text) - 1)
    cursor = badge_x + (badge_w - total_w) // 2
    text_y = badge_y + (badge_h - text_bbox(draw, text, font)[1]) // 2 - int(w * 0.008)
    for ch in text:
        ch_w, _ = text_bbox(draw, ch, font)
        draw.text((cursor + int(w * 0.004), text_y + int(w * 0.004)), ch, fill=TEXT_SHADOW, font=font)
        draw.text((cursor, text_y), ch, fill=TEXT_FILL, font=font)
        cursor += ch_w + tracking

    work.alpha_composite(overlay)
    return work.resize((size, size), Image.Resampling.LANCZOS)


def save_png(image: Image.Image, path: Path, size: int, *, remove_alpha: bool = False) -> None:
    path.parent.mkdir(parents=True, exist_ok=True)
    fit_square(image, size, remove_alpha=remove_alpha).save(path)


def copy_json(source: Path, target: Path) -> None:
    target.parent.mkdir(parents=True, exist_ok=True)
    target.write_text(json.dumps(json.loads(source.read_text()), indent=2) + "\n")


def write_android_xml() -> None:
    (ANDROID_STAGING_RES / "mipmap-anydpi-v26").mkdir(parents=True, exist_ok=True)
    (ANDROID_STAGING_RES / "mipmap-anydpi-v26" / "ic_launcher.xml").write_text(
        '<adaptive-icon xmlns:android="http://schemas.android.com/apk/res/android">\n'
        '  <background android:drawable="@color/ic_launcher_background"/>\n'
        '  <foreground android:drawable="@drawable/ic_launcher_foreground"/>\n'
        "</adaptive-icon>\n"
    )
    (ANDROID_STAGING_RES / "values").mkdir(parents=True, exist_ok=True)
    (ANDROID_STAGING_RES / "values" / "colors.xml").write_text(
        '<resources>\n'
        f'    <color name="ic_launcher_background">{ANDROID_BACKGROUND}</color>\n'
        "</resources>\n"
    )


def main() -> None:
    padded = draw_staging_banner(open_source("app_icon_padded.png"))
    foreground = draw_staging_banner(open_source("app_icon_foreground.png"))
    favicon = draw_staging_banner(open_source("app_icon_favicon.png"))

    save_png(padded, STAGING_DIR / "source" / "app_icon_master.png", 1024)
    save_png(padded, STAGING_DIR / "source" / "app_icon_padded.png", 1024)
    save_png(foreground, STAGING_DIR / "source" / "app_icon_foreground.png", 1024)
    save_png(favicon, STAGING_DIR / "source" / "app_icon_favicon.png", 1024)

    for directory, size in ANDROID_MIPMAP_FILES.items():
        save_png(padded, STAGING_DIR / "android" / directory / "ic_launcher.png", size)
        save_png(padded, ANDROID_STAGING_RES / directory / "ic_launcher.png", size)
    for directory, size in ANDROID_FOREGROUND_FILES.items():
        save_png(foreground, STAGING_DIR / "android" / directory / "ic_launcher_foreground.png", size)
        save_png(foreground, ANDROID_STAGING_RES / directory / "ic_launcher_foreground.png", size)
    save_png(padded, STAGING_DIR / "android" / "playstore" / "ic_launcher.png", 512)
    write_android_xml()

    ios_dir = STAGING_DIR / "ios" / "AppIcon.appiconset"
    for file_name, size in IOS_ICON_FILES.items():
        save_png(padded, ios_dir / file_name, size, remove_alpha=True)
    copy_json(ROOT / "ios" / "Runner" / "Assets.xcassets" / "AppIcon.appiconset" / "Contents.json", ios_dir / "Contents.json")

    macos_dir = STAGING_DIR / "macos" / "AppIcon.appiconset"
    for file_name, size in MACOS_ICON_FILES.items():
        save_png(padded, macos_dir / file_name, size)
    copy_json(
        ROOT / "macos" / "Runner" / "Assets.xcassets" / "AppIcon.appiconset" / "Contents.json",
        macos_dir / "Contents.json",
    )

    web_dir = STAGING_DIR / "web"
    save_png(favicon, web_dir / "favicon.png", 48)
    save_png(padded, web_dir / "icons" / "Icon-192.png", 192)
    save_png(padded, web_dir / "icons" / "Icon-512.png", 512)
    save_png(padded, web_dir / "icons" / "Icon-maskable-192.png", 192)
    save_png(padded, web_dir / "icons" / "Icon-maskable-512.png", 512)

    windows_png_dir = STAGING_DIR / "windows" / "png"
    for file_name, size in WINDOWS_ICON_FILES.items():
        save_png(padded, windows_png_dir / file_name, size)
    ico_path = STAGING_DIR / "windows" / "app_icon.ico"
    ico_path.parent.mkdir(parents=True, exist_ok=True)
    padded.save(
        ico_path,
        format="ICO",
        sizes=[(16, 16), (32, 32), (48, 48), (64, 64), (128, 128), (256, 256)],
    )

    print(f"Generated staging icons under {STAGING_DIR.relative_to(ROOT)}")
    print(f"Generated Android flavor resources under {ANDROID_STAGING_RES.relative_to(ROOT)}")


if __name__ == "__main__":
    main()
