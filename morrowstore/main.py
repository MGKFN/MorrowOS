#!/usr/bin/env python3
"""
MorrowStore — MorrowOS App Manager
Entry point
"""
import sys
import gi
gi.require_version("Gtk", "4.0")
gi.require_version("Adw", "1")
from gi.repository import Gtk, Adw, GLib
from app_window import MorrowStoreWindow

class MorrowStoreApp(Adw.Application):
    def __init__(self):
        super().__init__(application_id="os.morrow.store")
        self.connect("activate", self.on_activate)

    def on_activate(self, app):
        win = MorrowStoreWindow(application=app)
        win.present()

def main():
    app = MorrowStoreApp()
    return app.run(sys.argv)

if __name__ == "__main__":
    sys.exit(main())
