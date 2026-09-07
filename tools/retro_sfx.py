#!/usr/bin/env python3

"""
retro_sopwith_sfx.py

Procedural sound-effect generator for a Sopwith-inspired arcade game.

Goals:
- Soft and pleasant
- Synthesized rather than sampled
- Inspired by real sounds
- Warm low-mid emphasis
- Minimal harsh high frequencies
- Suitable for endless replay

Usage:

    python retro_sopwith_sfx.py engine
    python retro_sopwith_sfx.py bang
    python retro_sopwith_sfx.py bump
    python retro_sopwith_sfx.py boing
    python retro_sopwith_sfx.py bonus

    python retro_sopwith_sfx.py engine -o engine.wav
"""

import argparse
import wave

import numpy as np

SAMPLE_RATE = 48000

###########################################################################
# Utility
###########################################################################

def normalize(audio, peak=0.80):
    m = np.max(np.abs(audio))
    if m > 0:
        audio = audio / m
    return audio * peak

def lowpass_fft(audio, cutoff_hz):
    fft = np.fft.rfft(audio)

    freqs = np.fft.rfftfreq(len(audio), 1.0 / SAMPLE_RATE)

    response = 1.0 / (1.0 + (freqs / cutoff_hz) ** 6)

    fft *= response

    return np.fft.irfft(fft, n=len(audio))

def soft_saturate(audio):
    return np.tanh(audio * 1.3)

def save_wav(filename, audio):

    audio = np.clip(audio, -1.0, 1.0)

    pcm = (audio * 32767).astype(np.int16)

    with wave.open(filename, "wb") as wav:
        wav.setnchannels(1)
        wav.setsampwidth(2)
        wav.setframerate(SAMPLE_RATE)
        wav.writeframes(pcm.tobytes())

def noise(seed, size):
    rng = np.random.default_rng(seed)
    return rng.normal(0.0, 1.0, size)

###########################################################################
# Engine
###########################################################################

def engine(duration=3.0):

    n = int(duration * SAMPLE_RATE)
    t = np.arange(n) / SAMPLE_RATE

    rpm_wobble = 1.0 + 0.02 * np.sin(2 * np.pi * 0.45 * t)

    base_freq = 82.0 * rpm_wobble

    phase1 = np.cumsum(base_freq) * (2 * np.pi / SAMPLE_RATE)
    phase2 = phase1 * 2
    phase3 = phase1 * 3

    body = 0.55 * np.sin(phase1) + 0.25 * np.sin(phase2 + 0.4) + 0.15 * np.sin(phase3 + 0.9)

    pulse_rate = 19.0

    pulse = 0.5 + 0.5 * np.sin(2 * np.pi * pulse_rate * t)

    pulse = pulse**2

    combustion_noise = noise(1, n)
    combustion_noise = lowpass_fft(combustion_noise, 1200)

    combustion = pulse * combustion_noise * 0.20

    prop_noise = noise(2, n)
    prop_noise = lowpass_fft(prop_noise, 800)

    propeller = 0.08 * prop_noise * (0.5 + 0.5 * np.sin(2 * np.pi * 38 * t))

    audio = body + combustion + propeller

    audio = lowpass_fft(audio, 2200)
    audio = soft_saturate(audio)
    audio = normalize(audio)

    # Loop-friendly boundary matching

    fade = 2048

    blend = (audio[:fade] + audio[-fade:]) * 0.5

    audio[:fade] = blend
    audio[-fade:] = blend

    return audio

###########################################################################
# Bang
###########################################################################

def bang(duration=0.25):

    n = int(duration * SAMPLE_RATE)
    t = np.arange(n) / SAMPLE_RATE

    burst = noise(3, n)

    burst = lowpass_fft(burst, 1500)

    env = np.exp(-t * 16)

    resonance = 0.9 * np.sin(2 * np.pi * 90 * t) + 0.4 * np.sin(2 * np.pi * 220 * t)

    audio = (burst * 0.7 + resonance) * env

    audio = lowpass_fft(audio, 1800)
    audio = soft_saturate(audio)

    return normalize(audio)

###########################################################################
# Bump
###########################################################################

def bump(duration=0.20):

    n = int(duration * SAMPLE_RATE)
    t = np.arange(n) / SAMPLE_RATE

    attack = np.minimum(t * 60, 1.0)

    decay = np.exp(-t * 14)

    env = attack * decay

    dirt = noise(4, n)

    dirt = lowpass_fft(dirt, 500)

    body = np.sin(2 * np.pi * 110 * t) + 0.25 * np.sin(2 * np.pi * 220 * t)

    audio = (body * 0.8 + dirt * 0.3) * env

    audio = lowpass_fft(audio, 1200)

    return normalize(audio)

###########################################################################
# Boing
###########################################################################

def boing(duration=0.55):

    n = int(duration * SAMPLE_RATE)
    t = np.arange(n) / SAMPLE_RATE

    f0 = 240
    f1 = 90

    freq = f0 + (f1 - f0) * (t / duration)

    phase = np.cumsum(freq) * (2 * np.pi / SAMPLE_RATE)

    env = np.exp(-t * 4.5)

    oscillator = np.sin(phase) + 0.40 * np.sin(phase * 2.03)

    click = noise(5, n)

    click = lowpass_fft(click, 2000)

    click *= np.exp(-t * 50)

    audio = (oscillator + click * 0.20) * env

    audio = lowpass_fft(audio, 1800)

    return normalize(audio)

###########################################################################
# Bonus Pickup
###########################################################################

def bonus(duration=0.35):

    n = int(duration * SAMPLE_RATE)
    t = np.arange(n) / SAMPLE_RATE

    attack = np.minimum(t * 80, 1.0)

    decay = np.exp(-t * 7)

    env = attack * decay

    f1 = 660
    f2 = 990

    audio = 0.9 * np.sin(2 * np.pi * f1 * t) + 0.6 * np.sin(2 * np.pi * f2 * t) + 0.15 * np.sin(2 * np.pi * 1320 * t)

    audio *= env

    audio = lowpass_fft(audio, 2500)

    audio = soft_saturate(audio)

    return normalize(audio, 0.70)

###########################################################################
# Engine Sputter
###########################################################################

def sputter(duration=2.2):

    n = int(duration * SAMPLE_RATE)
    t = np.arange(n) / SAMPLE_RATE

    rng = np.random.default_rng(6)

    #
    # Engine gradually slows
    #

    rpm = np.linspace(85.0, 45.0, n)

    phase = np.cumsum(rpm) * (2 * np.pi / SAMPLE_RATE)

    body = (
        0.60 * np.sin(phase)
        + 0.25 * np.sin(phase * 2 + 0.35)
        + 0.12 * np.sin(phase * 3 + 0.8)
    )

    #
    # Irregular combustion pulses
    #

    pulse_rate = np.linspace(20.0, 10.0, n)

    pulse_phase = np.cumsum(pulse_rate) * (2 * np.pi / SAMPLE_RATE)

    pulses = (np.sin(pulse_phase) > 0).astype(float)

    #
    # Randomly remove more pulses as time passes
    #

    keep_probability = np.linspace(0.95, 0.30, n)

    mask = (rng.random(n) < keep_probability).astype(float)

    pulses *= mask

    #
    # Slightly smooth pulse edges
    #

    kernel = np.hanning(101)
    kernel /= kernel.sum()

    pulses = np.convolve(pulses, kernel, mode="same")

    #
    # Combustion noise
    #

    combustion = noise(61, n)
    combustion = lowpass_fft(combustion, 1200)
    combustion *= pulses * 0.30

    #
    # Occasional backfires
    #

    backfire = np.zeros(n)

    for when in [0.55, 1.05, 1.55]:

        idx = int(when * SAMPLE_RATE)

        if idx >= n:
            continue

        length = min(2500, n - idx)

        env = np.exp(-np.arange(length) / 300)

        burst = noise(idx, length)

        burst = lowpass_fft(burst, 2200)

        burst += 0.8 * np.sin(
            2 * np.pi * 170 *
            np.arange(length) / SAMPLE_RATE
        )

        backfire[idx:idx + length] += 0.35 * burst * env

    #
    # Propeller wash
    #

    prop = noise(62, n)

    prop = lowpass_fft(prop, 700)

    prop *= (
        0.05
        * (0.5 + 0.5 * np.sin(phase * 0.45))
    )

    #
    # Fade toward silence
    #

    envelope = np.linspace(1.0, 0.0, n)

    audio = (
        body * (0.55 + 0.45 * pulses)
        + combustion
        + prop
        + backfire
    )

    audio *= envelope

    audio = lowpass_fft(audio, 2000)

    audio = soft_saturate(audio)

    return normalize(audio)

###########################################################################
# Registry
###########################################################################

GENERATORS = {
    "engine": engine,
    "bang": bang,
    "sputter": sputter,
    "bump": bump,
    "boing": boing,
    "bonus": bonus,
}

###########################################################################
# Main
###########################################################################

def main():

    parser = argparse.ArgumentParser(description="Generate Sopwith-style retro arcade sound effects.")

    parser.add_argument(
        "sound",
        choices=GENERATORS.keys(),
        help="Sound effect type",
    )

    parser.add_argument(
        "-o",
        "--output",
        help="Output WAV filename",
    )

    args = parser.parse_args()
    audio = GENERATORS[args.sound]()
    output = args.output or f"{args.sound}.wav"
    save_wav(output, audio)
    print(f"Wrote {output}")

if __name__ == "__main__":
    main()
