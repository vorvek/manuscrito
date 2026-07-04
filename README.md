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
- `Backspace` and `Delete` delete; `Enter` inserts a new line.
- `Arrow` keys move the cursor; `Ctrl+Left/Right` moves by word.
- `Home`/`End` jump to the start or end of the paragraph; `Ctrl+Home/End` to the start or end of the document.
- `Shift` with any movement key selects text; `Ctrl+A` selects everything.
- `Ctrl+Z` undoes; `Ctrl+Shift+Z` redoes.
- Click to place the cursor; drag or `Shift+Click` to select.
- The mouse wheel moves the cursor by paragraph; `Shift+Wheel` selects; `Ctrl+Wheel` zooms.
- `Ctrl+B`, `Ctrl+I`, `Ctrl+U` toggle bold, italics, and underline.
- `Ctrl+H` toggles a marker highlight; each theme has its own highlight color.
- `Ctrl+S` saves; `Ctrl+Shift+S` saves as; `Ctrl+O` opens; `Ctrl+N` starts a new document.
- `Ctrl+F` finds text; `Enter` in the prompt jumps to the next match.
- `Ctrl+C`, `Ctrl+X`, `Ctrl+V` copy, cut, and paste.
- `Ctrl++`, `Ctrl+-`, `Ctrl+0` zoom in, out, and reset.
- `Tab` toggles first-line indentation for the current paragraph.
- `Ctrl+P` or `Esc` opens the palette; type in it to filter commands.

Quit, Open, and New warn about unsaved changes; run the command a second time to discard them.

All commands are also available from the palette, including headers, alignment, and themes. Toggles such as Page View and Keep Cursor Centered show their state in the palette. Page View splits the writing area into novel-sized pages of about 250 words.

## License

GPL-3.0-only. See `LICENSE`.
