/*
 * WorklogView.vala - the whole worklog UI (header + calendar + bottom panel +
 * footer), reused by both the main application window and the floating popup.
 *
 * Header : title, week nav (< Hoy >), week label, 9h/24h toggle, sync, source
 *          menu, and (popup only) an "Abrir aplicación" button.
 * Body   : CalendarGrid.
 * Bottom : rings / subtasks / heatmap, switched by a vertical button strip.
 * Footer : totals, (combined) project picker + Jira->Clockify button, prefs.
 */

namespace Worklog {

    public class WorklogView : Gtk.Box {
        private Config cfg;
        private JiraStore jira;
        private JiraStore jira2;
        private ClockifyStore clockify;
        private GoogleStore google;
        private bool is_popup;
        private Gtk.ToggleButton google_toggle;

        private int64 week_start;
        private Gtk.Label week_label;
        private Gtk.Label status_label;
        private Gtk.Button mode_toggle;
        private CalendarGrid calendar;
        private Gtk.Stack bottom_stack;
        private SprintGauges gauges;
        private SubtaskTable subtask_table;
        private MonthHeatmap heatmap;
        private Gtk.Label footer_totals;
        private Gtk.Box sync_box;
        private Gtk.Box bottom_panel;

        private JiraEditDialog? jira_dialog = null;
        private ClockifyEditDialog? clockify_dialog = null;
        private uint status_clear_id = 0;

        public signal void open_app_requested();
        public signal void open_prefs_requested();

        public WorklogView(Config cfg, JiraStore jira, JiraStore jira2, ClockifyStore clockify, GoogleStore google, bool is_popup) {
            Object(orientation: Gtk.Orientation.VERTICAL, spacing: 6);
            this.cfg = cfg;
            this.jira = jira;
            this.jira2 = jira2;
            this.clockify = clockify;
            this.google = google;
            this.is_popup = is_popup;
            this.week_start = Util.sunday_of(Util.now_ms());
            set_margin_start(8); set_margin_end(8); set_margin_top(8); set_margin_bottom(8);
            build();

            jira.changed.connect(on_store_changed);
            jira2.changed.connect(on_store_changed);
            clockify.changed.connect(on_store_changed);
            cfg.settings.changed["worklog-source"].connect(() => { calendar.change_source(cfg.source); update_source_ui(); sync_now(); });
            cfg.settings.changed["view-mode"].connect(() => { update_mode_toggle(); calendar.refresh(); });
            cfg.settings.changed["bottom-view"].connect(() => { apply_bottom_view(); refresh_bottom(); });
            cfg.settings.changed["google-cal-enabled"].connect(() => {
                google_toggle.active = cfg.google_cal_enabled;
                calendar.refresh();
                if (cfg.google_cal_enabled) google.fetch_week.begin(week_start, (o, r) => google.fetch_week.end(r));
            });
            cfg.settings.changed["jira2-enabled"].connect(() => { calendar.refresh(); sync_now(); });

            // First load.
            apply_bottom_view();
            sync_now();
        }

        private void build() {
            build_header();
            status_label = new Gtk.Label(" ");
            status_label.set_halign(Gtk.Align.START);
            status_label.add_css_class("caption");
            append(status_label);

            calendar = new CalendarGrid(cfg, jira, jira2, clockify, google);
            calendar.set_week(week_start);
            calendar.change_source(cfg.source);
            calendar.vexpand = true;
            calendar.create_requested.connect(on_create);
            calendar.edit_requested.connect(on_edit);
            calendar.move_requested.connect(on_move);
            calendar.duplicate_requested.connect(on_duplicate);
            append(calendar);

            build_bottom_panel();
            build_footer();
            update_source_ui();
            update_mode_toggle();
        }

        private void build_header() {
            var header = new Gtk.Box(Gtk.Orientation.HORIZONTAL, 6);

            var icon = new Gtk.Image.from_icon_name("io.github.peperina.WorklogCalendar-symbolic");
            header.append(icon);
            var title = new Gtk.Label("");
            title.add_css_class("heading");
            title.label = "Worklog";
            header.append(title);

            var prev = new Gtk.Button.from_icon_name("go-previous-symbolic");
            prev.add_css_class("flat");
            prev.clicked.connect(() => { shift_week(-7); });
            header.append(prev);
            var today = new Gtk.Button.with_label("Hoy");
            today.clicked.connect(() => { week_start = Util.sunday_of(Util.now_ms()); calendar.set_week(week_start); update_week_label(); sync_now(); });
            header.append(today);
            var next = new Gtk.Button.from_icon_name("go-next-symbolic");
            next.add_css_class("flat");
            next.clicked.connect(() => { shift_week(7); });
            header.append(next);

            week_label = new Gtk.Label("");
            week_label.add_css_class("heading");
            week_label.hexpand = true;
            week_label.set_halign(Gtk.Align.CENTER);
            header.append(week_label);

            mode_toggle = new Gtk.Button.with_label("Modo 9h");
            mode_toggle.set_tooltip_text("Cambiar entre vista 09:00–18:00 y 00:00–24:00");
            mode_toggle.clicked.connect(() => { cfg.view_mode = cfg.view_mode == "9h" ? "24h" : "9h"; });
            header.append(mode_toggle);

            var sync = new Gtk.Button.from_icon_name("view-refresh-symbolic");
            sync.add_css_class("flat");
            sync.set_tooltip_text("Sincronizar");
            sync.clicked.connect(sync_now);
            header.append(sync);

            // Google Calendar events toggle.
            google_toggle = new Gtk.ToggleButton();
            google_toggle.set_icon_name("x-office-calendar-symbolic");
            google_toggle.add_css_class("flat");
            google_toggle.set_tooltip_text("Mostrar / ocultar eventos de Google Calendar");
            google_toggle.active = cfg.google_cal_enabled;
            google_toggle.toggled.connect(() => {
                if (google_toggle.active != cfg.google_cal_enabled)
                    cfg.google_cal_enabled = google_toggle.active;
            });
            header.append(google_toggle);

            // Source menu (jira / jira-clockify / clockify).
            var menu_btn = new Gtk.MenuButton();
            menu_btn.set_icon_name("open-menu-symbolic");
            menu_btn.set_tooltip_text("Fuente de worklog");
            menu_btn.set_popover(build_source_popover());
            header.append(menu_btn);

            if (is_popup) {
                var open_app = new Gtk.Button.from_icon_name("view-fullscreen-symbolic");
                open_app.set_tooltip_text("Abrir la aplicación completa");
                open_app.add_css_class("flat");
                open_app.clicked.connect(() => open_app_requested());
                header.append(open_app);
            }

            append(header);
            update_week_label();
        }

        private Gtk.Popover build_source_popover() {
            var pop = new Gtk.Popover();
            var box = new Gtk.Box(Gtk.Orientation.VERTICAL, 4);
            box.set_margin_start(10); box.set_margin_end(10); box.set_margin_top(10); box.set_margin_bottom(10);
            Gtk.CheckButton? group = null;
            string[,] opts = {{"jira", "Jira"}, {"jira-clockify", "Jira / Clockify"}, {"clockify", "Clockify"}};
            for (int i = 0; i < 3; i++) {
                var rb = new Gtk.CheckButton.with_label(opts[i, 1]);
                if (group == null) group = rb; else rb.set_group(group);
                string val = opts[i, 0];
                rb.active = cfg.source == val;
                rb.toggled.connect(() => { if (rb.active && cfg.source != val) { cfg.source = val; pop.popdown(); } });
                box.append(rb);
            }
            pop.set_child(box);
            return pop;
        }

        private void build_bottom_panel() {
            bottom_panel = new Gtk.Box(Gtk.Orientation.HORIZONTAL, 6);
            bottom_panel.set_valign(Gtk.Align.START);
            // Explicitly non-expanding so the calendar (which fills) gets ALL
            // the vertical slack — otherwise the subtask scroller's vexpand
            // propagates up and this panel would grab half the empty space.
            bottom_panel.set_vexpand(false);

            bottom_stack = new Gtk.Stack();
            bottom_stack.set_transition_type(Gtk.StackTransitionType.SLIDE_UP_DOWN);
            bottom_stack.hexpand = true;
            // Size the panel to the CURRENT view, not the tallest one — the
            // subtask table's scroller would otherwise inflate the whole panel.
            bottom_stack.set_vhomogeneous(false);
            gauges = new SprintGauges(jira);
            gauges.set_valign(Gtk.Align.CENTER);
            bottom_stack.add_named(gauges, "rings");
            subtask_table = new SubtaskTable(jira, cfg);
            subtask_table.status_message.connect((msg, err) => set_status(msg, err));
            bottom_stack.add_named(subtask_table, "subtasks");
            heatmap = new MonthHeatmap(clockify, jira);
            heatmap.set_valign(Gtk.Align.CENTER);
            heatmap.day_selected.connect((ms) => { week_start = Util.sunday_of(ms); calendar.set_week(week_start); update_week_label(); sync_now(); });
            bottom_stack.add_named(heatmap, "heatmap");
            bottom_panel.append(bottom_stack);

            // Vertical switch strip.
            var strip = new Gtk.Box(Gtk.Orientation.VERTICAL, 2);
            strip.set_valign(Gtk.Align.CENTER);
            add_switch_button(strip, "office-chart-ring-symbolic", "Anillos (Sprint / Horas)", "rings");
            if (cfg.show_subtask_table)
                add_switch_button(strip, "view-list-symbolic", "Tabla de subtareas", "subtasks");
            add_switch_button(strip, "x-office-calendar-symbolic", "Heatmap mensual", "heatmap");
            bottom_panel.append(strip);

            append(bottom_panel);
            bottom_panel.visible = cfg.show_bottom_panel;
        }

        private void add_switch_button(Gtk.Box strip, string icon, string tip, string view) {
            var btn = new Gtk.Button.from_icon_name(icon);
            btn.add_css_class("flat");
            btn.set_tooltip_text(tip);
            btn.clicked.connect(() => { cfg.bottom_view = view; });
            strip.append(btn);
        }

        private void build_footer() {
            var footer = new Gtk.Box(Gtk.Orientation.HORIZONTAL, 8);
            footer_totals = new Gtk.Label("");
            footer_totals.add_css_class("caption");
            footer_totals.set_halign(Gtk.Align.START);
            footer_totals.hexpand = true;
            footer.append(footer_totals);

            // Combined-mode sync button. Each Jira instance maps to a Clockify
            // project (set in Preferences → Clockify).
            sync_box = new Gtk.Box(Gtk.Orientation.HORIZONTAL, 6);
            var sync_btn = new Gtk.Button.with_label("Jira → Clockify");
            sync_btn.set_tooltip_text("Crea una entrada Clockify por cada worklog de Jira que aún no tenga su réplica, en el proyecto mapeado por instancia.");
            sync_btn.clicked.connect(sync_jira_into_clockify);
            sync_box.append(sync_btn);
            footer.append(sync_box);

            var prefs = new Gtk.Button.from_icon_name("emblem-system-symbolic");
            prefs.set_tooltip_text("Configurar…");
            prefs.add_css_class("flat");
            prefs.clicked.connect(() => open_prefs_requested());
            footer.append(prefs);

            append(footer);
        }

        // ------------------------------------------------------------------
        private void shift_week(int days) {
            week_start = new DateTime.from_unix_local(week_start / 1000).add_days(days).to_unix() * 1000;
            calendar.set_week(week_start);
            update_week_label();
            sync_now();
        }

        private void update_week_label() {
            var s = new DateTime.from_unix_local(week_start / 1000);
            var e = s.add_days(6);
            week_label.label = "%d %s — %d %s %d".printf(
                s.get_day_of_month(), Util.short_month(s.get_month() - 1),
                e.get_day_of_month(), Util.short_month(e.get_month() - 1), e.get_year());
        }

        private void update_mode_toggle() {
            mode_toggle.label = cfg.view_mode == "9h" ? "Modo 9h" : "Modo 24h";
        }

        private bool show_jira() { return cfg.source == "jira" || cfg.source == "jira-clockify"; }
        private bool show_clockify() { return cfg.source == "clockify" || cfg.source == "jira-clockify"; }

        private void update_source_ui() {
            sync_box.visible = cfg.source == "jira-clockify";
        }

        public void sync_now() {
            if (show_jira()) jira.fetch_week.begin(week_start, (o, r) => jira.fetch_week.end(r));
            if (show_jira() && cfg.jira2_enabled) jira2.fetch_week.begin(week_start, (o, r) => jira2.fetch_week.end(r));
            if (show_clockify()) clockify.fetch_week.begin(week_start, (o, r) => clockify.fetch_week.end(r));
            if (cfg.google_cal_enabled) google.fetch_week.begin(week_start, (o, r) => google.fetch_week.end(r));
            refresh_bottom();
        }

        private void refresh_bottom() {
            if (!cfg.show_bottom_panel) return;
            switch (cfg.bottom_view) {
                case "rings":
                    jira.fetch_sprint_info.begin((o, r) => { jira.fetch_sprint_info.end(r); gauges.start_fill_animation(); });
                    break;
                case "subtasks": subtask_table.refresh(); break;
                case "heatmap": heatmap.refresh(); break;
            }
        }

        private void apply_bottom_view() {
            bottom_panel.visible = cfg.show_bottom_panel;
            string v = cfg.bottom_view;
            if (v == "subtasks" && !cfg.show_subtask_table) v = "rings";
            bottom_stack.set_visible_child_name(v);
        }

        private void on_store_changed() {
            update_footer_totals();
            // Surface store errors.
            if (jira.last_error.length > 0 && show_jira()) set_status("Jira: " + jira.last_error, true);
            else if (cfg.jira2_enabled && jira2.last_error.length > 0 && show_jira()) set_status("Jira 2: " + jira2.last_error, true);
            else if (clockify.last_error.length > 0 && show_clockify()) set_status("Clockify: " + clockify.last_error, true);
        }

        private void update_footer_totals() {
            var sb = new StringBuilder();
            if (show_jira()) {
                int jt = 0; foreach (var w in jira.worklogs) jt += w.duration_sec;
                sb.append("Jira: %s".printf(Util.fmt_hm(jt)));
                if (cfg.jira2_enabled) {
                    int jt2 = 0; foreach (var w in jira2.worklogs) jt2 += w.duration_sec;
                    sb.append("   ·   Jira 2: %s".printf(Util.fmt_hm(jt2)));
                }
            }
            if (show_clockify()) {
                int ct = 0; foreach (var e in clockify.entries) ct += e.duration_sec;
                if (sb.len > 0) sb.append("   ·   ");
                sb.append("Clockify: %s".printf(Util.fmt_hm(ct)));
            }
            footer_totals.label = sb.str;
        }

        // ------------------------------------------------------------------
        private Gtk.Window root_window() { return (Gtk.Window) get_root(); }

        private JiraEditDialog ensure_jira_dialog() {
            if (jira_dialog == null) {
                jira_dialog = new JiraEditDialog(root_window(), jira, jira2, cfg);
                jira_dialog.saved.connect(sync_now);
            }
            return jira_dialog;
        }
        private ClockifyEditDialog ensure_clockify_dialog() {
            if (clockify_dialog == null) {
                clockify_dialog = new ClockifyEditDialog(root_window(), clockify, cfg);
                clockify_dialog.saved.connect(sync_now);
            }
            return clockify_dialog;
        }

        private JiraStore jira_of(string kind) { return kind == "jira2" ? jira2 : jira; }

        private void on_create(string kind, int64 day_ms, int64 start_ms, int64 end_ms) {
            if (kind == "clockify") ensure_clockify_dialog().open_create(start_ms, end_ms);
            else ensure_jira_dialog().open_create(day_ms, start_ms, end_ms);
        }

        private void on_edit(string kind, Object entry) {
            if (kind == "clockify") ensure_clockify_dialog().open_edit((ClockifyEntry) entry);
            else ensure_jira_dialog().open_edit((Worklog) entry, kind == "jira2" ? 2 : 1);
        }

        private void on_move(string kind, Object entry, int64 new_start_ms, int new_dur_sec) {
            if (kind != "clockify") {
                var w = (Worklog) entry;
                var store = jira_of(kind);
                set_status("Actualizando worklog Jira…", false);
                store.update_worklog.begin(w.issue_key, w.id, new_start_ms, new_dur_sec, null, (o, r) => {
                    var res = store.update_worklog.end(r);
                    if (res.ok) sync_now(); else set_status("Jira: " + res.err, true);
                });
            } else {
                var c = (ClockifyEntry) entry;
                set_status("Actualizando entrada Clockify…", false);
                int64 ne = new_start_ms + (int64) new_dur_sec * 1000;
                clockify.update_entry.begin(c.id, new_start_ms, ne, c.description, c.project_id, c.tag_ids, c.billable, (o, r) => {
                    var res = clockify.update_entry.end(r);
                    if (res.ok) sync_now(); else set_status("Clockify: " + res.err, true);
                });
            }
        }

        private void on_duplicate(string kind, Object entry) {
            if (kind != "clockify") {
                var w = (Worklog) entry;
                var store = jira_of(kind);
                set_status("Duplicando worklog Jira…", false);
                store.create_worklog.begin(w.issue_key, w.started, w.duration_sec, w.comment, (o, r) => {
                    var res = store.create_worklog.end(r);
                    if (res.ok) sync_now(); else set_status("Jira: " + res.err, true);
                });
            } else {
                var c = (ClockifyEntry) entry;
                set_status("Duplicando entrada Clockify…", false);
                int64 ne = c.started + (int64) c.duration_sec * 1000;
                clockify.create_entry.begin(c.started, ne, c.description, c.project_id, c.tag_ids, c.billable, (o, r) => {
                    var res = clockify.create_entry.end(r);
                    if (res.ok) sync_now(); else set_status("Clockify: " + res.err, true);
                });
            }
        }

        // Sync both Jira instances into their mapped Clockify projects,
        // sequentially, and report combined totals.
        private void sync_jira_into_clockify() {
            set_status("Copiando Jira → Clockify…", false);
            bool bill = cfg.clockify_billable_default;
            clockify.sync_from_jira.begin(jira.worklogs, cfg.jira_clockify_project(1), bill, (o1, r1) => {
                var c1 = clockify.sync_from_jira.end(r1);
                if (cfg.jira2_enabled) {
                    clockify.sync_from_jira.begin(jira2.worklogs, cfg.jira_clockify_project(2), bill, (o2, r2) => {
                        var c2 = clockify.sync_from_jira.end(r2);
                        report_sync(c1[0] + c2[0], c1[1] + c2[1], c1[2] + c2[2]);
                    });
                } else {
                    report_sync(c1[0], c1[1], c1[2]);
                }
            });
        }

        private void report_sync(int created, int skipped, int failed) {
            set_status("Sync terminado: %d creadas, %d ya existían, %d fallaron.".printf(created, skipped, failed), failed > 0);
            clockify.fetch_week.begin(week_start, (o, r) => clockify.fetch_week.end(r));
        }

        private void set_status(string msg, bool error) {
            status_label.label = msg;
            if (error) status_label.add_css_class("error"); else status_label.remove_css_class("error");
            if (status_clear_id != 0) Source.remove(status_clear_id);
            status_clear_id = Timeout.add_seconds(6, () => {
                status_label.label = " ";
                status_label.remove_css_class("error");
                status_clear_id = 0;
                return Source.REMOVE;
            });
        }
    }
}
