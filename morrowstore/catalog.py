"""
MorrowStore — App catalog loader
Reads from /usr/share/morrowstore/catalog.json (system)
or ~/.config/morrowstore/catalog.json (user override).
Falls back to built-in default catalog.
"""
import json
import os
from pathlib import Path

SYSTEM_CATALOG = Path("/usr/share/morrowstore/catalog.json")
USER_CATALOG   = Path.home() / ".config/morrowstore/catalog.json"

DEFAULT_CATALOG = [
    {
        "name": "Firefox",
        "description": "Fast, private web browser",
        "category": "Internet",
        "icon": "firefox",
        "method": "apt",
        "package": "firefox"
    },
    {
        "name": "VLC",
        "description": "Play any video or audio file",
        "category": "Media",
        "icon": "vlc",
        "method": "apt",
        "package": "vlc"
    },
    {
        "name": "GIMP",
        "description": "Professional image editor",
        "category": "Graphics",
        "icon": "gimp",
        "method": "apt",
        "package": "gimp"
    },
    {
        "name": "LibreOffice",
        "description": "Full office suite",
        "category": "Office",
        "icon": "libreoffice-writer",
        "method": "apt",
        "package": "libreoffice"
    },
    {
        "name": "VS Code",
        "description": "Code editor by Microsoft",
        "category": "Development",
        "icon": "code",
        "method": "flatpak",
        "package": "com.visualstudio.code",
        "remote": "flathub"
    },
    {
        "name": "Spotify",
        "description": "Music streaming",
        "category": "Media",
        "icon": "spotify",
        "method": "flatpak",
        "package": "com.spotify.Client",
        "remote": "flathub"
    },
    {
        "name": "OBS Studio",
        "description": "Screen recording and streaming",
        "category": "Media",
        "icon": "obs",
        "method": "flatpak",
        "package": "com.obsproject.Studio",
        "remote": "flathub"
    },
    {
        "name": "Discord",
        "description": "Voice, video, and text chat",
        "category": "Internet",
        "icon": "discord",
        "method": "flatpak",
        "package": "com.discordapp.Discord",
        "remote": "flathub"
    },
]

def load_catalog() -> list:
    # User catalog overrides system catalog
    for path in [USER_CATALOG, SYSTEM_CATALOG]:
        if path.exists():
            try:
                with open(path) as f:
                    return json.load(f)
            except Exception:
                pass
    return DEFAULT_CATALOG
