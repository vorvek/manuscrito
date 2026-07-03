package main

import rl "vendor:raylib"
import "core:c"

Theme :: struct {
	name:        cstring,
	background:  rl.Color,
	foreground:  rl.Color,
	muted:       rl.Color,
	panel:       rl.Color,
	border:      rl.Color,
	accent:      rl.Color,
}

App :: struct {
	text:             [dynamic]rune,
	menu_open:        bool,
	selected_command: int,
	theme_index:      int,
	quit:             bool,
}

THEMES := [?]Theme {
	{"Paper", rl.Color{248, 246, 239, 255}, rl.Color{31, 33, 36, 255}, rl.Color{130, 126, 116, 255}, rl.Color{255, 253, 247, 245}, rl.Color{205, 199, 188, 255}, rl.Color{41, 103, 92, 255}},
	{"Night", rl.Color{19, 22, 26, 255}, rl.Color{229, 231, 235, 255}, rl.Color{137, 146, 158, 255}, rl.Color{31, 36, 42, 245}, rl.Color{73, 84, 96, 255}, rl.Color{122, 178, 255, 255}},
}

COMMANDS := [?]cstring {
	"Theme: Paper",
	"Theme: Night",
	"Quit",
}

main :: proc() {
	rl.SetConfigFlags({.VSYNC_HINT, .WINDOW_HIGHDPI, .WINDOW_RESIZABLE})
	rl.InitWindow(1280, 720, "Manuscrito")
	defer rl.CloseWindow()

	monitor := rl.GetCurrentMonitor()
	rl.SetWindowSize(rl.GetMonitorWidth(monitor), rl.GetMonitorHeight(monitor))
	rl.ToggleFullscreen()
	rl.SetExitKey(.KEY_NULL)
	rl.SetTargetFPS(60)

	app := App {
		text = make([dynamic]rune, 0, 8192),
	}
	defer delete(app.text)

	for !app.quit && !rl.WindowShouldClose() {
		update(&app)
		draw(&app)
	}
}

ctrl_down :: proc() -> bool {
	return rl.IsKeyDown(.LEFT_CONTROL) || rl.IsKeyDown(.RIGHT_CONTROL)
}

update :: proc(app: ^App) {
	if ctrl_down() && rl.IsKeyPressed(.P) {
		app.menu_open = !app.menu_open
		return
	}

	if app.menu_open {
		update_menu(app)
		return
	}

	if rl.IsKeyPressed(.ESCAPE) {
		app.menu_open = true
		return
	}

	if rl.IsKeyPressed(.BACKSPACE) || rl.IsKeyPressedRepeat(.BACKSPACE) {
		if len(app.text) > 0 {
			_ = pop(&app.text)
		}
	}

	if rl.IsKeyPressed(.ENTER) {
		append(&app.text, '\n')
	}

	for {
		ch := rl.GetCharPressed()
		if ch == 0 {
			break
		}
		if ch >= ' ' && ch != 127 {
			append(&app.text, ch)
		}
	}
}

update_menu :: proc(app: ^App) {
	if rl.IsKeyPressed(.ESCAPE) {
		app.menu_open = false
		return
	}
	if rl.IsKeyPressed(.DOWN) {
		app.selected_command = (app.selected_command + 1) % len(COMMANDS)
	}
	if rl.IsKeyPressed(.UP) {
		app.selected_command = (app.selected_command + len(COMMANDS) - 1) % len(COMMANDS)
	}
	if rl.IsKeyPressed(.ENTER) {
		switch app.selected_command {
		case 0:
			app.theme_index = 0
		case 1:
			app.theme_index = 1
		case 2:
			app.quit = true
		}
		app.menu_open = false
	}
}

draw :: proc(app: ^App) {
	theme := THEMES[app.theme_index]

	rl.BeginDrawing()
	defer rl.EndDrawing()

	rl.ClearBackground(theme.background)
	draw_document(app, theme)
	if app.menu_open {
		draw_command_menu(app, theme)
	}
}

draw_document :: proc(app: ^App, theme: Theme) {
	screen_w := int(rl.GetScreenWidth())
	screen_h := int(rl.GetScreenHeight())
	margin_x := max(48, screen_w / 5)
	top := max(48, screen_h / 8)
	max_x := f32(screen_w - margin_x)
	x := f32(margin_x)
	y := f32(top)
	font := rl.GetFontDefault()
	font_size := f32(32)
	spacing := f32(2)
	line_height := f32(44)

	if len(app.text) == 0 {
		rl.DrawText("Start writing.", c.int(margin_x), c.int(top), c.int(font_size), theme.muted)
	}

	for ch in app.text {
		if ch == '\n' {
			x = f32(margin_x)
			y += line_height
			continue
		}

		glyph := rl.GetGlyphInfo(font, ch)
		advance := f32(glyph.advanceX) * font_size / f32(font.baseSize)
		if advance <= 0 {
			advance = font_size * 0.55
		}
		if x + advance > max_x {
			x = f32(margin_x)
			y += line_height
		}
		// ponytail: no scrolling yet; add viewport state once documents outgrow one screen.
		if y > f32(screen_h - 80) {
			break
		}
		rl.DrawTextCodepoint(font, ch, rl.Vector2{x, y}, font_size, theme.foreground)
		x += advance + spacing
	}

	if !app.menu_open && (int(rl.GetTime() * 2) % 2 == 0) {
		rl.DrawRectangle(c.int(x), c.int(y), 2, c.int(font_size), theme.accent)
	}
}

draw_command_menu :: proc(app: ^App, theme: Theme) {
	screen_w := int(rl.GetScreenWidth())
	screen_h := int(rl.GetScreenHeight())
	panel_w := min(560, screen_w - 80)
	row_h := 48
	panel_h := 84 + row_h * len(COMMANDS)
	panel_x := (screen_w - panel_w) / 2
	panel_y := (screen_h - panel_h) / 2

	rl.DrawRectangle(0, 0, c.int(screen_w), c.int(screen_h), rl.ColorAlpha(theme.background, 0.72))
	rl.DrawRectangle(c.int(panel_x), c.int(panel_y), c.int(panel_w), c.int(panel_h), theme.panel)
	rl.DrawRectangleLines(c.int(panel_x), c.int(panel_y), c.int(panel_w), c.int(panel_h), theme.border)
	rl.DrawText("Command", c.int(panel_x + 24), c.int(panel_y + 20), 24, theme.foreground)

	for command, i in COMMANDS {
		row_y := panel_y + 64 + i * row_h
		if i == app.selected_command {
			rl.DrawRectangle(c.int(panel_x + 12), c.int(row_y - 6), c.int(panel_w - 24), c.int(row_h - 4), rl.ColorAlpha(theme.accent, 0.18))
		}
		rl.DrawText(command, c.int(panel_x + 28), c.int(row_y), 22, theme.foreground)
	}
}
