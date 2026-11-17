#!/usr/bin/env python3
"""合成武器音效，输出到 assets/sfx/*.wav。

纯标准库（没有 numpy 也能跑），固定随机种子，每次生成结果一样。
跑法：python3 tools/gen_sfx.py

每把武器两个音：
  <武器>_swing  出手（不管打没打中）
  <武器>_hit    砍中人
外加通用的 kill（击杀）。

音色思路（跟武器特点对齐）：
  匕首  短、高、快 —— 细小的"嗖"+ 尖锐的划破声
  长枪  中等 —— 破风声 + 木杆捅进去的闷"噗"
  铁鞭  长、低、沉 —— 重物抡起来的"呼"+ 带链节碰撞的金属"锵"
以后有了正式音效，直接替换同名 wav 即可，代码不用改。
"""
import math
import os
import random
import struct
import wave

SR = 44100
OUT = os.path.join(os.path.dirname(__file__), "..", "assets", "sfx")
rng = random.Random(20261117)


# ---------- 基础积木 ----------

def silence(sec):
    return [0.0] * int(SR * sec)


def noise(sec):
    return [rng.uniform(-1.0, 1.0) for _ in range(int(SR * sec))]


def env_ad(n, attack, decay_pow=1.0):
    """attack 秒线性起音，剩下的按幂次衰减到 0"""
    a = max(1, int(SR * attack))
    out = []
    for i in range(n):
        if i < a:
            out.append(i / a)
        else:
            t = (i - a) / max(1, n - a)
            out.append((1.0 - t) ** decay_pow)
    return out


def env_exp(n, tau):
    return [math.exp(-i / (SR * tau)) for i in range(n)]


def mul(a, b):
    return [x * y for x, y in zip(a, b)]


def gain(a, g):
    return [x * g for x in a]


def mix(*tracks):
    n = max(len(t) for t in tracks)
    out = [0.0] * n
    for t in tracks:
        for i, x in enumerate(t):
            out[i] += x
    return out


def delay(a, sec):
    return silence(sec) + a


def bandpass_sweep(x, f0, f1, q):
    """RBJ 带通，中心频率从 f0 指数滑到 f1 —— 破风声的核心"""
    n = len(x)
    out = [0.0] * n
    x1 = x2 = y1 = y2 = 0.0
    for i in range(n):
        f = f0 * (f1 / f0) ** (i / max(1, n - 1))
        w = 2 * math.pi * f / SR
        alpha = math.sin(w) / (2 * q)
        b0, b2 = alpha, -alpha
        a0, a1, a2 = 1 + alpha, -2 * math.cos(w), 1 - alpha
        y = (b0 * x[i] + b2 * x2 - a1 * y1 - a2 * y2) / a0
        x2, x1 = x1, x[i]
        y2, y1 = y1, y
        out[i] = y
    return out


def lowpass(x, fc):
    a = math.exp(-2 * math.pi * fc / SR)
    out, y = [], 0.0
    for v in x:
        y = (1 - a) * v + a * y
        out.append(y)
    return out


def highpass(x, fc):
    lp = lowpass(x, fc)
    return [a - b for a, b in zip(x, lp)]


def sine_sweep(sec, f0, f1):
    n = int(SR * sec)
    out, ph = [], 0.0
    for i in range(n):
        f = f0 * (f1 / f0) ** (i / max(1, n - 1))
        ph += 2 * math.pi * f / SR
        out.append(math.sin(ph))
    return out


def partials(sec, freqs, tau):
    """一组非整数倍泛音，各自指数衰减 —— 金属的"当"声"""
    n = int(SR * sec)
    out = [0.0] * n
    for k, f in enumerate(freqs):
        amp = 1.0 / (1 + k * 0.6)
        t_k = tau / (1 + k * 0.35)
        for i in range(n):
            out[i] += amp * math.sin(2 * math.pi * f * i / SR) * math.exp(-i / (SR * t_k))
    return out


def normalize(x, peak):
    m = max(abs(v) for v in x) or 1.0
    return [v / m * peak for v in x]


def fade_tail(x, sec=0.01):
    n = int(SR * sec)
    for i in range(min(n, len(x))):
        x[-1 - i] *= i / n
    return x


def write(name, x, peak=0.8):
    x = fade_tail(normalize(x, peak))
    path = os.path.join(OUT, name + ".wav")
    with wave.open(path, "wb") as w:
        w.setnchannels(1)
        w.setsampwidth(2)
        w.setframerate(SR)
        w.writeframes(b"".join(struct.pack("<h", int(max(-1, min(1, v)) * 32767)) for v in x))
    print(f"  {name:14s} {len(x) / SR:.2f}s")


def whoosh(sec, f0, f1, q, attack=0.35, pow_=1.6):
    n = noise(sec)
    return mul(bandpass_sweep(n, f0, f1, q), env_ad(len(n), sec * attack, pow_))


# ---------- 各武器 ----------

def dagger():
    # 出手：很短很高的"嗖"
    write("dagger_swing", whoosh(0.09, 2600, 6000, 2.2, attack=0.3), peak=0.55)
    # 命中：尖锐的划破 —— 高通噪声瞬态 + 一点高频金属擦刮
    n = 0.07
    slash = mul(highpass(noise(n), 3000), env_exp(int(SR * n), 0.015))
    scrape = mul(sine_sweep(n, 3200, 2200), env_exp(int(SR * n), 0.02))
    body = mul(sine_sweep(0.06, 260, 140), env_exp(int(SR * 0.06), 0.02))
    write("dagger_hit", mix(slash, gain(scrape, 0.25), gain(body, 0.5)), peak=0.75)


def spear():
    # 出手：中频破风，带一点往前捅的力度（尾巴收得快）
    write("spear_swing", whoosh(0.16, 900, 2200, 1.6, attack=0.4, pow_=2.2), peak=0.6)
    # 命中：闷"噗"—— 低频下滑的冲击 + 木头敲击 + 低通噪声
    n = 0.14
    thump = mul(sine_sweep(n, 180, 70), env_exp(int(SR * n), 0.05))
    knock = mul(partials(0.08, [620, 1480], 0.018), [1.0] * int(SR * 0.08))
    dust = mul(lowpass(noise(0.08), 1800), env_exp(int(SR * 0.08), 0.02))
    write("spear_hit", mix(thump, gain(knock, 0.35), gain(dust, 0.6)), peak=0.85)


def whip():
    # 出手：又长又低的"呼——"，后半段夹几下链节碰撞的细碎金属声
    base = whoosh(0.28, 350, 1300, 1.2, attack=0.5, pow_=1.3)
    chain = []
    for t in (0.06, 0.13, 0.19):
        ping = partials(0.05, [2900 + rng.uniform(-200, 200), 4300], 0.008)
        chain.append(gain(delay(ping, t), 0.18))
    write("whip_swing", mix(base, *chain), peak=0.65)
    # 命中：重金属"锵"—— 非谐波泛音长衰减 + 冲击瞬态 + 低频撞击
    n = 0.4
    clang = partials(n, [430, 1010, 1580, 2210, 3170], 0.12)
    hit = mul(noise(0.03), env_exp(int(SR * 0.03), 0.006))
    boom = mul(sine_sweep(0.15, 120, 55), env_exp(int(SR * 0.15), 0.05))
    write("whip_hit", mix(gain(clang, 0.55), gain(hit, 0.6), boom), peak=0.85)


def kill():
    # 击杀：低沉的"咚"+ 往下掉的音，跟命中声叠在一起也分得出来
    n = 0.45
    drop = mul(sine_sweep(n, 330, 80), env_ad(int(SR * n), 0.005, 1.8))
    sub = mul(sine_sweep(n, 90, 40), env_exp(int(SR * n), 0.15))
    crunch = mul(lowpass(noise(0.1), 2500), env_exp(int(SR * 0.1), 0.03))
    write("kill", mix(gain(drop, 0.5), sub, gain(crunch, 0.5)), peak=0.8)


if __name__ == "__main__":
    os.makedirs(OUT, exist_ok=True)
    print("生成音效 →", os.path.normpath(OUT))
    dagger()
    spear()
    whip()
    kill()
