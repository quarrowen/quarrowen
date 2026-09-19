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

    # Footsteps, block breaks and breaking glass used to be generated here. They are Kenney's now - see
    # tools/import_kenney_sounds.py, which is where they come from and what records the licence. Taking
    # them out re-rolled the sounds generated after them, once, which is why a dozen creature noises
    # changed in the same commit: one RNG drives the whole file in order. (2026-09-18)
    write("mods/base/sounds/eat.wav", mix(noise_burst(0.09, 0.2, gain=0.5), [0.0] * n(0.14) + noise_burst(0.09, 0.2, gain=0.5), [0.0] * n(0.28) + noise_burst(0.09, 0.2, gain=0.4)))

    # --- vanilla: mobs ---
    write("mods/vanilla/sounds/zombie_ambient.wav", tone(0.9, 120, 90, shape="saw", gain=0.35, curve=1.5, vibrato=0.06))
    write("mods/vanilla/sounds/zombie_hurt.wav", tone(0.3, 180, 110, shape="saw", gain=0.5, curve=2.0, vibrato=0.1))
    write("mods/vanilla/sounds/zombie_death.wav", tone(0.8, 150, 50, shape="saw", gain=0.5, curve=1.5, vibrato=0.08))
    write("mods/vanilla/sounds/pig_ambient.wav", mix(tone(0.18, 420, 300, shape="square", gain=0.25, vibrato=0.15), [0.0] * n(0.22) + tone(0.16, 400, 280, shape="square", gain=0.2, vibrato=0.15)))
    write("mods/vanilla/sounds/pig_hurt.wav", tone(0.22, 700, 420, shape="square", gain=0.3, vibrato=0.2))
    write("mods/vanilla/sounds/pig_death.wav", tone(0.5, 600, 180, shape="square", gain=0.3, curve=1.5, vibrato=0.2))

    rattle = []
    for k in range(5):
        rattle = mix(rattle, [0.0] * n(0.035 * k) + resonant_knock(0.05, [900 + rng.uniform(-150, 250), 1700], 80))
    write("mods/vanilla/sounds/skeleton_hurt.wav", rattle)
    write("mods/vanilla/sounds/skeleton_death.wav", mix(rattle, [0.0] * n(0.15) + rattle, [0.0] * n(0.3) + noise_burst(0.2, 0.3, gain=0.3)))
    write("mods/vanilla/sounds/colossus_stomp.wav", mix(tone(0.9, 70, 35, gain=0.7, curve=2.0), noise_burst(0.5, 0.04, curve=2.0, gain=0.8)))
    write("mods/vanilla/sounds/colossus_roar.wav", mix(tone(1.4, 95, 70, shape="saw", gain=0.45, curve=1.2, vibrato=0.08), noise_burst(1.2, 0.06, curve=1.5, gain=0.3)))
    write("mods/vanilla/sounds/colossus_hurt.wav", mix(resonant_knock(0.4, [110, 160, 240], 9), noise_burst(0.25, 0.2, gain=0.3)))

    # --- arcana & guild ---

    crafting_sounds()
    hunger_sounds()
    guide_sounds()
    animal_sounds()
    # Last, always. One RNG drives every sound in order, so a call inserted anywhere but the end
    # re-rolls all of them - which is what happened the first time this line went in, quietly changing
    # a dozen sounds that were fine. Same rule as tools/generate_textures.gd. (2026-09-18)
    ambient_sounds()
    weather_sounds()


def animal_sounds():
    # --- Vanilla farm animals (a separate function so it can be regenerated alone) ---
    write("mods/vanilla/sounds/cow_ambient.wav", tone(0.9, 150, 115, shape="saw", gain=0.35, curve=1.2, vibrato=0.06))
    write("mods/vanilla/sounds/cow_hurt.wav", tone(0.35, 190, 140, shape="saw", gain=0.4, curve=1.8, vibrato=0.1))
    write("mods/vanilla/sounds/sheep_ambient.wav", tone(0.55, 420, 360, shape="square", gain=0.22, curve=1.5, vibrato=0.35))
    write("mods/vanilla/sounds/sheep_hurt.wav", tone(0.25, 480, 380, shape="square", gain=0.28, curve=2.0, vibrato=0.3))
    write("mods/vanilla/sounds/chicken_ambient.wav", mix(tone(0.07, 900, 700, shape="square", gain=0.2), [0.0] * n(0.11) + tone(0.07, 950, 750, shape="square", gain=0.2),
                                                         [0.0] * n(0.22) + tone(0.14, 1000, 650, shape="square", gain=0.22)))
    write("mods/vanilla/sounds/chicken_hurt.wav", tone(0.18, 1200, 700, shape="square", gain=0.3, curve=2.0))
    write("mods/vanilla/sounds/wolf_ambient.wav", mix(tone(0.12, 520, 380, shape="saw", gain=0.3, curve=2.5), [0.0] * n(0.2) + tone(0.14, 560, 360, shape="saw", gain=0.3, curve=2.5)))
    write("mods/vanilla/sounds/wolf_hurt.wav", tone(0.3, 900, 500, shape="square", gain=0.25, curve=2.0, vibrato=0.2))
    write("mods/vanilla/sounds/wolf_growl.wav", tone(0.6, 110, 90, shape="saw", gain=0.35, curve=1.2, vibrato=0.4))
    write("mods/vanilla/sounds/spider_ambient.wav", mix(noise_burst(0.3, 0.6, curve=1.5, gain=0.25), [0.0] * n(0.05) + resonant_knock(0.05, [2400], 60), [0.0] * n(0.15) + resonant_knock(0.05, [2600], 60)))
    write("mods/vanilla/sounds/spider_hurt.wav", mix(noise_burst(0.2, 0.8, gain=0.4), tone(0.15, 1500, 900, shape="square", gain=0.15)))
    write("mods/vanilla/sounds/slime_hop.wav", mix(tone(0.14, 180, 420, gain=0.35, curve=2.0), noise_burst(0.08, 0.1, gain=0.2)))
    write("mods/vanilla/sounds/slime_hurt.wav", tone(0.2, 420, 160, gain=0.35, curve=2.0, vibrato=0.2))
    write("mods/vanilla/sounds/stalker_ambient.wav", mix(noise_burst(0.9, 0.05, curve=1.0, gain=0.25), tone(0.9, 90, 70, shape="saw", gain=0.12, curve=1.0, vibrato=0.5)))
    write("mods/vanilla/sounds/stalker_screech.wav", mix(tone(0.5, 1400, 700, shape="saw", gain=0.25, curve=1.5, vibrato=0.6), noise_burst(0.4, 0.5, gain=0.25)))
    write("mods/vanilla/sounds/milk.wav", mix(noise_burst(0.2, 0.15, curve=2.0, gain=0.3), tone(0.2, 300, 500, gain=0.12)))


def hunger_sounds():
    # --- Engine: eating (a separate function so it can be regenerated alone) ---
    write("engine/client/sounds/munch.wav", mix(noise_burst(0.07, 0.25, curve=3.0, gain=0.55), noise_burst(0.05, 0.08, gain=0.35)))
    write("engine/client/sounds/burp.wav", tone(0.32, 180, 120, shape="saw", gain=0.35, curve=1.8, vibrato=0.25))
    write("engine/client/sounds/explosion.wav", mix(noise_burst(1.2, 0.08, curve=1.6, gain=1.0), noise_burst(0.3, 0.5, curve=3.0, gain=0.6), tone(0.8, 90, 35, gain=0.6, curve=1.5)))
    write("engine/client/sounds/fuse.wav", noise_burst(1.4, 0.9, curve=0.3, gain=0.35))
    write("engine/client/sounds/gulp.wav", mix(tone(0.12, 220, 420, gain=0.4, curve=2.5), noise_burst(0.08, 0.05, gain=0.25)))


def guide_sounds():
    # --- Engine: guidebook page turn (a separate function so it can be regenerated alone) ---
    swish = [s * math.sin(math.pi * i / n(0.22)) for i, s in enumerate(noise_burst(0.22, 0.35, curve=0.8, gain=0.35))]


def crafting_sounds():
    # --- Engine: crafting (a separate function so it can be regenerated alone) ---
    chime = mix(tone(0.18, 1046, 1046, gain=0.3, curve=3.0), [0.0] * n(0.07) + tone(0.22, 1318, 1318, gain=0.28, curve=3.0),
                [0.0] * n(0.14) + tone(0.35, 1568, 1568, gain=0.25, curve=3.0))


def weather_sounds():
    """Rain and a storm, as loops. Last in the file, same rule as everything else here.

    Rain is filtered noise with no shape to it at all - shape is what makes a loop audible as a loop,
    and this one plays for minutes. The storm is the same thing lower and heavier, so walking from one
    into the other is a change of weight rather than a change of sound.
    """
    def hiss(seconds, cutoff, gain):
        body = lowpass(noise_burst(seconds, cutoff, curve=0.0, gain=gain), 0.8)
        # Ends where it begins, so the loop has no seam: the same lesson the music generator learned.
        blend = n(0.25)
        for i in range(blend):
            f = i / blend
            body[i] = body[i] * f + body[len(body) - blend + i] * (1 - f)
        return body[:len(body) - blend]

    write("mods/vanilla/sounds/rain.wav", hiss(4.0, 0.22, 0.30))
    write("mods/vanilla/sounds/storm.wav", hiss(4.0, 0.10, 0.42))


def ambient_sounds():
    """Atmosphere: wind, a cave drip, water at the edge of a lake.

    Kenney's packs have none of these - they are footsteps, impacts and interface - so they stay
    synthesised. Longer and quieter than an effect, because these arrive unasked every twenty seconds
    or so and the job is to be noticed once and then not thought about.
    """
    # Wind: filtered noise with a slow swell, so it breathes rather than hisses.
    gust = lowpass(noise_burst(3.2, 0.06, curve=0.25, gain=0.5), 0.9)
    gust = [s * (0.35 + 0.65 * (0.5 - 0.5 * math.cos(2 * math.pi * i / len(gust)))) for i, s in enumerate(gust)]
    write("mods/vanilla/sounds/wind.wav", gust)

    # A drip: a short wet knock with a rising tail, which is what makes it read as a drop rather than
    # a tap, plus a small room to fall in.
    drop = mix(tone(0.05, 900, 1700, gain=0.35, curve=4.0), noise_burst(0.02, 0.5, gain=0.12))
    echo = [0.0] * n(0.13) + [s * 0.3 for s in drop]
    write("mods/vanilla/sounds/drip.wav", mix(drop, echo))

    # Water at the edge: two soft washes of filtered noise, one after the other.
    def wash(seconds, gain):
        body = lowpass(noise_burst(seconds, 0.12, curve=0.5, gain=gain), 0.75)
        return [s * math.sin(math.pi * i / len(body)) for i, s in enumerate(body)]
    write("mods/vanilla/sounds/lapping.wav", mix(wash(0.9, 0.35), [0.0] * n(0.7) + wash(1.1, 0.28)))


if __name__ == "__main__":
    main()
