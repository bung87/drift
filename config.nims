switch("define", "useGlfw")

when defined(macosx):
  switch("passC", "-Wno-incompatible-function-pointer-types")
