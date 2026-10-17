# Witty icon source

Witty's icon is a four-leaf clover on warm paper. The four heart-shaped leaves sit in the four
quadrants, so the cross-shaped gap between them reads as a 2×2 split of terminal panes, which is
Witty's tmux split. A white `>_` prompt sits on the top-left leaf's centroid. The clover belongs
to the plant family of Reality Inc.'s open-source tools; the warm paper is the shared ground.

Everything is drawn by one script, so the artwork can be regenerated rather than retouched:

```sh
swift images/witty-icon-src/draw_clover.swift <output-dir>
```

It writes three files. Copy them into the repository like this:

| Output | Goes to | Used for |
|---|---|---|
| `Clover.png` | `images/Ghostty.icon/Assets/Clover.png` | The app icon. It is the only layer of the Icon Composer document; `icon.json` supplies the warm-paper fill. |
| `witty-icon-preview.png` | `macos/Assets.xcassets/AppIconImage.imageset/`, resized to 1024, 512 and 256 px with `sips -Z` | The in-app image: Settings, the error view, and the Dock tile fallback. |
| `clover-silhouette.png` | `macos/Assets.xcassets/Custom Icon/CustomIconGhost.imageset/clover.png` | The tintable glyph of the "custom" Dock icon style, placed where upstream's ghost sat. |

Two measurements keep the pieces aligned:

- **Icon Composer scale.** The Icon Composer canvas is the rounded square itself (1024 pt), while
  the preview's square is 824 px. `Clover.png` is therefore drawn 1024/824 larger, so the clover
  fills about 79% of the canvas in both.
- **Prompt position.** The prompt's bounding box is centred on the top-left leaf's area centroid,
  which the script computes rather than placing by eye.

The Icon Composer document keeps upstream's file name, `images/Ghostty.icon`, because the Xcode
project refers to the app icon as `Ghostty` (`ASSETCATALOG_COMPILER_APPICON_NAME`). Renaming it
would only add merge conflicts. Upstream's CRT frame layers (bevel, screen, gloss, screen effects)
and the ghost glyph are no longer used. The `macos-icon` alternate icons under
`macos/Assets.xcassets/Alternate Icons/` are still upstream's artwork; they appear only when a user
picks one in the config.
