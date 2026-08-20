/*
 * JiraEditDialog.vala - create / edit / delete a Jira worklog.
 *
 * Create: pick an issue from the configurable JQL picker, set the time range
 * and an optional comment. Edit: time + comment editable, issue locked, Delete
 * available.
 */

namespace Worklog {

    public class JiraEditDialog : Adw.Window {
        private JiraStore jira1;
        private JiraStore jira2;
        private Config cfg;
        private JiraStore store;   // the active instance
        private bool is_edit = false;
        private Worklog? editing = null;
        private int64 day_ms = 0;
        private int64 start_ms = 0;
        private int64 end_ms = 0;
        private string selected_key = "";

        private Gtk.Entry start_entry;
        private Gtk.Entry end_entry;
        private Gtk.SearchEntry picker_search;
        private Gtk.ListBox picker_list;
        private Gtk.Label picker_selected;
        private Gtk.TextView comment_view;
        private Gtk.Label status;
        private Gtk.Button save_btn;
        private Gtk.Button delete_btn;
        private Gtk.Box picker_box;
        private Gtk.Box instance_box;
        private Gtk.ToggleButton inst1_btn;
        private Gtk.ToggleButton inst2_btn;

        public signal void saved();

        public JiraEditDialog(Gtk.Window parent, JiraStore jira1, JiraStore jira2, Config cfg) {
            Object(transient_for: parent, modal: true, title: "Worklog de Jira");
            this.jira1 = jira1;
            this.jira2 = jira2;
            this.cfg = cfg;
            this.store = jira1;
            set_default_size(640, 560);
            build();
        }

        private void build() {
            var toolbar = new Adw.ToolbarView();
            var header = new Adw.HeaderBar();
            toolbar.add_top_bar(header);

            var content = new Gtk.Box(Gtk.Orientation.VERTICAL, 10);
            content.set_margin_start(16); content.set_margin_end(16);
            content.set_margin_top(12); content.set_margin_bottom(12);

            // Instance selector (Jira 1 / Jira 2) — shown only when a second
            // instance is enabled and we're creating a new worklog.
            instance_box = new Gtk.Box(Gtk.Orientation.HORIZONTAL, 0);
            instance_box.add_css_class("linked");
            instance_box.set_halign(Gtk.Align.CENTER);
            inst1_btn = new Gtk.ToggleButton.with_label("Jira 1");
            inst2_btn = new Gtk.ToggleButton.with_label("Jira 2");
            inst2_btn.set_group(inst1_btn);
            inst1_btn.active = true;
            inst1_btn.toggled.connect(() => { if (inst1_btn.active) set_active_instance(1); });
            inst2_btn.toggled.connect(() => { if (inst2_btn.active) set_active_instance(2); });
            instance_box.append(inst1_btn);
            instance_box.append(inst2_btn);
            content.append(instance_box);

            // Time row
            var timerow = new Gtk.Box(Gtk.Orientation.HORIZONTAL, 8);
            timerow.append(new Gtk.Label("Inicio"));
            start_entry = new Gtk.Entry(); start_entry.set_max_width_chars(6); start_entry.set_width_chars(6);
            timerow.append(start_entry);
            timerow.append(new Gtk.Label("Fin"));
            end_entry = new Gtk.Entry(); end_entry.set_max_width_chars(6); end_entry.set_width_chars(6);
            timerow.append(end_entry);
            var dur_label = new Gtk.Label("");
            dur_label.add_css_class("dim-label");
            timerow.append(dur_label);
            content.append(timerow);
            start_entry.changed.connect(() => update_duration(dur_label));
            end_entry.changed.connect(() => update_duration(dur_label));

            // Picker
            picker_box = new Gtk.Box(Gtk.Orientation.VERTICAL, 6);
            picker_box.vexpand = true;
            var picker_lbl = new Gtk.Label("Issue");
            picker_lbl.set_halign(Gtk.Align.START);
            picker_box.append(picker_lbl);
            picker_selected = new Gtk.Label("(ninguno)");
            picker_selected.add_css_class("dim-label");
            picker_selected.set_halign(Gtk.Align.START);
            picker_box.append(picker_selected);
            picker_search = new Gtk.SearchEntry();
            picker_search.set_placeholder_text("Filtrar issues…");
            picker_search.search_changed.connect(filter_picker);
            picker_box.append(picker_search);
            var sw = new Gtk.ScrolledWindow();
            sw.vexpand = true;
            sw.set_policy(Gtk.PolicyType.NEVER, Gtk.PolicyType.AUTOMATIC);
            picker_list = new Gtk.ListBox();
            picker_list.add_css_class("boxed-list");
            picker_list.row_activated.connect(on_pick);
            sw.set_child(picker_list);
            picker_box.append(sw);
            content.append(picker_box);

            // Comment
            var clbl = new Gtk.Label("Comentario");
            clbl.set_halign(Gtk.Align.START);
            content.append(clbl);
            var csw = new Gtk.ScrolledWindow();
            csw.set_min_content_height(70);
            comment_view = new Gtk.TextView();
            comment_view.set_wrap_mode(Gtk.WrapMode.WORD);
            comment_view.add_css_class("card");
            csw.set_child(comment_view);
            content.append(csw);

            status = new Gtk.Label("");
            status.set_halign(Gtk.Align.START);
            content.append(status);

            // Buttons
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

        // Switch the active Jira instance (create mode); reload the picker.
        private void set_active_instance(int inst) {
            store = (inst == 2) ? jira2 : jira1;
            selected_key = "";
            picker_selected.label = "(ninguno)";
            if (!is_edit) refresh_picker();
        }

        public void open_create(int64 day_ms, int64 s, int64 e) {
            is_edit = false; editing = null;
            this.day_ms = day_ms; start_ms = s; end_ms = e;
            selected_key = "";
            picker_selected.label = "(ninguno)";
            start_entry.text = Util.fmt_clock(s);
            end_entry.text = Util.fmt_clock(e);
            comment_view.buffer.text = "";
            status.label = "";
            picker_box.visible = true;
            delete_btn.visible = false;
            // Instance tabs only when a second instance is configured.
            instance_box.visible = cfg.jira2_enabled;
            inst1_btn.active = true;
            store = jira1;
            refresh_picker();
            present();
        }

        public void open_edit(Worklog w, int inst = 1) {
            is_edit = true; editing = w;
            store = (inst == 2) ? jira2 : jira1;
            start_ms = w.started; end_ms = w.started + (int64) w.duration_sec * 1000;
            selected_key = w.issue_key;
            picker_selected.label = w.issue_key + (w.issue_summary.length > 0 ? ": " + w.issue_summary : "");
            start_entry.text = Util.fmt_clock(start_ms);
            end_entry.text = Util.fmt_clock(end_ms);
            comment_view.buffer.text = w.comment;
            status.label = "";
            picker_box.visible = false;
            instance_box.visible = false;   // locked to the block's instance
            delete_btn.visible = true;
            present();
        }

        private void refresh_picker() {
            status.label = "Cargando issues…";
            store.fetch_assignable_issues.begin((obj, res) => {
                store.fetch_assignable_issues.end(res);
                status.label = "";
                filter_picker();
            });
        }

        private void filter_picker() {
            Gtk.Widget? c = picker_list.get_first_child();
            while (c != null) { var n = c.get_next_sibling(); picker_list.remove(c); c = n; }
            string q = picker_search.text.down();
            foreach (var iss in store.assignable_issues) {
                if (q.length > 0) {
                    string hay = (iss.key + " " + iss.summary + " " + iss.status).down();
                    if (!hay.contains(q)) continue;
                }
                var row = new Gtk.ListBoxRow();
                var box = new Gtk.Box(Gtk.Orientation.HORIZONTAL, 8);
                box.set_margin_start(8); box.set_margin_end(8); box.set_margin_top(3); box.set_margin_bottom(3);
                var k = new Gtk.Label(iss.key); k.add_css_class("monospace"); k.set_width_chars(9); k.set_xalign(0);
                box.append(k);
                var s = new Gtk.Label(iss.summary); s.set_xalign(0); s.set_ellipsize(Pango.EllipsizeMode.END); s.hexpand = true;
                box.append(s);
                if (iss.remaining_sec > 0) {
                    var rem = new Gtk.Label(Util.fmt_hm(iss.remaining_sec)); rem.add_css_class("dim-label");
                    box.append(rem);
                }
                row.set_child(box);
                row.set_data<string>("key", iss.key);
                row.set_data<string>("summary", iss.summary);
                picker_list.append(row);
            }
        }

        private void on_pick(Gtk.ListBoxRow row) {
            selected_key = row.get_data<string>("key");
            string summary = row.get_data<string>("summary");
            picker_selected.label = selected_key + (summary.length > 0 ? ": " + summary : "");
        }

        private bool apply_time(string text, bool is_start) {
            var d = new DateTime.from_unix_local((is_start ? start_ms : end_ms) / 1000);
            int hh, mm;
            if (!parse_hhmm(text, out hh, out mm)) return false;
            var nd = new DateTime.local(d.get_year(), d.get_month(), d.get_day_of_month(), hh, mm, 0);
            int64 nms = nd.to_unix() * 1000;
            if (is_start) start_ms = nms; else end_ms = nms;
            return true;
        }
        private bool parse_hhmm(string t, out int hh, out int mm) {
            hh = 0; mm = 0;
            var parts = t.strip().split(":");
            if (parts.length != 2) return false;
            hh = int.parse(parts[0]); mm = int.parse(parts[1]);
            return hh >= 0 && hh <= 23 && mm >= 0 && mm <= 59;
        }
        private void update_duration(Gtk.Label lbl) {
            int hh = 0, mm = 0, hh2 = 0, mm2 = 0;
            if (parse_hhmm(start_entry.text, out hh, out mm) && parse_hhmm(end_entry.text, out hh2, out mm2)) {
                int s = (hh2 * 60 + mm2) - (hh * 60 + mm);
                if (s > 0) lbl.label = "(%s)".printf(Util.fmt_hm(s * 60));
                else lbl.label = "";
            }
        }

        private void on_save() {
            if (!apply_time(start_entry.text, true) || !apply_time(end_entry.text, false)) {
                set_status("Hora inválida (usá HH:MM).", true); return;
            }
            if (end_ms <= start_ms) { set_status("El fin debe ser posterior al inicio.", true); return; }
            if (selected_key.length == 0) { set_status("Elegí un issue.", true); return; }
            int dur = (int) ((end_ms - start_ms) / 1000);
            string comment = comment_view.buffer.text;
            save_btn.sensitive = false;
            set_status("Guardando…", false);
            if (is_edit) {
                store.update_worklog.begin(editing.issue_key, editing.id, start_ms, dur, comment, (o, r) => {
                    var res = store.update_worklog.end(r);
                    finish(res);
                });
            } else {
                store.create_worklog.begin(selected_key, start_ms, dur, comment, (o, r) => {
                    var res = store.create_worklog.end(r);
                    finish(res);
                });
            }
        }

        private void on_delete() {
            if (editing == null) return;
            delete_btn.sensitive = false;
            set_status("Borrando…", false);
            store.delete_worklog.begin(editing.issue_key, editing.id, (o, r) => {
                var res = store.delete_worklog.end(r);
                finish(res);
            });
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
