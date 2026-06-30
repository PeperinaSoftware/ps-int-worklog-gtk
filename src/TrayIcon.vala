/*
 * TrayIcon.vala - top-bar "white clock" indicator via the StatusNotifierItem
 * spec (no GTK3 AppIndicator dependency).
 *
 * Implemented with Vala's typed [DBus] object export. We expose
 * org.kde.StatusNotifierItem + a minimal com.canonical.dbusmenu, then register
 * with org.kde.StatusNotifierWatcher (provided on GNOME/Ubuntu by the bundled
 * AppIndicators extension). Left-click -> Activate -> show the clock window;
 * right-click -> menu whose last item is "Salir".
 *
 * If no watcher is present the registration just fails; the app keeps working
 * through its windows.
 */

namespace Worklog {

    // ---- org.kde.StatusNotifierItem ----
    [DBus(name = "org.kde.StatusNotifierItem")]
    public class SniItem : Object {
        public unowned TrayIcon owner;

        public string category { owned get { return "ApplicationStatus"; } }
        public string id { owned get { return "io.github.peperina.WorklogCalendar"; } }
        public string title { owned get { return "Worklog Calendar"; } }
        public string status { owned get { return "Active"; } }
        public string icon_name { owned get { return "io.github.peperina.WorklogCalendar-symbolic"; } }
        public string icon_theme_path { owned get { return ""; } }
        public bool item_is_menu { get { return false; } }
        public ObjectPath menu { owned get { return new ObjectPath("/MenuBar"); } }

        public signal void new_title();
        public signal void new_icon();
        public signal void new_status(string status);

        public void context_menu(int x, int y) throws Error { }
        public void activate(int x, int y) throws Error { owner.fire_activate(); }
        public void secondary_activate(int x, int y) throws Error { owner.fire_show_clock(); }
        public void scroll(int delta, string orientation) throws Error { }
    }

    // ---- com.canonical.dbusmenu ----
    [DBus(name = "com.canonical.dbusmenu")]
    public class DbusMenu : Object {
        public unowned TrayIcon owner;

        public uint version { get { return 3; } }
        public string status { owned get { return "normal"; } }
        public string text_direction { owned get { return "ltr"; } }

        public signal void layout_updated(uint revision, int parent);
        public signal void items_properties_updated(
            [DBus(signature = "a(ia{sv})")] Variant updated,
            [DBus(signature = "a(ias)")] Variant removed);

        public void get_layout(int parent_id, int recursion_depth, string[] property_names,
                               out uint revision,
                               [DBus(signature = "(ia{sv}av)")] out Variant layout) throws Error {
            revision = 1;
            layout = owner.layout_root();
        }

        public void get_group_properties(int[] ids, string[] property_names,
                                          [DBus(signature = "a(ia{sv})")] out Variant properties) throws Error {
            properties = owner.group_properties();
        }

        [DBus(name = "GetProperty")]
        public Variant get_item_property(int id, string name) throws Error {
            return owner.prop_value(id, name);
        }

        public void event(int id, string event_id, Variant data, uint timestamp) throws Error {
            if (event_id == "clicked") owner.menu_clicked(id);
        }

        public bool about_to_show(int id) throws Error { return false; }
    }

    public class TrayIcon : Object {
        public const int ID_CLOCK = 1;
        public const int ID_APP = 2;
        public const int ID_SEP = 3;
        public const int ID_QUIT = 4;

        public signal void activate();     // left click
        public signal void show_clock();
        public signal void open_app();
        public signal void quit();

        private DBusConnection? conn = null;
        private string bus_name;
        private SniItem sni;
        private DbusMenu dmenu;

        public TrayIcon() {
            bus_name = "org.kde.StatusNotifierItem-%u-1".printf(Random.next_int());
            sni = new SniItem();
            sni.owner = this;
            dmenu = new DbusMenu();
            dmenu.owner = this;
        }

        // Called from the D-Bus service objects.
        public void fire_activate() { activate(); }
        public void fire_show_clock() { show_clock(); }

        public void menu_clicked(int id) {
            switch (id) {
                case ID_CLOCK: show_clock(); break;
                case ID_APP: open_app(); break;
                case ID_QUIT: quit(); break;
            }
        }

        public void register() {
            Bus.own_name(BusType.SESSION, bus_name, BusNameOwnerFlags.NONE,
                on_bus_acquired, on_name_acquired, on_name_lost);
        }

        private void on_bus_acquired(DBusConnection c, string name) {
            conn = c;
            try {
                c.register_object("/StatusNotifierItem", sni);
                c.register_object("/MenuBar", dmenu);
            } catch (Error e) {
                warning("SNI register_object failed: %s", e.message);
            }
        }

        private void on_name_acquired(DBusConnection c, string name) {
            register_with_watcher.begin();
        }
        private void on_name_lost(DBusConnection? c, string name) { }

        private async void register_with_watcher() {
            if (conn == null) return;
            try {
                yield conn.call("org.kde.StatusNotifierWatcher",
                    "/StatusNotifierWatcher",
                    "org.kde.StatusNotifierWatcher",
                    "RegisterStatusNotifierItem",
                    new Variant("(s)", bus_name),
                    null, DBusCallFlags.NONE, -1, null);
            } catch (Error e) {
                message("No StatusNotifierWatcher available: %s", e.message);
            }
        }

        // ---- menu model builders ----
        private string label_for(int id) {
            switch (id) {
                case ID_CLOCK: return "Mostrar reloj";
                case ID_APP: return "Abrir aplicación";
                case ID_QUIT: return "Salir";
                default: return "";
            }
        }

        private Variant props_for(int id) {
            var b = new VariantBuilder(new VariantType("a{sv}"));
            if (id == 0) {
                b.add("{sv}", "children-display", new Variant.string("submenu"));
            } else if (id == ID_SEP) {
                b.add("{sv}", "type", new Variant.string("separator"));
            } else {
                b.add("{sv}", "label", new Variant.string(label_for(id)));
                b.add("{sv}", "enabled", new Variant.boolean(true));
                b.add("{sv}", "visible", new Variant.boolean(true));
            }
            return b.end();
        }

        private Variant item_node(int id) {
            var children = new VariantBuilder(new VariantType("av"));
            var b = new VariantBuilder(new VariantType("(ia{sv}av)"));
            b.add_value(new Variant.int32(id));
            b.add_value(props_for(id));
            b.add_value(children.end());
            return b.end();
        }

        public Variant layout_root() {
            var children = new VariantBuilder(new VariantType("av"));
            int[] ids = { ID_CLOCK, ID_APP, ID_SEP, ID_QUIT };
            foreach (int id in ids) children.add_value(new Variant.variant(item_node(id)));
            var b = new VariantBuilder(new VariantType("(ia{sv}av)"));
            b.add_value(new Variant.int32(0));
            b.add_value(props_for(0));
            b.add_value(children.end());
            return b.end();
        }

        public Variant group_properties() {
            var outer = new VariantBuilder(new VariantType("a(ia{sv})"));
            int[] all = { 0, ID_CLOCK, ID_APP, ID_SEP, ID_QUIT };
            foreach (int id in all) {
                var e = new VariantBuilder(new VariantType("(ia{sv})"));
                e.add_value(new Variant.int32(id));
                e.add_value(props_for(id));
                outer.add_value(e.end());
            }
            return outer.end();
        }

        public Variant prop_value(int id, string name) {
            if (name == "label") return new Variant.string(label_for(id));
            if (name == "enabled" || name == "visible") return new Variant.boolean(true);
            if (name == "type" && id == ID_SEP) return new Variant.string("separator");
            return new Variant.string("");
        }
    }
}
