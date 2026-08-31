# backgrounds

One wallpaper, `0288.jpg`, so a freshly built machine has a desktop background
without pulling a collection it does not need.

The other 327 images that used to live here are from DistroTube's collection:

```bash
git clone https://gitlab.com/dwt1/wallpapers.git ~/Pictures/wallpapers
```

They were removed in August 2026. At 362 MB they were the overwhelming majority
of a 394 MB repo — everything else came to about 13 MB — and every device build
cloned all of them before the desktop install could start. On a fleet rollout
that is tens of gigabytes of transfer and a slower install on every machine, to
ship wallpapers that are one `git clone` away from anyone who wants them.

Nothing in the build depends on any image here except `0288.jpg`.
