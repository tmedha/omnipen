# omnipen

A pen that writes everywhere on your MacBook. A menu bar tool you can use anytime, anywhere, in any
meeting, or just brainstorming by yourself.

Omnipen draws over whatever is already on screen: a document, a Chrome tab, Apple Music, VS Code. It
has no window of its own and no Dock icon, just a pen in the menu bar and a hotkey.

## Running it

```sh
make run      # build, bundle, and launch
make test     # unit tests
make release  # optimised build
make clean
```

Builds are currently unsigned and ad-hoc signed, so the first launch needs a right-click then Open,
and macOS may re-ask for Screen Recording after a rebuild. Signing comes before any real release.

## Modes

Omnipen is in one of three states:

| State | Overlay | Mouse |
|---|---|---|
| **Off** | hidden, ink retained | untouched |
| **Armed** | visible | captured for drawing |
| **Passthrough** | visible | falls through to the app underneath |

`Esc` steps down one level: armed becomes passthrough, so your annotations stay on screen while the
app underneath becomes clickable again. A second `Esc` puts the pen away. The palette stays up in
passthrough, with its pointer button lit, which is how you get back to drawing.

While off, Omnipen holds no windows and no bitmaps at all: about 11 MB and 0% CPU.

## Keys

| Key | Action |
|---|---|
| `⌥⌘D` | Arm / put away |
| `Esc` | Close a zoom panel, else step down a mode |
| `⇧⌥⌘D` | Clear all ink, on every display |
| `⌘Z` / `⇧⌘Z` | Undo / redo |
| `P` `H` `E` | Pen, Highlighter, Eraser |
| `A` `R` `O` | Arrow, Rectangle, Ellipse |
| `L` `T` `S` | Laser, Text, Snapshot |
| `1` to `8` | Colour slots |
| `[` / `]` | Thinner / thicker |
| `⇧` held | Constrain shapes to 45° or a perfect square |

Single-key shortcuts are live only while armed, and are suspended while a text box has focus, so
typing reaches the text field instead of switching tools.

## Tools

**Pen** and **highlighter** trace freehand. The highlighter is wide and translucent, and keeps one
uniform alpha even where a stroke crosses itself.

**Line, arrow, rectangle, ellipse** drag out from an anchor. Hold `⇧` to constrain.

**Text** places a field where you click. `Enter` commits, `⇧Enter` adds a line. This is the only tool
that takes keyboard focus, and it hands focus back when you are done.

**Laser** is a glowing dot with a short fading trail, for pointing without leaving marks.
**Spotlight** dims everything except a circle around the cursor. Both size off the width control.

**Eraser** removes whole strokes rather than pixels, so anything it takes can be undone.

**Snapshot** drags out a region, which floats as a magnified panel you can annotate, drag, resize,
and scroll to zoom. The surrounding screen stays visible so viewers keep their context.

**Blur** pixelates a dragged region, for hiding a token or a customer name mid-share. It pixelates
rather than blurs, because a gaussian blur is reversible and small text can be recovered from it.

Snapshot and blur are the only tools that read screen pixels, so they are the only ones that need
macOS's Screen Recording permission. It is requested the first time you use one; everything else
works without ever prompting.

## Known limitation: single-window screen shares

If you share **one window** in Zoom or Meet rather than a whole screen, your annotations will not
appear in what participants see. The compositor captures only that window's own buffer, and an
overlay is by definition not part of it. No application can change this.

Share your whole screen and the ink shows up normally.

## Layout

```
mac/
  Sources/OmnipenCore/      stroke model, smoothing, geometry (no graphics)
  Sources/OmnipenRender/    Core Graphics rendering (no AppKit, tested on real pixels)
  Sources/Omnipen/          AppKit shell: menu bar, overlays, palette, tools, capture
  Tests/
```

Windows and Linux are planned as a separate Rust/Tauri codebase built from a written UX spec, since
this app is mostly platform glue and a shared core would cost more than it returns.
