/*
 * CalendarGrid.vala - the week grid ("la planilla").
 *
 * A single Cairo DrawingArea inside a vertical ScrolledWindow renders the day
 * headers, per-day totals row, the hour-label column and the 7 day columns with
 * worklog blocks. Sources are routed by a `kind` string:
 *   - "jira"     : first Jira instance (configurable color)
 *   - "jira2"    : optional second Jira instance (own color; shares the region)
 *   - "clockify" : Clockify entries
 * In combined ("jira-clockify") mode each day column is split in half: both Jira
 * instances on the left, Clockify on the right.
 *
 * Google Calendar events (read-only) are drawn as translucent, immovable blocks
 * behind everything. Blocks that overlap another of the same source get an
 * orange (Jira) / gold (Clockify) outline.
 */

namespace Worklog {

    public class CalendarGrid : Gtk.Box {
        private Config cfg;
        private JiraStore jira;
        private JiraStore jira2;
        private ClockifyStore clockify;
        private GoogleStore google;
        public int64 week_start { get; set; }
        public string source { get; set; default = "jira"; }

        private Gtk.ScrolledWindow scroller;
        private Gtk.DrawingArea area;
        private int last_width = 800;

        private const double HOUR_W = 56;
        private const double MIN_ROW = 22;   // minimum 30-min slot height (px)
        private int last_height = 400;
        // Row height stretches to fill the viewport (so the 9h grid has no empty
        // band below it); clamped to MIN_ROW so the 24h grid scrolls instead.
        private double ROW_H {
            get {
                double h = (last_height - GRID_TOP) / (double) slots_per_day();
                return double.max(MIN_ROW, h);
            }
        }
        private const double HEADER_H = 22;
        private const double TOTALS_H = 22;
        private const double GRID_TOP = HEADER_H + TOTALS_H;
        private const double EDGE = 6;

        private enum Mode { NONE, CREATE, MOVE, RESIZE_TOP, RESIZE_BOTTOM }
        private Mode drag_mode = Mode.NONE;
        private double press_x;
        private double press_y;
        private string press_kind = "jira";     // "jira" | "jira2" | "clockify"
        private int press_day = 0;
        private Object? drag_entry = null;
        private int64 drag_started = 0;
        private int drag_dur = 0;
        private bool fine = false;
        private double sel_top;
        private double sel_bottom;

        // Overlap id sets per source, recomputed each draw.
        private Gee.HashSet<string> ov_jira = new Gee.HashSet<string>();
        private Gee.HashSet<string> ov_jira2 = new Gee.HashSet<string>();
        private Gee.HashSet<string> ov_clockify = new Gee.HashSet<string>();

        // Signals consumed by WorklogView. `kind` is "jira" | "jira2" | "clockify".
        public signal void create_requested(string kind, int64 day_ms, int64 start_ms, int64 end_ms);
        public signal void edit_requested(string kind, Object entry);
        public signal void move_requested(string kind, Object entry, int64 new_start_ms, int new_dur_sec);
        public signal void duplicate_requested(string kind, Object entry);

        public CalendarGrid(Config cfg, JiraStore jira, JiraStore jira2, ClockifyStore clockify, GoogleStore google) {
            Object(orientation: Gtk.Orientation.VERTICAL, spacing: 0);
            this.cfg = cfg;
            this.jira = jira;
            this.jira2 = jira2;
            this.clockify = clockify;
            this.google = google;
            vexpand = true;
            hexpand = true;

            scroller = new Gtk.ScrolledWindow();
            scroller.set_policy(Gtk.PolicyType.NEVER, Gtk.PolicyType.AUTOMATIC);
            scroller.vexpand = true;
            scroller.hexpand = true;
            append(scroller);

            area = new Gtk.DrawingArea();
            area.hexpand = true;
            area.vexpand = true;   // fill the viewport; rows stretch (see ROW_H)
            area.set_content_height((int) (GRID_TOP + slots_per_day() * MIN_ROW));
            area.set_draw_func(draw);
            scroller.set_child(area);

            jira.changed.connect(() => { update_height(); area.queue_draw(); });
            jira2.changed.connect(() => area.queue_draw());
            clockify.changed.connect(() => area.queue_draw());
            google.changed.connect(() => area.queue_draw());

            var drag = new Gtk.GestureDrag();
            drag.drag_begin.connect(on_drag_begin);
            drag.drag_update.connect(on_drag_update);
            drag.drag_end.connect(on_drag_end);
            area.add_controller(drag);

            var rclick = new Gtk.GestureClick();
            rclick.set_button(3);
            rclick.released.connect(on_right_click);
            area.add_controller(rclick);
        }

        public void set_week(int64 ms) { week_start = ms; update_height(); area.queue_draw(); }
        public void change_source(string s) { source = s; area.queue_draw(); }
        public void refresh() { update_height(); area.queue_draw(); }

        private void update_height() {
            area.set_content_height((int) (GRID_TOP + slots_per_day() * MIN_ROW));
        }

        // ---- geometry helpers ----
        private bool combined() { return source == "jira-clockify"; }
        private bool show_jira() { return source == "jira" || source == "jira-clockify"; }
        private bool show_jira2() { return show_jira() && cfg.jira2_enabled; }
        private bool show_clockify() { return source == "clockify" || source == "jira-clockify"; }
        private bool show_google() { return cfg.google_cal_enabled; }
        private int start_hour() { return cfg.view_mode == "24h" ? 0 : 9; }
        private int end_hour() { return cfg.view_mode == "24h" ? 24 : 18; }
        private int slots_per_day() { return (end_hour() - start_hour()) * 2; }
        private double col_w() { return (last_width - HOUR_W) / 7.0; }

        private int64 day_ms(int d) {
            return new DateTime.from_unix_local(week_start / 1000).add_days(d).to_unix() * 1000;
        }
        private int day_index_of(int64 started) {
            for (int d = 0; d < 7; d++) {
                if (started >= day_ms(d) && started < day_ms(d + 1)) return d;
            }
            return -1;
        }
        private double y_for(int64 started, int d) {
            double min_from_start = (started - day_ms(d)) / 60000.0 - start_hour() * 60;
            return GRID_TOP + (min_from_start / 30.0) * ROW_H;
        }
        private double h_for(int dur_sec) {
            return double.max(ROW_H / 3.0, (dur_sec / 1800.0) * ROW_H);
        }

        // ---- overlap maps ----
        private Gee.HashSet<string> compute_overlaps(Gee.ArrayList<Worklog>? wl, Gee.ArrayList<ClockifyEntry>? ce) {
            var ids = new Gee.HashSet<string>();
            // Bucket per day, then O(n^2) within a day (small n).
            var starts = new Gee.ArrayList<int64?>();
            var ends = new Gee.ArrayList<int64?>();
            var idlist = new Gee.ArrayList<string>();
            var days = new Gee.ArrayList<int>();
            if (wl != null) foreach (var w in wl) {
                starts.add(w.started); ends.add(w.started + (int64) w.duration_sec * 1000);
                idlist.add(w.id); days.add(day_index_of(w.started));
            }
            if (ce != null) foreach (var e in ce) {
                starts.add(e.started); ends.add(e.started + (int64) e.duration_sec * 1000);
                idlist.add(e.id); days.add(day_index_of(e.started));
            }
            int n = idlist.size;
            for (int i = 0; i < n; i++) {
                for (int j = i + 1; j < n; j++) {
                    if (days[i] != days[j] || days[i] < 0) continue;
                    if (starts[i] < ends[j] && starts[j] < ends[i]) {
                        ids.add(idlist[i]); ids.add(idlist[j]);
                    }
                }
            }
            return ids;
        }

        // ---- drawing ----
        private void draw(Gtk.DrawingArea da, Cairo.Context cr, int width, int height) {
            last_width = width;
            last_height = height;
            cr.select_font_face("Sans", Cairo.FontSlant.NORMAL, Cairo.FontWeight.NORMAL);
            cr.set_font_size(9);
            double cw = col_w();
            int slots = slots_per_day();

            ov_jira = show_jira() ? compute_overlaps(jira.worklogs, null) : new Gee.HashSet<string>();
            ov_jira2 = show_jira2() ? compute_overlaps(jira2.worklogs, null) : new Gee.HashSet<string>();
            ov_clockify = show_clockify() ? compute_overlaps(null, clockify.entries) : new Gee.HashSet<string>();

            // Background slot rows.
            for (int d = 0; d < 7; d++) {
                double bx = HOUR_W + d * cw;
                if (is_weekend(d)) { set_rgba(cr, 0, 0, 0, 0.18); cr.rectangle(bx, GRID_TOP, cw, slots * ROW_H); cr.fill(); }
                if (is_today(d)) { set_rgba(cr, 0.30, 0.55, 0.90, 0.10); cr.rectangle(bx, GRID_TOP, cw, slots * ROW_H); cr.fill(); }
                for (int s = 0; s < slots; s++) {
                    double ry = GRID_TOP + s * ROW_H;
                    if (s % 2 == 0) { set_rgba(cr, 1, 1, 1, 0.03); cr.rectangle(bx, ry, cw, ROW_H); cr.fill(); }
                    set_rgba(cr, 1, 1, 1, 0.06);
                    cr.set_line_width(1);
                    cr.rectangle(bx + 0.5, ry + 0.5, cw - 1, ROW_H - 1);
                    cr.stroke();
                }
                if (combined()) {
                    set_rgba(cr, 1, 1, 1, 0.12);
                    cr.set_line_width(1);
                    cr.move_to(bx + cw / 2, GRID_TOP);
                    cr.line_to(bx + cw / 2, GRID_TOP + slots * ROW_H);
                    cr.stroke();
                }
            }

            // Hour labels.
            for (int s = 0; s < slots; s++) {
                double ry = GRID_TOP + s * ROW_H;
                if (s % 2 == 0) { set_rgba(cr, 1, 1, 1, 0.02); cr.rectangle(0, ry, HOUR_W, ROW_H); cr.fill(); }
                int minutes = start_hour() * 60 + s * 30;
                string lbl = "%02d:%02d".printf(minutes / 60, minutes % 60);
                set_rgba(cr, 1, 1, 1, s % 2 == 0 ? 0.85 : 0.45);
                Cairo.TextExtents te; cr.text_extents(lbl, out te);
                cr.move_to(HOUR_W - te.width - 4, ry + ROW_H / 2 + te.height / 2);
                cr.show_text(lbl);
            }

            // Google Calendar events (behind everything else).
            if (show_google()) foreach (var g in google.events) draw_google(cr, g);

            // Worklog blocks: jira1, jira2, clockify.
            if (show_jira()) foreach (var w in jira.worklogs) draw_block(cr, w, "jira", ov_jira.contains(w.id));
            if (show_jira2()) foreach (var w in jira2.worklogs) draw_block(cr, w, "jira2", ov_jira2.contains(w.id));
            if (show_clockify()) foreach (var e in clockify.entries) draw_block(cr, e, "clockify", ov_clockify.contains(e.id));

            // Day headers + totals.
            set_rgba(cr, 0.12, 0.12, 0.14, 1);
            cr.rectangle(0, 0, width, GRID_TOP);
            cr.fill();
            draw_cell_border(cr, 0, 0, HOUR_W, GRID_TOP);
            set_rgba(cr, 1, 1, 1, 0.6);
            center_text(cr, "total", 0, 0, HOUR_W, GRID_TOP, false);
            for (int d = 0; d < 7; d++) {
                double bx = HOUR_W + d * cw;
                if (is_today(d)) set_rgba(cr, 0.30, 0.55, 0.90, 0.22);
                else if (is_weekend(d)) set_rgba(cr, 0, 0, 0, 0.18);
                else set_rgba(cr, 1, 1, 1, 0.04);
                cr.rectangle(bx, 0, cw, HEADER_H); cr.fill();
                draw_cell_border(cr, bx, 0, cw, HEADER_H);
                set_rgba(cr, 1, 1, 1, 1);
                center_text(cr, day_header(d), bx, 0, cw, HEADER_H, true);
                int sec = total_sec_for_day(d);
                double t = cfg.daily_target_hours * 3600;
                if (sec <= 0) set_rgba(cr, 1, 1, 1, 0.02);
                else if (sec >= t) set_rgba(cr, 0.18, 0.80, 0.44, 0.18);
                else set_rgba(cr, 0.95, 0.77, 0.06, 0.18);
                cr.rectangle(bx, HEADER_H, cw, TOTALS_H); cr.fill();
                draw_cell_border(cr, bx, HEADER_H, cw, TOTALS_H);
                set_rgba(cr, 1, 1, 1, 0.9);
                center_text(cr, totals_text(sec), bx, HEADER_H, cw, TOTALS_H, false);
            }

            // Create-drag selection preview.
            if (drag_mode == Mode.CREATE) {
                double bx = HOUR_W + press_day * cw;
                double x = bx;
                double w = cw;
                if (combined()) { x = (press_kind != "clockify") ? bx : bx + cw / 2; w = cw / 2; }
                set_rgba(cr, 0.30, 0.55, 0.90, 0.30);
                cr.rectangle(x, GRID_TOP + sel_top, w, sel_bottom - sel_top); cr.fill();
                set_rgba(cr, 0.30, 0.55, 0.90, 1);
                cr.set_line_width(1);
                cr.rectangle(x + 0.5, GRID_TOP + sel_top + 0.5, w - 1, sel_bottom - sel_top - 1); cr.stroke();
                string range = Util.fmt_clock(px_to_ms(press_day, sel_top)) + " - " + Util.fmt_clock(px_to_ms(press_day, sel_bottom));
                set_rgba(cr, 1, 1, 1, 1);
                center_text(cr, range, x, GRID_TOP + sel_top, w, sel_bottom - sel_top, true);
            }
        }

        // Translucent, full-column-width, immovable Google event block.
        private void draw_google(Cairo.Context cr, GEvent g) {
            int d = day_index_of(g.started);
            if (d < 0) return;
            double cw = col_w();
            double x = HOUR_W + d * cw + 2;
            double w = cw - 4;
            double y = y_for(g.started, d);
            double h = h_for(g.duration_sec);
            var col = Util.hex_rgba(google.calendar_color(g.calendar_id));
            rounded(cr, x, y, w, h, 3);
            cr.set_source_rgba(col.red, col.green, col.blue, 0.18);
            cr.fill();
            cr.set_source_rgba(col.red, col.green, col.blue, 0.45);
            cr.set_line_width(1);
            rounded(cr, x + 0.5, y + 0.5, w - 1, h - 1, 3);
            cr.stroke();
            if (!google_covered(g, d)) {
                cr.save();
                cr.rectangle(x + 2, y, w - 4, h);
                cr.clip();
                set_rgba(cr, 1, 1, 1, 0.85);
                cr.set_font_size(9);
                cr.move_to(x + 4, y + 12);
                cr.show_text(g.summary);
                cr.restore();
            }
        }

        // A Google block is "covered" when a worklog block on the same day
        // overlaps it in time (so its label doesn't bleed through).
        private bool google_covered(GEvent g, int d) {
            int64 s = g.started, e = g.started + (int64) g.duration_sec * 1000;
            if (show_jira()) foreach (var w in jira.worklogs) {
                if (day_index_of(w.started) != d) continue;
                if (s < w.started + (int64) w.duration_sec * 1000 && w.started < e) return true;
            }
            if (show_jira2()) foreach (var w in jira2.worklogs) {
                if (day_index_of(w.started) != d) continue;
                if (s < w.started + (int64) w.duration_sec * 1000 && w.started < e) return true;
            }
            if (show_clockify()) foreach (var c in clockify.entries) {
                if (day_index_of(c.started) != d) continue;
                if (s < c.started + (int64) c.duration_sec * 1000 && c.started < e) return true;
            }
            return false;
        }

        private void draw_block(Cairo.Context cr, Object entry, string kind, bool overlapping) {
            int64 eff_start = entry_started(entry);
            int eff_dur = entry_dur(entry);
            if (drag_entry == entry) {
                if (drag_mode == Mode.MOVE) { eff_start = drag_started; }
                else if (drag_mode == Mode.RESIZE_TOP) { eff_start = drag_started; eff_dur = drag_dur; }
                else if (drag_mode == Mode.RESIZE_BOTTOM) { eff_dur = drag_dur; }
            }
            int d = day_index_of(eff_start);
            if (d < 0) return;
            bool is_jira = (kind != "clockify");
            double cw = col_w();
            double bx = HOUR_W + d * cw;
            double x, w;
            if (combined()) {
                x = is_jira ? bx + 2 : bx + cw / 2 + 1;
                w = cw / 2 - 3;
            } else {
                x = bx + 2; w = cw - 4;
            }
            double y = y_for(eff_start, d);
            double h = h_for(eff_dur);

            // Fill.
            if (is_jira) {
                var c = Util.hex_rgba(cfg.jira_block_color(kind == "jira2" ? 2 : 1), 0.55);
                cr.set_source_rgba(c.red, c.green, c.blue, c.alpha);
            } else {
                var pc = entry as ClockifyEntry;
                if (!combined() && pc != null && pc.project_color.length > 0) {
                    var c = Util.hex_rgba(pc.project_color, 0.6);
                    cr.set_source_rgba(c.red, c.green, c.blue, c.alpha);
                } else {
                    set_rgba(cr, 120/255.0, 215/255.0, 145/255.0, 0.55);
                }
            }
            rounded(cr, x, y, w, h, 3);
            cr.fill();

            // Border (overlap outline overrides the normal color).
            if (overlapping) {
                if (is_jira) set_rgba(cr, 1, 140/255.0, 0, 1);       // orange
                else set_rgba(cr, 1, 215/255.0, 0, 1);               // gold
                cr.set_line_width(2);
            } else {
                if (is_jira) {
                    var c = Util.hex_rgba(cfg.jira_block_color(kind == "jira2" ? 2 : 1), 0.95);
                    cr.set_source_rgba(c.red, c.green, c.blue, c.alpha);
                } else {
                    set_rgba(cr, 70/255.0, 170/255.0, 100/255.0, 0.95);
                }
                cr.set_line_width(1);
            }
            rounded(cr, x + 0.5, y + 0.5, w - 1, h - 1, 3);
            cr.stroke();

            // Text.
            cr.save();
            cr.rectangle(x + 2, y, w - 4, h);
            cr.clip();
            set_rgba(cr, 1, 1, 1, 0.95);
            cr.set_font_size(combined() ? 8 : 9);
            string top, bottom;
            if (is_jira) {
                var ww = entry as Worklog;
                top = "%s-%s".printf(Util.fmt_clock(eff_start), Util.fmt_clock(eff_start + (int64) eff_dur * 1000));
                bottom = (cfg.show_issue_summary && ww.issue_summary.length > 0) ? ww.issue_key + ": " + ww.issue_summary : ww.issue_key;
            } else {
                var ee = entry as ClockifyEntry;
                top = "%s-%s".printf(Util.fmt_clock(eff_start), Util.fmt_clock(eff_start + (int64) eff_dur * 1000));
                bottom = ee.description.length > 0 ? ee.description : (ee.project_name.length > 0 ? ee.project_name : "(sin descripción)");
            }
            if (h <= ROW_H + 1) {
                cr.move_to(x + 4, y + h / 2 + 3);
                cr.show_text(Util.fmt_clock(eff_start) + "  " + bottom);
            } else {
                cr.move_to(x + 4, y + 11);
                cr.show_text(top);
                cr.move_to(x + 4, y + 22);
                cr.show_text(bottom);
            }
            cr.restore();
        }

        // ---- gestures ----
        private void on_drag_begin(double x, double y) {
            press_x = x; press_y = y;
            fine = get_state_shift();
            drag_entry = null;
            drag_mode = Mode.NONE;

            string hk;
            if (hit_test(x, y, out drag_entry, out hk)) {
                press_kind = hk;
                var es = entry_started(drag_entry);
                var ed = entry_dur(drag_entry);
                int d = day_index_of(es);
                double by = y_for(es, d);
                double bh = h_for(ed);
                drag_started = es; drag_dur = ed;
                if (y - by <= EDGE) drag_mode = Mode.RESIZE_TOP;
                else if (by + bh - y <= EDGE) drag_mode = Mode.RESIZE_BOTTOM;
                else drag_mode = Mode.MOVE;
                return;
            }

            int day = day_index_at(x);
            if (day < 0) { drag_mode = Mode.NONE; return; }
            press_day = day;
            double cw = col_w();
            double bx = HOUR_W + day * cw;
            bool left = combined() ? (x - bx < cw / 2) : (source != "clockify");
            press_kind = left ? "jira" : "clockify";
            double local_y = y - GRID_TOP;
            sel_top = snap_px(local_y);
            sel_bottom = sel_top + step_px();
            drag_mode = Mode.CREATE;
            area.queue_draw();
        }

        private void on_drag_update(double ox, double oy) {
            fine = get_state_shift();
            if (drag_mode == Mode.CREATE) {
                double lo = double.min(press_y, press_y + oy) - GRID_TOP;
                double hi = double.max(press_y, press_y + oy) - GRID_TOP;
                sel_top = snap_px(lo);
                sel_bottom = double.max(sel_top + step_px(), snap_px(hi) + step_px());
                area.queue_draw();
            } else if (drag_mode == Mode.MOVE) {
                int step_min = px_to_snapped_min(oy);
                double cw = col_w();
                int days = cw > 0 ? (int) Math.round(ox / cw) : 0;
                drag_started = entry_started(drag_entry) + (int64) days * Util.DAY_MS + (int64) step_min * 60000;
                area.queue_draw();
            } else if (drag_mode == Mode.RESIZE_TOP) {
                int step_min = px_to_snapped_min(oy);
                drag_started = entry_started(drag_entry) + (int64) step_min * 60000;
                drag_dur = int.max(600, entry_dur(drag_entry) - step_min * 60);
                area.queue_draw();
            } else if (drag_mode == Mode.RESIZE_BOTTOM) {
                int step_min = px_to_snapped_min(oy);
                drag_dur = int.max(600, entry_dur(drag_entry) + step_min * 60);
                area.queue_draw();
            }
        }

        private void on_drag_end(double ox, double oy) {
            var mode = drag_mode;
            var entry = drag_entry;
            drag_mode = Mode.NONE;
            drag_entry = null;

            if (mode == Mode.CREATE) {
                int64 start_ms = px_to_ms(press_day, sel_top);
                int64 end_ms = px_to_ms(press_day, sel_bottom);
                if (end_ms <= start_ms) end_ms = start_ms + (fine ? 10 : 30) * 60000;
                create_requested(press_kind, day_ms(press_day), start_ms, end_ms);
                area.queue_draw();
                return;
            }
            if (entry == null) { area.queue_draw(); return; }

            bool moved = Math.fabs(ox) > 3 || Math.fabs(oy) > 3;
            if (!moved && mode == Mode.MOVE) {
                edit_requested(press_kind, entry);
                area.queue_draw();
                return;
            }
            int64 ns = clamp_start(drag_started, drag_dur);
            int nd = int.max(600, drag_dur);
            if (ns != entry_started(entry) || nd != entry_dur(entry)) {
                move_requested(press_kind, entry, ns, nd);
            } else {
                area.queue_draw();
            }
        }

        private void on_right_click(int n, double x, double y) {
            Object? e; string kind;
            if (!hit_test(x, y, out e, out kind)) return;
            var pop = new Gtk.Popover();
            pop.set_parent(area);
            var rect = Gdk.Rectangle() { x = (int) x, y = (int) y, width = 1, height = 1 };
            pop.set_pointing_to(rect);
            var box = new Gtk.Box(Gtk.Orientation.VERTICAL, 2);
            box.set_margin_start(6); box.set_margin_end(6); box.set_margin_top(6); box.set_margin_bottom(6);
            var dup = new Gtk.Button.with_label("Duplicar");
            dup.add_css_class("flat");
            dup.clicked.connect(() => { duplicate_requested(kind, e); pop.popdown(); });
            box.append(dup);
            var ed = new Gtk.Button.with_label("Editar");
            ed.add_css_class("flat");
            ed.clicked.connect(() => { edit_requested(kind, e); pop.popdown(); });
            box.append(ed);
            pop.set_child(box);
            pop.popup();
        }

        // ---- hit testing ----
        private bool hit_test(double x, double y, out Object? entry, out string kind) {
            entry = null; kind = "jira";
            if (show_clockify()) {
                for (int i = clockify.entries.size - 1; i >= 0; i--) {
                    var e = clockify.entries.get(i);
                    if (point_in_block(x, y, e.started, e.duration_sec, false)) { entry = e; kind = "clockify"; return true; }
                }
            }
            if (show_jira2()) {
                for (int i = jira2.worklogs.size - 1; i >= 0; i--) {
                    var w = jira2.worklogs.get(i);
                    if (point_in_block(x, y, w.started, w.duration_sec, true)) { entry = w; kind = "jira2"; return true; }
                }
            }
            if (show_jira()) {
                for (int i = jira.worklogs.size - 1; i >= 0; i--) {
                    var w = jira.worklogs.get(i);
                    if (point_in_block(x, y, w.started, w.duration_sec, true)) { entry = w; kind = "jira"; return true; }
                }
            }
            return false;
        }

        private bool point_in_block(double x, double y, int64 started, int dur_sec, bool left_half) {
            int d = day_index_of(started);
            if (d < 0) return false;
            double cw = col_w();
            double bx = HOUR_W + d * cw;
            double rx, rw;
            if (combined()) { rx = left_half ? bx + 2 : bx + cw / 2 + 1; rw = cw / 2 - 3; }
            else { rx = bx + 2; rw = cw - 4; }
            double ry = y_for(started, d);
            double rh = h_for(dur_sec);
            return x >= rx && x <= rx + rw && y >= ry && y <= ry + rh;
        }

        // ---- snapping / conversions ----
        private double step_px() { return fine ? ROW_H / 3.0 : ROW_H; }
        private double snap_px(double y) {
            double step = step_px();
            double maxpx = slots_per_day() * ROW_H;
            return double.max(0, double.min(maxpx, Math.round(y / step) * step));
        }
        private int px_to_snapped_min(double px) {
            int g = fine ? 10 : 30;
            double raw = (px / ROW_H) * 30;
            return (int) (Math.round(raw / g) * g);
        }
        private int64 px_to_ms(int day, double px) {
            double min_from_start = (px / ROW_H) * 30;
            return day_ms(day) + (int64) ((start_hour() * 60 + min_from_start) * 60000);
        }
        private int day_index_at(double x) {
            if (x < HOUR_W) return -1;
            double cw = col_w();
            int idx = (int) ((x - HOUR_W) / cw);
            return (idx < 0) ? 0 : (idx > 6 ? 6 : idx);
        }
        private int64 clamp_start(int64 start, int dur) {
            int64 ws = week_start;
            int64 we = day_ms(7);
            int64 durms = (int64) dur * 1000;
            if (start < ws) start = ws;
            if (start + durms > we) start = we - durms;
            return start;
        }

        // ---- misc ----
        private int64 entry_started(Object? e) {
            var w = e as Worklog; if (w != null) return w.started;
            var c = e as ClockifyEntry; if (c != null) return c.started;
            return 0;
        }
        private int entry_dur(Object? e) {
            var w = e as Worklog; if (w != null) return w.duration_sec;
            var c = e as ClockifyEntry; if (c != null) return c.duration_sec;
            return 0;
        }

        private bool get_state_shift() {
            var dpy = get_display();
            var seat = dpy.get_default_seat();
            if (seat == null) return false;
            var kbd = seat.get_keyboard();
            if (kbd == null) return false;
            return (kbd.get_modifier_state() & Gdk.ModifierType.SHIFT_MASK) != 0;
        }

        private bool is_weekend(int d) { return d == 0 || d == 6; }
        private bool is_today(int d) { return Util.same_day(day_ms(d), Util.now_ms()); }

        private string day_header(int d) {
            string[] names = {"Dom","Lun","Mar","Mié","Jue","Vie","Sáb"};
            var dt = new DateTime.from_unix_local(day_ms(d) / 1000);
            return "%s %d/%s".printf(names[d], dt.get_day_of_month(), Util.short_month(dt.get_month() - 1));
        }
        private int total_sec_for_day(int d) {
            int s = 0;
            if (show_jira()) { foreach (var w in jira.worklogs) if (day_index_of(w.started) == d) s += w.duration_sec; }
            else { foreach (var e in clockify.entries) if (day_index_of(e.started) == d) s += e.duration_sec; }
            return s;
        }
        private string totals_text(int sec) {
            if (sec <= 0) return "—";
            string diff = "";
            double target = cfg.daily_target_hours * 3600;
            int64 d = sec - (int64) target;
            if (d != 0) {
                string sign = d > 0 ? "+" : "-";
                int ad = (int) (d > 0 ? d : -d);
                int h = ad / 3600, m = (ad % 3600) / 60;
                diff = " (%s%s%s)".printf(sign, h > 0 ? "%dh".printf(h) : "", m > 0 ? (h > 0 ? " " : "") + "%dm".printf(m) : "");
            }
            return Util.fmt_hm(sec) + diff;
        }

        private void set_rgba(Cairo.Context cr, double r, double g, double b, double a) { cr.set_source_rgba(r, g, b, a); }
        private void rounded(Cairo.Context cr, double x, double y, double w, double h, double r) {
            if (w < 2 * r) r = w / 2;
            if (h < 2 * r) r = h / 2;
            cr.new_sub_path();
            cr.arc(x + w - r, y + r, r, -Math.PI / 2, 0);
            cr.arc(x + w - r, y + h - r, r, 0, Math.PI / 2);
            cr.arc(x + r, y + h - r, r, Math.PI / 2, Math.PI);
            cr.arc(x + r, y + r, r, Math.PI, 3 * Math.PI / 2);
            cr.close_path();
        }
        private void draw_cell_border(Cairo.Context cr, double x, double y, double w, double h) {
            set_rgba(cr, 1, 1, 1, 0.1);
            cr.set_line_width(1);
            cr.rectangle(x + 0.5, y + 0.5, w - 1, h - 1);
            cr.stroke();
        }
        private void center_text(Cairo.Context cr, string s, double x, double y, double w, double h, bool bold) {
            cr.select_font_face("Sans", Cairo.FontSlant.NORMAL, bold ? Cairo.FontWeight.BOLD : Cairo.FontWeight.NORMAL);
            cr.set_font_size(9);
            Cairo.TextExtents te; cr.text_extents(s, out te);
            cr.move_to(x + (w - te.width) / 2 - te.x_bearing, y + (h - te.height) / 2 - te.y_bearing);
            cr.show_text(s);
        }
    }
}
