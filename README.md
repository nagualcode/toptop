# TopTop

The [Omarchy](https://omarchy.org/) bar, reshaped into a notch in the top
centre of the screen.

The stock bar spreads its three layout sections across three screen edges. TopTop
gathers all of them into one block hanging off the top edge, and keeps that block
folded down to just the centre section until you point at it.

```
  ┌───────────────┐         ┌──────────────────────────────────────────────┐
  │  …  menu  …   │   ⇄     │  menu  …  🔊  🔋  ▣  🕐  ⌨  ⬆  …  ▲  💬  🌙  │
  └───────────────┘         └──────────────────────────────────────────────┘
   folded: the centre section    unfolded: every icon, in layout order
```

The folded notch is whatever you left in the centre of the layout, and nothing
else — see [Which icons stay visible](#which-icons-stay-visible).

## Installing

```bash
omarchy plugin add https://github.com/nagualcode/toptop.git --enable
```

That clones the plugin into `~/.config/omarchy/plugins/nagualcode.toptop` and
makes it the bar. Because it stays a git checkout, later versions come from:

```bash
omarchy plugin update nagualcode.toptop
```

Your `bar.layout` is not touched. TopTop reads the same layout the stock bar did
and centres the three sections itself, so your icons keep their order and their
per-widget settings.

<details>
<summary>Installing from a clone instead</summary>

```bash
git clone https://github.com/nagualcode/toptop.git
cd toptop
./scripts/install.sh
```

Useful if you would rather review the code before switching bars — plugins run
unsandboxed inside `omarchy-shell`, so reading `Bar.qml` first is a reasonable
habit. `install.sh` takes a git URL or a local path, `--force` overwrites an
already-installed copy, and it keeps a copy of your `shell.json` at
`~/.config/omarchy/toptop-shell.json.bak` together with a record of which bar was
in use, which is what lets `uninstall.sh` put that bar back automatically.

Both scripts are safe to re-run; a second run is how you repair a broken install.

</details>

## Uninstalling

If you installed with `omarchy plugin add`:

```bash
omarchy-shell shell enablePlugin omarchy.bar '{}'
omarchy plugin remove nagualcode.toptop --yes
```

Switching the bar back first matters: `omarchy plugin remove` deletes the plugin,
and a `shell.json` still pointing at a plugin that is gone leaves the shell with
no bar at all.

If you installed with `scripts/install.sh`, one command does both, restoring
whichever bar was in use before:

```bash
./scripts/uninstall.sh
```

It falls back to `omarchy.bar` when it has no record of the previous bar, so it
also works on a plugin installed either way. Your layout is left untouched, and
`bar.toptop` is dropped from `shell.json` unless you pass `--keep-config`.

## How it behaves

**The notch never reserves screen space.** The layer surface spans the full width
of the screen so it can be centred, but it asks for `ExclusionMode.Ignore`, so
windows keep the full height and the notch is drawn over them. Only the notch
itself accepts pointer input, via a mask.

**Hovering unfolds it.** The pointer entering the collapsed notch expands it
sideways; leaving starts a short timer, and if the pointer has not come back by
the time it fires, the notch folds again. Moving between icons never re-triggers
the collapse, because the pointer stays inside the notch the whole time.

**You can pin it open.** If you would rather the notch never shrinks, keep it
fully unfolded:

```bash
omarchy-toggle-toptop-hover off     # folding off — the bar stays fully open
omarchy-toggle-toptop-hover on      # folding on (default) — hover unfolds it
omarchy-toggle-toptop-hover         # flip whichever state it is in
```

`off` writes the `toptop-stay-open` flag under `~/.local/state/omarchy/toggles/`
(remove the flag to fold again), and the bar picks the change up immediately,
with no restart and no `shell.json` edit. The default is hover-to-unfold;
nothing is written unless you toggle it.

**Widget order is layout order.** Left section, centre section, right section,
read left to right. TopTop does not reorder or drop anything, so your existing
`bar.layout` means exactly what it means for the stock bar.

**Dragging still reorders.** Left-drag any icon to move it, exactly as in the
stock bar. Dragging the bar itself to another screen edge is gone: a notch has
nowhere else to go, and `position` is pinned to `top`.

**Double-clicking the notch toggles transparency**, also inherited from upstream.

**Right-clicking the notch manages the bar's widgets.** It lists every installed
bar widget with the section it currently sits in, and the one you pick can be
moved to another section, taken off the bar (disabled — and re-addable from the
same menu) or, for a third-party widget, uninstalled outright. It is a thin
front-end over `omarchy bar move`, `omarchy plugin enable` and
`omarchy plugin disable`, run as `bin/omarchy-toptop-widgets`, so what the menu
reports is what the shell will actually do. Browsing and installing *plugins*
is not part of it — that is `omarchy plugin add`.

## Configuration

Everything is optional. Add a `toptop` block under `bar` in
`~/.config/omarchy/shell.json`:

```json
{
  "bar": {
    "id": "nagualcode.toptop",
    "toptop": {
      "radius": 12,
      "padding": 8,
      "revealDuration": 180,
      "revealDelay": 120
    }
  }
}
```

| Key | Meaning | Default |
| --- | --- | --- |
| `pinned` | Extra widget ids to keep visible while folded, on top of the centre section | none |
| `radius` | Bottom corner radius of the notch | theme corner radius |
| `padding` | Space between the notch's ends and its outermost icons | `8` |
| `revealDuration` | Unfold/fold animation, in ms | `180` |
| `revealDelay` | Grace period after the pointer leaves, in ms | `120` |

### Which icons stay visible

**Whatever is in the centre section. That is the whole rule.**

Belonging to the centre is what makes an icon visible when the notch folds. Drag
an icon into the centre while the notch is unfolded and it stays visible when the
notch folds; drag it back out and it starts hiding again. The notch is reshaped
by dragging icons rather than by editing a list, so there is nothing to keep in
sync.

**Nothing is pinned implicitly.** There is no rule for the clock and none for
batteries. If you leave the battery in a side section, the folded notch does not
show it — not even because its id ends in `.power`. Move the clock out of the
centre and the notch stops showing the clock too. An empty centre means an empty
notch: the shape is hidden rather than left as a bare pill hanging off the top
edge, but the strip keeps its hover target, so the bar still unfolds when you
point at it and you can drag an icon back into the centre.

To pin an icon without moving it, name it in `pinned` — matched on the ids used
in `bar.layout`:

```json
"toptop": { "pinned": ["io.github.***.battery"] }
```

Pinned entries are always shown, and everything not pinned hides. The folded row
is centred as a whole, so with a single entry it lands dead centre; with two, they
sit side by side around the midpoint.

### A layout that suits a notch

Because the centre is what stays visible, the centre wants to be short. The stock
Omarchy layout puts four widgets there, which would make the folded notch wide.
Moving three of them out to the right — where they unfold next to the clock —
leaves the clock alone in the centre:

```
center:  omarchy.clock
right:   omarchy.indicators  omarchy.keyboard-layout  omarchy.system-update  omarchy.tray  …
left:    omarchy.menu  omarchy.monitor  omarchy.audio  omarchy.bluetooth  omarchy.network  …
```

Edit that with the stock bar active, by dragging the icons, then install TopTop.
Folded, the notch is the clock alone, dead centre. To see the battery in the
notch as well, drag it into the centre next to the clock — the two then sit side
by side around the midpoint rather than the clock being exactly central.

## Relationship to `omarchy.bar`

This is a fork of the bar that ships with Omarchy, not a rewrite. `BarModel.js`
is untouched upstream code, and in `Bar.qml` every change is marked with a comment
beginning `nagualcode.toptop`. The diff against a fresh upstream copy is
therefore the whole story:

```bash
git diff --no-index /usr/share/omarchy/shell/plugins/bar/Bar.qml Bar.qml
```

The substantive changes:

| Area | Upstream | TopTop |
| --- | --- | --- |
| Window | full-width, reserves space, one screen edge | full-width, `ExclusionMode.Ignore`, `position` pinned to `top` |
| Layout | three sections, one per edge | three sections side by side in one centred row |
| Shell components | `horizontalBar`, `verticalBar`, `ModuleList` | `NotchBackground`, `NotchGroup`, `NotchGestureArea` |
| Corner rounding | theme radius on all corners | `PathSvg` outline, straight on top, rounded at the bottom |
| Reveal | driven by upstream's centre-hover API | own hover state, timer and animation |
| Moving the bar | drag the bar to another edge | removed |
| Reordering widgets | left-drag | unchanged |

## Licence

MIT, same as Omarchy. See [LICENSE](LICENSE).