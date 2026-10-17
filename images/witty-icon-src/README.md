# Witty icon source

Witty's icon is a four-leaf clover on warm paper. The four heart-shaped leaves sit in the four
quadrants, so the cross-shaped gap between them reads as a 2×2 split of terminal panes, which is
Witty's tmux split. A white `>_` prompt sits on the top-left leaf's centroid. The clover belongs
to the plant family of Reality Inc.'s open-source tools; the warm paper is the shared ground.

Everything is drawn by one script, so the artwork can be regenerated rather than retouched:

```sh
swift images/witty-icon-src/draw_clover.swift <output-dir>
```

It writes the files below. Copy them into the repository like this:

| Output | Goes to | Used for |
|---|---|---|
| `Clover-leaves.png`, `Clover-prompt.png` | `images/Ghostty.icon/Assets/` | The app icon: the two layers of the Icon Composer document. `icon.json` supplies the background fill for each appearance. |
| `witty-icon-preview.png` | `macos/Assets.xcassets/AppIconImage.imageset/`, resized to 1024, 512 and 256 px with `sips -Z` | The in-app image: Settings, the error view, and the Dock tile fallback. |
| `clover-silhouette.png` | `macos/Assets.xcassets/Custom Icon/CustomIconGhost.imageset/clover.png` | The tintable glyph of the "custom" Dock icon style, placed where upstream's ghost sat. |
| `<Name>Image.png` (8 files) | `macos/Assets.xcassets/Alternate Icons/<Name>Image.imageset/macOS-AppIcon-1024px.png` | The `macos-icon` alternates (see below). |

## Appearances

macOS 26 draws every icon in six appearances: Default, Dark, Clear (light and dark) and Tinted
(light and dark). `icon.json` specialises two things:

- **Dark.** `fill-specializations` swaps the warm paper for a deep forest green.
- **Clear and tinted.** These monochrome appearances use the `tinted` key. There,
  `hidden-specializations` hides the prompt layer. The leaves carry the prompt as a cut-out, so it
  reads as negative space instead of a white stroke that would vanish against pale glass.

Preview any appearance before committing:

```sh
ictool images/Ghostty.icon --export-image --output-file out.png --platform macOS \
  --rendition Dark --width 512 --height 512 --scale 1
```

The renditions are `Default`, `Dark`, `ClearLight`, `ClearDark`, `TintedLight` and `TintedDark`.
For the tinted ones, also pass `--tint-color` and `--tint-strength`. `ictool` ships inside Icon
Composer, in `Xcode.app/Contents/Applications/Icon Composer.app/Contents/Executables/`.

## Alternates

`macos-icon = blueprint | chalkboard | glass | holographic | microchip | paper | retro | xray`
picks one of eight clover variants. They keep upstream's theme names, so the config values and
the Swift that maps them (`macos/Sources/Features/Custom App Icon/AppIcon.swift`) are unchanged.
Only the images differ:

| Name | Variant |
|---|---|
| blueprint | White line drawing on a technical grid |
| chalkboard | Chalk sketch on slate, in a wooden frame |
| glass | Frosted leaves over soft colour, in the Liquid Glass manner |
| holographic | Iridescent leaves over a synthwave horizon |
| microchip | Gold leaves on a circuit board, joined by a chip at the crossing |
| paper | Marker drawing on ruled notebook paper |
| retro | Pixel clover on a scanlined CRT, the prompt as dark pixels |
| xray | Glowing outlines with the leaves' veins showing |

The textures (wood grain, chalk dust, circuit traces) come from a seeded generator, so every run
draws the same pixels.

## Measurements that keep the pieces aligned

- **Icon Composer scale.** The Icon Composer canvas is the rounded square itself (1024 pt), while
  the preview's square is 824 px. The two layers are therefore drawn 1024/824 larger, so the
  clover fills about 79% of the square in both. In the compiled icon it measured 79.4%, centred.
- **Prompt position.** The prompt's bounding box is centred on the top-left leaf's area centroid,
  which the script computes rather than placing by eye.

The Icon Composer document keeps upstream's file name, `images/Ghostty.icon`, because the Xcode
project refers to the app icon as `Ghostty` (`ASSETCATALOG_COMPILER_APPICON_NAME`). Renaming it
would only add merge conflicts. Upstream's CRT frame layers and ghost glyph are no longer used.
