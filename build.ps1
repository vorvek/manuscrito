$ErrorActionPreference = "Stop"
New-Item -ItemType Directory -Force build | Out-Null
$clang = Get-Command clang -ErrorAction SilentlyContinue
$cl = Get-Command cl -ErrorAction SilentlyContinue
if ($clang) {
	& $clang.Source -c src/vendor/tinyfiledialogs/tinyfiledialogs.c -o build/tinyfiledialogs.obj
} elseif ($cl) {
	& $cl.Source /nologo /c src/vendor/tinyfiledialogs/tinyfiledialogs.c /Fo:build/tinyfiledialogs.obj
} else {
	throw "clang or cl is required to compile tinyfiledialogs.c"
}
odin build src -out:build/manuscrito.exe -subsystem:windows
