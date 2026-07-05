package main

import "core:c"
import "core:strings"

when ODIN_OS == .Windows {
	foreign import tinyfd_lib {
		"../build/tinyfiledialogs.obj",
		"system:User32.lib",
		"system:Shell32.lib",
		"system:Comdlg32.lib",
		"system:Ole32.lib",
	}
} else {
	foreign import tinyfd_lib "../build/tinyfiledialogs.o"
}

@(default_calling_convention="c", link_prefix="tinyfd_")
foreign tinyfd_lib {
	openFileDialog :: proc(
		title: cstring,
		default_path: cstring,
		filter_count: c.int,
		filter_patterns: [^]cstring,
		filter_description: cstring,
		allow_multiple: c.int,
	) -> cstring ---
	saveFileDialog :: proc(
		title: cstring,
		default_path: cstring,
		filter_count: c.int,
		filter_patterns: [^]cstring,
		filter_description: cstring,
	) -> cstring ---
}

native_open_path :: proc() -> (path: string, ok: bool) {
	patterns := [?]cstring{"*.manuscrito", "*.txt", "*.md"}
	return clone_dialog_path(openFileDialog("Open", nil, len(patterns), raw_data(patterns[:]), "Documents", 0))
}

native_save_path :: proc() -> (path: string, ok: bool) {
	patterns := [?]cstring{"*.manuscrito"}
	return clone_dialog_path(saveFileDialog("Save As", "document.manuscrito", len(patterns), raw_data(patterns[:]), "Manuscrito documents"))
}

native_export_path :: proc(format: Export_Format) -> (path: string, ok: bool) {
	patterns := [?]cstring{export_filter_pattern(format)}
	return clone_dialog_path(saveFileDialog(export_title(format), export_default_path(format), len(patterns), raw_data(patterns[:]), export_filter_description(format)))
}

clone_dialog_path :: proc(path: cstring) -> (string, bool) {
	if path == nil {
		return "", false
	}
	return strings.clone_from_cstring(path), true
}

export_default_path :: proc(format: Export_Format) -> cstring {
	switch format {
	case .Txt:  return "document.txt"
	case .Rtf:  return "document.rtf"
	case .Doc:  return "document.doc"
	case .Md:   return "document.md"
	case .Html: return "document.html"
	}
	return "document.txt"
}

export_filter_pattern :: proc(format: Export_Format) -> cstring {
	switch format {
	case .Txt:  return "*.txt"
	case .Rtf:  return "*.rtf"
	case .Doc:  return "*.doc"
	case .Md:   return "*.md"
	case .Html: return "*.html"
	}
	return "*.txt"
}

export_filter_description :: proc(format: Export_Format) -> cstring {
	switch format {
	case .Txt:  return "Text files"
	case .Rtf:  return "RTF files"
	case .Doc:  return "DOC files"
	case .Md:   return "Markdown files"
	case .Html: return "HTML files"
	}
	return "Text files"
}
