# Manuscrito

Distraction-free writing app for Windows, Linux, and macOS, built with Odin and Raylib.

## Run

```sh
odin run src
```

## Build

```sh
odin build src -out:build/manuscrito
```

Windows users can run `.\build.ps1`; Linux/macOS users can run `./build.sh`.

## Controls

- Type to write.
- `Backspace` deletes; `Enter` inserts a new line.
- `Arrow` keys move the cursor; `Ctrl+Left/Right` moves by word.
- `Shift+Arrow` selects text; `Ctrl+Shift+Left/Right` selects words.
- `Ctrl+Z` undoes; `Ctrl+Shift+Z` redoes.
- `Ctrl+B`, `Ctrl+I`, `Ctrl+U` toggle bold, italics, and underline.
- `Ctrl+S` saves; `Ctrl+Shift+S` saves as; `Ctrl+O` opens.
- `Ctrl+C`, `Ctrl+X`, `Ctrl+V` copy, cut, and paste.
- `Ctrl++`, `Ctrl+-`, `Ctrl+0` zoom in, out, and reset.
- `Tab` sets first-line indentation for the current paragraph.
- `Ctrl+P` or `Esc` opens the palette; type in it to filter commands.

All commands are also available from the palette, including headers, alignment, and themes.

## License

GPL-3.0-only. See `LICENSE`.
