#!/usr/bin/env python3
"""Generate the alternate app icons unlocked by the tip jar.

Every variant composites the *real* remote artwork - the transparent foreground
layer Icon Composer draws the shipping icon from, AppIcon.icon/Assets/
VisionAppIcon.png - over a different backdrop. The alternates are therefore the
same icon the user already knows, not a lookalike.

Midnight is the one exception: that artwork is dark purple, which disappears
against a near-black backdrop, so midnight keeps a redrawn light-on-dark remote.

ImageMagick is not installed on this machine (AppIcons/script.zsh depends on
it), so rendering goes through Inkscape and resizing through macOS `sips`.

Usage:  python3 AppIcons/generate-alternates.py
Writes: Shared/AppIcon.xcassets/AppIcon<Name>.appiconset/  (1024 single-size)
        Shared/AppIcon.xcassets/AppIcon<Name>Preview.imageset/  (180pt swatch)
        Shared/AppIcon.xcassets/AppIconPreview.imageset/  (swatch for the
        default icon, which the picker needs and cannot read from
        AppIcon.appiconset)
"""

import json
import os
import subprocess
import sys

HERE = os.path.dirname(os.path.abspath(__file__))
REPO = os.path.dirname(HERE)
XCASSETS = os.path.join(REPO, "Shared", "AppIcon.xcassets")
BUILD = os.path.join(HERE, "generated")

INKSCAPE = "/Applications/Inkscape.app/Contents/MacOS/inkscape"

# The shipping icon's foreground layer, with a transparent background. This is
# the source of truth for what the remote looks like.
ARTWORK = os.path.join(HERE, "AppIcon.icon", "Assets", "VisionAppIcon.png")
# The rendered default icon, used only for the picker's "Default" swatch.
DEFAULT_ICON = os.path.join(XCASSETS, "AppIcon.appiconset", "1024-any.png")

# Palette lifted from the existing icon so the alternates sit in the same family.
BODY = "#46415F"
BODY_EDGE = "#2A1840"
BTN = "#EAE6F9"
BTN_ACCENT = "#6D3FE0"
# Neutral rather than the original's purple: these backdrops are busy, and a
# tinted shadow reads as a stray coloured band over the pride stripes.
SHADOW = "#000000"


def artwork_remote():
    """The shipping icon's own foreground layer, dropped in as a raster.

    Icon Composer applies the icon's shadow at render time and that shadow is
    not part of the layer, so it is reapplied here - without it the remote
    reads as a sticker pasted onto the backdrop rather than sitting on it.

    The shadow is an offset copy flattened to black and blurred, rather than
    the one-line `feDropShadow`: this Inkscape rejects that primitive outright
    ("unknown type: svg:feDropShadow") and drops the filtered element entirely,
    which silently produces an icon with no remote on it at all.
    """
    return (
        '<defs>'
        '<filter id="shadow" x="-25%" y="-25%" width="150%" height="150%">'
        '<feColorMatrix type="matrix" values="'
        '0 0 0 0 0  0 0 0 0 0  0 0 0 0 0  0 0 0 0.30 0"/>'
        '<feGaussianBlur stdDeviation="16"/>'
        '</filter>'
        '</defs>'
        f'<g transform="translate(24,26)">'
        f'<image x="0" y="0" width="1024" height="1024" filter="url(#shadow)" '
        f'xlink:href="{ARTWORK}"/>'
        f'</g>'
        f'<image x="0" y="0" width="1024" height="1024" xlink:href="{ARTWORK}"/>'
    )


def remote(body=BODY, edge=BODY_EDGE, btn=BTN, accent=BTN_ACCENT, shadow=SHADOW):
    """A redrawn remote, used only where the real artwork has no contrast."""
    parts = []

    # Offset drop shadow, drawn first so it sits behind the body.
    parts.append(
        f'<rect x="428" y="225" width="244" height="628" rx="30" '
        f'fill="{shadow}" opacity="0.22"/>'
    )
    parts.append(
        f'<rect x="390" y="195" width="244" height="628" rx="30" '
        f'fill="{body}" stroke="{edge}" stroke-width="16"/>'
    )

    # Power + back, then two rows of three.
    parts.append(f'<circle cx="455" cy="272" r="28" fill="{btn}"/>')
    parts.append(f'<circle cx="575" cy="272" r="28" fill="{accent}"/>')
    for cy in (342, 400):
        for cx in (455, 512, 575):
            parts.append(f'<circle cx="{cx}" cy="{cy}" r="23" fill="{btn}"/>')

    # D-pad.
    parts.append(f'<circle cx="512" cy="492" r="52" fill="{body}" stroke="{edge}" stroke-width="14"/>')
    parts.append(f'<circle cx="512" cy="492" r="24" fill="{accent}" stroke="{edge}" stroke-width="10"/>')

    # Three rows of three.
    for cy in (585, 645, 705):
        for cx in (455, 512, 575):
            parts.append(f'<circle cx="{cx}" cy="{cy}" r="23" fill="{btn}"/>')

    return "\n  ".join(parts)


def svg(background, foreground=None):
    return (
        '<svg xmlns="http://www.w3.org/2000/svg" '
        'xmlns:xlink="http://www.w3.org/1999/xlink" width="1024" height="1024" '
        'viewBox="0 0 1024 1024">\n  '
        + background
        + "\n  "
        + (foreground or artwork_remote())
        + "\n</svg>\n"
    )


# --- Backdrops -------------------------------------------------------------

PRIDE_COLORS = ["#E40303", "#FF8C00", "#FFED00", "#008026", "#24408E", "#732982"]
pride_bg = "".join(
    f'<rect x="0" y="{i * 1024 / 6:.2f}" width="1024" height="{1024 / 6:.2f}" fill="{c}"/>'
    for i, c in enumerate(PRIDE_COLORS)
)

BARS = ["#C0C0C0", "#C0C000", "#00C0C0", "#00C000", "#C000C0", "#C00000", "#0000C0"]
retro_bg = "".join(
    f'<rect x="{i * 1024 / 7:.2f}" y="0" width="{1024 / 7:.2f}" height="1024" fill="{c}"/>'
    for i, c in enumerate(BARS)
) + "".join(
    f'<rect x="0" y="{y}" width="1024" height="4" fill="#000000" opacity="0.18"/>'
    for y in range(0, 1024, 12)
)

midnight_bg = '<rect width="1024" height="1024" fill="#0B0A14"/>'

VARIANTS = {
    "AppIconPride": svg(pride_bg),
    "AppIconRetro": svg(retro_bg),
    # The only variant that does not use the real artwork: the shipping remote
    # is dark purple and vanishes on near-black, so it is redrawn inverted.
    "AppIconMidnight": svg(
        midnight_bg,
        remote(
            body="#EDEAF7",
            edge="#FFFFFF",
            btn="#2A2340",
            accent="#8B5CF6",
            shadow="#2A2340",
        ),
    ),
}


def run(cmd):
    subprocess.run(cmd, check=True, capture_output=True)


def write_preview(name, source_png):
    """Preview swatch for the in-app picker.

    App icon *sets* are not addressable as `Image(...)` at runtime, so every
    option in the picker - the default included - needs a plain image set
    alongside. The default's absence is what left its cell blank.
    """
    imageset = os.path.join(XCASSETS, f"{name}.imageset")
    os.makedirs(imageset, exist_ok=True)
    preview = os.path.join(imageset, f"{name}.png")
    run(["sips", "-z", "180", "180", source_png, "--out", preview])
    with open(os.path.join(imageset, "Contents.json"), "w") as handle:
        json.dump(
            {
                "images": [
                    {"filename": f"{name}.png", "idiom": "universal", "scale": "1x"},
                    {"idiom": "universal", "scale": "2x"},
                    {"idiom": "universal", "scale": "3x"},
                ],
                "info": {"author": "xcode", "version": 1},
            },
            handle,
            indent=2,
        )


def main():
    if not os.path.exists(INKSCAPE):
        sys.exit(f"Inkscape not found at {INKSCAPE}")

    os.makedirs(BUILD, exist_ok=True)

    write_preview("AppIconPreview", DEFAULT_ICON)
    print("generated AppIconPreview")

    for name, markup in VARIANTS.items():
        svg_path = os.path.join(BUILD, f"{name}.svg")
        png_path = os.path.join(BUILD, f"{name}.png")
        with open(svg_path, "w") as handle:
            handle.write(markup)

        run([INKSCAPE, svg_path, "--export-type=png", "--export-filename=" + png_path,
             "--export-width=1024", "--export-height=1024"])

        # Single-size 1024 app icon. Xcode 14+ slices the rest itself, and
        # alternate icons do not need the separate marketing asset.
        iconset = os.path.join(XCASSETS, f"{name}.appiconset")
        os.makedirs(iconset, exist_ok=True)
        run(["cp", png_path, os.path.join(iconset, f"{name}.png")])
        with open(os.path.join(iconset, "Contents.json"), "w") as handle:
            json.dump(
                {
                    "images": [
                        {
                            "filename": f"{name}.png",
                            "idiom": "universal",
                            "platform": "ios",
                            "size": "1024x1024",
                        }
                    ],
                    "info": {"author": "xcode", "version": 1},
                },
                handle,
                indent=2,
            )

        write_preview(f"{name}Preview", png_path)

        print(f"generated {name}")


if __name__ == "__main__":
    main()
