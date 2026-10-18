# Theming Screen AI

Screen AI reads one file: `~/.config/screen-ai/theme.conf`. It is created on
first launch from `theme.conf` in this folder, and then it is yours to edit.
Changes apply live — the overlay polls this file and the palette sources about
twice a second, so an edit lands while the card is still on screen.

## Priority

For each color role, the first source that defines it wins:

1. explicit colors in `[palette]` of `theme.conf`
2. `~/.config/screen-ai/colors.conf` (written by Matugen, see below)
3. the active Qt/KDE scheme (`kdeglobals`, `qt5ct`, `qt6ct`)
4. GTK `@define-color` values (`gtk-4.0/gtk.css`, then `gtk-3.0/gtk.css`)
5. Screen AI's built-in dark and light colors

`[palette] source = matugen|qt|gtk|builtin` limits this to one layer.

## Matugen

```sh
mkdir -p ~/.config/matugen/templates ~/.config/screen-ai
cp theming/matugen/screen-ai-colors.conf ~/.config/matugen/templates/
cat theming/matugen/config.toml.snippet >> ~/.config/matugen/config.toml
matugen image /path/to/wallpaper.jpg
```

Matugen then writes `~/.config/screen-ai/colors.conf` on every run, and the
overlay picks up the new colors within about half a second.

To point at another palette file, set `source_file` in `[palette]`.

## Other keys

`[shape]` — every value is optional; anything unset is borrowed from the
compositor (Niri's `config.kdl`, including its `include`d files) and then falls
back to a built-in default:

- `radius`: card corner radius in px (0 to 48). Niri: `geometry-corner-radius`.
- `inner_radius`: panels, message bubbles and the shot preview (default `radius - 4`).
- `control_radius`: buttons, inputs and pills (default `radius - 8`).
- `border_width`: card outline in px (0 to 16). Borrowed from Niri's `focus-ring`
  or `border` width, capped at 2px — a width sized for a whole window is too
  heavy on a card.
- `active_border` / `inactive_border`: card outline while the overlay holds the
  keyboard, and once it has handed it back. Borrowed from Niri's `focus-ring`
  `active-color` / `inactive-color`, then the accent color.
- `gap`: screen-edge margin in px (0 to 120). Niri: `layout { gaps }`.
- `shadow`: any CSS `box-shadow`. Niri's `layout { shadow }` is translated,
  keeping its alpha (`#rrggbbaa`).

`[appearance]` — the whole card, including everything Settings → Appearance can
set. A key written here wins over the saved setting; the panel rewrites the file
on save so the two never disagree.

- `theme`: `auto`, `dark`, `light`, or `qt` (the desktop Qt/Matugen colors).
- `position`: `bottom-left`, `bottom-center`, `bottom-right`.
- `opacity`: 10 to 100 (%). Multiplied into *every* surface the card paints —
  plate, command palette, chat bubbles, code blocks, settings fields — so the
  card fades as one object. Foreground colors keep their own contrast.
- `blur`: 0 to 64 px. A blurred copy of the capture is used as the card's plate,
  because an overlay window cannot sample the desktop behind it. Needs
  `opacity < 100` to be visible.
- `noise`: 0 to 100 (%). Film grain over the finished card, text included.
- `shadow_intensity` (0 to 200 %), `shadow_blur`, `shadow_offset`,
  `shadow_spread`, `shadow_color`: the drop shadow, as parts. `shadow_intensity
  = 0` removes it; setting any part stops the shadow from being borrowed from
  Niri. `[shape] shadow` still overrides all of them with one CSS string.

`[input] keyboard` — `auto` (grab on summon, release on focus change),
`on-demand` (never grab), or `sticky` (never release until dismissed).
`$SCREEN_AI_KEYBOARD` wins over it.

`[type]` — `font`, `mono`, `size` (8 to 32): UI font, monospace font, base size.

`[motion]` — `mode = reduced` turns off non-essential animation; `speed` scales
every duration (0.5 is twice as fast, 2.0 twice as slow, 0.1 to 4).
