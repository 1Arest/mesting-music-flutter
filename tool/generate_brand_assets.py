from pathlib import Path

from PIL import Image, ImageDraw, ImageFilter


APP_ROOT = Path(__file__).resolve().parents[1]
BRAND_DIR = APP_ROOT / "assets" / "branding"
ANDROID_RES = APP_ROOT / "android" / "app" / "src" / "main" / "res"

BRAND_CORAL = (217, 80, 70, 255)
BRAND_INK = (23, 19, 27, 255)
BRAND_CREAM = (247, 248, 255, 255)
PREVIEW_SURFACE = (247, 248, 252, 255)

MORNING_CANVAS = (255, 247, 229, 255)
MORNING_MINT = (169, 216, 208, 255)
MORNING_GOLD = (242, 184, 75, 255)
MORNING_INK = (23, 60, 74, 255)

MIDNIGHT_CANVAS = (8, 24, 36, 255)
MIDNIGHT_SURFACE = (16, 46, 61, 255)
MIDNIGHT_MINT = (66, 201, 180, 255)
MIDNIGHT_GOLD = (245, 196, 81, 255)
MIDNIGHT_PAPER = (244, 241, 232, 255)

LEGACY_ICON_SIZES = {
    "mipmap-mdpi": 48,
    "mipmap-hdpi": 72,
    "mipmap-xhdpi": 96,
    "mipmap-xxhdpi": 144,
    "mipmap-xxxhdpi": 192,
}


def render_in_square(
    source: Image.Image,
    size: int,
    content_fraction: float,
) -> Image.Image:
    content_size = round(size * content_fraction)
    scale = min(content_size / source.width, content_size / source.height)
    rendered_size = (
        max(1, round(source.width * scale)),
        max(1, round(source.height * scale)),
    )
    rendered = source.resize(rendered_size, Image.Resampling.LANCZOS)
    result = Image.new("RGBA", (size, size), (0, 0, 0, 0))
    result.alpha_composite(
        rendered,
        (
            (size - rendered.width) // 2,
            (size - rendered.height) // 2,
        ),
    )
    return result


def extract_light_asset(
    source: Image.Image,
    crop: tuple[int, int, int, int],
) -> Image.Image:
    extracted = source.crop(crop).convert("RGBA")
    blue = extracted.getchannel("B")
    alpha = blue.point(
        lambda value: (
            0
            if value <= 105
            else 255
            if value >= 225
            else round((value - 105) * 255 / 120)
        )
    )
    bounds = alpha.getbbox()
    if bounds is None:
        raise ValueError(f"No light asset found in crop {crop}")
    alpha = alpha.crop(bounds)
    foreground = Image.new("RGBA", alpha.size, BRAND_CREAM[:-1] + (0,))
    foreground.putalpha(alpha)
    return foreground


def flatten_generated_asset(source: Image.Image) -> Image.Image:
    bounds = source.getchannel("A").getbbox()
    if bounds is None:
        raise ValueError("Generated source has no visible pixels")
    alpha = source.getchannel("A").crop(bounds)
    foreground = Image.new("RGBA", alpha.size, BRAND_CREAM[:-1] + (0,))
    foreground.putalpha(alpha)
    return foreground


def save_png(image: Image.Image, path: Path) -> None:
    path.parent.mkdir(parents=True, exist_ok=True)
    image.save(path, format="PNG", optimize=True)


def save_webp(image: Image.Image, path: Path) -> None:
    path.parent.mkdir(parents=True, exist_ok=True)
    image.convert("RGB").save(
        path,
        format="WEBP",
        quality=94,
        method=6,
    )


def diagonal_gradient(
    size: tuple[int, int],
    start: tuple[int, int, int],
    end: tuple[int, int, int],
) -> Image.Image:
    sample_size = 192
    sample = Image.new("RGBA", (sample_size, sample_size))
    pixels = sample.load()
    for y in range(sample_size):
        for x in range(sample_size):
            amount = (x + y) / (2 * (sample_size - 1))
            pixels[x, y] = tuple(
                round(start[channel] * (1 - amount) + end[channel] * amount)
                for channel in range(3)
            ) + (255,)
    return sample.resize(size, Image.Resampling.BICUBIC)


def add_soft_glow(
    image: Image.Image,
    center: tuple[float, float],
    radius: float,
    color: tuple[int, int, int, int],
) -> None:
    diameter = round(radius * 2)
    glow = Image.new("RGBA", image.size, (0, 0, 0, 0))
    draw = ImageDraw.Draw(glow)
    x = round(center[0] - radius)
    y = round(center[1] - radius)
    draw.ellipse((x, y, x + diameter, y + diameter), fill=color)
    glow = glow.filter(ImageFilter.GaussianBlur(max(1, round(radius * 0.42))))
    image.alpha_composite(glow)


def create_morning_background(size: tuple[int, int]) -> Image.Image:
    width, height = size
    background = diagonal_gradient(
        size,
        MORNING_CANVAS[:3],
        (222, 239, 228),
    )
    draw = ImageDraw.Draw(background, "RGBA")

    sun_radius = round(min(size) * 0.25)
    sun_center = (round(width * 0.83), round(height * 0.17))
    draw.ellipse(
        (
            sun_center[0] - sun_radius,
            sun_center[1] - sun_radius,
            sun_center[0] + sun_radius,
            sun_center[1] + sun_radius,
        ),
        fill=MORNING_GOLD[:3] + (255,),
    )
    draw.ellipse(
        (
            sun_center[0] - sun_radius * 0.63,
            sun_center[1] - sun_radius * 0.63,
            sun_center[0] + sun_radius * 0.63,
            sun_center[1] + sun_radius * 0.63,
        ),
        fill=(255, 231, 157, 255),
    )

    wave_stroke = max(10, round(min(size) * 0.035))
    wave_box = (
        -round(width * 0.42),
        round(height * 0.60),
        round(width * 0.83),
        round(height * 1.29),
    )
    for inset, color in (
        (0, MORNING_MINT[:3] + (238,)),
        (round(min(size) * 0.10), (83, 158, 154, 205)),
        (round(min(size) * 0.20), (70, 92, 199, 145)),
    ):
        draw.arc(
            (
                wave_box[0] + inset,
                wave_box[1] + inset,
                wave_box[2] - inset,
                wave_box[3] - inset,
            ),
            196,
            344,
            fill=color,
            width=wave_stroke,
        )
    return background


def create_midnight_background(size: tuple[int, int]) -> Image.Image:
    width, height = size
    background = diagonal_gradient(
        size,
        MIDNIGHT_SURFACE[:3],
        MIDNIGHT_CANVAS[:3],
    )
    add_soft_glow(
        background,
        (width * 0.22, height * 0.18),
        min(size) * 0.30,
        MIDNIGHT_MINT[:3] + (54,),
    )

    grooves = Image.new("RGBA", size, (0, 0, 0, 0))
    draw = ImageDraw.Draw(grooves)
    center = (width * 0.50, height * 0.52)
    stroke = max(2, round(min(size) * 0.0038))
    for index, scale in enumerate(
        (0.34, 0.43, 0.52, 0.61, 0.70, 0.79, 0.88, 0.97)
    ):
        diameter = min(size) * scale
        alpha = 94 if index % 2 == 0 else 54
        draw.ellipse(
            (
                center[0] - diameter / 2,
                center[1] - diameter / 2,
                center[0] + diameter / 2,
                center[1] + diameter / 2,
            ),
            outline=MIDNIGHT_MINT[:3] + (alpha,),
            width=stroke,
        )
    orbit = min(size) * 0.79
    draw.arc(
        (
            center[0] - orbit / 2,
            center[1] - orbit / 2,
            center[0] + orbit / 2,
            center[1] + orbit / 2,
        ),
        284,
        342,
        fill=MIDNIGHT_GOLD,
        width=max(5, round(min(size) * 0.012)),
    )
    dot_radius = max(6, round(min(size) * 0.018))
    dot_x = round(center[0] + orbit * 0.385)
    dot_y = round(center[1] - orbit * 0.105)
    draw.ellipse(
        (
            dot_x - dot_radius,
            dot_y - dot_radius,
            dot_x + dot_radius,
            dot_y + dot_radius,
        ),
        fill=MIDNIGHT_GOLD,
    )
    background.alpha_composite(grooves)
    return background


def create_brand_foreground(
    canonical_mark: Image.Image,
    name: str,
) -> Image.Image:
    alpha = canonical_mark.getchannel("A")
    if name == "morning":
        foreground = Image.new("RGBA", canonical_mark.size, MORNING_INK)
    elif name == "midnight":
        foreground = Image.new("RGBA", canonical_mark.size, MIDNIGHT_PAPER)
    else:
        raise ValueError(f"Unknown brand foreground: {name}")
    foreground.putalpha(alpha)
    return foreground


def clip_rounded_icon(
    image: Image.Image,
    radius_fraction: float = 0.225,
) -> Image.Image:
    mask = Image.new("L", image.size, 0)
    draw = ImageDraw.Draw(mask)
    draw.rounded_rectangle(
        (0, 0, image.width - 1, image.height - 1),
        radius=round(min(image.size) * radius_fraction),
        fill=255,
    )
    result = image.copy()
    result.putalpha(mask)
    return result


def compose_brand_icon(
    background: Image.Image,
    foreground: Image.Image,
    size: int,
) -> Image.Image:
    icon = background.resize((size, size), Image.Resampling.LANCZOS)
    icon.alpha_composite(
        foreground.resize((size, size), Image.Resampling.LANCZOS)
    )
    return clip_rounded_icon(icon)


def generate_dress_up_icons(canonical_mark: Image.Image) -> None:
    backgrounds = {
        "morning": create_morning_background((1024, 1024)),
        "midnight": create_midnight_background((1024, 1024)),
    }
    for name, background in backgrounds.items():
        foreground = create_brand_foreground(canonical_mark, name)
        save_png(
            compose_brand_icon(background, foreground, 1024),
            BRAND_DIR / f"dress-{name}-icon-v2.png",
        )
        save_png(
            foreground,
            ANDROID_RES / "drawable-xxxhdpi" / f"mesting_{name}_foreground.png",
        )
        save_png(
            background.resize((432, 432), Image.Resampling.LANCZOS),
            ANDROID_RES
            / "drawable-xxxhdpi"
            / f"mesting_{name}_adaptive_background.png",
        )
        for directory, size in LEGACY_ICON_SIZES.items():
            save_png(
                compose_brand_icon(background, foreground, size),
                ANDROID_RES / directory / f"ic_launcher_{name}.png",
            )


def create_morning_launch_background(
    size: tuple[int, int],
) -> Image.Image:
    width, height = size
    background = diagonal_gradient(
        size,
        MORNING_CANVAS[:3],
        (226, 241, 232),
    )
    draw = ImageDraw.Draw(background, "RGBA")

    sun_radius = round(width * 0.42)
    sun_center = (round(width * 0.90), round(height * 0.13))
    draw.ellipse(
        (
            sun_center[0] - sun_radius,
            sun_center[1] - sun_radius,
            sun_center[0] + sun_radius,
            sun_center[1] + sun_radius,
        ),
        fill=MORNING_GOLD[:3] + (238,),
    )
    draw.ellipse(
        (
            sun_center[0] - sun_radius * 0.72,
            sun_center[1] - sun_radius * 0.72,
            sun_center[0] + sun_radius * 0.72,
            sun_center[1] + sun_radius * 0.72,
        ),
        fill=(255, 233, 166, 255),
    )

    wave_stroke = max(10, round(width * 0.026))
    wave_box = (
        -round(width * 0.72),
        round(height * 0.67),
        round(width * 1.05),
        round(height * 1.10),
    )
    for inset, color in (
        (0, MORNING_MINT[:3] + (240,)),
        (round(width * 0.12), (83, 158, 154, 205)),
        (round(width * 0.24), (70, 92, 199, 136)),
    ):
        draw.arc(
            (
                wave_box[0] + inset,
                wave_box[1] + inset,
                wave_box[2] - inset,
                wave_box[3] - inset,
            ),
            202,
            337,
            fill=color,
            width=wave_stroke,
        )

    rhythm_x = round(width * 0.78)
    rhythm_y = round(height * 0.78)
    for index, bar_height in enumerate((0.06, 0.11, 0.17, 0.10, 0.07)):
        x = rhythm_x + round(index * width * 0.035)
        height_px = round(height * bar_height)
        draw.rounded_rectangle(
            (
                x,
                rhythm_y - height_px // 2,
                x + round(width * 0.012),
                rhythm_y + height_px // 2,
            ),
            radius=round(width * 0.006),
            fill=MORNING_INK[:3] + (96,),
        )
    return background


def create_midnight_launch_background(
    size: tuple[int, int],
) -> Image.Image:
    width, height = size
    background = diagonal_gradient(
        size,
        MIDNIGHT_SURFACE[:3],
        MIDNIGHT_CANVAS[:3],
    )
    add_soft_glow(
        background,
        (width * 0.18, height * 0.16),
        width * 0.46,
        MIDNIGHT_MINT[:3] + (48,),
    )
    draw = ImageDraw.Draw(background, "RGBA")

    center = (round(width * 0.80), round(height * 0.78))
    for index, scale in enumerate(
        (0.48, 0.62, 0.76, 0.90, 1.04, 1.18, 1.32, 1.46)
    ):
        radius = width * scale
        color = MIDNIGHT_MINT[:3] + ((84 if index % 2 == 0 else 42),)
        draw.ellipse(
            (
                center[0] - radius,
                center[1] - radius,
                center[0] + radius,
                center[1] + radius,
            ),
            outline=color,
            width=max(2, round(width * 0.006)),
        )

    orbit_radius = width * 1.04
    draw.arc(
        (
            center[0] - orbit_radius,
            center[1] - orbit_radius,
            center[0] + orbit_radius,
            center[1] + orbit_radius,
        ),
        216,
        284,
        fill=MIDNIGHT_GOLD,
        width=max(5, round(width * 0.014)),
    )
    dot_radius = max(8, round(width * 0.022))
    dot_x = round(center[0] - orbit_radius * 0.88)
    dot_y = round(center[1] + orbit_radius * 0.35)
    draw.ellipse(
        (
            dot_x - dot_radius,
            dot_y - dot_radius,
            dot_x + dot_radius,
            dot_y + dot_radius,
        ),
        fill=MIDNIGHT_GOLD,
    )

    for index, width_fraction in enumerate((0.20, 0.31, 0.15)):
        y = round(height * (0.12 + index * 0.035))
        draw.rounded_rectangle(
            (
                round(width * 0.08),
                y,
                round(width * (0.08 + width_fraction)),
                y + round(width * 0.009),
            ),
            radius=round(width * 0.005),
            fill=MIDNIGHT_PAPER[:3] + (72 - index * 14,),
        )
    return background


def generate_launch_backgrounds() -> None:
    size = (900, 2000)
    save_webp(
        create_morning_launch_background(size),
        BRAND_DIR / "dress-morning-launch.webp",
    )
    save_webp(
        create_midnight_launch_background(size),
        BRAND_DIR / "dress-midnight-launch-v2.webp",
    )


def create_legacy_icon(mark: Image.Image, size: int) -> Image.Image:
    icon = Image.new("RGBA", (size, size), (0, 0, 0, 0))
    draw = ImageDraw.Draw(icon)
    radius = round(size * 0.225)
    draw.rounded_rectangle(
        (0, 0, size - 1, size - 1),
        radius=radius,
        fill=BRAND_CORAL,
    )
    icon.alpha_composite(mark.resize((size, size), Image.Resampling.LANCZOS))
    return icon


def place_centered(
    canvas: Image.Image,
    asset: Image.Image,
    box: tuple[int, int, int, int],
) -> None:
    left, top, right, bottom = box
    available_width = right - left
    available_height = bottom - top
    scale = min(
        available_width / asset.width,
        available_height / asset.height,
    )
    size = (
        max(1, round(asset.width * scale)),
        max(1, round(asset.height * scale)),
    )
    rendered = asset.resize(size, Image.Resampling.LANCZOS)
    x = left + (available_width - rendered.width) // 2
    y = top + (available_height - rendered.height) // 2
    canvas.alpha_composite(rendered, (x, y))


def create_preview(mark: Image.Image, lockup: Image.Image) -> Image.Image:
    preview = Image.new("RGBA", (1800, 1100), PREVIEW_SURFACE)
    draw = ImageDraw.Draw(preview)

    icon_box = (110, 250, 710, 850)
    draw.rounded_rectangle(icon_box, radius=138, fill=BRAND_CORAL)
    place_centered(preview, mark, icon_box)

    light_splash = (840, 70, 1260, 1030)
    dark_splash = (1300, 70, 1720, 1030)
    draw.rectangle(light_splash, fill=BRAND_CORAL)
    draw.rectangle(dark_splash, fill=BRAND_INK)

    light_lockup_box = (900, 285, 1200, 815)
    dark_lockup_box = (1360, 285, 1660, 815)
    place_centered(preview, lockup, light_lockup_box)
    place_centered(preview, lockup, dark_lockup_box)
    return preview


def create_light_implementation(
    mark: Image.Image,
    lockup: Image.Image,
    lockup_box: tuple[int, int, int, int] = (1010, 385, 1310, 685),
) -> Image.Image:
    implementation = Image.new("RGBA", (1536, 1024), PREVIEW_SURFACE)
    draw = ImageDraw.Draw(implementation)

    icon_box = (178, 208, 752, 798)
    draw.rounded_rectangle(icon_box, radius=132, fill=BRAND_CORAL)
    place_centered(implementation, mark, icon_box)

    splash_box = (913, 30, 1406, 993)
    draw.rectangle(splash_box, fill=BRAND_CORAL)
    place_centered(
        implementation,
        lockup,
        lockup_box,
    )
    return implementation


def create_side_by_side(
    left: Image.Image,
    right: Image.Image,
) -> Image.Image:
    separator = 8
    comparison = Image.new(
        "RGBA",
        (left.width + separator + right.width, max(left.height, right.height)),
        PREVIEW_SURFACE,
    )
    comparison.alpha_composite(left, (0, 0))
    comparison.alpha_composite(right, (left.width + separator, 0))
    return comparison


def main() -> None:
    generated_mark = BRAND_DIR / "mesting-mark-master.png"
    generated_lockup = BRAND_DIR / "mesting-launch-lockup-master.png"
    selected_concept = BRAND_DIR / "mesting-brand-selected-concept.png"
    if not selected_concept.exists():
        raise FileNotFoundError(selected_concept)

    source = Image.open(selected_concept).convert("RGBA")
    if source.size != (1536, 1024):
        raise ValueError("Selected concept must be 1536 x 1024")

    mark = render_in_square(
        extract_light_asset(source, (270, 325, 665, 690)),
        432,
        content_fraction=0.61,
    )
    lockup = render_in_square(
        extract_light_asset(source, (990, 370, 1325, 700)),
        912,
        content_fraction=0.88,
    )

    save_png(
        mark,
        ANDROID_RES / "drawable-xxxhdpi" / "mesting_mark_foreground.png",
    )
    save_png(
        lockup,
        ANDROID_RES / "drawable-xxxhdpi" / "mesting_launch_lockup.png",
    )

    for directory, size in LEGACY_ICON_SIZES.items():
        save_png(
            create_legacy_icon(mark, size),
            ANDROID_RES / directory / "ic_launcher.png",
        )

    preview = create_preview(mark, lockup)
    save_png(
        preview,
        BRAND_DIR / "mesting-brand-implementation-preview.png",
    )

    light_implementation = create_light_implementation(mark, lockup)
    save_png(
        light_implementation,
        BRAND_DIR / "mesting-brand-light-implementation.png",
    )

    save_png(
        create_side_by_side(source, light_implementation),
        BRAND_DIR / "mesting-design-qa-full.png",
    )

    initial_mark = render_in_square(
        flatten_generated_asset(Image.open(generated_mark).convert("RGBA")),
        432,
        content_fraction=0.665,
    )
    initial_lockup = render_in_square(
        flatten_generated_asset(
            Image.open(generated_lockup).convert("RGBA")
        ),
        768,
        content_fraction=0.84,
    )
    initial_implementation = create_light_implementation(
        initial_mark,
        initial_lockup,
        lockup_box=(1028, 360, 1291, 725),
    )
    save_png(
        create_side_by_side(source, initial_implementation),
        BRAND_DIR / "mesting-design-qa-iteration-1.png",
    )
    icon_box = (178, 208, 752, 798)
    save_png(
        create_side_by_side(
            source.crop(icon_box),
            light_implementation.crop(icon_box),
        ),
        BRAND_DIR / "mesting-design-qa-icon.png",
    )
    splash_box = (913, 30, 1406, 993)
    save_png(
        create_side_by_side(
            source.crop(splash_box),
            light_implementation.crop(splash_box),
        ),
        BRAND_DIR / "mesting-design-qa-splash.png",
    )
    generate_dress_up_icons(mark)
    generate_launch_backgrounds()


if __name__ == "__main__":
    main()
