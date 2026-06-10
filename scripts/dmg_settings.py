# dmgbuild settings for the Voice installer (design: voice.pen "DMG Installer").
# Usage: dmgbuild -s scripts/dmg_settings.py "Voice" Voice.dmg
import os.path

# make_dmg.sh runs dmgbuild from the repository root
ROOT = os.getcwd()

format = "UDZO"
volume_name = "Voice"
files = [os.path.join(ROOT, "Voice.app")]
symlinks = {"Applications": "/Applications"}

badge_icon = os.path.join(ROOT, "app", "AppIcon.icns")
background = os.path.join(ROOT, "build", "dmg-bg.png")

window_rect = ((200, 160), (680, 460))
default_view = "icon-view"
show_status_bar = False
show_tab_view = False
show_toolbar = False
show_pathbar = False
show_sidebar = False

icon_size = 128
text_size = 13
icon_locations = {
    "Voice.app": (181, 258),
    "Applications": (465, 258),
}
