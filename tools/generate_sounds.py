#!/usr/bin/env python3
"""Synthesizes the placeholder sound effects used by the engine and bundled mods (pure Python, no
dependencies). Writes 22.05 kHz mono 16-bit WAV files.

  python3 tools/generate_sounds.py

Engine sounds (hurt, pickup, ...) go to engine/client/sounds and ship inside the client; mod sounds go
to each mod's sounds/ folder and are streamed to clients like textures.
"""

import math
import os
import random
import struct
import wave

RATE = 22050
ROOT = os.path.join(os.path.dirname(os.path.abspath(__file__)), "..")
rng = random.Random(4242)


def write(path, samples):
    path = os.path.join(ROOT, path)
    os.makedirs(os.path.dirname(path), exist_ok=True)
    peak = max(1e-6, max(abs(s) for s in samples))
    scale = 0.9 / peak if peak > 0.9 else 1.0
    with wave.open(path, "wb") as w:
        w.setnchannels(1)
        w.setsampwidth(2)
        w.setframerate(RATE)
        w.writeframes(b"".join(struct.pack("<h", int(max(-1.0, min(1.0, s * scale)) * 32767)) for s in samples))
    print(f"wrote {os.path.relpath(path, ROOT)} ({len(samples) / RATE:.2f}s)")


def n(seconds):
    return int(seconds * RATE)


def envelope(i, total, attack=0.005, curve=4.0):
    t = i / RATE
    a = min(1.0, t / attack) if attack > 0 else 1.0
    return a * (1.0 - i / total) ** curve


def lowpass(samples, amount):
    out, y = [], 0.0
    for s in samples:
        y += amount * (s - y)
        out.append(y)
    return out


def noise_burst(seconds, cutoff, curve=4.0, gain=1.0):
    total = n(seconds)
    raw = [rng.uniform(-1, 1) for _ in range(total)]
    filtered = lowpass(raw, cutoff)
    return [filtered[i] * envelope(i, total, curve=curve) * gain * 3.0 for i in range(total)]


def tone(seconds, freq_start, freq_end, curve=3.0, shape="sine", gain=1.0, vibrato=0.0):
    total = n(seconds)
    phase, out = 0.0, []
    for i in range(total):
        f = freq_start + (freq_end - freq_start) * (i / total)
        f *= 1.0 + vibrato * math.sin(2 * math.pi * 7.0 * i / RATE)
        phase += 2 * math.pi * f / RATE
        if shape == "sine":
            v = math.sin(phase)
        elif shape == "saw":
            v = 2.0 * ((phase / (2 * math.pi)) % 1.0) - 1.0
        else:  # square-ish
            v = math.tanh(3.0 * math.sin(phase))
        out.append(v * envelope(i, total, curve=curve) * gain)
    return out


def mix(*layers):
    length = max(len(layer) for layer in layers)
    return [sum(layer[i] for layer in layers if i < len(layer)) for i in range(length)]


def resonant_knock(seconds, freqs, decay):
    total = n(seconds)
    return [sum(math.sin(2 * math.pi * f * i / RATE) * math.exp(-decay * i / RATE) for f in freqs) / len(freqs)
            * min(1.0, i / 40.0) for i in range(total)]


def main():
    # --- Engine (built into the client) ---
    write("engine/client/sounds/hurt.wav", mix(tone(0.22, 320, 140, shape="square", gain=0.5), noise_burst(0.12, 0.2, gain=0.4)))
    write("engine/client/sounds/death.wav", mix(tone(0.6, 260, 60, shape="square", gain=0.5, curve=2.0), noise_burst(0.3, 0.1, gain=0.3)))
    write("engine/client/sounds/pickup.wav", mix(tone(0.07, 900, 1300, gain=0.5, curve=1.5), [0.0] * n(0.05) + tone(0.08, 1300, 1800, gain=0.4)))
    write("engine/client/sounds/swing.wav", noise_burst(0.14, 0.08, curve=2.0, gain=0.6))
    write("engine/client/sounds/ui_click.wav", tone(0.03, 1800, 1400, gain=0.4, curve=6.0))
    write("engine/client/sounds/drop.wav", tone(0.08, 500, 300, gain=0.4))

    # --- base: block materials ---
    for variant in range(2):
        write(f"mods/base/sounds/stone_break{variant}.wav", mix(noise_burst(0.18, 0.35, gain=0.9), resonant_knock(0.15, [180 + variant * 30, 410], 30)))
        write(f"mods/base/sounds/wood_break{variant}.wav", mix(resonant_knock(0.2, [210 + variant * 25, 330, 520], 22), noise_burst(0.1, 0.15, gain=0.3)))
        write(f"mods/base/sounds/dirt_break{variant}.wav", noise_burst(0.16, 0.08 + variant * 0.02, curve=3.0))
        write(f"mods/base/sounds/grass_break{variant}.wav", mix(noise_burst(0.14, 0.25, curve=3.0, gain=0.6), noise_burst(0.14, 0.05, gain=0.5)))
        write(f"mods/base/sounds/sand_break{variant}.wav", noise_burst(0.2, 0.5, curve=2.0, gain=0.5))
    for variant in range(3):
        write(f"mods/base/sounds/stone_step{variant}.wav", noise_burst(0.06, 0.3, gain=0.5))
        write(f"mods/base/sounds/wood_step{variant}.wav", resonant_knock(0.08, [240 + variant * 20, 400], 50))
        write(f"mods/base/sounds/soft_step{variant}.wav", noise_burst(0.08, 0.06, gain=0.6))
    glass = []
    for k in range(6):
        glass = mix(glass, [0.0] * n(0.02 * k) + tone(0.25, 2200 + rng.uniform(-400, 900), 2000, gain=0.25, curve=3.0))
    write("mods/base/sounds/glass_break.wav", mix(glass, noise_burst(0.1, 0.6, gain=0.4)))
    write("mods/base/sounds/eat.wav", mix(noise_burst(0.09, 0.2, gain=0.5), [0.0] * n(0.14) + noise_burst(0.09, 0.2, gain=0.5), [0.0] * n(0.28) + noise_burst(0.09, 0.2, gain=0.4)))

    # --- vanilla: mobs ---
    write("mods/vanilla/sounds/zombie_ambient.wav", tone(0.9, 120, 90, shape="saw", gain=0.35, curve=1.5, vibrato=0.06))
    write("mods/vanilla/sounds/zombie_hurt.wav", tone(0.3, 180, 110, shape="saw", gain=0.5, curve=2.0, vibrato=0.1))
    write("mods/vanilla/sounds/zombie_death.wav", tone(0.8, 150, 50, shape="saw", gain=0.5, curve=1.5, vibrato=0.08))
    write("mods/vanilla/sounds/pig_ambient.wav", mix(tone(0.18, 420, 300, shape="square", gain=0.25, vibrato=0.15), [0.0] * n(0.22) + tone(0.16, 400, 280, shape="square", gain=0.2, vibrato=0.15)))
    write("mods/vanilla/sounds/pig_hurt.wav", tone(0.22, 700, 420, shape="square", gain=0.3, vibrato=0.2))
    write("mods/vanilla/sounds/pig_death.wav", tone(0.5, 600, 180, shape="square", gain=0.3, curve=1.5, vibrato=0.2))

    # --- arcana & guild ---
    write("mods/arcana/sounds/spark_cast.wav", mix(tone(0.25, 600, 2400, gain=0.35, curve=1.5), noise_burst(0.2, 0.7, gain=0.15)))
    write("mods/arcana/sounds/spark_hit.wav", mix(tone(0.2, 1800, 500, gain=0.3), noise_burst(0.15, 0.5, gain=0.35)))
    write("mods/guild/sounds/coin.wav", mix(tone(0.12, 1568, 1568, gain=0.35, curve=2.0), [0.0] * n(0.09) + tone(0.3, 2093, 2093, gain=0.35, curve=2.5)))


if __name__ == "__main__":
    main()
