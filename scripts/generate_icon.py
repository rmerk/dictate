#!/usr/bin/env python3
"""Generate Robin app icon at all required macOS sizes."""

from PIL import Image, ImageDraw, ImageFont
import math
import os

def draw_rounded_rect(draw, bbox, radius, fill):
    x0, y0, x1, y1 = bbox
    draw.rounded_rectangle(bbox, radius=radius, fill=fill)

def create_icon(size):
    """Create a macOS app icon at the given pixel size."""
    img = Image.new('RGBA', (size, size), (0, 0, 0, 0))
    draw = ImageDraw.Draw(img)

    # macOS icon shape: rounded square (22.37% corner radius)
    margin = int(size * 0.02)
    icon_size = size - margin * 2
    corner_radius = int(icon_size * 0.2237)

    # Background gradient (deep blue to darker blue)
    # Simulate gradient with horizontal bands
    for y in range(margin, margin + icon_size):
        t = (y - margin) / icon_size
        r = int(20 + t * 10)
        g = int(100 + (1 - t) * 60)
        b = int(220 + (1 - t) * 35)
        for x in range(margin, margin + icon_size):
            img.putpixel((x, y), (r, g, b, 255))

    # Apply rounded rectangle mask
    mask = Image.new('L', (size, size), 0)
    mask_draw = ImageDraw.Draw(mask)
    mask_draw.rounded_rectangle(
        [margin, margin, margin + icon_size, margin + icon_size],
        radius=corner_radius, fill=255
    )
    img.putalpha(mask)

    # Draw waveform bars in the center
    cx = size // 2
    cy = size // 2
    bar_count = 5
    bar_width = int(size * 0.055)
    bar_gap = int(size * 0.04)
    total_width = bar_count * bar_width + (bar_count - 1) * bar_gap

    # Bar heights as fraction of icon size (symmetric waveform pattern)
    bar_heights = [0.18, 0.32, 0.42, 0.32, 0.18]

    start_x = cx - total_width // 2

    for i, h_frac in enumerate(bar_heights):
        bx = start_x + i * (bar_width + bar_gap)
        bar_h = int(icon_size * h_frac)
        by = cy - bar_h // 2
        bar_radius = bar_width // 2

        # White bars with slight transparency for depth
        draw_rounded_rect(
            draw,
            [bx, by, bx + bar_width, by + bar_h],
            radius=bar_radius,
            fill=(255, 255, 255, 240)
        )

    # Re-apply the rounded mask (bars may have drawn outside)
    final = Image.new('RGBA', (size, size), (0, 0, 0, 0))
    final.paste(img, mask=mask)

    # Add subtle inner shadow at top for depth
    shadow = Image.new('RGBA', (size, size), (0, 0, 0, 0))
    shadow_draw = ImageDraw.Draw(shadow)
    for y in range(margin, margin + int(icon_size * 0.15)):
        t = (y - margin) / (icon_size * 0.15)
        alpha = int(30 * (1 - t))
        for x in range(margin, margin + icon_size):
            px = shadow.getpixel((x, y))
            if mask.getpixel((x, y)) > 0:
                shadow.putpixel((x, y), (255, 255, 255, alpha))

    final = Image.alpha_composite(final, shadow)

    return final

def main():
    icon_dir = os.path.join(
        os.path.dirname(__file__), '..', 'app', 'Robin', 'Robin',
        'Assets.xcassets', 'AppIcon.appiconset'
    )
    os.makedirs(icon_dir, exist_ok=True)

    # macOS icon sizes: size@scale -> pixel size
    sizes = {
        (16, 1): 16,
        (16, 2): 32,
        (32, 1): 32,
        (32, 2): 64,
        (128, 1): 128,
        (128, 2): 256,
        (256, 1): 256,
        (256, 2): 512,
        (512, 1): 512,
        (512, 2): 1024,
    }

    # Generate master at 1024 and downscale
    master = create_icon(1024)

    images_json = []
    for (pt_size, scale), px_size in sizes.items():
        filename = f"icon_{pt_size}x{pt_size}@{scale}x.png"
        filepath = os.path.join(icon_dir, filename)

        icon = master.resize((px_size, px_size), Image.LANCZOS)
        icon.save(filepath, 'PNG')
        print(f"  {filename} ({px_size}x{px_size}px)")

        images_json.append({
            "filename": filename,
            "idiom": "mac",
            "scale": f"{scale}x",
            "size": f"{pt_size}x{pt_size}"
        })

    # Write Contents.json
    import json
    contents = {
        "images": images_json,
        "info": {"author": "xcode", "version": 1}
    }
    with open(os.path.join(icon_dir, 'Contents.json'), 'w') as f:
        json.dump(contents, f, indent=2)

    print(f"\nDone! Icons saved to {icon_dir}")

if __name__ == '__main__':
    main()
