package app.md4a

internal fun previewDocument(body: String): String = """<!doctype html>
<html><head><meta name="viewport" content="width=device-width,initial-scale=1">
<style>
:root { color-scheme: light dark; }
body { box-sizing: border-box; max-width: 52rem; margin: 0 auto; padding: 1rem; font: 16px/1.55 sans-serif; overflow-wrap: anywhere; }
pre { overflow-x: auto; padding: .75rem; background: color-mix(in srgb, CanvasText 8%, Canvas); }
code { font-family: monospace; } img { max-width: 100%; } table { border-collapse: collapse; }
th, td { border: 1px solid color-mix(in srgb, CanvasText 30%, Canvas); padding: .4rem; }
</style></head><body>$body</body></html>"""
