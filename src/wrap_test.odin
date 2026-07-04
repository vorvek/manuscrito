// SPDX-License-Identifier: GPL-3.0-only
package main

import "core:strings"
import "core:testing"

// Cost of a given partition (line-start word indices): sum of squared slack over
// every line but the last. Single overlong words are free; any other overflow is
// infeasible (a huge cost so the brute-force search rejects it).
partition_cost :: proc(sp, ep: []f32, avail: f32, starts: []int) -> f64 {
	W := len(sp)
	cost: f64
	for idx in 0 ..< len(starts) {
		b := starts[idx]
		e := (starts[idx + 1] - 1) if idx + 1 < len(starts) else (W - 1)
		w := f64(ep[e] - sp[b])
		if w > f64(avail) {
			if e == b {
				continue // forced single overlong word
			}
			return 1e30 // infeasible
		}
		if idx + 1 < len(starts) {
			slack := f64(avail) - w
			cost += slack * slack
		}
	}
	return cost
}

// Minimum achievable cost over every possible partition, found by brute force.
brute_min_cost :: proc(sp, ep: []f32, avail: f32) -> f64 {
	W := len(sp)
	best: f64 = 1e30
	for mask in 0 ..< (1 << uint(W - 1)) {
		starts := make([dynamic]int, context.temp_allocator)
		append(&starts, 0)
		for m in 0 ..< W - 1 {
			if mask & (1 << uint(m)) != 0 {
				append(&starts, m + 1)
			}
		}
		c := partition_cost(sp, ep, avail, starts[:])
		if c < best {
			best = c
		}
	}
	return best
}

@(test)
test_min_raggedness_is_optimal :: proc(t: ^testing.T) {
	cases := [][]f32{
		{3, 3, 3, 3},
		{9, 1, 5, 5},
		{4, 4, 4, 4, 4},
		{6, 2, 6, 2, 6},
		{2, 8, 2, 8, 2, 2},
		{5, 5, 5, 5, 5, 5, 5},
		{1, 9, 1, 9, 1, 9, 1},
	}
	space: f32 = 1
	avail: f32 = 10
	for widths in cases {
		W := len(widths)
		sp := make([]f32, W)
		ep := make([]f32, W)
		defer delete(sp)
		defer delete(ep)
		p: f32
		for k in 0 ..< W {
			sp[k] = p
			p += widths[k]
			ep[k] = p
			p += space
		}
		got := min_raggedness_breaks(sp, ep, avail, avail)
		dp := partition_cost(sp, ep, avail, got)
		best := brute_min_cost(sp, ep, avail)
		testing.expectf(t, abs(dp - best) < 1e-6, "widths %v: dp cost %.3f, optimal %.3f", widths, dp, best)
	}
}

// The first line is narrower (indent); the break for a narrow first line must not
// overflow it.
@(test)
test_first_line_indent :: proc(t: ^testing.T) {
	// Five words of width 4, single spaces. First line only fits 9px (2 words = 9),
	// the rest fit 14px (would be 3 words otherwise).
	widths := []f32{4, 4, 4, 4, 4}
	W := len(widths)
	sp := make([]f32, W)
	ep := make([]f32, W)
	defer delete(sp)
	defer delete(ep)
	p: f32
	for k in 0 ..< W {
		sp[k] = p
		p += widths[k]
		ep[k] = p
		p += 1
	}
	got := min_raggedness_breaks(sp, ep, 14, 9)
	// First line must hold at most 2 words: its second break starts at word index 2 or less.
	testing.expect(t, len(got) >= 2 && got[1] <= 2, "first line overflowed its indent")
	testing.expect(t, got[0] == 0, "first line must start at word 0")
}

@(test)
test_style_code_roundtrip :: proc(t: ^testing.T) {
	s := Char_Style{bold = true, italic = false, underline = true, highlight = false, strike = true}
	code := style_code(s)
	back := style_from_code(code)
	testing.expect(t, same_style(s, back), "strike bit must round-trip through style_code")
	testing.expect(t, code & 16 != 0, "strike must occupy bit 16")
}

push_run :: proc(app: ^App, text: string, style: Char_Style) {
	for ch in text {
		append(&app.text, ch)
		append(&app.styles, style)
	}
}

@(test)
test_export_markers :: proc(t: ^testing.T) {
	app := App{
		text       = make([dynamic]rune, context.temp_allocator),
		styles     = make([dynamic]Char_Style, context.temp_allocator),
		paragraphs = make([dynamic]Paragraph, context.temp_allocator),
	}
	// Paragraph 0: heading level 1, plain text "Hi".
	append(&app.paragraphs, Paragraph{header = 1})
	push_run(&app, "Hi", Char_Style{})
	append(&app.text, '\n')
	append(&app.styles, Char_Style{})
	// Paragraph 1: bold+italic+strike "X", first-line indent.
	append(&app.paragraphs, Paragraph{first_indent = true})
	push_run(&app, "X", Char_Style{bold = true, italic = true, strike = true})

	html := strings.builder_make(context.temp_allocator)
	export_html(&app, &html)
	h := strings.to_string(html)
	testing.expect(t, strings.contains(h, "<h1>"), "html has h1")
	testing.expect(t, strings.contains(h, "<s>"), "html has strike")
	testing.expect(t, strings.contains(h, "text-indent"), "html has indent")

	md := strings.builder_make(context.temp_allocator)
	export_md(&app, &md)
	m := strings.to_string(md)
	testing.expect(t, strings.contains(m, "# Hi"), "md has heading")
	testing.expect(t, strings.contains(m, "~~"), "md has strike")

	rtf := strings.builder_make(context.temp_allocator)
	export_rtf(&app, &rtf)
	r := strings.to_string(rtf)
	testing.expect(t, strings.contains(r, "\\strike"), "rtf has strike")
	testing.expect(t, strings.contains(r, "\\fi720"), "rtf has indent")

	txt := strings.builder_make(context.temp_allocator)
	export_txt(&app, &txt)
	testing.expect(t, strings.contains(strings.to_string(txt), "Hi"), "txt has text")
}
