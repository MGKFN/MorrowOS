"""
MorrowStore — App Card widget
"""
import gi
gi.require_version("Gtk", "4.0")
gi.require_version("Adw", "1")
from gi.repository import Gtk, Adw, GdkPixbuf, Gio

class AppCard(Gtk.FlowBoxChild):
    def __init__(self, app_data: dict, on_install, installed=False):
        super().__init__()
        self.app_data = app_data
        self.on_install = on_install

        card = Gtk.Box(orientation=Gtk.Orientation.VERTICAL, spacing=8)
        card.add_css_class("card")
        card.set_margin_top(4)
        card.set_margin_bottom(4)
        card.set_margin_start(4)
        card.set_margin_end(4)
        card.set_size_request(200, 220)

        # Icon
        icon = Gtk.Image()
        icon.set_pixel_size(64)
        icon.set_margin_top(16)
        # Try icon theme first, fall back to generic
        icon_name = app_data.get("icon", "application-x-executable")
        icon.set_from_icon_name(icon_name)
        card.append(icon)

        # Name
        name_label = Gtk.Label(label=app_data["name"])
        name_label.add_css_class("title-3")
        name_label.set_wrap(True)
        name_label.set_justify(Gtk.Justification.CENTER)
        card.append(name_label)

        # Description
        desc_label = Gtk.Label(label=app_data.get("description", ""))
        desc_label.add_css_class("caption")
        desc_label.set_wrap(True)
        desc_label.set_justify(Gtk.Justification.CENTER)
        desc_label.set_max_width_chars(28)
        desc_label.set_margin_start(8)
        desc_label.set_margin_end(8)
        card.append(desc_label)

        # Spacer
        spacer = Gtk.Box()
        spacer.set_vexpand(True)
        card.append(spacer)

        # Install button
        self.btn = Gtk.Button(label="Installed" if installed else "Install")
        if installed:
            self.btn.add_css_class("flat")
            self.btn.set_sensitive(False)
        else:
            self.btn.add_css_class("suggested-action")
        self.btn.add_css_class("pill")
        self.btn.set_margin_bottom(12)
        self.btn.set_margin_start(16)
        self.btn.set_margin_end(16)
        self.btn.connect("clicked", self._on_clicked)
        card.append(self.btn)

        self.set_child(card)

    def mark_installed(self):
        self.btn.set_sensitive(False)
        self.btn.remove_css_class("suggested-action")
        self.btn.add_css_class("flat")
        self.btn.set_label("Installed")

    def _on_clicked(self, btn):
        btn.set_sensitive(False)
        btn.set_label("Installing…")
        self.on_install(self.app_data)
