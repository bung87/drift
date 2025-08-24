import os

version       = "0.1"
author        = "DriftTeam"
description   = "Drift - Lightweight IDE / text editor"
license       = "MIT"
srcDir        = "src"
bin           = @["drift"]

requires "nim >= 2.0.2"
requires "results"
requires "naylib"
requires "https://github.com/bung87/lsp_client >= 0.5.0"
requires "chronos"
requires "chroma >= 0.2.7"
requires "https://github.com/ferus-web/stylus"
requires "pixie >= 5.0.0"
requires "winim"
requires "darwin"