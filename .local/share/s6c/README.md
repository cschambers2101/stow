# s6c

Small S6C-branded assets the build needs at runtime.

## avatar-default.png

The default user picture the greeter shows before anyone sets their own.

It exists because of an upstream DMS bug rather than a preference.
`GreeterContent.qml` passes `fallbackIcon: "person"` to `DankCircularImage`,
and `AppIconRenderer` dispatches on a *prefix* — `material:` for a Material
Symbols glyph, `svg:`/`image:` for a path, and anything unprefixed goes to a
freedesktop icon-theme lookup. `"person"` is unprefixed and no installed icon
theme has an icon by that name, so the fallback silently draws nothing and the
greeter shows an empty circle. Patching the shipped QML would be reverted by
the next package update, so the installer gives the greeter a real image to
find instead, at `~/.face`.

Drawn here rather than copied from Yaru: Yaru's `avatar-default.png` is
CC-BY-SA, and this repo is public. This one is 256x256, navy `#022B3A` on
cream `#FAF7F0` — 13.93:1, AAA — matching `brand.md`.

Regenerate with ImageMagick:

    convert -size 512x512 xc:none -fill '#022B3A' \
        -draw 'circle 256,256 256,4' bg.png
    convert -size 512x512 xc:none -fill '#FAF7F0' \
        -draw 'circle 256,195 256,110' \
        -draw 'ellipse 256,520 150,210 180,360' fig.png
    convert -size 512x512 xc:black -fill white \
        -draw 'circle 256,256 256,4' mask.png
    convert bg.png fig.png -compose Over -composite combined.png
    convert combined.png \( mask.png -alpha off \) \
        -compose CopyOpacity -composite -resize 256x256 avatar-default.png

Two traps if you edit it. Composite the figure over the disc BEFORE clipping:
`CopyOpacity` replaces alpha outright, so clipping a part-transparent figure
first turns its transparent areas opaque black. And the shoulders are the top
half of an ellipse, so its centre y must sit BELOW the disc's bottom edge or
the arch is cut off flat instead of meeting the rim.
