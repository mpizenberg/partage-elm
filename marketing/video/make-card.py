#!/usr/bin/env python3
"""Render the demo video's opening and closing card, one per language.

The card is the static site's hero at the screen recording's own resolution, so
a cut between card and recording lands on the same background.
"""
import pathlib
import subprocess
import sys

W, H = 864, 1920

# Copied from public/marketing.css, which has no way to export them to a script.
BG, TEXT, SUBTLE, BRAND, LINK = "#fff8f0", "#2d2d2d", "#7a7570", "#e8725c", "#c4503c"
FONT = "Helvetica Neue, Helvetica, Arial, sans-serif"

LOGO_SIZE, LOGO_Y = 280, 570
TITLE_SIZE, TITLE_Y = 116, 990
SUB_SIZE, SUB_Y, SUB_STEP = 42, 1100, 62
DOMAIN, DOMAIN_SIZE, DOMAIN_Y = "onpartage.eu", 46, 1345

# SVG cannot wrap text, so each tagline is broken into its rendered lines.
CARDS = {
    "en": ["Private, encrypted bill splitting", "that works offline —", "no account needed."],
    "fr": ["Le partage de frais privé et chiffré", "qui fonctionne hors-ligne —", "sans compte."],
}


def svg(lines):
    subtitle = "\n".join(
        f'  <text x="{W / 2}" y="{SUB_Y + i * SUB_STEP}" font-family="{FONT}" font-size="{SUB_SIZE}"'
        f' fill="{SUBTLE}" text-anchor="middle">{line}</text>'
        for i, line in enumerate(lines)
    )
    return f"""<svg xmlns="http://www.w3.org/2000/svg" width="{W}" height="{H}" viewBox="0 0 {W} {H}">
  <rect width="{W}" height="{H}" fill="{BG}"/>
  <g transform="translate({(W - LOGO_SIZE) / 2},{LOGO_Y}) scale({LOGO_SIZE / 512})">
    <circle cx="256" cy="256" r="240" fill="{BRAND}"/>
    <line x1="256" y1="96" x2="256" y2="416" stroke="white" stroke-width="32" stroke-linecap="round"/>
    <circle cx="160" cy="256" r="48" fill="white"/>
    <circle cx="352" cy="256" r="48" fill="white"/>
  </g>
  <text x="{W / 2}" y="{TITLE_Y}" font-family="{FONT}" font-size="{TITLE_SIZE}" font-weight="700"
        letter-spacing="{-0.02 * TITLE_SIZE:.1f}" fill="{TEXT}" text-anchor="middle">Partage</text>
{subtitle}
  <text x="{W / 2}" y="{DOMAIN_Y}" font-family="{FONT}" font-size="{DOMAIN_SIZE}" font-weight="600"
        fill="{LINK}" text-anchor="middle">{DOMAIN}</text>
</svg>
"""


def render(media):
    for language, lines in CARDS.items():
        source = media / f"card-{language}.svg"
        source.write_text(svg(lines))
        subprocess.run(
            ["rsvg-convert", "-w", str(W), "-h", str(H), "-o", str(media / f"card-{language}.png"), str(source)],
            check=True,
        )
        print(f"card-{language}.png")


if __name__ == "__main__":
    if len(sys.argv) != 2:
        raise SystemExit(f"usage: {sys.argv[0]} <media-directory>")
    render(pathlib.Path(sys.argv[1]))
