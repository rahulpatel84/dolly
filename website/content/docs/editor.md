# Screenshot editor

^ The editor opens the moment a screenshot is taken. Everything is non-destructive until you save; the preview is pixel-sharp at any zoom.

![The editor with annotations](/shots/editor.png "Arrows, numbered steps, a highlight and a label on a captured page.")

## Toolbar

Left to right: **Copy** · **Save ▾** (Save as New / Overwrite Original) · **Pin** · **Share** · the tools · **Undo / Redo** · **Copy Text** · size readout · **Zoom** · **Style** · **Export** · **Done**. Hover any control for a description; it also appears in the hint line at the bottom.

## Tools

| Tool | Key | Use |
|---|---|---|
| Colour picker | [[P]] | Click a pixel to copy its hex colour. |
| Arrow | [[A]] | Drag tail → head. Single, double or plain line in the strip below. |
| Rectangle | [[R]] | Drag to outline. |
| Ellipse | [[O]] | Drag to circle. |
| Line | [[L]] | Straight line. |
| Highlighter | [[H]] | Translucent band over text. |
| Blur | [[B]] | Pixelates anything sensitive. |
| Text | [[T]] | Click, type, click away. |
| Number | [[N]] | Drops 1, 2, 3… badges. |
| Crop | [[C]] | Drag the area to keep; Done applies it. |

Colours and stroke width (keys [[1]]–[[9]]) are in the strip under the toolbar. Stroke width is in screen points, so it looks the same at any image size. [[⌘Z]] / [[⇧⌘Z]] undo and redo; [[⌘+]] / [[⌘−]] zoom; click the percentage for *Fit* or *100 %*.

## Copy Text (OCR)

**Copy Text** recognises every word in the image with Apple's Vision framework — on device, no network — and copies the text. It runs on a ≤2000 px copy and takes well under a second.

## Style

![Styled screenshot with a macOS window frame on a gradient](/shots/editor-styled.png "Style: Midnight gradient, macOS window frame with a title.")

The paint-palette button decorates the screenshot: six gradient backgrounds (Midnight, Sunset, Ocean, Mint, Graphite, Paper), padding and corner-radius sliders, a shadow, and an optional **macOS window frame** with traffic lights and a title. The decoration previews live and applies identically to Copy, Save, Share and Export. Annotations stay inside the image.

## Export

The document-arrow button exports in another format: **PNG** or **TIFF** (lossless), **JPEG**, **HEIC** or **WebP** with a quality slider and a live size estimate, or **PDF** (one page at the image's pixel size). HEIC and WebP are roughly half the size of JPEG at the same quality.

## Finishing

**Copy** ([[⇧⌘C]]) puts the finished image on the clipboard. **Save ▾** writes a new file or overwrites the original. **Share** opens the macOS share sheet. **Pin** floats a copy above every window — drag it anywhere, click ✕ to dismiss. **Done** ([[⏎]]) saves, copies and closes.
