$ErrorActionPreference = "Stop"
New-Item -ItemType Directory -Force build | Out-Null
odin build src -out:build/manuscrito.exe
