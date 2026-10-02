"""16x16 void-and-cluster blue-noise threshold matrix (Ulichney 1993).

Ordered dithering, so the pattern depends only on pixel position and is stable
while scrolling -- unlike error diffusion, which re-flows and crawls. Blue noise
avoids Bayer's periodic crosshatch while keeping that stability.

Values are 1..255, never 0 and never 256: at levels=1 the driver renders white
iff BAYER[x,y] + pixel >= 256, so a 0 entry puts a black dot on pure white and a
256 entry puts a white dot on pure black.
"""
import numpy as np

N = 16
SIG = 1.9
rng = np.random.default_rng(20260922)

# toroidal gaussian, precomputed as an FFT kernel
ax = np.arange(N)
d = np.minimum(ax, N - ax)
g1 = np.exp(-(d ** 2) / (2 * SIG ** 2))
K = np.outer(g1, g1)
KF = np.fft.rfft2(K)


def energy(b):
    return np.fft.irfft2(np.fft.rfft2(b.astype(float)) * KF, s=(N, N))


def tightest_cluster(b):
    e = np.where(b == 1, energy(b), -np.inf)
    return np.unravel_index(np.argmax(e), e.shape)


def largest_void(b):
    e = np.where(b == 0, energy(b), np.inf)
    return np.unravel_index(np.argmin(e), e.shape)


# phase 0: scatter, then relax to a well-spaced prototype
b = np.zeros((N, N), int)
flat = rng.permutation(N * N)[: (N * N) // 10]
b.flat[flat] = 1
while True:
    c = tightest_cluster(b)
    b[c] = 0
    v = largest_void(b)
    if v == c:
        b[c] = 1
        break
    b[v] = 1

proto = b.copy()
ones = int(proto.sum())
rank = np.full((N, N), -1, int)

# phase 1: remove clusters, ranking downwards
b = proto.copy()
for r in range(ones - 1, -1, -1):
    c = tightest_cluster(b)
    b[c] = 0
    rank[c] = r

# phase 2: fill voids, ranking upwards to half
b = proto.copy()
for r in range(ones, (N * N) // 2):
    v = largest_void(b)
    b[v] = 1
    rank[v] = r

# phase 3: past half, the roles swap -- tightest cluster of zeros
for r in range((N * N) // 2, N * N):
    inv = 1 - b
    e = np.where(inv == 1, energy(inv), -np.inf)
    c = np.unravel_index(np.argmax(e), e.shape)
    b[c] = 1
    rank[c] = r

assert sorted(rank.flat) == list(range(N * N)), "ranking incomplete"

# ranks 0..255 -> thresholds 1..255
vals = 1 + (rank.astype(int) * 255) // 256
assert vals.min() >= 1 and vals.max() <= 255

# the driver indexes BAYER[(x&15)*16 + (y&15)] -- x major, y minor
out = [int(vals[x, y]) for x in range(N) for y in range(N)]
print("min", min(out), "max", max(out), "distinct", len(set(out)))
np.save("bluenoise.npy", np.array(out, dtype=np.int32))
print(out[:16])
