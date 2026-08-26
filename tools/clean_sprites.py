#!/usr/bin/env python3
"""Remove baked checkerboard/white backgrounds via border flood-fill, then autocrop.
Dark sprite outlines act as a barrier; interior desaturated stone is preserved."""
import sys
from collections import deque
from PIL import Image
import numpy as np

def process(path, out=None, sat_max=26, bright_min=48):
    out = out or path
    im = Image.open(path).convert("RGBA")
    w, h = im.size
    arr = np.array(im)
    rgb = arr[:, :, :3].astype(int)
    mx = rgb.max(axis=2); mn = rgb.min(axis=2)
    sat = mx - mn                      # low => grey/white
    bright = mx
    # a pixel is "background-like": desaturated AND light enough (not dark outline)
    bg_like = (sat <= sat_max) & (bright >= bright_min)
    visited = np.zeros((h, w), dtype=bool)
    q = deque()
    for x in range(w):
        for y in (0, h - 1):
            if bg_like[y, x] and not visited[y, x]:
                visited[y, x] = True; q.append((x, y))
    for y in range(h):
        for x in (0, w - 1):
            if bg_like[y, x] and not visited[y, x]:
                visited[y, x] = True; q.append((x, y))
    while q:
        x, y = q.popleft()
        for dx, dy in ((1,0),(-1,0),(0,1),(0,-1)):
            nx, ny = x+dx, y+dy
            if 0 <= nx < w and 0 <= ny < h and not visited[ny, nx] and bg_like[ny, nx]:
                visited[ny, nx] = True; q.append((nx, ny))
    arr[:, :, 3] = np.where(visited, 0, 255).astype(np.uint8)
    # soften 1px halo: any opaque pixel adjacent to transparent keeps, but blend edges
    im2 = Image.fromarray(arr, "RGBA")
    bbox = im2.getbbox()
    if bbox:
        im2 = im2.crop(bbox)
    im2.save(out)
    return im2.size

if __name__ == "__main__":
    for p in sys.argv[1:]:
        size = process(p)
        print(p, "->", size)
