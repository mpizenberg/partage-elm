#!/usr/bin/env python3
"""Assemble the demo clips: opening card, screen recording, closing card.

Takes the directory holding the screen recordings, which lives outside the
repository. Regenerates the cards there first so they cannot fall behind an edit
to make-card.py, then re-probes each export and reports whether it meets the
constraints the clips are published under.
"""
import json
import pathlib
import subprocess
import sys

HERE = pathlib.Path(__file__).parent
RECORDING = "partage-demo-screenrecord-{language}-*.mp4"

FRAME = (864, 1920)
FPS = 30
OPEN_SECONDS = 2.0
CLOSE_SECONDS = 2.5
CRF = 16
PRESET = "slow"

DURATION_RANGE = (20.0, 30.0)
MAX_BYTES = 8 * 1024 * 1024

# `start` and `end` trim the recording, in seconds; None keeps the whole take.
TRIM = {
    "en": {"start": None, "end": None},
    "fr": {"start": None, "end": None},
}


def probe(path):
    out = subprocess.run(
        ["ffprobe", "-v", "error", "-show_streams", "-show_format", "-of", "json", str(path)],
        check=True,
        capture_output=True,
        text=True,
    )
    return json.loads(out.stdout)


def video_stream(info):
    return next(s for s in info["streams"] if s["codec_type"] == "video")


def has_faststart(path):
    """The moov atom must precede mdat, or a player cannot start before it downloads."""
    head = path.read_bytes()[:4096]
    moov, mdat = head.find(b"moov"), head.find(b"mdat")
    return moov != -1 and (mdat == -1 or moov < mdat)


def find_recording(media, language):
    pattern = RECORDING.format(language=language)
    matches = sorted(media.glob(pattern))
    if len(matches) != 1:
        raise SystemExit(f"expected exactly one {pattern} in {media}, found {len(matches)}")
    return matches[0]


def assemble(media, language, recording, trim):
    card = media / f"card-{language}.png"
    output = media / f"partage-demo-{language}.mp4"

    source = video_stream(probe(recording))
    if (source["width"], source["height"]) != FRAME:
        raise SystemExit(
            f"{recording.name} is {source['width']}x{source['height']}, but the cards are "
            f"{FRAME[0]}x{FRAME[1]}. Render the cards at the recording's size rather than "
            "rescaling the interface."
        )

    seek = []
    if trim["start"] is not None:
        seek += ["-ss", str(trim["start"])]
    if trim["end"] is not None:
        seek += ["-t", str(trim["end"] - (trim["start"] or 0))]

    normalize = f"fps={FPS},format=yuv420p,setsar=1"
    subprocess.run(
        # fmt: off
        [
            "ffmpeg", "-hide_banner", "-loglevel", "error", "-y",
            "-loop", "1", "-t", str(OPEN_SECONDS), "-i", str(card),
            *seek, "-i", str(recording),
            "-loop", "1", "-t", str(CLOSE_SECONDS), "-i", str(card),
            "-filter_complex",
            f"[0:v]{normalize}[open];[1:v]{normalize}[body];[2:v]{normalize}[close];"
            "[open][body][close]concat=n=3:v=1:a=0[v]",
            "-map", "[v]",
            "-an",
            "-c:v", "libx264", "-crf", str(CRF), "-preset", PRESET,
            "-movflags", "+faststart",
            str(output),
        ],
        # fmt: on
        check=True,
    )
    return output


def verify(output):
    info = probe(output)
    stream = video_stream(info)
    duration = float(info["format"]["duration"])
    size = int(info["format"]["size"])
    audio = [s for s in info["streams"] if s["codec_type"] == "audio"]
    faststart = has_faststart(output)

    return [
        ("frame", f"{stream['width']}x{stream['height']}", (stream["width"], stream["height"]) == FRAME),
        ("frame rate", stream["r_frame_rate"], stream["r_frame_rate"] == f"{FPS}/1"),
        ("pixel format", stream["pix_fmt"], stream["pix_fmt"] == "yuv420p"),
        ("codec", stream["codec_name"], stream["codec_name"] == "h264"),
        ("audio track", "none" if not audio else f"{len(audio)} present", not audio),
        ("duration", f"{duration:.1f}s", DURATION_RANGE[0] <= duration <= DURATION_RANGE[1]),
        ("size", f"{size / 1024 / 1024:.1f} MB", size <= MAX_BYTES),
        ("fast start", "yes" if faststart else "no", faststart),
    ]


def main():
    if len(sys.argv) != 2:
        raise SystemExit(f"usage: {sys.argv[0]} <media-directory>")
    media = pathlib.Path(sys.argv[1])
    if not media.is_dir():
        raise SystemExit(f"{media} is not a directory")

    # Resolve every input before writing anything, so a directory holding no
    # recording is left as it was found.
    recordings = {language: find_recording(media, language) for language in TRIM}
    subprocess.run([sys.executable, str(HERE / "make-card.py"), str(media)], check=True)

    failed = False
    for language, trim in TRIM.items():
        output = assemble(media, language, recordings[language], trim)
        print(f"\n{output.name}")
        for label, value, ok in verify(output):
            print(f"  {'ok  ' if ok else 'FAIL'}  {label}: {value}")
            failed |= not ok

    print("\nWatch each export once at feed size and once through a full loop.")
    return 1 if failed else 0


if __name__ == "__main__":
    sys.exit(main())
