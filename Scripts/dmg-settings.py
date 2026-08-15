# dmgbuild settings for the OriginCheck installer DMG.
# dmgbuild writes the window layout directly into the image's .DS_Store,
# so it does not depend on Finder automation.
import os

app = os.environ.get("APP_PATH", "build/OriginCheck.app")
bg = os.environ.get("DMG_BG", "assets/dmg-background@2x.png")

# --- Image ---
format = "UDZO"
volume_name = "OriginCheck"

# --- Contents ---
files = [app]
symlinks = {"Applications": "/Applications"}

# --- Window / view ---
if os.path.exists(bg):
    background = bg
default_view = "icon-view"
show_status_bar = False
show_tab_view = False
show_toolbar = False
show_pathbar = False
show_sidebar = False
window_rect = ((200, 120), (660, 460))
icon_size = 128
text_size = 13
icon_locations = {
    "OriginCheck.app": (170, 250),
    "Applications": (490, 250),
}
