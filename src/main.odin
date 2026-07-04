// SPDX-License-Identifier: GPL-3.0-only
package main

import rl "vendor:raylib"
import "core:c"
import "core:fmt"
import "core:math"
import "core:os"
import "core:path/filepath"
import "core:slice"
import "core:strconv"
import "core:strings"
import "core:unicode"
import "core:unicode/utf8"

VERSION :: "1.0.3"
MAGIC :: "MANUSCRITO\t1"
// Text lines per page in page view. With the 60-char column this lands near
// 250 words, the usual novel manuscript page.
PAGE_LINES :: 25
SPLASH_JPG :: #load("scriptorium.jpg")
EB_GARAMOND_REGULAR :: #load("fonts/EBGaramond-Regular.ttf")
EB_GARAMOND_ITALIC :: #load("fonts/EBGaramond-Italic.ttf")
TANGERINE_BOLD :: #load("fonts/Tangerine-Bold.ttf")
NUNITO_SANS :: #load("fonts/NunitoSans.ttf")

Align :: enum int {
	Left,
	Center,
	Right,
	Justify,
}

Path_Action :: enum int {
	None,
	Save_As,
	Open,
	Find,
}

Palette_Mode :: enum int {
	Commands,
	Path,
}

Command_Kind :: enum int {
	Save,
	Save_As,
	Open,
	New,
	Find,
	Select_All,
	Undo,
	Redo,
	Copy,
	Cut,
	Paste,
	Bold,
	Italic,
	Underline,
	Highlight,
	Strike,
	Header_1,
	Header_2,
	Header_3,
	Header_4,
	Size_Paragraph,
	Align_Left,
	Align_Center,
	Align_Right,
	Align_Justify,
	Zoom_In,
	Zoom_Out,
	Zoom_Reset,
	First_Line_Indent,
	Keep_Cursor_Centered,
	Page_View,
	Theme_Cycle,
	Quit,
}

// Coalesces consecutive same-kind edits into one undo step; a boundary is forced
// whenever the kind changes (see begin_edit) or the caret moves.
Edit_Kind :: enum int {
	Other,
	Insert,
	Delete,
}

Snapshot :: struct {
	text:       []rune,
	styles:     []Char_Style,
	paragraphs: []Paragraph,
	cursor:     int,
	anchor:     int,
}

Style_Field :: enum int {
	Bold,
	Italic,
	Underline,
	Highlight,
	Strike,
}

Char_Style :: struct {
	bold:      bool,
	italic:    bool,
	underline: bool,
	highlight: bool,
	strike:    bool,
}

Paragraph :: struct {
	header:       int,
	align:        Align,
	first_indent: bool,
}

Theme :: struct {
	name:        cstring,
	background:  rl.Color,
	foreground:  rl.Color,
	muted:       rl.Color,
	panel:       rl.Color,
	border:      rl.Color,
	accent:      rl.Color,
	selection:   rl.Color,
	page:        rl.Color,
	highlight:   rl.Color,
}

Fonts :: struct {
	regular:           rl.Font,
	bold:              rl.Font,
	italic:            rl.Font,
	bold_italic:       rl.Font,
	title:             rl.Font,
	ui:                rl.Font,
	regular_loaded:    bool,
	bold_loaded:       bool,
	italic_loaded:     bool,
	bold_italic_loaded: bool,
	title_loaded:      bool,
	ui_loaded:         bool,
}

Command :: struct {
	label: cstring,
	kind:  Command_Kind,
}

App :: struct {
	text:             [dynamic]rune,
	styles:           [dynamic]Char_Style,
	paragraphs:       [dynamic]Paragraph,
	cursor:           int,
	anchor:           int,
	active_style:     Char_Style,
	undo:             [dynamic]Snapshot,
	redo:             [dynamic]Snapshot,
	last_edit:        Edit_Kind,
	palette_open:     bool,
	palette_mode:     Palette_Mode,
	palette_query:    [dynamic]rune,
	recent:           [dynamic]Command_Kind,
	selected_command: int,
	path_action:      Path_Action,
	path_input:       [dynamic]rune,
	file_path:        string,
	theme_index:      int,
	zoom:             f32,
	scroll_y:         f32,
	scroll_target:    f32,
	keep_cursor_centered: bool,
	show_pages:       bool,
	mouse_selecting:  bool,
	wheel_accum:      f32,
	dirty:            bool,
	show_splash:      bool,
	splash:           rl.Texture2D,
	splash_loaded:    bool,
	quit:             bool,
	confirm_pending:  bool,
	confirm_kind:     Command_Kind,
	status:           cstring,
	status_time:      f64,
	fonts:            Fonts,
	help_open:        bool,
}

Help_Entry :: struct {
	keys: cstring,
	desc: cstring,
}

HELP_ENTRIES := [?]Help_Entry {
	{"F1",                    "Toggle this help"},
	{"Ctrl+P / Esc",          "Open the command palette"},
	{"Ctrl+S / Ctrl+Shift+S", "Save / Save As"},
	{"Ctrl+O / Ctrl+N",       "Open / New document"},
	{"Ctrl+F",                "Find; Enter jumps to the next match"},
	{"Ctrl+Z / Ctrl+Shift+Z", "Undo / Redo"},
	{"Ctrl+A",                "Select all"},
	{"Ctrl+C / X / V",        "Copy / Cut / Paste"},
	{"Ctrl+B / I / U",        "Bold / Italic / Underline"},
	{"Ctrl+H",                "Highlight"},
	{"Ctrl+J",                "Strikethrough"},
	{"Ctrl++ / - / 0",        "Zoom in / out / reset"},
	{"Up / Down",             "Move by line"},
	{"Ctrl+Left/Right",       "Move by word"},
	{"Ctrl+Up / Down",        "Move by paragraph"},
	{"Ctrl+Home/End",         "Jump to start/end of document"},
	{"Ctrl+Wheel",            "Zoom"},
	{"Tab",                   "Toggle first-line indent"},
	{"Ctrl+Q",                "Quit (press again to confirm)"},
}

// Fields: name, background, foreground, muted, panel, border, accent, selection, page, highlight.
THEMES := [?]Theme {
	// Light
	{"Paper",    rl.Color{248, 246, 239, 255}, rl.Color{31, 33, 36, 255},   rl.Color{130, 126, 116, 255}, rl.Color{255, 253, 247, 245}, rl.Color{205, 199, 188, 255}, rl.Color{41, 103, 92, 255},  rl.Color{191, 221, 214, 160}, rl.Color{255, 254, 249, 255}, rl.Color{247, 222, 116, 255}},
	{"Sepia",    rl.Color{237, 224, 200, 255}, rl.Color{60, 44, 30, 255},   rl.Color{140, 120, 95, 255},  rl.Color{247, 236, 214, 245}, rl.Color{206, 188, 158, 255}, rl.Color{150, 90, 40, 255},  rl.Color{219, 197, 158, 160}, rl.Color{247, 237, 217, 255}, rl.Color{231, 196, 100, 255}},
	{"Daylight", rl.Color{247, 249, 252, 255}, rl.Color{28, 34, 42, 255},   rl.Color{120, 132, 148, 255}, rl.Color{255, 255, 255, 245}, rl.Color{206, 214, 226, 255}, rl.Color{40, 110, 200, 255}, rl.Color{190, 214, 244, 160}, rl.Color{255, 255, 255, 255}, rl.Color{250, 229, 120, 255}},
	{"Mint",     rl.Color{240, 247, 242, 255}, rl.Color{26, 40, 34, 255},   rl.Color{116, 140, 128, 255}, rl.Color{250, 255, 252, 245}, rl.Color{200, 220, 208, 255}, rl.Color{34, 130, 96, 255},  rl.Color{194, 226, 210, 160}, rl.Color{250, 255, 252, 255}, rl.Color{236, 228, 122, 255}},
	// Dark
	{"Night",    rl.Color{19, 22, 26, 255},    rl.Color{229, 231, 235, 255}, rl.Color{137, 146, 158, 255}, rl.Color{31, 36, 42, 245},   rl.Color{73, 84, 96, 255},    rl.Color{122, 178, 255, 255}, rl.Color{52, 88, 134, 170},  rl.Color{27, 31, 37, 255},   rl.Color{102, 82, 26, 255}},
	{"Nord",     rl.Color{46, 52, 64, 255},    rl.Color{216, 222, 233, 255}, rl.Color{136, 146, 167, 255}, rl.Color{59, 66, 82, 245},   rl.Color{76, 86, 106, 255},   rl.Color{136, 192, 208, 255}, rl.Color{67, 76, 94, 180},   rl.Color{56, 63, 77, 255},   rl.Color{110, 96, 46, 255}},
	{"Dracula",  rl.Color{40, 42, 54, 255},    rl.Color{248, 248, 242, 255}, rl.Color{140, 144, 160, 255}, rl.Color{54, 57, 74, 245},   rl.Color{68, 71, 90, 255},    rl.Color{189, 147, 249, 255}, rl.Color{68, 71, 110, 180},  rl.Color{52, 55, 70, 255},   rl.Color{112, 96, 40, 255}},
	{"Gruvbox",  rl.Color{40, 40, 40, 255},    rl.Color{235, 219, 178, 255}, rl.Color{168, 153, 132, 255}, rl.Color{60, 56, 54, 245},   rl.Color{80, 73, 69, 255},    rl.Color{215, 153, 33, 255},  rl.Color{80, 73, 69, 180},   rl.Color{50, 48, 46, 255},   rl.Color{112, 88, 22, 255}},
	// High contrast
	{"Contrast Dark",  rl.Color{0, 0, 0, 255},       rl.Color{255, 255, 255, 255}, rl.Color{180, 180, 180, 255}, rl.Color{16, 16, 16, 255},    rl.Color{140, 140, 140, 255}, rl.Color{255, 234, 0, 255},   rl.Color{0, 90, 200, 220},   rl.Color{16, 16, 16, 255},   rl.Color{96, 84, 0, 255}},
	{"Contrast Light", rl.Color{255, 255, 255, 255}, rl.Color{0, 0, 0, 255},       rl.Color{80, 80, 80, 255},    rl.Color{245, 245, 245, 255}, rl.Color{60, 60, 60, 255},    rl.Color{0, 40, 200, 255},    rl.Color{150, 190, 255, 200}, rl.Color{248, 248, 248, 255}, rl.Color{255, 235, 59, 255}},
}

COMMANDS := [?]Command {
	{"Save", .Save},
	{"Save As...", .Save_As},
	{"Open...", .Open},
	{"New", .New},
	{"Find...", .Find},
	{"Select All", .Select_All},
	{"Undo", .Undo},
	{"Redo", .Redo},
	{"Copy", .Copy},
	{"Cut", .Cut},
	{"Paste", .Paste},
	{"Bold", .Bold},
	{"Italics", .Italic},
	{"Underline", .Underline},
	{"Highlight", .Highlight},
	{"Strikethrough", .Strike},
	{"Size: Heading 1", .Header_1},
	{"Size: Heading 2", .Header_2},
	{"Size: Heading 3", .Header_3},
	{"Size: Heading 4", .Header_4},
	{"Size: Paragraph", .Size_Paragraph},
	{"Align Left", .Align_Left},
	{"Align Center", .Align_Center},
	{"Align Right", .Align_Right},
	{"Align Justify", .Align_Justify},
	{"Zoom In", .Zoom_In},
	{"Zoom Out", .Zoom_Out},
	{"Zoom Reset", .Zoom_Reset},
	{"First Line Indent", .First_Line_Indent},
	{"Keep Cursor Centered Vertically", .Keep_Cursor_Centered},
	{"Page View", .Page_View},
	{"Theme: Next", .Theme_Cycle},
	{"Quit", .Quit},
}

main :: proc() {
	rl.SetConfigFlags({.VSYNC_HINT, .WINDOW_HIGHDPI, .WINDOW_UNDECORATED, .WINDOW_RESIZABLE})
	rl.InitWindow(1280, 720, "Manuscrito")
	defer rl.CloseWindow()

	monitor := rl.GetCurrentMonitor()
	monitor_pos := rl.GetMonitorPosition(monitor)
	// Borderless fullscreen is an undecorated monitor-sized window. The +1 extra line
	// keeps it 1px past the monitor so Windows' fullscreen optimizations don't promote
	// it to exclusive fullscreen. The off-screen row is invisible.
	rl.SetWindowPosition(c.int(monitor_pos.x), c.int(monitor_pos.y))
	rl.SetWindowSize(rl.GetMonitorWidth(monitor), rl.GetMonitorHeight(monitor) + 1)
	when ODIN_OS == .Windows {
		rl.SetWindowState({.WINDOW_UNDECORATED, .WINDOW_TOPMOST})
		rl.SetWindowFocused()
	}
	rl.SetExitKey(.KEY_NULL)
	rl.SetTargetFPS(60)

	app := App {
		text       = make([dynamic]rune, 0, 8192),
		styles     = make([dynamic]Char_Style, 0, 8192),
		paragraphs = make([dynamic]Paragraph, 0, 256),
		path_input = make([dynamic]rune, 0, 512),
		zoom       = 1,
		keep_cursor_centered = true,
		show_splash = true,
		splash     = load_splash_texture(),
		status     = "New document",
		fonts      = load_fonts(),
	}
	app.splash_loaded = rl.IsTextureValid(app.splash)
	append(&app.paragraphs, Paragraph{})
	load_settings(&app)
	defer {
		if app.splash_loaded {
			rl.UnloadTexture(app.splash)
		}
		unload_fonts(&app.fonts)
		delete(app.text)
		delete(app.styles)
		delete(app.paragraphs)
		delete(app.path_input)
		for snap in app.undo {
			free_snapshot(snap)
		}
		delete(app.undo)
		for snap in app.redo {
			free_snapshot(snap)
		}
		delete(app.redo)
		delete(app.palette_query)
		delete(app.recent)
		if len(app.file_path) > 0 {
			delete(app.file_path)
		}
	}

	for !app.quit {
		if rl.WindowShouldClose() {
			execute_command(&app, .Quit)
			if app.quit {
				break
			}
		}
		update(&app)
		draw(&app)
		free_all(context.temp_allocator)
	}
}

load_fonts :: proc() -> Fonts {
	fonts := Fonts{}
	fonts.regular, fonts.regular_loaded = load_font_from_memory(EB_GARAMOND_REGULAR, 128)
	fonts.italic, fonts.italic_loaded = load_font_from_memory(EB_GARAMOND_ITALIC, 128)
	fonts.title, fonts.title_loaded = load_font_from_memory(TANGERINE_BOLD, 128)
	fonts.ui, fonts.ui_loaded = load_font_from_memory(NUNITO_SANS, 128)
	if !fonts.regular_loaded {
		fonts.regular = rl.GetFontDefault()
	}
	if !fonts.italic_loaded {
		fonts.italic = fonts.regular
	}
	if !fonts.title_loaded {
		fonts.title = fonts.regular
	}
	if !fonts.ui_loaded {
		fonts.ui = fonts.regular
	}
	fonts.bold = fonts.regular
	fonts.bold_italic = fonts.italic
	return fonts
}

load_font_from_memory :: proc(data: []u8, size: int) -> (font: rl.Font, loaded: bool) {
	font = rl.LoadFontFromMemory(".ttf", raw_data(data), c.int(len(data)), c.int(size), nil, 0)
	if rl.IsFontValid(font) {
		// Atlas is baked at `size` px but drawn far smaller; mipmaps + trilinear
		// keep thin strokes solid and edges smooth instead of faint and aliased.
		rl.GenTextureMipmaps(&font.texture)
		rl.SetTextureFilter(font.texture, .TRILINEAR)
	}
	return font, rl.IsFontValid(font)
}

load_splash_texture :: proc() -> rl.Texture2D {
	image := rl.LoadImageFromMemory(".jpg", raw_data(SPLASH_JPG), c.int(len(SPLASH_JPG)))
	if !rl.IsImageValid(image) {
		return rl.Texture2D{}
	}
	defer rl.UnloadImage(image)
	return rl.LoadTextureFromImage(image)
}

unload_fonts :: proc(fonts: ^Fonts) {
	if fonts.regular_loaded { rl.UnloadFont(fonts.regular) }
	if fonts.bold_loaded { rl.UnloadFont(fonts.bold) }
	if fonts.italic_loaded { rl.UnloadFont(fonts.italic) }
	if fonts.bold_italic_loaded { rl.UnloadFont(fonts.bold_italic) }
	if fonts.title_loaded { rl.UnloadFont(fonts.title) }
	if fonts.ui_loaded { rl.UnloadFont(fonts.ui) }
}

ctrl_down :: proc() -> bool {
	return rl.IsKeyDown(.LEFT_CONTROL) || rl.IsKeyDown(.RIGHT_CONTROL)
}

shift_down :: proc() -> bool {
	return rl.IsKeyDown(.LEFT_SHIFT) || rl.IsKeyDown(.RIGHT_SHIFT)
}

pressed_or_repeat :: proc(key: rl.KeyboardKey) -> bool {
	return rl.IsKeyPressed(key) || rl.IsKeyPressedRepeat(key)
}

update :: proc(app: ^App) {
	if app.show_splash {
		if splash_dismissed() {
			app.show_splash = false
		}
		return
	}

	if rl.IsKeyPressed(.F1) && !app.palette_open {
		app.help_open = !app.help_open
		return
	}
	if app.help_open {
		if rl.IsKeyPressed(.ESCAPE) {
			app.help_open = false
		}
		return
	}

	if ctrl_down() && rl.IsKeyPressed(.P) {
		if app.palette_open {
			app.palette_open = false
		} else {
			open_command_palette(app)
		}
		return
	}

	if app.palette_open {
		update_palette(app)
		return
	}

	if handle_shortcuts(app) {
		return
	}
	handle_mouse(app)
	handle_movement(app)
	handle_editing(app)
}

handle_mouse :: proc(app: ^App) {
	if rl.IsMouseButtonReleased(.LEFT) {
		app.mouse_selecting = false
	}
	if rl.IsMouseButtonPressed(.LEFT) {
		// Ignore clicks on the status bar.
		if rl.GetMousePosition().y > f32(rl.GetScreenHeight() - 52) {
			return
		}
		app.mouse_selecting = true
		move_cursor(app, text_index_at_point(app, rl.GetMousePosition()), shift_down())
	} else if app.mouse_selecting && rl.IsMouseButtonDown(.LEFT) {
		move_cursor(app, text_index_at_point(app, rl.GetMousePosition()), true)
	}
	// Ctrl+wheel zooms with the same limits as the zoom commands.
	if ctrl_down() {
		app.zoom = clamp(app.zoom + rl.GetMouseWheelMove() * 0.1, 0.5, 2.5)
		return
	}
	// The wheel moves the cursor by paragraph; the view follows it as with any
	// other movement. Fractional touchpad deltas accumulate until a whole step.
	app.wheel_accum += rl.GetMouseWheelMove()
	for app.wheel_accum >= 1 {
		move_cursor(app, prev_paragraph_column(app), shift_down())
		app.wheel_accum -= 1
	}
	for app.wheel_accum <= -1 {
		move_cursor(app, next_paragraph_column(app), shift_down())
		app.wheel_accum += 1
	}
}

splash_dismissed :: proc() -> bool {
	if rl.GetKeyPressed() != .KEY_NULL {
		return true
	}
	return rl.IsMouseButtonPressed(.LEFT) ||
	       rl.IsMouseButtonPressed(.RIGHT) ||
	       rl.IsMouseButtonPressed(.MIDDLE) ||
	       rl.IsMouseButtonPressed(.SIDE) ||
	       rl.IsMouseButtonPressed(.EXTRA) ||
	       rl.IsMouseButtonPressed(.FORWARD) ||
	       rl.IsMouseButtonPressed(.BACK)
}

handle_shortcuts :: proc(app: ^App) -> bool {
	if !ctrl_down() {
		return false
	}
	if rl.IsKeyPressed(.S) {
		execute_command(app, .Save_As if shift_down() else .Save)
		return true
	}
	if rl.IsKeyPressed(.O) {
		execute_command(app, .Open)
		return true
	}
	if rl.IsKeyPressed(.N) {
		execute_command(app, .New)
		return true
	}
	if rl.IsKeyPressed(.F) {
		execute_command(app, .Find)
		return true
	}
	if rl.IsKeyPressed(.A) {
		execute_command(app, .Select_All)
		return true
	}
	if rl.IsKeyPressed(.Z) {
		execute_command(app, .Redo if shift_down() else .Undo)
		return true
	}
	if rl.IsKeyPressed(.C) {
		execute_command(app, .Copy)
		return true
	}
	if rl.IsKeyPressed(.X) {
		execute_command(app, .Cut)
		return true
	}
	if rl.IsKeyPressed(.V) {
		execute_command(app, .Paste)
		return true
	}
	if rl.IsKeyPressed(.B) {
		execute_command(app, .Bold)
		return true
	}
	if rl.IsKeyPressed(.I) {
		execute_command(app, .Italic)
		return true
	}
	if rl.IsKeyPressed(.U) {
		execute_command(app, .Underline)
		return true
	}
	if rl.IsKeyPressed(.H) {
		execute_command(app, .Highlight)
		return true
	}
	if rl.IsKeyPressed(.J) {
		execute_command(app, .Strike)
		return true
	}
	if rl.IsKeyPressed(.Q) {
		execute_command(app, .Quit)
		return true
	}
	if rl.IsKeyPressed(.EQUAL) || rl.IsKeyPressed(.KP_ADD) {
		execute_command(app, .Zoom_In)
		return true
	}
	if rl.IsKeyPressed(.MINUS) || rl.IsKeyPressed(.KP_SUBTRACT) {
		execute_command(app, .Zoom_Out)
		return true
	}
	if rl.IsKeyPressed(.ZERO) || rl.IsKeyPressed(.KP_0) {
		execute_command(app, .Zoom_Reset)
		return true
	}
	return false
}

handle_movement :: proc(app: ^App) {
	selecting := shift_down()
	by_word := ctrl_down()
	if pressed_or_repeat(.LEFT) {
		move_cursor(app, prev_word(app, app.cursor) if by_word else app.cursor - 1, selecting)
	}
	if pressed_or_repeat(.RIGHT) {
		move_cursor(app, next_word(app, app.cursor) if by_word else app.cursor + 1, selecting)
	}
	if pressed_or_repeat(.UP) {
		if by_word {
			move_cursor(app, prev_paragraph_column(app), selecting)
		} else {
			move_visual_line(app, -1, selecting)
		}
	}
	if pressed_or_repeat(.DOWN) {
		if by_word {
			move_cursor(app, next_paragraph_column(app), selecting)
		} else {
			move_visual_line(app, +1, selecting)
		}
	}
	if pressed_or_repeat(.HOME) {
		move_cursor(app, 0 if by_word else paragraph_start(app, paragraph_index_at(app, app.cursor)), selecting)
	}
	if pressed_or_repeat(.END) {
		move_cursor(app, len(app.text) if by_word else paragraph_end(app, paragraph_start(app, paragraph_index_at(app, app.cursor))), selecting)
	}
}

handle_editing :: proc(app: ^App) {
	if rl.IsKeyPressed(.ESCAPE) {
		open_command_palette(app)
		return
	}
	if rl.IsKeyPressed(.TAB) {
		execute_command(app, .First_Line_Indent)
		return
	}
	if pressed_or_repeat(.BACKSPACE) && (app.cursor > 0 || has_selection(app)) {
		begin_edit(app, .Delete)
		backspace(app)
	}
	if pressed_or_repeat(.DELETE) && (app.cursor < len(app.text) || has_selection(app)) {
		begin_edit(app, .Delete)
		forward_delete(app)
	}
	if rl.IsKeyPressed(.ENTER) {
		begin_edit(app, .Other)
		insert_rune(app, '\n')
	}
	for {
		ch := rl.GetCharPressed()
		if ch == 0 {
			break
		}
		if ch >= ' ' && ch != 127 {
			begin_typing_edit(app, ch)
			insert_rune(app, ch)
		}
	}
}

open_command_palette :: proc(app: ^App) {
	app.palette_open = true
	app.palette_mode = .Commands
	app.selected_command = 0
	clear(&app.palette_query)
}

update_palette :: proc(app: ^App) {
	if app.palette_mode == .Path {
		update_path_prompt(app)
		return
	}
	if rl.IsKeyPressed(.ESCAPE) {
		app.palette_open = false
		return
	}
	entries := palette_entries(app)
	n := len(entries)
	if pressed_or_repeat(.DOWN) && n > 0 {
		app.selected_command = (app.selected_command + 1) % n
	}
	if pressed_or_repeat(.UP) && n > 0 {
		app.selected_command = (app.selected_command + n - 1) % n
	}
	if rl.IsKeyPressed(.ENTER) && n > 0 {
		sel := clamp(app.selected_command, 0, n - 1)
		execute_command(app, COMMANDS[entries[sel]].kind)
		return
	}
	if pressed_or_repeat(.BACKSPACE) && len(app.palette_query) > 0 {
		pop(&app.palette_query)
		app.selected_command = 0
	}
	for {
		ch := rl.GetCharPressed()
		if ch == 0 {
			break
		}
		if ch >= ' ' && ch != 127 {
			append(&app.palette_query, ch)
			app.selected_command = 0
		}
	}
}

// Command indices to show: filtered by the query, or (when empty) recents first.
palette_entries :: proc(app: ^App) -> []int {
	entries := make([dynamic]int, context.temp_allocator)
	if len(app.palette_query) == 0 {
		for kind in app.recent {
			idx := command_index(kind)
			if idx >= 0 {
				append(&entries, idx)
			}
		}
		for cmd, i in COMMANDS {
			if !slice.contains(app.recent[:], cmd.kind) {
				append(&entries, i)
			}
		}
	} else {
		q := palette_query_lower(app)
		for cmd, i in COMMANDS {
			if command_label_matches(cmd.label, q) {
				append(&entries, i)
			}
		}
	}
	return entries[:]
}

command_index :: proc(kind: Command_Kind) -> int {
	for cmd, i in COMMANDS {
		if cmd.kind == kind {
			return i
		}
	}
	return -1
}

palette_query_lower :: proc(app: ^App) -> string {
	sb := strings.builder_make(context.temp_allocator)
	for ch in app.palette_query {
		strings.write_rune(&sb, unicode.to_lower(ch))
	}
	return strings.to_string(sb)
}

palette_query_cstring :: proc(app: ^App) -> cstring {
	sb := strings.builder_make(context.temp_allocator)
	for ch in app.palette_query {
		strings.write_rune(&sb, ch)
	}
	cs, _ := strings.to_cstring(&sb)
	return cs
}

command_label_matches :: proc(label: cstring, q: string) -> bool {
	return strings.contains(strings.to_lower(string(label), context.temp_allocator), q)
}

record_recent :: proc(app: ^App, kind: Command_Kind) {
	for r, i in app.recent {
		if r == kind {
			ordered_remove(&app.recent, i)
			break
		}
	}
	inject_at(&app.recent, 0, kind)
	for len(app.recent) > 3 {
		pop(&app.recent)
	}
}

update_path_prompt :: proc(app: ^App) {
	if rl.IsKeyPressed(.ESCAPE) {
		app.palette_open = false
		app.palette_mode = .Commands
		return
	}
	if ctrl_down() && rl.IsKeyPressed(.V) {
		paste_into_path(app)
		return
	}
	if pressed_or_repeat(.BACKSPACE) && len(app.path_input) > 0 {
		_ = pop(&app.path_input)
	}
	if rl.IsKeyPressed(.ENTER) {
		path := path_input_string(app)
		defer delete(path)
		if len(path) > 0 {
			switch app.path_action {
			case .Save_As:
				save_document(app, path)
			case .Open:
				open_document(app, path)
			case .Find:
				// The prompt stays open so Enter jumps to the next match.
				find_next(app, path)
				return
			case .None:
			case:
			}
		}
		app.palette_open = false
		app.palette_mode = .Commands
		return
	}
	for {
		ch := rl.GetCharPressed()
		if ch == 0 {
			break
		}
		if ch >= ' ' && ch != 127 {
			append(&app.path_input, ch)
		}
	}
}

execute_command :: proc(app: ^App, kind: Command_Kind) {
	// Quit always needs a second run so a stray Ctrl+Q doesn't close the app;
	// Open/New only need it when there are unsaved changes to discard.
	if (kind == .Quit || (app.dirty && (kind == .Open || kind == .New))) &&
	   (!app.confirm_pending || app.confirm_kind != kind) {
		app.confirm_pending = true
		app.confirm_kind = kind
		app.palette_open = false
		app.status = "Unsaved changes. Repeat the command to discard." if app.dirty else "Press Ctrl+Q again to quit."
		return
	}
	app.confirm_pending = false
	if kind != .Theme_Cycle && kind != .Undo && kind != .Redo {
		record_recent(app, kind)
	}
	#partial switch kind {
	case .Cut, .Paste, .Bold, .Italic, .Underline, .Highlight, .Strike, .Header_1 ..= .Size_Paragraph, .Align_Left ..= .Align_Justify, .First_Line_Indent:
		begin_edit(app, .Other)
	}
	switch kind {
	case .Save:
		if len(app.file_path) == 0 {
			begin_path_prompt(app, .Save_As)
		} else {
			save_document(app, app.file_path)
			app.palette_open = false
		}
	case .Save_As:
		begin_path_prompt(app, .Save_As)
	case .Open:
		begin_path_prompt(app, .Open)
	case .New:
		clear_document(app)
		clear_snapshots(&app.undo)
		clear_snapshots(&app.redo)
		app.last_edit = .Other
		if len(app.file_path) > 0 {
			delete(app.file_path)
			app.file_path = ""
		}
		set_status(app, "New document")
		app.palette_open = false
	case .Find:
		begin_path_prompt(app, .Find)
	case .Select_All:
		app.anchor = 0
		app.cursor = len(app.text)
		sync_active_style(app)
		app.last_edit = .Other
		app.palette_open = false
	case .Undo:
		undo(app)
		app.palette_open = false
	case .Redo:
		redo(app)
		app.palette_open = false
	case .Copy:
		copy_selection(app)
		app.palette_open = false
	case .Cut:
		copy_selection(app)
		delete_selection(app)
		app.palette_open = false
	case .Paste:
		paste_clipboard(app)
		app.palette_open = false
	case .Bold:
		toggle_style(app, .Bold)
		app.palette_open = false
	case .Italic:
		toggle_style(app, .Italic)
		app.palette_open = false
	case .Underline:
		toggle_style(app, .Underline)
		app.palette_open = false
	case .Highlight:
		toggle_style(app, .Highlight)
		app.palette_open = false
	case .Strike:
		toggle_style(app, .Strike)
		app.palette_open = false
	case .Header_1:
		apply_header(app, 1)
		app.palette_open = false
	case .Header_2:
		apply_header(app, 2)
		app.palette_open = false
	case .Header_3:
		apply_header(app, 3)
		app.palette_open = false
	case .Header_4:
		apply_header(app, 4)
		app.palette_open = false
	case .Size_Paragraph:
		apply_header(app, 0)
		app.palette_open = false
	case .Align_Left:
		apply_align(app, .Left)
		app.palette_open = false
	case .Align_Center:
		apply_align(app, .Center)
		app.palette_open = false
	case .Align_Right:
		apply_align(app, .Right)
		app.palette_open = false
	case .Align_Justify:
		apply_align(app, .Justify)
		app.palette_open = false
	case .Zoom_In:
		app.zoom = min(app.zoom + 0.1, 2.5)
		app.palette_open = false
	case .Zoom_Out:
		app.zoom = max(app.zoom - 0.1, 0.5)
		app.palette_open = false
	case .Zoom_Reset:
		app.zoom = 1
		app.palette_open = false
	case .First_Line_Indent:
		apply_first_line_indent(app)
		app.palette_open = false
	case .Keep_Cursor_Centered:
		app.keep_cursor_centered = !app.keep_cursor_centered
		app.palette_open = false
	case .Page_View:
		app.show_pages = !app.show_pages
		app.palette_open = false
	case .Theme_Cycle:
		app.theme_index = (app.theme_index + 1) % len(THEMES)
		set_status(app, THEMES[app.theme_index].name)
		save_settings(app)
		// palette stays open so repeated Enter browses every theme
	case .Quit:
		app.quit = true
	}
}

begin_path_prompt :: proc(app: ^App, action: Path_Action) {
	clear(&app.path_input)
	if action == .Save_As && len(app.file_path) > 0 {
		for ch in app.file_path {
			append(&app.path_input, ch)
		}
	}
	app.path_action = action
	app.palette_open = true
	app.palette_mode = .Path
}

paste_into_path :: proc(app: ^App) {
	for ch in string(rl.GetClipboardText()) {
		if ch >= ' ' && ch != 127 {
			append(&app.path_input, ch)
		}
	}
}

path_input_string :: proc(app: ^App) -> string {
	sb := strings.builder_make()
	defer strings.builder_destroy(&sb)
	for ch in app.path_input {
		_, _ = strings.write_rune(&sb, ch)
	}
	return strings.clone(strings.to_string(sb))
}

has_selection :: proc(app: ^App) -> bool {
	return app.cursor != app.anchor
}

selection_range :: proc(app: ^App) -> (lo, hi: int) {
	return min(app.cursor, app.anchor), max(app.cursor, app.anchor)
}

move_cursor :: proc(app: ^App, pos: int, selecting: bool) {
	app.cursor = clamp(pos, 0, len(app.text))
	if !selecting {
		app.anchor = app.cursor
	}
	sync_active_style(app)
	app.last_edit = .Other // moving the caret ends the current undo group
}

sync_active_style :: proc(app: ^App) {
	if app.cursor > 0 && app.cursor <= len(app.styles) {
		app.active_style = app.styles[app.cursor - 1]
	} else {
		app.active_style = Char_Style{}
	}
}

// Snapshot the document before an edit, coalescing runs of the same kind.
begin_edit :: proc(app: ^App, kind: Edit_Kind) {
	app.confirm_pending = false
	if kind == .Other || app.last_edit != kind {
		push_undo(app)
	}
	app.last_edit = kind
}

// Word-granular undo, like Word: start a new undo step at each word boundary so
// Ctrl+Z peels off a word at a time rather than the whole typing burst.
begin_typing_edit :: proc(app: ^App, ch: rune) {
	app.confirm_pending = false
	word_start := is_word(ch) && (app.cursor == 0 || !is_word(app.text[app.cursor - 1]))
	if word_start || app.last_edit != .Insert {
		push_undo(app)
	}
	app.last_edit = .Insert
}

push_undo :: proc(app: ^App) {
	append(&app.undo, current_snapshot(app))
	clear_snapshots(&app.redo) // a fresh edit invalidates the redo history
	// Cap the history at 200 full snapshots. Documents are small, so this is plenty.
	if len(app.undo) > 200 {
		free_snapshot(app.undo[0])
		ordered_remove(&app.undo, 0)
	}
}

undo :: proc(app: ^App) {
	if len(app.undo) == 0 {
		return
	}
	append(&app.redo, current_snapshot(app))
	snap := pop(&app.undo)
	restore_snapshot(app, snap)
	free_snapshot(snap)
	app.last_edit = .Other
	app.dirty = true
}

redo :: proc(app: ^App) {
	if len(app.redo) == 0 {
		return
	}
	append(&app.undo, current_snapshot(app))
	snap := pop(&app.redo)
	restore_snapshot(app, snap)
	free_snapshot(snap)
	app.last_edit = .Other
	app.dirty = true
}

current_snapshot :: proc(app: ^App) -> Snapshot {
	return Snapshot {
		text       = slice.clone(app.text[:]),
		styles     = slice.clone(app.styles[:]),
		paragraphs = slice.clone(app.paragraphs[:]),
		cursor     = app.cursor,
		anchor     = app.anchor,
	}
}

restore_snapshot :: proc(app: ^App, snap: Snapshot) {
	clear(&app.text)
	append(&app.text, ..snap.text)
	clear(&app.styles)
	append(&app.styles, ..snap.styles)
	clear(&app.paragraphs)
	append(&app.paragraphs, ..snap.paragraphs)
	app.cursor = clamp(snap.cursor, 0, len(app.text))
	app.anchor = clamp(snap.anchor, 0, len(app.text))
	sync_active_style(app)
}

free_snapshot :: proc(snap: Snapshot) {
	delete(snap.text)
	delete(snap.styles)
	delete(snap.paragraphs)
}

clear_snapshots :: proc(stack: ^[dynamic]Snapshot) {
	for snap in stack {
		free_snapshot(snap)
	}
	clear(stack)
}

count_words :: proc(app: ^App) -> int {
	n := 0
	in_word := false
	for ch in app.text {
		space := ch == ' ' || ch == '\t' || ch == '\n' || ch == '\r'
		if !space && !in_word {
			n += 1
		}
		in_word = !space
	}
	return n
}

// Set a transient status message and stamp it, so the status bar can fade it.
set_status :: proc(app: ^App, msg: cstring) {
	app.status = msg
	app.status_time = rl.GetTime()
}

// The page the cursor sits on (1-based). In page view this is the layout page;
// otherwise it is a word-based estimate matching the page count.
current_page :: proc(app: ^App) -> int {
	screen_w := f32(rl.GetScreenWidth())
	base_size := f32(30) * app.zoom
	content_w := min(max(screen_w - 112, 240), char_width(app, 'n', Char_Style{}, base_size) * 60)
	_, period := page_metrics(app, base_size)
	if period > 0 {
		return int(math.floor(cursor_document_y(app, content_w, base_size) / period)) + 1
	}
	n := 0
	in_word := false
	for i in 0 ..< app.cursor {
		ch := app.text[i]
		space := ch == ' ' || ch == '\t' || ch == '\n' || ch == '\r'
		if !space && !in_word {
			n += 1
		}
		in_word = !space
	}
	return n / 250 + 1
}

settings_file :: proc() -> string {
	dir: string
	when ODIN_OS == .Windows {
		dir = os.get_env("LOCALAPPDATA", context.temp_allocator)
		if dir == "" {
			dir = os.get_env("APPDATA", context.temp_allocator)
		}
	} else {
		dir = os.get_env("XDG_CONFIG_HOME", context.temp_allocator)
		if dir == "" {
			dir, _ = filepath.join({os.get_env("HOME", context.temp_allocator), ".config"}, context.temp_allocator)
		}
	}
	if dir == "" {
		return ""
	}
	path, _ := filepath.join({dir, "Manuscrito", "settings.txt"}, context.temp_allocator)
	return path
}

save_settings :: proc(app: ^App) {
	path := settings_file()
	if path == "" {
		return
	}
	os.make_directory(filepath.dir(path, context.temp_allocator))
	_ = os.write_entire_file(path, fmt.tprintf("theme=%s\n", THEMES[app.theme_index].name))
}

load_settings :: proc(app: ^App) {
	path := settings_file()
	if path == "" {
		return
	}
	data, err := os.read_entire_file(path, context.temp_allocator)
	if err != nil {
		return
	}
	text := string(data)
	for line in strings.split_lines_iterator(&text) {
		if strings.has_prefix(line, "theme=") {
			set_theme_by_name(app, strings.trim_space(line[6:]))
		}
	}
}

set_theme_by_name :: proc(app: ^App, name: string) {
	for theme, i in THEMES {
		if string(theme.name) == name {
			app.theme_index = i
			return
		}
	}
}

prev_word :: proc(app: ^App, pos: int) -> int {
	i := clamp(pos, 0, len(app.text))
	for i > 0 && !is_word(app.text[i - 1]) {
		i -= 1
	}
	for i > 0 && is_word(app.text[i - 1]) {
		i -= 1
	}
	return i
}

next_word :: proc(app: ^App, pos: int) -> int {
	i := clamp(pos, 0, len(app.text))
	for i < len(app.text) && !is_word(app.text[i]) {
		i += 1
	}
	for i < len(app.text) && is_word(app.text[i]) {
		i += 1
	}
	return i
}

is_word :: proc(ch: rune) -> bool {
	return unicode.is_letter(ch) || unicode.is_digit(ch) || ch == '_'
}

prev_paragraph_column :: proc(app: ^App) -> int {
	p := paragraph_index_at(app, app.cursor)
	if p <= 0 {
		return 0
	}
	col := app.cursor - paragraph_start(app, p)
	prev_start := paragraph_start(app, p - 1)
	prev_end := paragraph_end(app, prev_start)
	return prev_start + min(col, prev_end - prev_start)
}

next_paragraph_column :: proc(app: ^App) -> int {
	p := paragraph_index_at(app, app.cursor)
	if p >= len(app.paragraphs) - 1 {
		return len(app.text)
	}
	col := app.cursor - paragraph_start(app, p)
	next_start := paragraph_start(app, p + 1)
	next_end := paragraph_end(app, next_start)
	return next_start + min(col, next_end - next_start)
}

// Layout facts for paragraph p at the current zoom and width.
para_layout :: proc(app: ^App, p: int, content_w, base_size: f32) -> (start, end: int, font_size, indent: f32, starts: []int) {
	start = paragraph_start(app, p)
	end = paragraph_end(app, start)
	para := app.paragraphs[p]
	font_size = header_size(para.header, base_size)
	indent = font_size * 2.25 if para.first_indent else 0
	starts = paragraph_line_starts(app, start, end, content_w, indent, font_size)
	return
}

// Absolute x of a caret index within one visual line. Forward companion to
// index_in_visual_line, so the same alignment and justify math is used.
visual_x_of_index :: proc(app: ^App, paragraph: Paragraph, start, end: int, left, available, font_size: f32, last_line: bool, target: int) -> f32 {
	line_width := line_advance(app, start, end, font_size)
	x := left
	switch paragraph.align {
	case .Center:
		x += max((available - line_width) * 0.5, 0)
	case .Right:
		x += max(available - line_width, 0)
	case .Left, .Justify:
	case:
	}
	content_end, extra_space := justify_metrics(app, paragraph, start, end, available, line_width, font_size, last_line)
	for i in start ..< end {
		if i >= target {
			break
		}
		adv := char_width(app, app.text[i], app.styles[i], font_size) + 2
		if app.text[i] == ' ' && i < content_end {
			adv += extra_space
		}
		x += adv
	}
	return x
}

// Up/Down move the caret one visual line, holding the horizontal position, across
// wrapped lines and paragraph boundaries.
// ponytail: the goal x is taken from the caret each press, so it drifts toward short
// lines' ends over several moves; add a sticky goal column if that becomes annoying.
move_visual_line :: proc(app: ^App, dir: int, selecting: bool) {
	screen_w := f32(rl.GetScreenWidth())
	base_size := f32(30) * app.zoom
	content_w := min(max(screen_w - 112, 240), char_width(app, 'n', Char_Style{}, base_size) * 60)
	left := (screen_w - content_w) * 0.5

	p := paragraph_index_at(app, app.cursor)
	_, end, font_size, indent, starts := para_layout(app, p, content_w, base_size)
	L := 0
	for k in 0 ..< len(starts) {
		if starts[k] <= app.cursor {
			L = k
		} else {
			break
		}
	}
	ls := starts[L]
	next := starts[L + 1] if L + 1 < len(starts) else end
	line_indent := indent if L == 0 else 0
	last := L + 1 >= len(starts)
	goal_x := visual_x_of_index(app, app.paragraphs[p], ls, next, left + line_indent, content_w - line_indent, font_size, last, app.cursor)

	tp := p
	tend := end
	tfont := font_size
	tindent := indent
	tstarts := starts
	tL := L + dir
	if tL < 0 {
		if p == 0 {
			move_cursor(app, 0, selecting)
			return
		}
		tp = p - 1
		_, tend, tfont, tindent, tstarts = para_layout(app, tp, content_w, base_size)
		tL = len(tstarts) - 1
	} else if tL >= len(starts) {
		if p >= len(app.paragraphs) - 1 {
			move_cursor(app, len(app.text), selecting)
			return
		}
		tp = p + 1
		_, tend, tfont, tindent, tstarts = para_layout(app, tp, content_w, base_size)
		tL = 0
	}
	tls := tstarts[tL]
	tnext := tstarts[tL + 1] if tL + 1 < len(tstarts) else tend
	tline_indent := tindent if tL == 0 else 0
	tlast := tL + 1 >= len(tstarts)
	tlw := line_advance(app, tls, tnext, tfont)
	idx := index_in_visual_line(app, app.paragraphs[tp], tls, tnext, left + tline_indent, content_w - tline_indent, tlw, tfont, tlast, goal_x)
	move_cursor(app, idx, selecting)
}

paragraph_index_at :: proc(app: ^App, pos: int) -> int {
	p := 0
	limit := clamp(pos, 0, len(app.text))
	for i in 0..<limit {
		if app.text[i] == '\n' {
			p += 1
		}
	}
	return min(p, max(len(app.paragraphs) - 1, 0))
}

paragraph_start :: proc(app: ^App, paragraph: int) -> int {
	if paragraph <= 0 {
		return 0
	}
	p := 0
	for ch, i in app.text {
		if ch == '\n' {
			p += 1
			if p == paragraph {
				return i + 1
			}
		}
	}
	return len(app.text)
}

paragraph_end :: proc(app: ^App, start: int) -> int {
	for i := start; i < len(app.text); i += 1 {
		if app.text[i] == '\n' {
			return i
		}
	}
	return len(app.text)
}

selected_paragraphs :: proc(app: ^App) -> (first, last: int) {
	if !has_selection(app) {
		p := paragraph_index_at(app, app.cursor)
		return p, p
	}
	lo, hi := selection_range(app)
	end_pos := hi
	if hi > lo && app.text[hi - 1] == '\n' {
		end_pos -= 1
	}
	return paragraph_index_at(app, lo), paragraph_index_at(app, end_pos)
}

delete_selection :: proc(app: ^App) {
	if !has_selection(app) {
		return
	}
	lo, hi := selection_range(app)
	delete_range(app, lo, hi)
	app.cursor = lo
	app.anchor = lo
	sync_active_style(app)
	app.dirty = true
}

delete_range :: proc(app: ^App, lo, hi: int) {
	for i := hi - 1; i >= lo; i -= 1 {
		if app.text[i] == '\n' {
			p := paragraph_index_at(app, i) + 1
			if p < len(app.paragraphs) {
				ordered_remove(&app.paragraphs, p)
			}
		}
		ordered_remove(&app.text, i)
		ordered_remove(&app.styles, i)
		if i == 0 {
			break
		}
	}
	if len(app.paragraphs) == 0 {
		append(&app.paragraphs, Paragraph{})
	}
}

backspace :: proc(app: ^App) {
	if has_selection(app) {
		delete_selection(app)
		return
	}
	if app.cursor <= 0 {
		return
	}
	delete_range(app, app.cursor - 1, app.cursor)
	app.cursor -= 1
	app.anchor = app.cursor
	sync_active_style(app)
	app.dirty = true
}

forward_delete :: proc(app: ^App) {
	if has_selection(app) {
		delete_selection(app)
		return
	}
	if app.cursor >= len(app.text) {
		return
	}
	delete_range(app, app.cursor, app.cursor + 1)
	app.anchor = app.cursor
	sync_active_style(app)
	app.dirty = true
}

insert_rune :: proc(app: ^App, ch: rune) {
	if has_selection(app) {
		delete_selection(app)
	}
	insert_rune_at(app, app.cursor, ch, app.active_style)
	app.cursor += 1
	app.anchor = app.cursor
	app.dirty = true
}

insert_rune_at :: proc(app: ^App, at: int, ch: rune, style: Char_Style) {
	idx := clamp(at, 0, len(app.text))
	inject_at(&app.text, idx, ch)
	inject_at(&app.styles, idx, style)
	if ch == '\n' {
		p := paragraph_index_at(app, idx) + 1
		base := Paragraph{}
		if p > 0 && p - 1 < len(app.paragraphs) {
			base = app.paragraphs[p - 1]
		}
		inject_at(&app.paragraphs, p, base)
	}
}

toggle_style :: proc(app: ^App, field: Style_Field) {
	if has_selection(app) {
		lo, hi := selection_range(app)
		// If any char lacks the style, apply it to the whole selection; otherwise clear it.
		target := false
		for i in lo..<hi {
			if !get_style_field(app.styles[i], field) {
				target = true
				break
			}
		}
		for i in lo..<hi {
			set_style_field(&app.styles[i], field, target)
		}
		app.dirty = true
		return
	}
	set_style_field(&app.active_style, field, !get_style_field(app.active_style, field))
}

get_style_field :: proc(style: Char_Style, field: Style_Field) -> bool {
	switch field {
	case .Bold:
		return style.bold
	case .Italic:
		return style.italic
	case .Underline:
		return style.underline
	case .Highlight:
		return style.highlight
	case .Strike:
		return style.strike
	}
	return false
}

set_style_field :: proc(style: ^Char_Style, field: Style_Field, value: bool) {
	switch field {
	case .Bold:
		style.bold = value
	case .Italic:
		style.italic = value
	case .Underline:
		style.underline = value
	case .Highlight:
		style.highlight = value
	case .Strike:
		style.strike = value
	}
}

apply_header :: proc(app: ^App, level: int) {
	first, last := selected_paragraphs(app)
	for p in first..=last {
		app.paragraphs[p].header = level
	}
	app.dirty = true
}

apply_align :: proc(app: ^App, align: Align) {
	first, last := selected_paragraphs(app)
	for p in first..=last {
		app.paragraphs[p].align = align
	}
	app.dirty = true
}

apply_first_line_indent :: proc(app: ^App) {
	first, last := selected_paragraphs(app)
	all := true
	for p in first..=last {
		if !app.paragraphs[p].first_indent {
			all = false
			break
		}
	}
	for p in first..=last {
		app.paragraphs[p].first_indent = !all
	}
	app.dirty = true
}

copy_selection :: proc(app: ^App) {
	if !has_selection(app) {
		return
	}
	lo, hi := selection_range(app)
	sb := strings.builder_make()
	defer strings.builder_destroy(&sb)
	for i in lo..<hi {
		_, _ = strings.write_rune(&sb, app.text[i])
	}
	clip, err := strings.to_cstring(&sb)
	if err == nil {
		rl.SetClipboardText(clip)
		set_status(app, "Copied")
	}
}

paste_clipboard :: proc(app: ^App) {
	text := string(rl.GetClipboardText())
	if len(text) == 0 {
		return
	}
	if has_selection(app) {
		delete_selection(app)
	}
	for ch in text {
		if ch == '\r' {
			continue
		}
		insert_rune_at(app, app.cursor, ch, app.active_style)
		app.cursor += 1
	}
	app.anchor = app.cursor
	app.dirty = true
	set_status(app, "Pasted")
}

clear_document :: proc(app: ^App) {
	clear(&app.text)
	clear(&app.styles)
	clear(&app.paragraphs)
	append(&app.paragraphs, Paragraph{})
	app.cursor = 0
	app.anchor = 0
	app.active_style = Char_Style{}
	app.dirty = false
}

// Case-insensitive search from the cursor, wrapping around; selects the match.
find_next :: proc(app: ^App, query: string) {
	q := utf8.string_to_runes(query, context.temp_allocator)
	if len(q) == 0 || len(q) > len(app.text) {
		set_status(app, "Not found")
		return
	}
	for i in 0..<len(q) {
		q[i] = unicode.to_lower(q[i])
	}
	last := len(app.text) - len(q)
	from := clamp(app.cursor, 0, len(app.text))
	for k in 0..=last {
		pos := (from + k) % (last + 1)
		match := true
		for j in 0..<len(q) {
			if unicode.to_lower(app.text[pos + j]) != q[j] {
				match = false
				break
			}
		}
		if match {
			app.anchor = pos
			app.cursor = pos + len(q)
			sync_active_style(app)
			app.last_edit = .Other
			set_status(app, "Found")
			return
		}
	}
	set_status(app, "Not found")
}

set_file_path :: proc(app: ^App, path: string) {
	new_path := strings.clone(path)
	if len(app.file_path) > 0 {
		delete(app.file_path)
	}
	app.file_path = new_path
}

open_document :: proc(app: ^App, path: string) {
	data, err := os.read_entire_file(path, context.allocator)
	if err != nil {
		set_status(app, "Open failed")
		return
	}
	defer delete(data)

	clear_document(app)
	// The old document's undo history must not leak into the new file, or an
	// undo followed by a save would overwrite it with the previous document.
	clear_snapshots(&app.undo)
	clear_snapshots(&app.redo)
	app.last_edit = .Other
	content := string(data)
	if strings.has_prefix(content, MAGIC) {
		parse_manuscrito(app, content)
	} else {
		load_plain_text(app, content)
	}
	set_file_path(app, path)
	app.cursor = len(app.text)
	app.anchor = app.cursor
	sync_active_style(app)
	app.dirty = false
	set_status(app, "Opened")
}

load_plain_text :: proc(app: ^App, content: string) {
	clear(&app.paragraphs)
	append(&app.paragraphs, Paragraph{})
	for ch in content {
		if ch == '\r' {
			continue
		}
		append(&app.text, ch)
		append(&app.styles, Char_Style{})
		if ch == '\n' {
			append(&app.paragraphs, Paragraph{})
		}
	}
}

parse_manuscrito :: proc(app: ^App, content: string) {
	clear(&app.paragraphs)
	seen_paragraph := false
	lines := strings.split_lines(content, context.temp_allocator)
	for line, index in lines {
		if index == 0 || len(line) == 0 {
			continue
		}
		tag := field_at(line, 0)
		if tag == "P" {
			if seen_paragraph {
				append(&app.text, '\n')
				append(&app.styles, Char_Style{})
			}
			append(&app.paragraphs, Paragraph{
				header       = parse_int_or(field_at(line, 1), 0),
				align        = parse_align_or(field_at(line, 2), .Left),
				first_indent = parse_int_or(field_at(line, 3), 0) != 0,
			})
			seen_paragraph = true
		} else if tag == "R" {
			if !seen_paragraph {
				append(&app.paragraphs, Paragraph{})
				seen_paragraph = true
			}
			style := style_from_code(parse_int_or(field_at(line, 1), 0))
			append_unescaped(app, field_at(line, 2), style)
		}
	}
	if len(app.paragraphs) == 0 {
		append(&app.paragraphs, Paragraph{})
	}
}

save_document :: proc(app: ^App, path: string) {
	sb := strings.builder_make()
	defer strings.builder_destroy(&sb)
	serialize_document(app, &sb)
	if os.write_entire_file(path, strings.to_string(sb)) == nil {
		set_file_path(app, path)
		app.dirty = false
		set_status(app, "Saved")
	} else {
		set_status(app, "Save failed")
	}
}

serialize_document :: proc(app: ^App, sb: ^strings.Builder) {
	strings.write_string(sb, MAGIC)
	strings.write_byte(sb, '\n')
	start := 0
	for paragraph, p in app.paragraphs {
		write_paragraph(sb, paragraph)
		end := paragraph_end(app, start)
		i := start
		for i < end {
			style := app.styles[i]
			run_start := i
			for i < end && same_style(app.styles[i], style) {
				i += 1
			}
			write_run(sb, style, app.text[run_start:i])
		}
		start = end + 1
		if p == len(app.paragraphs) - 1 {
			break
		}
	}
}

write_paragraph :: proc(sb: ^strings.Builder, paragraph: Paragraph) {
	strings.write_string(sb, "P\t")
	strings.write_int(sb, paragraph.header)
	strings.write_byte(sb, '\t')
	strings.write_int(sb, int(paragraph.align))
	strings.write_byte(sb, '\t')
	strings.write_int(sb, 1 if paragraph.first_indent else 0)
	strings.write_byte(sb, '\n')
}

write_run :: proc(sb: ^strings.Builder, style: Char_Style, text: []rune) {
	strings.write_string(sb, "R\t")
	strings.write_int(sb, style_code(style))
	strings.write_byte(sb, '\t')
	for ch in text {
		switch ch {
		case '\\':
			strings.write_string(sb, "\\\\")
		case '\t':
			strings.write_string(sb, "\\t")
		case '\n':
			strings.write_string(sb, "\\n")
		case:
			_, _ = strings.write_rune(sb, ch)
		}
	}
	strings.write_byte(sb, '\n')
}

append_unescaped :: proc(app: ^App, text: string, style: Char_Style) {
	for i := 0; i < len(text); /**/ {
		if text[i] == '\\' && i + 1 < len(text) {
			switch text[i + 1] {
			case '\\':
				append(&app.text, '\\')
			case 't':
				append(&app.text, '\t')
			case 'n':
				append(&app.text, '\n')
			case:
				append(&app.text, rune(text[i + 1]))
			}
			append(&app.styles, style)
			i += 2
			continue
		}
		ch, width := utf8.decode_rune_in_string(text[i:])
		append(&app.text, ch)
		append(&app.styles, style)
		i += width
	}
}

field_at :: proc(line: string, wanted: int) -> string {
	start := 0
	field := 0
	for i := 0; i <= len(line); i += 1 {
		if i == len(line) || line[i] == '\t' {
			if field == wanted {
				return line[start:i]
			}
			field += 1
			start = i + 1
		}
	}
	return ""
}

parse_int_or :: proc(text: string, fallback: int) -> int {
	value, ok := strconv.parse_int(text)
	return value if ok else fallback
}

parse_align_or :: proc(text: string, fallback: Align) -> Align {
	value := parse_int_or(text, int(fallback))
	if value < int(Align.Left) || value > int(Align.Justify) {
		return fallback
	}
	return Align(value)
}

same_style :: proc(a, b: Char_Style) -> bool {
	return a.bold == b.bold && a.italic == b.italic && a.underline == b.underline && a.highlight == b.highlight && a.strike == b.strike
}

style_code :: proc(style: Char_Style) -> int {
	code := 0
	if style.bold { code |= 1 }
	if style.italic { code |= 2 }
	if style.underline { code |= 4 }
	if style.highlight { code |= 8 }
	if style.strike { code |= 16 }
	return code
}

style_from_code :: proc(code: int) -> Char_Style {
	return Char_Style{
		bold      = (code & 1) != 0,
		italic    = (code & 2) != 0,
		underline = (code & 4) != 0,
		highlight = (code & 8) != 0,
		strike    = (code & 16) != 0,
	}
}

draw :: proc(app: ^App) {
	theme := THEMES[app.theme_index]
	rl.BeginDrawing()
	defer rl.EndDrawing()

	rl.ClearBackground(theme.background)
	if app.show_splash {
		draw_splash(app, theme)
		return
	}
	draw_document(app, theme)
	if app.palette_open {
		draw_palette(app, theme)
	}
	if app.help_open {
		draw_help(app, theme)
	}
}

draw_splash :: proc(app: ^App, theme: Theme) {
	screen_w := f32(rl.GetScreenWidth())
	screen_h := f32(rl.GetScreenHeight())
	card_w := min(screen_w - 80, 420)
	card_w = max(card_w, min(screen_w - 40, 300))
	image_h := card_w * 1.18
	title_h := f32(78)
	details_h := f32(166)
	card_h := image_h + title_h + details_h
	card_x := (screen_w - card_w) * 0.5
	card_y := (screen_h - card_h) * 0.5
	if card_y < 28 {
		card_y = 28
	}

	image_rect := rl.Rectangle{card_x, card_y, card_w, image_h}
	title_rect := rl.Rectangle{card_x, card_y + image_h, card_w, title_h}
	details_rect := rl.Rectangle{card_x, card_y + image_h + title_h, card_w, details_h}

	rl.DrawRectangle(c.int(card_x + 10), c.int(card_y + 12), c.int(card_w), c.int(card_h), rl.ColorAlpha(rl.BLACK, 0.16))
	rl.DrawRectangleRec(image_rect, rl.Color{238, 234, 224, 255})
	if app.splash_loaded {
		source := cover_source_rect(app.splash, image_rect.width / image_rect.height)
		rl.DrawTexturePro(
			app.splash,
			source,
			image_rect,
			rl.Vector2{0, 0},
			0,
			rl.WHITE,
		)
	} else {
		draw_centered_text(app.fonts.ui, "Missing splash image", image_rect.x, image_rect.y + image_rect.height * 0.45, image_rect.width, 22, theme.muted)
	}
	rl.DrawRectangleLines(c.int(image_rect.x), c.int(image_rect.y), c.int(image_rect.width), c.int(image_rect.height), theme.border)

	title: cstring = "Manuscrito"
	title_size := f32(62)
	title_spacing := f32(1)
	rl.DrawRectangleRec(title_rect, rl.Color{249, 247, 241, 255})
	rl.DrawRectangleLines(c.int(title_rect.x), c.int(title_rect.y), c.int(title_rect.width), c.int(title_rect.height), theme.border)
	draw_centered_text(app.fonts.title, title, title_rect.x, title_rect.y + 5, title_rect.width, title_size, rl.BLACK)

	rl.DrawRectangleRec(details_rect, rl.Color{255, 253, 247, 255})
	rl.DrawRectangleLines(c.int(details_rect.x), c.int(details_rect.y), c.int(details_rect.width), c.int(details_rect.height), theme.border)
	detail_size := f32(20)
	line_y := details_rect.y + 20
	draw_centered_text(app.fonts.ui, "Version " + VERSION, details_rect.x, line_y, details_rect.width, detail_size, rl.BLACK)
	draw_centered_text(app.fonts.ui, "by Jon Tamayo", details_rect.x, line_y + 26, details_rect.width, detail_size, rl.BLACK)
	draw_centered_text(app.fonts.ui, "Copyright 2026", details_rect.x, line_y + 52, details_rect.width, detail_size, rl.BLACK)
	draw_centered_text(app.fonts.ui, "GPL-3.0-only", details_rect.x, line_y + 78, details_rect.width, detail_size, rl.BLACK)
	draw_centered_text(app.fonts.ui, "github.com/vorvek/manuscrito", details_rect.x, line_y + 112, details_rect.width, detail_size, rl.BLACK)
}

cover_source_rect :: proc(texture: rl.Texture2D, dest_ratio: f32) -> rl.Rectangle {
	source_w := f32(texture.width)
	source_h := f32(texture.height)
	source_ratio := source_w / source_h
	if source_ratio > dest_ratio {
		w := source_h * dest_ratio
		return rl.Rectangle{(source_w - w) * 0.5, 0, w, source_h}
	}
	h := source_w / dest_ratio
	return rl.Rectangle{0, (source_h - h) * 0.5, source_w, h}
}

draw_centered_text :: proc(font: rl.Font, text: cstring, x, y, width, size: f32, color: rl.Color) {
	spacing := f32(1)
	measured := rl.MeasureTextEx(font, text, size, spacing)
	rl.DrawTextEx(font, text, rl.Vector2{x + (width - measured.x) * 0.5, y}, size, spacing, color)
}

draw_document :: proc(app: ^App, theme: Theme) {
	screen_w := int(rl.GetScreenWidth())
	screen_h := int(rl.GetScreenHeight())
	top := max(48, screen_h / 9)
	base_size := f32(30) * app.zoom
	max_content_w := max(f32(screen_w - 112), 240)
	content_w := min(max_content_w, char_width(app, 'n', Char_Style{}, base_size) * 60)
	margin_x := int((f32(screen_w) - content_w) * 0.5)
	// The "page": a slightly different shade behind the text, padded on both sides.
	page_pad := f32(44)
	page_x := f32(margin_x) - page_pad
	ensure_cursor_visible(app, content_w, base_size, f32(screen_h - top - 96))
	origin := f32(top) - app.scroll_y
	page_h, period := page_metrics(app, base_size)
	page_count := 0
	if period > 0 {
		// One rectangle per page, separated by bands of background.
		pad := base_size * 1.2
		last_page := int(math.floor(document_bottom(app, content_w, base_size) / period))
		page_count = last_page + 1
		for k in 0..=last_page {
			ry := origin + f32(k) * period - pad
			if ry > f32(screen_h) {
				break
			}
			if ry + page_h + pad * 2 < 0 {
				continue
			}
			rl.DrawRectangle(c.int(max(page_x, 0)), c.int(ry), c.int(content_w + page_pad * 2), c.int(page_h + pad * 2), theme.page)
			num := fmt.ctprintf("%d", k + 1)
			num_w := rl.MeasureTextEx(app.fonts.ui, num, 16, 1)
			rl.DrawTextEx(app.fonts.ui, num, rl.Vector2{page_x + content_w + page_pad * 2 - num_w.x - 14, ry + page_h + pad * 2 - 30}, 16, 1, theme.muted)
		}
	} else {
		rl.DrawRectangle(c.int(max(page_x, 0)), 0, c.int(content_w + page_pad * 2), c.int(screen_h), theme.page)
	}
	y: f32
	start := 0

	if len(app.text) == 0 {
		rl.DrawTextEx(app.fonts.regular, "Start writing. Press F1 for help.", rl.Vector2{f32(margin_x), f32(top)}, base_size, 2, theme.muted)
	}

	for paragraph, p in app.paragraphs {
		end := paragraph_end(app, start)
		y = draw_paragraph(app, theme, paragraph, start, end, f32(margin_x), origin, y, content_w, base_size, page_h, period)
		if origin + y > f32(screen_h - 96) {
			break
		}
		start = end + 1
		if p == len(app.paragraphs) - 1 {
			break
		}
	}

	rl.DrawRectangle(0, c.int(screen_h - 52), c.int(screen_w), 52, rl.ColorAlpha(theme.background, 0.92))
	rl.DrawRectangle(0, c.int(screen_h - 52), c.int(screen_w), 52, rl.ColorAlpha(rl.BLACK, 0.14))
	bar_y := f32(screen_h - 38)

	// Left: file name, with a bullet when there are unsaved changes.
	name: cstring = "New document"
	if len(app.file_path) > 0 {
		name = fmt.ctprintf("%s", filepath.base(app.file_path))
	}
	left_text := fmt.ctprintf("%s •", name) if app.dirty else name
	rl.DrawTextEx(app.fonts.ui, left_text, rl.Vector2{24, bar_y}, 18, 1, theme.foreground)

	// Center: confirm prompt, else a fresh transient message, else the palette hint.
	center: cstring = "Press Ctrl+P to open the Command Palette"
	center_color := theme.muted
	if app.confirm_pending {
		center = app.status
		center_color = theme.foreground
	} else if rl.GetTime() - app.status_time < 2.5 {
		center = app.status
		center_color = theme.foreground
	}
	center_w := rl.MeasureTextEx(app.fonts.ui, center, 18, 1)
	rl.DrawTextEx(app.fonts.ui, center, rl.Vector2{(f32(screen_w) - center_w.x) * 0.5, bar_y}, 18, 1, center_color)

	// Right: current page and totals.
	words := count_words(app)
	pages := page_count if page_count > 0 else (words + 249) / 250
	count_text := fmt.ctprintf("Page %d · %d words / %d pages", current_page(app), words, pages)
	count_w := rl.MeasureTextEx(app.fonts.ui, count_text, 18, 1)
	rl.DrawTextEx(app.fonts.ui, count_text, rl.Vector2{f32(screen_w) - count_w.x - 24, bar_y}, 18, 1, theme.foreground)
}

// Maps a screen point to a text index by replaying the same wrapping as draw_paragraph.
text_index_at_point :: proc(app: ^App, point: rl.Vector2) -> int {
	screen_w := f32(rl.GetScreenWidth())
	screen_h := int(rl.GetScreenHeight())
	top := max(48, screen_h / 9)
	base_size := f32(30) * app.zoom
	content_w := min(max(screen_w - 112, 240), char_width(app, 'n', Char_Style{}, base_size) * 60)
	left := (screen_w - content_w) * 0.5
	py := point.y - (f32(top) - app.scroll_y)
	if py < 0 {
		return 0
	}
	page_h, period := page_metrics(app, base_size)
	y: f32
	start := 0
	for paragraph, p in app.paragraphs {
		end := paragraph_end(app, start)
		font_size := header_size(paragraph.header, base_size)
		line_h := font_size * 1.42
		indent := font_size * 2.25 if paragraph.first_indent else 0
		y = page_snap(y, line_h, page_h, period)
		starts := paragraph_line_starts(app, start, end, content_w, indent, font_size)
		for ls, k in starts {
			next := starts[k + 1] if k + 1 < len(starts) else end
			last := k + 1 >= len(starts)
			line_indent := indent if k == 0 else 0
			available := content_w - line_indent
			lw := line_advance(app, ls, next, font_size)
			// The last visual line owns the gap below it, so it hit-tests taller.
			line_bottom := y + (line_h * 1.25 if last else line_h)
			if py < line_bottom {
				return index_in_visual_line(app, paragraph, ls, next, left + line_indent, available, lw, font_size, last, point.x)
			}
			if last {
				y += line_h * 1.25
				break
			}
			y += line_h
			y = page_snap(y, line_h, page_h, period)
		}
		start = end + 1
		if p == len(app.paragraphs) - 1 {
			break
		}
	}
	return len(app.text)
}

// Walks the glyph advances of one visual line (same alignment and justify math as
// draw_visual_line) and returns the index nearest to the given x.
index_in_visual_line :: proc(app: ^App, paragraph: Paragraph, start, end: int, left, available, line_width, font_size: f32, last_line: bool, px: f32) -> int {
	x := left
	switch paragraph.align {
	case .Center:
		x += max((available - line_width) * 0.5, 0)
	case .Right:
		x += max(available - line_width, 0)
	case .Left, .Justify:
	case:
	}
	content_end, extra_space := justify_metrics(app, paragraph, start, end, available, line_width, font_size, last_line)
	for i in start..<end {
		adv := char_width(app, app.text[i], app.styles[i], font_size) + 2
		if app.text[i] == ' ' && i < content_end {
			adv += extra_space
		}
		if px < x + adv * 0.5 {
			return i
		}
		x += adv
	}
	return end
}

ensure_cursor_visible :: proc(app: ^App, width, base_size, viewport_h: f32) {
	cursor_y := cursor_document_y(app, width, base_size)
	if app.keep_cursor_centered {
		app.scroll_target = max(cursor_y - viewport_h * 0.5, 0)
	} else {
		if cursor_y - app.scroll_target > viewport_h {
			app.scroll_target = cursor_y - viewport_h
		}
		if cursor_y - app.scroll_target < 0 {
			app.scroll_target = cursor_y
		}
		app.scroll_target = max(app.scroll_target, 0)
	}
	// Ease the view toward the target: exponential smoothing, frame-rate
	// independent, snapped once the gap falls under half a pixel.
	app.scroll_y += (app.scroll_target - app.scroll_y) * (1 - math.exp(-12 * rl.GetFrameTime()))
	if abs(app.scroll_target - app.scroll_y) < 0.5 {
		app.scroll_y = app.scroll_target
	}
}

// Page view metrics in document space: a page holds PAGE_LINES regular lines,
// and period is the page height plus the gap to the next one. Zero when off.
page_metrics :: proc(app: ^App, base_size: f32) -> (page_h, period: f32) {
	if !app.show_pages {
		return 0, 0
	}
	page_h = base_size * 1.42 * PAGE_LINES
	period = page_h + base_size * 4
	return
}

// Pushes a line down to the next page start when it would cross a page boundary.
page_snap :: proc(y, line_h, page_h, period: f32) -> f32 {
	if period <= 0 {
		return y
	}
	k := math.floor(y / period)
	if y + line_h > k * period + page_h {
		return (k + 1) * period
	}
	return y
}

cursor_document_y :: proc(app: ^App, width, base_size: f32) -> f32 {
	page_h, period := page_metrics(app, base_size)
	y: f32
	start := 0
	for paragraph, p in app.paragraphs {
		end := paragraph_end(app, start)
		font_size := header_size(paragraph.header, base_size)
		line_h := font_size * 1.42
		indent := font_size * 2.25 if paragraph.first_indent else 0
		y = page_snap(y, line_h, page_h, period)
		if app.cursor <= start {
			return y
		}
		starts := paragraph_line_starts(app, start, end, width, indent, font_size)
		for ls, k in starts {
			next := starts[k + 1] if k + 1 < len(starts) else end
			// Cursor sits on this line when it falls before the next line's start.
			if app.cursor < next {
				break
			}
			if k + 1 < len(starts) {
				y += line_h
				y = page_snap(y, line_h, page_h, period)
			}
		}
		if app.cursor <= end {
			return y
		}
		y += line_h * 1.25
		start = end + 1
		if p == len(app.paragraphs) - 1 {
			break
		}
	}
	return y
}

// Document-space y just below the last visual line; used to count page rectangles.
document_bottom :: proc(app: ^App, width, base_size: f32) -> f32 {
	page_h, period := page_metrics(app, base_size)
	y: f32
	start := 0
	last_line_h := base_size * 1.42
	for paragraph, p in app.paragraphs {
		end := paragraph_end(app, start)
		font_size := header_size(paragraph.header, base_size)
		line_h := font_size * 1.42
		indent := font_size * 2.25 if paragraph.first_indent else 0
		y = page_snap(y, line_h, page_h, period)
		starts := paragraph_line_starts(app, start, end, width, indent, font_size)
		for _, k in starts {
			if k + 1 < len(starts) {
				y += line_h
				y = page_snap(y, line_h, page_h, period)
			}
		}
		last_line_h = line_h
		if p == len(app.paragraphs) - 1 {
			break
		}
		y += line_h * 1.25
		start = end + 1
	}
	return y + last_line_h
}

// Minimum-raggedness line breaking (the Knuth-Plass idea, ragged variant): choose
// the break points that minimize the sum of squared leftover space per line, so the
// right edge is even instead of greedily filled. The last line is free (a short last
// line is fine). Pure numeric core over word widths so it stays exact and testable.
//
// word_start_prefix[k] / word_end_prefix[k] are cumulative advances at the first and
// last char of word k, so the width of words i..j-1 on one line is
// word_end_prefix[j-1] - word_start_prefix[i] (inter-word spaces included, trailing
// space excluded). first_avail applies to the line holding word 0 (first-line indent);
// full_avail to the rest. Returns the word index that begins each line (word 0 first).
min_raggedness_breaks :: proc(word_start_prefix, word_end_prefix: []f32, full_avail, first_avail: f32) -> []int {
	W := len(word_start_prefix)
	if W == 0 {
		return {}
	}
	INF :: 1e30
	best := make([]f64, W + 1, context.temp_allocator)
	prev := make([]int, W + 1, context.temp_allocator)
	for k in 1 ..= W {
		best[k] = INF
	}
	best[0] = 0
	for j in 1 ..= W {
		// Try each line ending at word j-1 and starting at word i, widening as i
		// walks back until the line no longer fits.
		i := j - 1
		for i >= 0 {
			avail := f64(first_avail if i == 0 else full_avail)
			w := f64(word_end_prefix[j - 1] - word_start_prefix[i])
			if w > avail {
				// A single word wider than the line is forced onto its own line;
				// anything longer only gets wider, so stop walking back.
				if j - i == 1 && best[i] < best[j] {
					best[j] = best[i]
					prev[j] = i
				}
				break
			}
			slack := avail - w
			cost := 0.0 if j == W else slack * slack
			if best[i] + cost < best[j] {
				best[j] = best[i] + cost
				prev[j] = i
			}
			i -= 1
		}
	}
	starts := make([dynamic]int, context.temp_allocator)
	for j := W; j > 0; j = prev[j] {
		append(&starts, prev[j])
	}
	slice.reverse(starts[:])
	return starts[:]
}

// Char indices where each visual line of the paragraph begins (first element is
// always `start`), laid out with min_raggedness_breaks. Recomputed per call.
// ponytail: O(words) per call, re-run every frame for every paragraph; cache per
// paragraph keyed on text+width if large documents ever lag.
paragraph_line_starts :: proc(app: ^App, start, end: int, width, indent, font_size: f32) -> []int {
	result := make([dynamic]int, context.temp_allocator)
	append(&result, start)
	if start >= end {
		return result[:]
	}
	// Scan words (maximal non-space runs) and record cumulative advances at each
	// word's first and last char.
	word_first := make([dynamic]int, context.temp_allocator)
	start_prefix := make([dynamic]f32, context.temp_allocator)
	end_prefix := make([dynamic]f32, context.temp_allocator)
	prefix: f32
	in_word := false
	for i in start ..< end {
		if app.text[i] != ' ' && !in_word {
			append(&word_first, i)
			append(&start_prefix, prefix)
			in_word = true
		}
		prefix += char_width(app, app.text[i], app.styles[i], font_size) + 2
		if in_word && (i + 1 >= end || app.text[i + 1] == ' ') {
			append(&end_prefix, prefix)
			in_word = false
		}
	}
	if len(word_first) == 0 {
		return result[:] // paragraph is only spaces: one line
	}
	word_lines := min_raggedness_breaks(start_prefix[:], end_prefix[:], width, width - indent)
	for wi, k in word_lines {
		if k > 0 {
			append(&result, word_first[wi])
		}
	}
	return result[:]
}

// Total advance of the chars in [a, b), trailing space included.
line_advance :: proc(app: ^App, a, b: int, font_size: f32) -> f32 {
	w: f32
	for i in a ..< b {
		w += char_width(app, app.text[i], app.styles[i], font_size) + 2
	}
	return w
}

// Justify stretches the spaces to fill the line, but a wrapped line ends with the
// space that pushed the next word down; that trailing space is trimmed so the last
// word reaches the right margin. Returns the index past the last stretched char and
// the extra width to add to each interior space.
justify_metrics :: proc(app: ^App, paragraph: Paragraph, start, end: int, available, line_width, font_size: f32, last_line: bool) -> (content_end: int, extra_space: f32) {
	content_end = end
	if paragraph.align != .Justify || last_line {
		return end, 0
	}
	for content_end > start && app.text[content_end - 1] == ' ' {
		content_end -= 1
	}
	space_count := 0
	for i in start ..< content_end {
		if app.text[i] == ' ' {
			space_count += 1
		}
	}
	if space_count == 0 {
		return content_end, 0
	}
	trimmed := line_width
	for i in content_end ..< end {
		trimmed -= char_width(app, app.text[i], app.styles[i], font_size) + 2
	}
	return content_end, max(available - trimmed, 0) / f32(space_count)
}

// y is in document space; origin converts to screen coordinates at draw time.
draw_paragraph :: proc(app: ^App, theme: Theme, paragraph: Paragraph, start, end: int, left, origin, y, width, base_size, page_h, period: f32) -> f32 {
	font_size := header_size(paragraph.header, base_size)
	line_h := font_size * 1.42
	indent := font_size * 2.25 if paragraph.first_indent else 0
	yy := page_snap(y, line_h, page_h, period)
	starts := paragraph_line_starts(app, start, end, width, indent, font_size)
	for ls, k in starts {
		next := starts[k + 1] if k + 1 < len(starts) else end
		last := k + 1 >= len(starts)
		line_indent := indent if k == 0 else 0
		available := width - line_indent
		lw := line_advance(app, ls, next, font_size)
		draw_visual_line(app, theme, paragraph, ls, next, left + line_indent, origin + yy, available, lw, font_size, line_h, last)
		if last {
			break
		}
		yy += line_h
		yy = page_snap(yy, line_h, page_h, period)
	}
	return yy + line_h * 1.25
}

draw_visual_line :: proc(app: ^App, theme: Theme, paragraph: Paragraph, start, end: int, left, y, available, line_width, font_size, line_h: f32, last_line: bool) {
	x := left
	switch paragraph.align {
	case .Center:
		x += max((available - line_width) * 0.5, 0)
	case .Right:
		x += max(available - line_width, 0)
	case .Left, .Justify:
	case:
	}

	content_end, extra_space := justify_metrics(app, paragraph, start, end, available, line_width, font_size, last_line)
	lo, hi := selection_range(app)

	// Marker highlight goes under the glyphs and the selection tint. The +1 on the
	// width hides truncation gaps between adjacent rectangles.
	hx := x
	for i in start..<end {
		adv := char_width(app, app.text[i], app.styles[i], font_size) + 2
		if app.text[i] == ' ' && i < content_end {
			adv += extra_space
		}
		if app.styles[i].highlight {
			rl.DrawRectangle(c.int(hx), c.int(y - 2), c.int(adv + 1), c.int(line_h), theme.highlight)
		}
		hx += adv
	}

	// One rectangle over the whole selected span on this line (no per-glyph boxes).
	if has_selection(app) {
		sx := x
		sel_x0, sel_x1: f32 = -1, -1
		for i in start..<end {
			adv := char_width(app, app.text[i], app.styles[i], font_size) + 2
			if app.text[i] == ' ' && i < content_end {
				adv += extra_space
			}
			if i >= lo && i < hi {
				if sel_x0 < 0 {
					sel_x0 = sx
				}
				sel_x1 = sx + adv
			}
			sx += adv
		}
		if sel_x0 >= 0 {
			rl.DrawRectangle(c.int(sel_x0), c.int(y - 2), c.int(sel_x1 - sel_x0), c.int(line_h), theme.selection)
		}
	}

	if app.cursor == start && !app.palette_open {
		draw_cursor(x, y, font_size, theme.accent)
	}

	// Draw glyphs; underline as continuous runs so there are no gaps between letters.
	ul_x0: f32 = -1
	st_x0: f32 = -1
	strike_y := y + font_size * 0.5
	for i in start..<end {
		style := app.styles[i]
		ch := app.text[i]
		w := char_width(app, ch, style, font_size)
		draw_codepoint(app, ch, style, rl.Vector2{x, y}, font_size, theme.foreground)
		if style.underline {
			if ul_x0 < 0 {
				ul_x0 = x
			}
		} else if ul_x0 >= 0 {
			rl.DrawLineEx(rl.Vector2{ul_x0, y + font_size + 4}, rl.Vector2{x, y + font_size + 4}, 1.5, theme.foreground)
			ul_x0 = -1
		}
		if style.strike {
			if st_x0 < 0 {
				st_x0 = x
			}
		} else if st_x0 >= 0 {
			rl.DrawLineEx(rl.Vector2{st_x0, strike_y}, rl.Vector2{x, strike_y}, 1.5, theme.foreground)
			st_x0 = -1
		}
		x += w + 2
		if ch == ' ' && i < content_end {
			x += extra_space
		}
		if app.cursor == i + 1 && !app.palette_open {
			draw_cursor(x, y, font_size, theme.accent)
		}
	}
	if ul_x0 >= 0 {
		rl.DrawLineEx(rl.Vector2{ul_x0, y + font_size + 4}, rl.Vector2{x, y + font_size + 4}, 1.5, theme.foreground)
	}
	if st_x0 >= 0 {
		rl.DrawLineEx(rl.Vector2{st_x0, strike_y}, rl.Vector2{x, strike_y}, 1.5, theme.foreground)
	}
}

draw_cursor :: proc(x, y, size: f32, color: rl.Color) {
	if int(rl.GetTime() * 2) % 2 == 0 {
		rl.DrawRectangle(c.int(x), c.int(y), 2, c.int(size), color)
	}
}

draw_codepoint :: proc(app: ^App, ch: rune, style: Char_Style, position: rl.Vector2, size: f32, color: rl.Color) {
	font, synthetic_bold := font_for_style(app, style)
	rl.DrawTextCodepoint(font, ch, position, size, color)
	if synthetic_bold {
		rl.DrawTextCodepoint(font, ch, rl.Vector2{position.x + 1, position.y}, size, color)
	}
}

char_width :: proc(app: ^App, ch: rune, style: Char_Style, size: f32) -> f32 {
	font, synthetic_bold := font_for_style(app, style)
	glyph := rl.GetGlyphInfo(font, ch)
	advance := f32(glyph.advanceX) * size / f32(font.baseSize)
	if advance <= 0 {
		advance = size * 0.5
	}
	if synthetic_bold {
		advance += 1
	}
	return advance
}

font_for_style :: proc(app: ^App, style: Char_Style) -> (rl.Font, bool) {
	if style.bold && style.italic {
		return app.fonts.bold_italic, !app.fonts.bold_italic_loaded
	}
	if style.bold {
		return app.fonts.bold, !app.fonts.bold_loaded
	}
	if style.italic {
		return app.fonts.italic, false
	}
	return app.fonts.regular, false
}

header_size :: proc(header: int, base: f32) -> f32 {
	switch header {
	case 1:
		return base * 1.7
	case 2:
		return base * 1.45
	case 3:
		return base * 1.25
	case 4:
		return base * 1.12
	case:
		return base
	}
}

draw_palette :: proc(app: ^App, theme: Theme) {
	if app.palette_mode == .Path {
		draw_path_prompt(app, theme)
		return
	}
	screen_w := int(rl.GetScreenWidth())
	screen_h := int(rl.GetScreenHeight())
	entries := palette_entries(app)
	row_h := 36
	visible := min(len(entries), max(6, (screen_h - 240) / row_h))
	visible = max(visible, 1)
	sel := clamp(app.selected_command, 0, max(len(entries) - 1, 0))
	first := clamp(sel - visible / 2, 0, max(len(entries) - visible, 0))
	panel_w := min(620, screen_w - 80)
	panel_h := 100 + visible * row_h
	panel_x := (screen_w - panel_w) / 2
	panel_y := (screen_h - panel_h) / 2
	text_color := readable_foreground(theme)

	rl.DrawRectangle(0, 0, c.int(screen_w), c.int(screen_h), rl.ColorAlpha(theme.background, 0.72))
	rl.DrawRectangle(c.int(panel_x), c.int(panel_y), c.int(panel_w), c.int(panel_h), opaque_panel(theme))
	rl.DrawRectangleLines(c.int(panel_x), c.int(panel_y), c.int(panel_w), c.int(panel_h), theme.border)

	// Text input for filtering.
	input_x := panel_x + 20
	input_y := panel_y + 20
	input_w := panel_w - 40
	input_h := 40
	rl.DrawRectangle(c.int(input_x), c.int(input_y), c.int(input_w), c.int(input_h), rl.ColorAlpha(theme.background, 0.55))
	rl.DrawRectangleLines(c.int(input_x), c.int(input_y), c.int(input_w), c.int(input_h), theme.border)
	if len(app.palette_query) == 0 {
		rl.DrawTextEx(app.fonts.ui, "Type to filter commands...", rl.Vector2{f32(input_x + 12), f32(input_y + 9)}, 21, 1, theme.muted)
	} else {
		rl.DrawTextEx(app.fonts.ui, palette_query_cstring(app), rl.Vector2{f32(input_x + 12), f32(input_y + 9)}, 21, 1, text_color)
	}

	list_y := panel_y + 76
	recent_count := len(app.recent) if len(app.palette_query) == 0 else 0
	for row in 0..<visible {
		i := first + row
		if i >= len(entries) {
			break
		}
		ry := list_y + row * row_h
		if i == sel {
			rl.DrawRectangle(c.int(panel_x + 12), c.int(ry - 6), c.int(panel_w - 24), c.int(row_h - 4), rl.ColorAlpha(theme.accent, 0.18))
		}
		rl.DrawTextEx(app.fonts.ui, palette_label(app, COMMANDS[entries[i]]), rl.Vector2{f32(panel_x + 28), f32(ry)}, 22, 1, text_color)
	}
	// Divider between the recents group and the rest.
	if recent_count > 0 && recent_count < len(entries) && recent_count >= first && recent_count < first + visible {
		dy := f32(list_y + (recent_count - first) * row_h - 8)
		rl.DrawLineEx(rl.Vector2{f32(panel_x + 16), dy}, rl.Vector2{f32(panel_x + panel_w - 16), dy}, 1, theme.border)
	}
}

draw_help :: proc(app: ^App, theme: Theme) {
	screen_w := int(rl.GetScreenWidth())
	screen_h := int(rl.GetScreenHeight())
	row_h := 28
	panel_w := min(640, screen_w - 80)
	panel_h := min(80 + len(HELP_ENTRIES) * row_h, screen_h - 80)
	panel_x := (screen_w - panel_w) / 2
	panel_y := (screen_h - panel_h) / 2
	text_color := readable_foreground(theme)

	rl.DrawRectangle(0, 0, c.int(screen_w), c.int(screen_h), rl.ColorAlpha(theme.background, 0.72))
	rl.DrawRectangle(c.int(panel_x), c.int(panel_y), c.int(panel_w), c.int(panel_h), opaque_panel(theme))
	rl.DrawRectangleLines(c.int(panel_x), c.int(panel_y), c.int(panel_w), c.int(panel_h), theme.border)
	rl.DrawTextEx(app.fonts.ui, "Keyboard Shortcuts", rl.Vector2{f32(panel_x + 24), f32(panel_y + 18)}, 25, 1, text_color)

	keys_x := panel_x + 28
	desc_x := panel_x + 220
	list_y := panel_y + 60
	for entry, i in HELP_ENTRIES {
		ry := list_y + i * row_h
		if ry + row_h > panel_y + panel_h - 10 {
			break
		}
		rl.DrawTextEx(app.fonts.ui, entry.keys, rl.Vector2{f32(keys_x), f32(ry)}, 18, 1, theme.accent)
		rl.DrawTextEx(app.fonts.ui, entry.desc, rl.Vector2{f32(desc_x), f32(ry)}, 18, 1, text_color)
	}
}

// Toggle commands show their current state in the palette.
palette_label :: proc(app: ^App, cmd: Command) -> cstring {
	on: bool
	#partial switch cmd.kind {
	case .Keep_Cursor_Centered:
		on = app.keep_cursor_centered
	case .Page_View:
		on = app.show_pages
	case:
		return cmd.label
	}
	return fmt.ctprintf("%s  [%s]", cmd.label, "on" if on else "off")
}

draw_path_prompt :: proc(app: ^App, theme: Theme) {
	screen_w := int(rl.GetScreenWidth())
	screen_h := int(rl.GetScreenHeight())
	panel_w := min(720, screen_w - 80)
	panel_h := 154
	panel_x := (screen_w - panel_w) / 2
	panel_y := (screen_h - panel_h) / 2
	text_color := readable_foreground(theme)
	title: cstring = "Path"
	if app.path_action == .Save_As {
		title = "Save As..."
	} else if app.path_action == .Open {
		title = "Open..."
	} else if app.path_action == .Find {
		title = "Find (Enter jumps to the next match)"
	}

	sb := strings.builder_make()
	defer strings.builder_destroy(&sb)
	for ch in app.path_input {
		_, _ = strings.write_rune(&sb, ch)
	}
	path_text, _ := strings.to_cstring(&sb)

	rl.DrawRectangle(0, 0, c.int(screen_w), c.int(screen_h), rl.ColorAlpha(theme.background, 0.72))
	rl.DrawRectangle(c.int(panel_x), c.int(panel_y), c.int(panel_w), c.int(panel_h), opaque_panel(theme))
	rl.DrawRectangleLines(c.int(panel_x), c.int(panel_y), c.int(panel_w), c.int(panel_h), theme.border)
	rl.DrawTextEx(app.fonts.ui, title, rl.Vector2{f32(panel_x + 24), f32(panel_y + 20)}, 25, 1, text_color)
	rl.DrawRectangle(c.int(panel_x + 24), c.int(panel_y + 72), c.int(panel_w - 48), 42, rl.ColorAlpha(theme.background, 0.78))
	rl.DrawTextEx(app.fonts.ui, path_text, rl.Vector2{f32(panel_x + 36), f32(panel_y + 82)}, 22, 1, text_color)
}

opaque_panel :: proc(theme: Theme) -> rl.Color {
	return rl.Color{theme.panel[0], theme.panel[1], theme.panel[2], 255}
}

readable_foreground :: proc(theme: Theme) -> rl.Color {
	if theme.background[0] < 80 && theme.background[1] < 80 && theme.background[2] < 80 {
		return rl.Color{245, 248, 252, 255}
	}
	return theme.foreground
}
