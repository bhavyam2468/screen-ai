# Theming Screen AI

Screen AI reads one file: `~/.config/screen-ai/theme.conf`. It is created on
first launch from `theme.conf` in this folder, and then it is yours to edit.
Changes apply live. The overlay watches the file and the palette sources.

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
overlay picks up the new colors within about 1.5 seconds.

To point at another palette file, set `source_file` in `[palette]`.

## Other keys

- `[shape] radius`: card corner radius in px (0 to 40).
- `[type] font`, `mono`, `size`: UI font, monospace font, and base size.
- `[motion] mode = reduced` turns off non-essential animation. `speed` scales
  durations (0.5 is faster, 2 is slower).
