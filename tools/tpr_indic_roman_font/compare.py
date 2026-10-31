"""Shape-overlap check: how much each letter of font A covers the same letter of font B.
Head bars are removed first (both fonts have one), then each letter is scaled to a
128x128 box and the overlap is measured as IoU (shared ink / total ink)."""
import sys
from PIL import Image, ImageDraw, ImageFont, ImageChops

N = 128
def mask(font_path, ch, size=300):
    f = ImageFont.truetype(font_path, size)
    img = Image.new('L', (size * 2, size * 2), 0)
    ImageDraw.Draw(img).text((size // 2, size // 2), ch, font=f, fill=255)
    bb = img.getbbox()
    if not bb:
        return None
    img = img.crop(bb)
    w, h = img.size
    px = img.load()
    for y in range(h):                       # blank out the head bar rows
        if sum(1 for x in range(w) if px[x, y] > 128) > 0.85 * w:
            for x in range(w):
                px[x, y] = 0
    bb = img.getbbox()
    if not bb:
        return None
    return img.crop(bb).resize((N, N)).point(lambda v: 255 if v > 128 else 0)

def iou(a, b):
    inter = ImageChops.multiply(a, b).histogram()[255]
    union = ImageChops.lighter(a, b).histogram()[255]
    return inter / union if union else 0

def compare(fa, fb, letters):
    out = {}
    for ch in letters:
        a, b = mask(fa, ch), mask(fb, ch)
        if a and b:
            out[ch] = iou(a, b)
    return out

if __name__ == '__main__':
    fa, fb, letters = sys.argv[1], sys.argv[2], sys.argv[3]
    r = compare(fa, fb, letters)
    print(' '.join(f'{k}:{v:.2f}' for k, v in r.items()))
    print('mean', round(sum(r.values()) / len(r), 3))
