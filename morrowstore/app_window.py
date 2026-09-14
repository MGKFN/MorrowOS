"""
MorrowStore - Main Window
"""
import gi
gi.require_version("Gtk", "4.0")
gi.require_version("Adw", "1")
from gi.repository import Gtk, Adw, GLib
from catalog import load_catalog
from installer import Installer
from app_card import AppCard


class MorrowStoreWindow(Adw.ApplicationWindow):
    def __init__(self, **kwargs):
        super().__init__(**kwargs)
        self.set_title("MorrowStore")
        self.set_default_size(1000, 680)

        self.installer = Installer()
        self.catalog = load_catalog()

        # State must exist before any widget callback can fire.
        self.current_category = "All"
        self.flow = None
        self.search_entry = None

        self._cards = {}

        self.toast_overlay = Adw.ToastOverlay()
        self.set_content(self.toast_overlay)

        box = Gtk.Box(orientation=Gtk.Orientation.VERTICAL)
        self.toast_overlay.set_child(box)

        header = Adw.HeaderBar()
        header.add_css_class("flat")
        self.search_entry = Gtk.SearchEntry()
        self.search_entry.set_placeholder_text("Search apps...")
        self.search_entry.set_hexpand(True)
        self.search_entry.connect("search-changed", self.on_search)
        header.set_title_widget(self.search_entry)
        box.append(header)

        content = Gtk.Box(orientation=Gtk.Orientation.HORIZONTAL)
        content.set_vexpand(True)
        box.append(content)

        # Build the grid FIRST — the sidebar's default selection fires a
        # callback that populates it, so it has to exist by then.
        scroll = Gtk.ScrolledWindow()
        scroll.set_hexpand(True)
        scroll.set_vexpand(True)

        self.flow = Gtk.FlowBox()
        self.flow.set_valign(Gtk.Align.START)
        self.flow.set_selection_mode(Gtk.SelectionMode.NONE)
        self.flow.set_max_children_per_line(4)
        self.flow.set_min_children_per_line(2)
        self.flow.set_row_spacing(12)
        self.flow.set_column_spacing(12)
        self.flow.set_margin_top(16)
        self.flow.set_margin_bottom(16)
        self.flow.set_margin_start(16)
        self.flow.set_margin_end(16)
        self.flow.set_homogeneous(True)
        scroll.set_child(self.flow)

        sidebar = self._build_sidebar()
        content.append(sidebar)
        content.append(Gtk.Separator(orientation=Gtk.Orientation.VERTICAL))
        content.append(scroll)

        self._populate_apps()

    def _build_sidebar(self):
        sidebar_scroll = Gtk.ScrolledWindow()
        sidebar_scroll.set_policy(Gtk.PolicyType.NEVER, Gtk.PolicyType.AUTOMATIC)
        sidebar_scroll.set_size_request(180, -1)

        list_box = Gtk.ListBox()
        list_box.set_selection_mode(Gtk.SelectionMode.SINGLE)
        list_box.add_css_class("navigation-sidebar")
        sidebar_scroll.set_child(list_box)

        categories = ["All"] + sorted({a["category"] for a in self.catalog})
        for cat in categories:
            row = Gtk.ListBoxRow()
            label = Gtk.Label(label=cat)
            label.set_halign(Gtk.Align.START)
            label.set_margin_start(12)
            label.set_margin_top(8)
            label.set_margin_bottom(8)
            row.set_child(label)
            row.category = cat
            list_box.append(row)

        # Select before connecting, so construction can't re-enter _populate_apps.
        list_box.select_row(list_box.get_row_at_index(0))
        list_box.connect("row-selected", self.on_category_selected)
        return sidebar_scroll

    def _populate_apps(self, search=""):
        if self.flow is None:
            return
        child = self.flow.get_first_child()
        while child is not None:
            nxt = child.get_next_sibling()
            self.flow.remove(child)
            child = nxt

        self._cards.clear()
        needle = (search or "").lower()
        for app in self.catalog:
            if self.current_category != "All" and app["category"] != self.current_category:
                continue
            if needle and needle not in app["name"].lower() \
                      and needle not in app.get("description", "").lower():
                continue
            card = AppCard(app, on_install=self._on_install_requested,
                            installed=self.installer.is_installed(app))
            self._cards[app["name"]] = card
            self.flow.append(card)

    def on_category_selected(self, listbox, row):
        if row is None:
            return
        self.current_category = row.category
        text = self.search_entry.get_text() if self.search_entry else ""
        self._populate_apps(text)

    def on_search(self, entry):
        self._populate_apps(entry.get_text())

    def _on_install_requested(self, app):
        self.toast_overlay.add_toast(Adw.Toast.new(f"Installing {app['name']}..."))
        self.installer.install_async(app, callback=self._on_install_done)

    def _on_install_done(self, app, success, error_msg=""):
        def notify():
            msg = f"{app['name']} installed" if success else f"Failed: {error_msg[:60]}"
            toast = Adw.Toast.new(msg)
            toast.set_timeout(4)
            self.toast_overlay.add_toast(toast)
            card = self._cards.get(app["name"])
            if card is not None:
                if success:
                    card.mark_installed()
                else:
                    card.btn.set_sensitive(True)
                    card.btn.set_label("Install")
            return False
        GLib.idle_add(notify)
