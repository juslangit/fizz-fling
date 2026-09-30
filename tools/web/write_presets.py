"""Writes export_presets.cfg, with tools/web/head.html as the page's head_include."""
import os, re
root = os.path.join(os.path.dirname(__file__), "..", "..")
head = open(os.path.join(os.path.dirname(__file__), "head.html")).read()
head = re.sub(r"<!--.*?-->", "", head, flags=re.S).strip()
head = head.replace("\\", "\\\\").replace('"', '\\"')
cfg = f'''[preset.0]

name="Web"
platform="Web"
runnable=true
advanced_options=false
dedicated_server=false
custom_features=""
export_filter="all_resources"
include_filter=""
exclude_filter="docs/*, tools/*, art/*, build/*"
export_path="build/web/index.html"
patches=PackedStringArray()
encryption_include_filters=""
encryption_exclude_filters=""
seed=0
encrypt_pck=false
encrypt_directory=false
script_export_mode=2

[preset.0.options]

custom_template/debug=""
custom_template/release=""
variant/extensions_support=false
variant/thread_support=false
vram_texture_compression/for_desktop=true
vram_texture_compression/for_mobile=true
html/export_icon=true
html/custom_html_shell=""
html/head_include="{head}"
html/canvas_resize_policy=2
html/focus_canvas_on_start=true
html/experimental_virtual_keyboard=false
progressive_web_app/enabled=false
'''
open(os.path.join(root, "export_presets.cfg"), "w").write(cfg)
