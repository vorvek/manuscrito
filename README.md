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
- `Backspace` deletes.
- `Enter` inserts a new line.
- `Ctrl+P` opens the palette.
- `Esc` opens or closes the palette.
- `Ctrl+B`, `Ctrl+I`, `Ctrl+U` toggle bold, italics, and underline.
- `Ctrl+S` saves; `Ctrl+Shift+S` saves as; `Ctrl+O` opens.
- `Ctrl+C`, `Ctrl+X`, `Ctrl+V` copy, cut, and paste.
- `Shift+Arrow` selects text; `Ctrl+Shift+Left/Right` selects words.
- `Ctrl++`, `Ctrl+-`, `Ctrl+0` zoom.
- `Tab` sets first-line indentation for the current paragraph.

All commands are also available from the palette.

## License

GPL-3.0-only. See `LICENSE`.
