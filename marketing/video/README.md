# Demo video assembly

Builds the social demo clip in each language: a fixed card, the phone screen
recording unaltered, then the same card again.

```sh
python3 marketing/video/make-video.py <media-directory>
```

The media directory holds the screen recordings, named
`partage-demo-screenrecord-<language>-<date>.mp4`, and receives the cards and the
finished `partage-demo-<language>.mp4`. It is deliberately **not** in this
repository: captures and exports are large binaries with no product value, and
the app never serves them. Keep it wherever the rest of the demo media lives.

`make-video.py` renders the cards through `make-card.py` before every build, so
they cannot fall behind an edit, and re-probes each export afterwards, reporting
frame size, rate, pixel format, codec, audio, duration, byte size, and fast
start. It exits non-zero if any of those is wrong.

Recordings are used at their own resolution and never rescaled, so the interface
is never cropped or softened; the card is rendered to match. A recording of a
different size is refused rather than stretched. `TRIM` in `make-video.py` cuts
the head or tail off a take.

Requires `ffmpeg`, `ffprobe`, and `rsvg-convert`. Nothing in `pnpm build` runs
this — the clips are made once per campaign, not once per deployment.
