#!/usr/bin/env python3
"""Turns the recorded tour into promo-en.mp4 and promo-zh.mp4, and tour.gif.

    promo.py <folder> <kokoro model> <kokoro voices>

The folder holds what linux/packaging/showcase.sh made: the pictures of
the features (watch-subtitles, danmaku, home-reasons, each also with
-zh-Hans for the Chinese interface), and tour.mp4 with scenes.txt.
The cut has animated titles over them, a narration read by Kokoro
(Apache-2.0), and music and sound effects synthesised here, so nothing in
the video comes from elsewhere.
"""

import math
import os
import re
import subprocess
import sys
import wave
from dataclasses import dataclass, field

import numpy as np
from PIL import Image, ImageDraw, ImageFilter, ImageFont
from scipy import signal

W, H, FPS, RATE = 1920, 1080, 30, 44100
OVERLAP = 0.45
RED = (229, 57, 53)
INK = (14, 14, 18)
URL = 'github.com/0x696c757a696f/lumtub'

STORY = {
    'en': {
        'voice': 'af_heart',
        'brand': (['Lumtub.', 'YouTube, made for your desktop.'], 'YouTube, made for your desktop'),
        'subtitles': ('Two subtitles at once, in any two languages.', 'Bilingual subtitles', ['Any two languages', 'Translated as it plays']),
        'danmaku': ('Live chat flies across the picture, as danmaku.', 'Danmaku', ['Live chat', 'Chat replay']),
        'home': ('Recommendations are worked out on your own computer, and every card says why.',
                 'A feed that explains itself', ['Worked out on your PC', 'Every card says why']),
        'palettes': ('Ten palettes, and seventy-two languages.', 'Make it yours', ['10 palettes', '72 languages']),
        'outro': (['Free. Open source. No ads.'], 'Free · Open source · No ads', 'Download free'),
    },
    'zh': {
        'voice': 'zf_xiaoxiao',
        'brand': (['Lumtub，', '为桌面打造的 YouTube 客户端。'], '为桌面打造的 YouTube 客户端'),
        'subtitles': ('双语字幕，任选两种语言同时显示。', '双语字幕', ['任选两种语言', '边播边翻译']),
        'danmaku': ('直播聊天变成弹幕，从画面上飞过。', '弹幕', ['直播聊天', '聊天回放']),
        'home': ('推荐只在你自己的电脑上计算，每张卡片都说明原因。', '会解释自己的推荐', ['只在本机计算', '每张卡片说明原因']),
        'palettes': ('十套配色，七十二种界面语言。', '换成你喜欢的样子', ['10 套配色', '72 种语言']),
        'outro': (['免费、开源、没有广告。'], '免费 · 开源 · 无广告', '免费下载'),
    },
}

# What each scene shows: a picture the showcase took (named for the
# interface language, else the English one), or a stretch of the recorded
# tour at a playback speed.
SCREENS = [('subtitles', 'watch-subtitles'), ('danmaku', 'danmaku'), ('home', 'home-reasons'), ('palettes', 2.5)]


def ease_out(x):
    x = min(max(x, 0.0), 1.0)
    return 1 - (1 - x) ** 3


def ease_back(x):
    x = min(max(x, 0.0), 1.0)
    c = 1.9
    return 1 + (c + 1) * (x - 1) ** 3 + c * (x - 1) ** 2


def font_file(pattern):
    override = os.environ.get('PROMO_FONT')
    if override:
        return override, 0
    out = subprocess.run(['fc-match', '-f', '%{file}\n%{index}', pattern], capture_output=True, text=True).stdout.split('\n')
    return out[0], int(out[1] or 0)


class Fonts:
    def __init__(self):
        self.file, self.index = font_file('Noto Sans CJK SC:bold')
        self.cache = {}

    def get(self, size):
        if size not in self.cache:
            self.cache[size] = ImageFont.truetype(self.file, size, index=self.index)
        return self.cache[size]


FONTS = Fonts()


def text_image(text, size, color=(255, 255, 255)):
    font = FONTS.get(size)
    box = font.getbbox(text)
    ascent, descent = font.getmetrics()
    # The font's own ascent and descent, so no accent or descender is cut,
    # with the empty space above capitals trimmed alike for every line.
    top = int(size * 0.18)
    img = Image.new('RGBA', (box[2] - box[0] + 8, ascent + descent - top + 6), (0, 0, 0, 0))
    ImageDraw.Draw(img).text((4 - box[0], 3 - top), text, font=font, fill=color)
    return img


def rounded(size, radius, color):
    s = 3
    img = Image.new('RGBA', (size[0] * s, size[1] * s), (0, 0, 0, 0))
    ImageDraw.Draw(img).rounded_rectangle((0, 0, size[0] * s - 1, size[1] * s - 1), radius * s, fill=color)
    return img.resize(size, Image.LANCZOS)


def logo(size):
    s = 4
    img = Image.new('RGBA', (size * s, size * s), (0, 0, 0, 0))
    d = ImageDraw.Draw(img)
    d.rounded_rectangle((0, 0, size * s - 1, size * s - 1), int(size * s * 0.24), fill=RED + (255,))
    c = size * s / 2
    r = size * s * 0.22
    d.polygon([(c - r * 0.75, c - r), (c - r * 0.75, c + r), (c + r * 1.05, c)], fill=(255, 255, 255, 255))
    return img.resize((size, size), Image.LANCZOS)


def place(canvas, img, x, y, alpha=1.0, scale=1.0, center=False):
    if alpha <= 0.01 or scale <= 0.01:
        return
    if scale != 1.0:
        img = img.resize((max(1, int(img.width * scale)), max(1, int(img.height * scale))), Image.BICUBIC)
    if alpha < 1.0:
        img = img.copy()
        img.putalpha(img.getchannel('A').point(lambda a: int(a * alpha)))
    if center:
        x, y = x - img.width // 2, y - img.height // 2
    canvas.alpha_composite(img, (int(x), int(y)))


class Backdrop:
    """Near-black with two slow coloured glows."""

    def __init__(self):
        self.base = Image.new('RGBA', (W, H), INK + (255,))
        glow = Image.new('RGBA', (900, 900), (0, 0, 0, 0))
        ImageDraw.Draw(glow).ellipse((150, 150, 750, 750), fill=RED + (70,))
        self.red = glow.filter(ImageFilter.GaussianBlur(150))
        glow = Image.new('RGBA', (900, 900), (0, 0, 0, 0))
        ImageDraw.Draw(glow).ellipse((150, 150, 750, 750), fill=(90, 70, 220, 60))
        self.blue = glow.filter(ImageFilter.GaussianBlur(160))

    def at(self, t):
        img = self.base.copy()
        img.alpha_composite(self.red, (int(-250 + 160 * math.sin(t * 0.35)), int(-300 + 120 * math.cos(t * 0.27))))
        img.alpha_composite(self.blue, (int(W - 650 + 140 * math.cos(t * 0.31)), int(H - 600 + 110 * math.sin(t * 0.23))))
        return img


class Clip:
    """Frames of tour.mp4 from a start time, read in order."""

    def __init__(self, path, start, end, speed, size):
        self.size, self.speed, self.length = size, speed, end - start
        self.proc = subprocess.Popen(['ffmpeg', '-v', 'error', '-ss', f'{start:.3f}', '-t', f'{end - start:.3f}', '-i', path,
                                      '-vf', f'scale={size[0]}:{size[1]}:flags=bicubic,fps={FPS}', '-f', 'rawvideo', '-pix_fmt', 'rgb24', '-'],
                                     stdout=subprocess.PIPE)
        self.index, self.frame = -1, Image.new('RGB', size, INK)

    def at(self, t):
        want = int(t * self.speed * FPS)
        while self.index < want:
            raw = self.proc.stdout.read(self.size[0] * self.size[1] * 3)
            if len(raw) < self.size[0] * self.size[1] * 3:
                break
            self.frame = Image.frombuffer('RGB', self.size, raw)
            self.index += 1
        return self.frame


@dataclass
class Segment:
    kind: str
    duration: float
    voice: np.ndarray
    cues: list
    data: dict = field(default_factory=dict)
    start: float = 0.0


class Voice:
    def __init__(self, model, voices):
        from kokoro_onnx import Kokoro
        self.kokoro = Kokoro(model, voices)
        self.zh = None

    def phonemes_zh(self, text):
        if self.zh is None:
            from misaki import zh
            self.zh = zh.ZHG2P()
        out = self.zh(text)
        out = out[0] if isinstance(out, tuple) else out
        # Latin words such as YouTube stay as letters; read them in English.
        return re.sub(r'[A-Za-z][A-Za-z0-9]*', lambda m: self.kokoro.tokenizer.phonemize(m[0], 'en-us'), out)

    def say(self, lang, voice, text):
        if lang == 'zh':
            audio, rate = self.kokoro.create(self.phonemes_zh(text), voice=voice, speed=1.0, is_phonemes=True)
        else:
            audio, rate = self.kokoro.create(text, voice=voice, speed=1.0, lang='en-us')
        audio = signal.resample_poly(np.asarray(audio, dtype=np.float64), RATE // 100, rate // 100)
        trimmed = np.nonzero(np.abs(audio) > 0.01)[0]
        return audio[max(0, trimmed[0] - 400):trimmed[-1] + 2000] if len(trimmed) else audio

    def lines(self, lang, voice, lines, gap=0.28):
        parts, cues, at = [], [], 0.0
        for line in lines:
            audio = self.say(lang, voice, line)
            cues.append(at)
            parts += [audio, np.zeros(int(gap * RATE))]
            at += len(audio) / RATE + gap
        return np.concatenate(parts), cues


def build(story, voice, scenes, lang, folder):
    v = story['voice']
    segments = []
    lines, tagline = story['brand']
    audio, cues = voice.lines(lang, v, lines, gap=0.3)
    segments.append(Segment('brand', len(audio) / RATE + 0.6, audio, cues, {'tagline': tagline}))
    for name, source in SCREENS:
        said, title, chips = story[name]
        data = {'name': name, 'title': title, 'chips': chips}
        if isinstance(source, str):
            still = picture(folder, source, lang)
            if still is None:
                continue
            data['still'] = still
        else:
            if name not in scenes:
                continue
            start, end = scenes[name]
            data.update({'from': start + 0.3, 'to': end, 'speed': source})
        audio = voice.say(lang, v, said)
        segments.append(Segment('screen', max(len(audio) / RATE + 0.6, 3.0), audio, [0.0], data))
    lines, title, button = story['outro']
    audio, cues = voice.lines(lang, v, lines, gap=0.3)
    segments.append(Segment('outro', len(audio) / RATE + 2.4, audio, cues, {'title': title, 'button': button}))
    at = 0.0
    for s in segments:
        s.start = at
        at += s.duration - OVERLAP
    return segments, at + OVERLAP


def picture(folder, name, lang):
    """The showcase's picture [name] in [lang]'s interface, else in English."""
    for file in ([f'{name}-zh-Hans.png'] if lang == 'zh' else []) + [f'{name}.png']:
        path = os.path.join(folder, file)
        if os.path.exists(path):
            img = Image.open(path).convert('RGB')
            # Cut to 16:9 around the middle, as the tour's frames are.
            w, h = img.size
            if w * 9 > h * 16:
                cut = (w - h * 16 // 9) // 2
                img = img.crop((cut, 0, w - cut, h))
            else:
                cut = (h - w * 9 // 16) // 2
                img = img.crop((0, cut, w, h - cut))
            return img.resize((1600, 900), Image.LANCZOS)
    return None


class Painter:
    def __init__(self, tour):
        self.tour = tour
        self.backdrop = Backdrop()
        self.cache = {}
        self.clips = {}
        self.window = (1440, 810)
        self.mask = rounded(self.window, 22, (255, 255, 255, 255)).getchannel('A')
        shadow = Image.new('RGBA', (self.window[0] + 160, self.window[1] + 160), (0, 0, 0, 0))
        ImageDraw.Draw(shadow).rounded_rectangle((80, 100, self.window[0] + 80, self.window[1] + 100), 24, fill=(0, 0, 0, 170))
        self.shadow = shadow.filter(ImageFilter.GaussianBlur(36))

    def text(self, text, size, color=(255, 255, 255)):
        key = (text, size, color)
        if key not in self.cache:
            self.cache[key] = text_image(text, size, color)
        return self.cache[key]

    def image(self, key, make):
        if key not in self.cache:
            self.cache[key] = make()
        return self.cache[key]

    def frame(self, seg, t, now):
        img = self.backdrop.at(now)
        getattr(self, seg.kind)(img, seg, t)
        return img

    def headline(self, img, title, t, y=64):
        p = ease_out((t - 0.15) / 0.5)
        bar = self.image(('bar',), lambda: rounded((10, 64), 5, RED + (255,)))
        place(img, bar, 240, y + 12, alpha=p)
        place(img, self.text(title, 60), 268, y + (1 - p) * 30, alpha=p)

    def chip(self, label):
        return self.image(('chip', label), lambda: self._chip(label))

    def _chip(self, label):
        txt = text_image(label, 34)
        img = rounded((txt.width + 64, 66), 33, (255, 255, 255, 236))
        dark = text_image(label, 34, INK)
        img.alpha_composite(dark, (32, (66 - dark.height) // 2 + 1))
        dot = rounded((14, 14), 7, RED + (255,))
        img.alpha_composite(dot, (12, 26))
        return img

    def brand(self, img, seg, t):
        p = ease_back((t - 0.15) / 0.55)
        size = 240
        place(img, self.image(('logo', size), lambda: logo(size)), W / 2, 400, alpha=min(1, max(0, (t - 0.15) / 0.2)), scale=max(0.01, p), center=True)
        name = self.text('Lumtub', 150)
        reveal = ease_out((t - 0.45) / 0.6)
        if reveal > 0:
            crop = name.crop((0, 0, max(1, int(name.width * reveal)), name.height))
            place(img, crop, W / 2 - name.width / 2, 560)
        cue = seg.cues[-1] if seg.cues else 1.2
        q = ease_out((t - cue) / 0.6)
        place(img, self.text(seg.data['tagline'], 52, (220, 220, 228)), W / 2, 820 + (1 - q) * 30, alpha=q, center=True)

    def screen(self, img, seg, t):
        d = seg.data
        name = d['name']
        if 'still' in d:
            frame = d['still']
        else:
            if name not in self.clips:
                self.clips[name] = Clip(self.tour, d['from'], d['to'], d['speed'], (1600, 900))
            frame = self.clips[name].at(t)
        zoom = 1.0 + 0.08 * (t / seg.duration)
        cw, ch = 1600 / zoom, 900 / zoom
        fx, fy = {'subtitles': (0.5, 0.85), 'danmaku': (0.5, 0.15)}.get(name, (0.5, 0.35))
        x0, y0 = (1600 - cw) * fx, (900 - ch) * fy
        shot = frame.crop((int(x0), int(y0), int(x0 + cw), int(y0 + ch))).resize(self.window, Image.BILINEAR).convert('RGBA')
        shot.putalpha(self.mask)
        rise = ease_out(t / 0.6)
        x, y = (W - self.window[0]) // 2, 200 + int((1 - rise) * 60)
        img.alpha_composite(self.shadow, (x - 80, y - 80))
        img.alpha_composite(shot, (x, y))
        self.headline(img, d['title'], t)
        for i, label in enumerate(d['chips']):
            p = (t - 0.9 - i * 0.45) / 0.35
            if p <= 0:
                continue
            chip = self.chip(label)
            place(img, chip, W - 250 - chip.width, 860 - (len(d['chips']) - 1 - i) * 84, alpha=min(1, p * 2), scale=0.7 + 0.3 * ease_back(p))

    def outro(self, img, seg, t):
        p = ease_back((t - 0.1) / 0.5)
        place(img, self.image(('logo', 150), lambda: logo(150)), W / 2 - 250, 300, scale=max(0.01, p), alpha=min(1, t / 0.2), center=True)
        q = ease_out((t - 0.3) / 0.5)
        place(img, self.text('Lumtub', 130), W / 2 + 90, 300 + (1 - q) * 20, alpha=q, center=True)
        r = ease_out((t - 0.7) / 0.5)
        place(img, self.text(seg.data['title'], 72), W / 2, 520 + (1 - r) * 30, alpha=r, center=True)
        place(img, self.text('Windows · Linux · macOS', 40, (190, 190, 200)), W / 2, 620, alpha=ease_out((t - 1.0) / 0.5), center=True)
        cue = seg.cues[-1] if len(seg.cues) > 1 else 1.4
        b = (t - cue) / 0.4
        if b > 0:
            button = self.image(('button', seg.data['button']), lambda: self._button(seg.data['button']))
            pulse = 1 + 0.03 * math.sin(max(0, t - cue - 0.4) * 6)
            place(img, button, W / 2, 770, alpha=min(1, b * 2), scale=(0.7 + 0.3 * ease_back(b)) * pulse, center=True)
            place(img, self.text(URL, 36, (200, 200, 210)), W / 2, 880, alpha=ease_out(b - 0.5), center=True)
        fade = (t - (seg.duration - 0.7)) / 0.7
        if fade > 0:
            img.alpha_composite(Image.new('RGBA', (W, H), (0, 0, 0, int(255 * min(1, fade)))))

    def _button(self, label):
        txt = text_image(label, 50)
        img = rounded((txt.width + 120, 104), 52, RED + (255,))
        img.alpha_composite(txt, (60, (104 - txt.height) // 2 + 2))
        return img


def render(segments, total, tour, out_video, audio_file):
    painter = Painter(tour)
    enc = subprocess.Popen(['ffmpeg', '-v', 'error', '-y', '-f', 'rawvideo', '-pix_fmt', 'rgb24', '-s', f'{W}x{H}', '-r', str(FPS), '-i', '-',
                            '-i', audio_file, '-c:v', 'libx264', '-preset', 'medium', '-crf', '20', '-pix_fmt', 'yuv420p',
                            '-c:a', 'aac', '-b:a', '160k', '-af', 'loudnorm=I=-14:TP=-1.5:LRA=11', '-shortest', '-movflags', '+faststart', out_video],
                           stdin=subprocess.PIPE)
    for n in range(int(total * FPS)):
        now = n / FPS
        live = [s for s in segments if s.start <= now < s.start + s.duration]
        frames = [painter.frame(s, now - s.start, now) for s in live]
        if len(frames) == 2:
            p = ease_out((now - live[1].start) / OVERLAP)
            incoming = frames[0].copy()
            incoming.paste(frames[1], (int((1 - p) * 140), 0))
            frame = Image.blend(frames[0], incoming, p)
        else:
            frame = frames[0] if frames else Image.new('RGBA', (W, H), (0, 0, 0, 255))
        enc.stdin.write(frame.convert('RGB').tobytes())
    enc.stdin.close()
    if enc.wait():
        raise SystemExit(f'ffmpeg failed on {out_video}')


# Sound.

def note(semitones_from_a4):
    return 440.0 * 2 ** (semitones_from_a4 / 12)


def tone(freq, dur, harmonics=6, detune=0.0):
    t = np.arange(int(dur * RATE)) / RATE
    out = np.zeros_like(t)
    for h in range(1, harmonics + 1):
        out += np.sin(2 * np.pi * freq * h * (1 + detune) * t) / h
    return out


def env(n, attack, release, total=None):
    e = np.ones(n)
    a, r = int(attack * RATE), int(release * RATE)
    if a:
        e[:a] = np.linspace(0, 1, a)
    if r:
        e[-r:] *= np.linspace(1, 0, r)
    return e


def lowpass(x, cutoff, order=2):
    b, a = signal.butter(order, min(cutoff / (RATE / 2), 0.99), 'low')
    return signal.lfilter(b, a, x)


def highpass(x, cutoff, order=2):
    b, a = signal.butter(order, cutoff / (RATE / 2), 'high')
    return signal.lfilter(b, a, x)


def bandpass(x, lo, hi):
    b, a = signal.butter(2, [lo / (RATE / 2), hi / (RATE / 2)], 'band')
    return signal.lfilter(b, a, x)


def add(track, at, sound, gain=1.0):
    i = int(at * RATE)
    if i >= track.shape[-1]:
        return
    j = min(track.shape[-1], i + sound.shape[-1])
    track[..., i:j] += gain * sound[..., :j - i]


def music(total, drop, rng):
    """Four chords in A minor at 110 bpm: pads and a muted arpeggio until
    the drop, then bass, kick, claps and hats; a last chord at the end."""
    beat = 60 / 110
    bar = 4 * beat
    left, right = np.zeros(int((total + 3) * RATE)), np.zeros(int((total + 3) * RATE))
    chords = [(0, 3, 7), (-4, 0, 3), (3, 7, 10), (-2, 2, 5)]  # Am F C G, from A4
    bars = int(total / bar) + 1
    for b in range(bars):
        at = b * bar
        root = chords[b % 4]
        for k, semi in enumerate(root):
            for side, track, det in ((0, left, -0.003), (1, right, 0.003)):
                pad = tone(note(semi - 12), bar + 0.4, harmonics=5, detune=det) * env(int((bar + 0.4) * RATE), 0.5, 0.6)
                add(track, at, lowpass(pad, 1800 if at >= drop else 700) * 0.05)
        for step in range(8):
            t0 = at + step * beat / 2
            semi = root[[0, 1, 2, 1, 0, 2, 1, 2][step]] + (12 if step % 4 == 2 else 0)
            n = int(0.35 * RATE)
            pl = (np.sin(2 * np.pi * note(semi) * np.arange(n) / RATE) + 0.3 * np.sin(4 * np.pi * note(semi) * np.arange(n) / RATE)) * np.exp(-np.arange(n) / RATE * 9)
            pl = lowpass(pl, 4000 if t0 >= drop else 1200)
            add(left, t0, pl, 0.07 if step % 2 == 0 else 0.05)
            add(right, t0, pl, 0.05 if step % 2 == 0 else 0.07)
        if at + bar <= drop:
            continue
        for k in range(4):
            t0 = at + k * beat
            if t0 < drop or t0 > total - 1.0:
                continue
            n = int(0.45 * RATE)
            tt = np.arange(n) / RATE
            kick = np.sin(2 * np.pi * (45 * tt + 70 / 18 * (1 - np.exp(-18 * tt)))) * np.exp(-tt * 7)
            add(left, t0, kick, 0.5)
            add(right, t0, kick, 0.5)
            bass_f = note(root[0] - 36 + (12 if root[0] < -2 else 0))
            nb = int(beat * 0.9 * RATE)
            bass = np.tanh(2 * np.sin(2 * np.pi * bass_f * np.arange(nb) / RATE)) * env(nb, 0.01, 0.15)
            add(left, t0, lowpass(bass, 500) * 0.16)
            add(right, t0, lowpass(bass, 500) * 0.16)
            if k in (1, 3):
                nc = int(0.2 * RATE)
                clap = bandpass(rng.standard_normal(nc), 900, 3500) * np.exp(-np.arange(nc) / RATE * 22)
                add(left, t0, clap, 0.12)
                add(right, t0, clap, 0.14)
            nh = int(0.06 * RATE)
            hat = highpass(rng.standard_normal(nh), 7000) * np.exp(-np.arange(nh) / RATE * 70)
            add(left, t0 + beat / 2, hat, 0.05)
            add(right, t0 + beat / 2, hat, 0.07)
    # The end: one chord that rings out.
    end = total - 1.6
    for semi in (0, 3, 7, 12):
        ring = tone(note(semi - 12), 3.0, harmonics=4) * np.exp(-np.arange(int(3.0 * RATE)) / RATE * 1.4)
        add(left, end, lowpass(ring, 2500), 0.08)
        add(right, end, lowpass(ring, 2500), 0.08)
    fade = np.ones(left.shape[0])
    stop = int(total * RATE)
    fade[stop - int(0.6 * RATE):stop] = np.linspace(1, 0, int(0.6 * RATE))
    fade[stop:] = 0
    return np.stack([left, right]) * fade


def whoosh(rng, dur=0.6):
    n = int(dur * RATE)
    noise = rng.standard_normal(n)
    pieces = 12
    out = np.zeros(n)
    for k in range(pieces):
        lo, hi = k * n // pieces, (k + 1) * n // pieces
        centre = 400 + 3500 * math.sin(math.pi * k / (pieces - 1))
        out[lo:hi] = bandpass(noise, centre * 0.6, min(centre * 1.6, 20000))[lo:hi]
    return out * np.sin(np.pi * np.arange(n) / n) ** 2 * 0.5


def pop(freq=520):
    n = int(0.12 * RATE)
    tt = np.arange(n) / RATE
    return np.sin(2 * np.pi * (freq * tt + freq * 1.4 * tt * tt / 0.12 / 2)) * np.exp(-tt * 35) * 0.5


def impact(rng):
    n = int(1.4 * RATE)
    tt = np.arange(n) / RATE
    boom = np.sin(2 * np.pi * (38 * tt + 50 / 5 * (1 - np.exp(-5 * tt)))) * np.exp(-tt * 3)
    hit = lowpass(rng.standard_normal(n), 1200) * np.exp(-tt * 14)
    return boom * 0.9 + hit * 0.5


def riser(rng, dur):
    n = int(dur * RATE)
    tt = np.arange(n) / RATE
    sweep = np.sin(2 * np.pi * (200 * tt + 600 * tt * tt / dur))
    noise = highpass(rng.standard_normal(n), 2500)
    return (sweep * 0.15 + noise * 0.12) * (tt / dur) ** 2


def mix(segments, total):
    rng = np.random.default_rng(7)
    voice = np.zeros(int((total + 3) * RATE))
    for s in segments:
        add(voice, s.start + 0.35, s.voice)
    drop = segments[1].start + 0.15
    bed = music(total, drop, rng)
    # Duck the music under the narration.
    level = lowpass(np.abs(voice), 6)
    duck = 1 - 0.55 * np.clip(level / (np.percentile(level[level > 1e-4], 60) if np.any(level > 1e-4) else 1), 0, 1)
    duck = lowpass(duck, 3)
    fx = np.zeros_like(bed)
    for i, s in enumerate(segments[1:], 1):
        if s.kind != 'brand':
            add(fx, s.start - 0.1, np.stack([whoosh(rng)] * 2), 0.35)
    add(fx, drop - 1.4, np.stack([riser(rng, 1.4)] * 2), 0.8)
    add(fx, drop, np.stack([impact(rng)] * 2), 0.7)
    for s in segments:
        if s.kind == 'screen':
            for i in range(len(s.data['chips'])):
                add(fx, s.start + 0.9 + i * 0.45, np.stack([pop(660 + 80 * i)] * 2), 0.3)
        elif s.kind == 'outro':
            add(fx, s.start + 0.1, np.stack([pop(380)] * 2), 0.4)
            cue = s.cues[-1] if len(s.cues) > 1 else 1.4
            add(fx, s.start + cue, np.stack([pop(880)] * 2), 0.45)
    out = bed * duck + fx + np.stack([voice, voice]) * 0.9
    out = out[:, :int(total * RATE)]
    out = np.tanh(out / max(1e-6, np.max(np.abs(out))) * 1.2) * 0.9
    return out


def write_wav(path, stereo):
    data = (np.clip(stereo.T, -1, 1) * 32767).astype('<i2')
    with wave.open(path, 'wb') as w:
        w.setnchannels(2)
        w.setsampwidth(2)
        w.setframerate(RATE)
        w.writeframes(data.tobytes())


def recording(folder, lang):
    """The tour recorded in [lang], or else the one in English."""
    suffix = {'zh': '-zh-Hans'}.get(lang, '')
    if not os.path.exists(os.path.join(folder, f'tour{suffix}.mp4')):
        suffix = ''
    return os.path.join(folder, f'tour{suffix}.mp4'), os.path.join(folder, f'scenes{suffix}.txt')


def read_scenes(path):
    marks = []
    with open(path) as f:
        for line in f:
            name, ms = line.split()
            marks.append((name, int(ms) / 1000))
    return {name: (start, marks[i + 1][1] if i + 1 < len(marks) else start + 8) for i, (name, start) in enumerate(marks)}


def gif(folder, scenes):
    start, end = scenes.get('palettes', (0, 12))
    subprocess.run(['ffmpeg', '-v', 'error', '-y', '-ss', f'{start + 0.5:.2f}', '-t', f'{min(12, end - start - 0.5):.2f}', '-i', os.path.join(folder, 'tour.mp4'),
                    '-vf', 'fps=10,scale=720:-1:flags=lanczos,split[a][b];[a]palettegen=max_colors=160[p];[b][p]paletteuse=dither=bayer:bayer_scale=4',
                    os.path.join(folder, 'tour.gif')], check=True)


def main():
    folder, model, voices = sys.argv[1:4]
    langs = sys.argv[4].split(',') if len(sys.argv) > 4 else ['en', 'zh']
    voice = Voice(model, voices)
    for lang in langs:
        tour, scenes = recording(folder, lang)
        scenes = read_scenes(scenes)
        segments, total = build(STORY[lang], voice, scenes, lang, folder)
        audio = os.path.join(folder, f'promo-{lang}.wav')
        write_wav(audio, mix(segments, total))
        render(segments, total, tour, os.path.join(folder, f'promo-{lang}.mp4'), audio)
        os.remove(audio)
        print(f'promo-{lang}.mp4: {total:.1f} s', flush=True)
    gif(folder, read_scenes(recording(folder, 'en')[1]))


if __name__ == '__main__':
    main()
