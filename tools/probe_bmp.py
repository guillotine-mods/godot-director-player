from pathlib import Path
from PIL import Image
import json

root = Path(r"E:\development\piposh_2_godot\assets\render_model\strtgame")
mem = json.loads((root / "members.json").read_text(encoding="utf-8"))["members"]
m = mem.get("1:307") or mem["307"]
print("member", m["width"], m["height"], m.get("reg_offset_x"), m.get("reg_offset_y"))
img = Image.open(root / "bitmaps" / "cast_0307.bmp")
print("bmp", img.size, img.mode)
# DAY1 channel 30
droot = Path(r"E:\development\piposh_2_godot\assets\render_model\DAY1")
frames = json.loads((droot / "frames.json").read_text(encoding="utf-8"))
members = json.loads((droot / "members.json").read_text(encoding="utf-8"))["members"]
fr = frames["frames"][39]
for s in fr["sprites"]:
    if s.get("channel") in (1, 30) or (s.get("has_image") and s.get("width", 0) > 500):
        key = f"{s['cast_lib']}:{s['cast_id']}"
        mm = members.get(key) or members.get(str(s["cast_id"]))
        print(
            "ch",
            s["channel"],
            "ink",
            s["ink"],
            "spr",
            s["width"],
            s["height"],
            "loc",
            s.get("loc_h"),
            s.get("loc_v"),
            "mem",
            None if not mm else (mm.get("width"), mm.get("height"), mm.get("path")),
        )
