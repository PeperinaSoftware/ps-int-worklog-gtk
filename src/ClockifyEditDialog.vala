/*
 * ClockifyEditDialog.vala - create / edit / delete a Clockify time entry.
 *
 * Fields: time range, project (dropdown), tags (multi toggle), billable, and
 * a description. Edit mode adds a Delete button.
 */

namespace Worklog {

    public class ClockifyEditDialog : Adw.Window {
        private ClockifyStore store;
        private Config cfg;
        private bool is_edit = false;
        private ClockifyEntry? editing = null;
        private int64 start_ms = 0;
        private int64 end_ms = 0;

        private Gtk.Entry start_entry;
        private Gtk.Entry end_entry;
        private Gtk.DropDown project_drop;
        private Gtk.FlowBox tags_box;
        private Gtk.CheckButton billable_check;
        private Gtk.Entry desc_entry;
        private Gtk.Label status;
        private Gtk.Button save_btn;
        private Gtk.Button delete_btn;
        private Gee.ArrayList<Gtk.ToggleButton> tag_toggles = new Gee.ArrayList<Gtk.ToggleButton>();
        private string[] project_ids = {};

        public signal void saved();

        public ClockifyEditDialog(Gtk.Window parent, ClockifyStore store, Config cfg) {
            Object(transient_for: parent, modal: true, title: "Entrada de Clockify");
            this.store = store;
            this.cfg = cfg;
            set_default_size(560, 480);
            build();
        }

        private void build() {
            var toolbar = new Adw.ToolbarView();
            toolbar.add_top_bar(new Adw.HeaderBar());
            var content = new Gtk.Box(Gtk.Orientation.VERTICAL, 10);
            content.set_margin_start(16); content.set_margin_end(16);
            content.set_margin_top(12); content.set_margin_bottom(12);

            var timerow = new Gtk.Box(Gtk.Orientation.HORIZONTAL, 8);
            timerow.append(new Gtk.Label("Inicio"));
            start_entry = new Gtk.Entry(); start_entry.set_width_chars(6); start_entry.set_max_width_chars(6);
            timerow.append(start_entry);
            timerow.append(new Gtk.Label("Fin"));
            end_entry = new Gtk.Entry(); end_entry.set_width_chars(6); end_entry.set_max_width_chars(6);
            timerow.append(end_entry);
            content.append(timerow);

            content.append(label("Descripción"));
            desc_entry = new Gtk.Entry();
            desc_entry.set_placeholder_text("Qué hiciste…");
            content.append(desc_entry);

            content.append(label("Proyecto"));
            project_drop = new Gtk.DropDown(null, null);
            content.append(project_drop);

            content.append(label("Tags"));
            var tags_scroll = new Gtk.ScrolledWindow();
            tags_scroll.set_min_content_height(60);
            tags_scroll.set_policy(Gtk.PolicyType.NEVER, Gtk.PolicyType.AUTOMATIC);
            tags_box = new Gtk.FlowBox();
            tags_box.set_selection_mode(Gtk.SelectionMode.NONE);
            tags_box.set_max_children_per_line(6);
            tags_scroll.set_child(tags_box);
            content.append(tags_scroll);

            billable_check = new Gtk.CheckButton.with_label("Facturable");
            content.append(billable_check);

            status = new Gtk.Label("");
            status.set_halign(Gtk.Align.START);
            content.append(status);

            var btnrow = new Gtk.Box(Gtk.Orientation.HORIZONTAL, 8);
            delete_btn = new Gtk.Button.with_label("Borrar");
            delete_btn.add_css_class("destructive-action");
            delete_btn.clicked.connect(on_delete);
            btnrow.append(delete_btn);
            var spacer = new Gtk.Box(Gtk.Orientation.HORIZONTAL, 0); spacer.hexpand = true;
            btnrow.append(spacer);
            var cancel = new Gtk.Button.with_label("Cancelar");
            cancel.clicked.connect(() => close());
            btnrow.append(cancel);
            save_btn = new Gtk.Button.with_label("Guardar");
            save_btn.add_css_class("suggested-action");
            save_btn.clicked.connect(on_save);
            btnrow.append(save_btn);
            content.append(btnrow);

            toolbar.set_content(content);
            set_content(toolbar);
        }

        private Gtk.Label label(string t) {
            var l = new Gtk.Label(t); l.set_halign(Gtk.Align.START); l.add_css_class("dim-label");
            return l;
        }

        private void populate_projects(string selected_id) {
            var model = new Gtk.StringList(null);
            var ids = new Gee.ArrayList<string>();
            model.append("(sin proyecto)"); ids.add("");
            int sel = 0, i = 1;
            foreach (var p in store.projects) {
                model.append(p.name); ids.add(p.id);
                if (p.id == selected_id) sel = i;
                i++;
            }
            project_ids = ids.to_array();
            project_drop.set_model(model);
            project_drop.set_selected(sel);
        }

        private void populate_tags(string[] selected) {
            tag_toggles.clear();
            Gtk.Widget? c = tags_box.get_first_child();
            while (c != null) { var n = c.get_next_sibling(); tags_box.remove(c); c = n; }
            foreach (var t in store.tags) {
                var tb = new Gtk.ToggleButton.with_label(t.name);
                tb.set_data<string>("id", t.id);
                foreach (var s in selected) if (s == t.id) tb.active = true;
                tag_toggles.add(tb);
                tags_box.append(tb);
            }
        }

        public void open_create(int64 s, int64 e) {
            is_edit = false; editing = null;
            start_ms = s; end_ms = e;
            start_entry.text = Util.fmt_clock(s);
            end_entry.text = Util.fmt_clock(e);
            desc_entry.text = "";
            status.label = "";
            billable_check.active = cfg.clockify_billable_default;
            delete_btn.visible = false;
            ensure_then(() => {
                populate_projects(cfg.clockify_default_project_id);
                populate_tags({});
            });
            present();
        }

        public void open_edit(ClockifyEntry entry) {
            is_edit = true; editing = entry;
            start_ms = entry.started; end_ms = entry.started + (int64) entry.duration_sec * 1000;
            start_entry.text = Util.fmt_clock(start_ms);
            end_entry.text = Util.fmt_clock(end_ms);
            desc_entry.text = entry.description;
            status.label = "";
            billable_check.active = entry.billable;
            delete_btn.visible = true;
            ensure_then(() => {
                populate_projects(entry.project_id);
                populate_tags(entry.tag_ids);
            });
            present();
        }

        // Make sure projects/tags are loaded before populating the widgets.
        private void ensure_then(owned VoidFunc cb) {
            if (store.projects.size > 0) { cb(); return; }
            status.label = "Cargando proyectos…";
            store.ensure_context.begin((o, r) => {
                store.ensure_context.end(r);
                status.label = "";
                cb();
            });
        }
        public delegate void VoidFunc();

        private bool parse_hhmm(string t, out int hh, out int mm) {
            hh = 0; mm = 0;
            var parts = t.strip().split(":");
            if (parts.length != 2) return false;
            hh = int.parse(parts[0]); mm = int.parse(parts[1]);
            return hh >= 0 && hh <= 23 && mm >= 0 && mm <= 59;
        }
        private bool apply_time(string text, bool is_start) {
            int hh, mm;
            if (!parse_hhmm(text, out hh, out mm)) return false;
            var d = new DateTime.from_unix_local((is_start ? start_ms : end_ms) / 1000);
            var nd = new DateTime.local(d.get_year(), d.get_month(), d.get_day_of_month(), hh, mm, 0);
            if (is_start) start_ms = nd.to_unix() * 1000; else end_ms = nd.to_unix() * 1000;
            return true;
        }

        private string[] selected_tag_ids() {
            var ids = new Gee.ArrayList<string>();
            foreach (var tb in tag_toggles) if (tb.active) ids.add(tb.get_data<string>("id"));
            return ids.to_array();
        }
        private string selected_project_id() {
            uint sel = project_drop.get_selected();
            if (sel < project_ids.length) return project_ids[sel];
            return "";
        }

        private void on_save() {
            if (!apply_time(start_entry.text, true) || !apply_time(end_entry.text, false)) {
                set_status("Hora inválida (HH:MM).", true); return;
            }
            if (end_ms <= start_ms) { set_status("El fin debe ser posterior al inicio.", true); return; }
            save_btn.sensitive = false;
            set_status("Guardando…", false);
            string desc = desc_entry.text;
            string pid = selected_project_id();
            string[] tids = selected_tag_ids();
            bool bill = billable_check.active;
            if (is_edit) {
                store.update_entry.begin(editing.id, start_ms, end_ms, desc, pid, tids, bill, (o, r) => {
                    finish(store.update_entry.end(r));
                });
            } else {
                store.create_entry.begin(start_ms, end_ms, desc, pid, tids, bill, (o, r) => {
                    finish(store.create_entry.end(r));
                });
            }
        }

        private void on_delete() {
            if (editing == null) return;
            delete_btn.sensitive = false;
            set_status("Borrando…", false);
            store.delete_entry.begin(editing.id, (o, r) => finish(store.delete_entry.end(r)));
        }

        private void finish(OpResult res) {
            save_btn.sensitive = true;
            delete_btn.sensitive = true;
            if (res.ok) { saved(); close(); }
            else set_status(res.err, true);
        }

        private void set_status(string msg, bool error) {
            status.label = msg;
            if (error) status.add_css_class("error"); else status.remove_css_class("error");
        }
    }
}
