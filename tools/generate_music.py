#!/usr/bin/env python3
"""Synthesizes the placeholder music the bundled mods play (pure Python, no dependencies).

  python3 tools/generate_music.py

These are stand-ins, the same as every texture and sound effect in this project: enough to prove the
music lane works and to give a world some atmosphere, not enough to be called a soundtrack. Replacing
them with real CC0 music is on the list; anything that arrives has to bring its attribution with it,
because `register_music` refuses a track without one.

Each track loops seamlessly: the whole piece is a whole number of bars, and every voice is built from
sine partials whose periods divide the loop length, so the end joins the beginning without a click.
"""

import math
import os
import shutil
import struct
import subprocess
import sys
import tempfile
import wave

RATE = 22050
ROOT = os.path.join(os.path.dirname(os.path.abspath(__file__)), "..")

# A pentatonic set, which has no semitone clashes, so voices can be laid over each other in any
# combination without anything sounding wrong. The whole point is music nobody has to pay attention to.
A_MINOR_PENT = [220.00, 261.63, 293.66, 329.63, 392.00, 440.00, 523.25, 587.33]


def write(path, samples):
    """Synthesize to WAV, then encode to Ogg Vorbis.

    Vorbis rather than the raw WAV because these travel to every player: 2 MB a track becomes about
    120 KB, and the encoder's one millisecond of padding is inaudible in an ambient pad. ffmpeg's own
    Vorbis encoder only does stereo, hence the duplicated channel - it costs almost nothing, since
    Vorbis couples two identical channels away again.
    """
    path = os.path.join(ROOT, path)
    os.makedirs(os.path.dirname(path), exist_ok=True)
    peak = max(1e-6, max(abs(s) for s in samples))
    scale = 0.82 / peak
    frames = b"".join(struct.pack("<h", int(max(-1.0, min(1.0, s * scale)) * 32767)) for s in samples)
    with tempfile.NamedTemporaryFile(suffix=".wav", delete=False) as tmp:
        raw = tmp.name
    with wave.open(raw, "wb") as w:
        w.setnchannels(1)
        w.setsampwidth(2)
        w.setframerate(RATE)
        w.writeframes(frames)
    subprocess.run(
        ["ffmpeg", "-hide_banner", "-loglevel", "error", "-y", "-i", raw,
         "-c:a", "vorbis", "-strict", "-2", "-q:a", "2", "-ar", str(RATE), "-ac", "2", path],
        check=True)
    os.unlink(raw)
    size = os.path.getsize(path)
    print(f"wrote {os.path.relpath(path, ROOT)} ({len(samples) / RATE:.1f}s, {size / 1024:.0f} KB)")


def pad(length, freq, gain, detune=0.0, harmonics=(1.0, 0.5, 0.25)):
    """A sustained voice.

    Every partial, the detuned one included, is snapped to a whole number of cycles per loop. Missing
    that on the detuned voice is what put an audible click at the loop point the first time: it was a
    fraction of a cycle short, so the waveform jumped where the end met the beginning.
    """
    total = int(length * RATE)
    cycles = max(1, round(freq * length))
    f = cycles / length
    out = [0.0] * total
    for index, level in enumerate(harmonics, start=1):
        beat = max(1, round(detune * length)) / length if detune else 0.0
        w = 2.0 * math.pi * f * index
        w2 = 2.0 * math.pi * (f * index + beat)
        for i in range(total):
            t = i / RATE
            out[i] += level * gain * 0.5 * (math.sin(w * t) + math.sin(w2 * t))
    return out


def swell(length, period, depth=0.6, offset=0.0):
    """A slow rise and fall, a whole number of times per loop, so it too joins up at the seam."""
    total = int(length * RATE)
    times = max(1, round(length / period))
    return [1.0 - depth + depth * 0.5 * (1.0 - math.cos(2.0 * math.pi * (times * i / total + offset)))
            for i in range(total)]


def bell(length, freq, at, decay=3.0, gain=0.3):
    """One struck note, wrapped around the loop end so a note near the seam is not cut in half."""
    total = int(length * RATE)
    out = [0.0] * total
    start = int(at * RATE)
    span = int(min(decay * 6.0, length) * RATE)
    for k in range(span):
        i = (start + k) % total
        t = k / RATE
        # Fade the tail to true zero rather than stopping at whatever exp() had reached, so the end of
        # a note is silence and not a step.
        env = math.exp(-t / decay) * (1.0 - k / span)
        out[i] += gain * env * (math.sin(2.0 * math.pi * freq * t) + 0.4 * math.sin(2.0 * math.pi * freq * 2.01 * t))
    return out


def mix(*layers):
    total = max(len(layer) for layer in layers)
    out = [0.0] * total
    for layer in layers:
        for i, s in enumerate(layer):
            out[i] += s
    return out


def multiply(a, b):
    return [x * y for x, y in zip(a, b)]


def daylight(length=48.0):
    """Open and unhurried: two low voices breathing against each other, with occasional high notes."""
    low = multiply(pad(length, A_MINOR_PENT[0], 0.5, detune=0.15), swell(length, 16.0, 0.5))
    mid = multiply(pad(length, A_MINOR_PENT[2], 0.32, detune=0.1), swell(length, 24.0, 0.6, offset=0.35))
    notes = [bell(length, A_MINOR_PENT[i], at, decay=2.6, gain=0.22)
             for i, at in [(5, 2.0), (4, 11.0), (6, 19.0), (5, 27.5), (7, 35.0), (4, 42.0)]]
    return mix(low, mid, *notes)


def night(length=48.0):
    """Lower, sparser and slower. The same notes, so walking from one into the other does not jar."""
    low = multiply(pad(length, A_MINOR_PENT[0] / 2.0, 0.55, detune=0.08), swell(length, 24.0, 0.55))
    mid = multiply(pad(length, A_MINOR_PENT[1], 0.22, detune=0.12), swell(length, 32.0, 0.7, offset=0.5))
    notes = [bell(length, A_MINOR_PENT[i], at, decay=4.0, gain=0.18)
             for i, at in [(2, 6.0), (0, 21.0), (3, 33.0), (1, 44.0)]]
    return mix(low, mid, *notes)


def hearth(length=40.0):
    """Warmer and closer, for a valley with its light back on: a major third over the same root."""
    low = multiply(pad(length, A_MINOR_PENT[0], 0.5, detune=0.12), swell(length, 20.0, 0.4))
    warm = multiply(pad(length, 277.18, 0.3, detune=0.1), swell(length, 20.0, 0.5, offset=0.25))
    notes = [bell(length, f, at, decay=3.2, gain=0.24)
             for f, at in [(440.0, 1.5), (554.37, 9.0), (659.25, 17.0), (440.0, 26.0), (554.37, 34.0)]]
    return mix(low, warm, *notes)


def deep(length=44.0):
    """Underground: the root an octave down and close, with a fifth leaning on it. **No bells** - the
    sparkle is what makes `daylight` feel like open air, and taking it away is most of what makes a
    place feel like it has a ceiling. What is left breathes slowly and does not resolve."""
    low = multiply(pad(length, A_MINOR_PENT[0] / 2.0, 0.6, detune=0.05), swell(length, 22.0, 0.45))
    lean = multiply(pad(length, A_MINOR_PENT[4] / 2.0, 0.26, detune=0.18), swell(length, 30.0, 0.75, offset=0.4))
    # One low note, rarely, so the loop has a landmark without becoming a tune.
    notes = [bell(length, A_MINOR_PENT[0], at, decay=5.5, gain=0.14) for at in [8.0, 30.0]]
    return mix(low, lean, *notes)


def bright(length=44.0):
    """Light where there has not been any: the same scale an octave up, bells close together and a pad
    thin enough to hear them through. Deliberately the inverse of `deep`, because the two are what a
    player walks between."""
    high = multiply(pad(length, A_MINOR_PENT[5], 0.24, detune=0.2), swell(length, 14.0, 0.5))
    under = multiply(pad(length, A_MINOR_PENT[2], 0.30, detune=0.08), swell(length, 18.0, 0.45, offset=0.3))
    notes = [bell(length, A_MINOR_PENT[i], at, decay=2.2, gain=0.26)
             for i, at in [(6, 1.0), (7, 5.5), (5, 10.0), (7, 16.0), (6, 22.0), (4, 28.0), (7, 33.0), (6, 39.0)]]
    return mix(high, under, *notes)


def main():
    if shutil.which("ffmpeg") is None:
        sys.exit("needs ffmpeg on PATH to encode Ogg Vorbis (brew install ffmpeg)")
    # **Re-encoding a track that has not changed still rewrites the file**, because ffmpeg gives each
    # Ogg stream a random serial - the decoded audio comes out byte-identical and the container does
    # not. So a run of this script always dirties every file it touches, and `git checkout` on the ones
    # you did not mean to change is part of using it. Measured rather than assumed: 399 bytes differ in
    # a 117 KB file and none of them are sound. (2026-09-27)
    #
    # The Proving Ground keeps its two, and they are load-bearing: music is the only content that
    # deliberately does *not* join the download a player waits through, and tests/smoke_test.gd asserts
    # the lazy asset lane against exactly these files. Two rather than one, because a track list with a
    # single entry cannot prove the client picked. (2026-09-21)
    write("tests/mods/proving/music/daylight.ogg", daylight())
    write("tests/mods/proving/music/night.ogg", night())

    # **And now the games, which is what this file has been waiting for.** The note above used to say
    # "because that is the only mod there is until 1.0's games are written" - firstlight, creative and
    # oneblock are written. (2026-09-27)
    #
    # Four moods rather than one per place: open, deep, bright and night. A mood is a thing a player can
    # learn to read, and six nearly-identical tracks would teach them nothing - whereas walking from
    # `open` into `deep` says you have gone underground before any text does.
    for mod in ["firstlight", "creative", "oneblock"]:
        write("mods/%s/music/open.ogg" % mod, daylight())
        write("mods/%s/music/night.ogg" % mod, night())
    # The two that only some places need.
    write("mods/oneblock/music/deep.ogg", deep())
    write("mods/oneblock/music/bright.ogg", bright())
    write("mods/firstlight/music/deep.ogg", deep())
    write("mods/firstlight/music/hearth.ogg", hearth())


if __name__ == "__main__":
    main()
