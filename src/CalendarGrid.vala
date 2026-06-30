/*
 * CalendarGrid.vala - the week grid ("la planilla").
 *
 * A single Cairo DrawingArea inside a vertical ScrolledWindow renders the day
 * headers, per-day totals row, the hour-label column and the 7 day columns
 * with worklog blocks for both sources. In combined ("jira-clockify") mode each
 * day column is split in half (Jira left / Clockify right).
 *
 * Interaction (GestureDrag + secondary GestureClick):
 *   - drag on an empty area of a day -> create (snap 30 min, 10 min with Shift)
 *   - click an existing block        -> edit
 *   - drag the middle of a block      -> move (cross-day + time)
 *   - drag a block's top/bottom edge  -> resize
 *   - right-click a block             -> menu (Duplicar)
 */

namespace Worklog {

    public class CalendarGrid : Gtk.Box {
        private Config cfg;
        private JiraStore jira;
        private ClockifyStore clockify;
        public int64 week_start { get; set; }
        public string source { get; set; default = "jira"; }

        private Gtk.ScrolledWindow scroller;
        private Gtk.DrawingArea area;
        private int last_width = 800;

        private const double HOUR_W = 56;
        private const double ROW_H = 22;
        private const double HEADER_H = 22;
        private const double TOTALS_H = 22;
        private const double GRID_TOP = HEADER_H + TOTALS_H;
        private const double EDGE = 6;   // px hit-zone for edge resize

        // Drag state.
        private enum Mode { NONE, CREATE, MOVE, RESIZE_TOP, RESIZE_BOTTOM }
        private Mode drag_mode = Mode.NONE;
        private double press_x;
        private double press_y;
        private bool press_is_jira = true;
        private int press_day = 0;
        private Object? drag_entry = null;
        private int64 drag_started = 0;
        private int drag_dur = 0;
        private bool fine = false;
        // create preview (px within day col)
        private double sel_top;
        private double sel_bottom;
        private double cur_dx = 0;
        private double cur_dy = 0;

        // Signals consumed by WorklogView.
        public signal void create_requested(bool is_jira, int64 day_ms, int64 start_ms, int64 end_ms);
        public signal void edit_requested(bool is_jira, Object entry);
        public signal void move_requested(bool is_jira, Object entry, int64 new_start_ms, int new_dur_sec);
        public signal void duplicate_requested(bool is_jira, Object entry);

        public CalendarGrid(Config cfg, JiraStore jira, ClockifyStore clockify) {
            Object(orientation: Gtk.Orientation.VERTICAL, spacing: 0);
            this.cfg = cfg;
            this.jira = jira;
            this.clockify = clockify;
            vexpand = true;
            hexpand = true;

            scroller = new Gtk.ScrolledWindow();
            scroller.set_policy(Gtk.PolicyType.NEVER, Gtk.PolicyType.AUTOMATIC);
            scroller.vexpand = true;
            scroller.hexpand = true;
            append(scroller);

            area = new Gtk.DrawingArea();
            area.hexpand = true;
            area.set_content_height((int) (GRID_TOP + slots_per_day() * ROW_H));
            area.set_draw_func(draw);
            scroller.set_child(area);

            jira.changed.connect(() => { update_height(); area.queue_draw(); });
            clockify.changed.connect(() => area.queue_draw());

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
            area.set_content_height((int) (GRID_TOP + slots_per_day() * ROW_H));
        }

        // ---- geometry helpers ----
        private bool combined() { return source == "jira-clockify"; }
        private bool show_jira() { return source == "jira" || source == "jira-clockify"; }
        private bool show_clockify() { return source == "clockify" || source == "jira-clockify"; }
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

        // ---- drawing ----
        private void draw(Gtk.DrawingArea da, Cairo.Context cr, int width, int height) {
            last_width = width;
            cr.select_font_face("Sans", Cairo.FontSlant.NORMAL, Cairo.FontWeight.NORMAL);
            cr.set_font_size(9);
            double cw = col_w();
            int slots = slots_per_day();

            // Background slot rows (under everything).
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

            // Worklog blocks.
            if (show_jira()) foreach (var w in jira.worklogs) draw_block(cr, w.started, w.duration_sec, true, w);
            if (show_clockify()) foreach (var e in clockify.entries) draw_block(cr, e.started, e.duration_sec, false, e);

            // Day headers + totals (drawn last so they sit above blocks that
            // could otherwise poke into negative y on the 9h view).
            set_rgba(cr, 0.12, 0.12, 0.14, 1);
            cr.rectangle(0, 0, width, GRID_TOP);
            cr.fill();
            // corner
            draw_cell_border(cr, 0, 0, HOUR_W, GRID_TOP);
            set_rgba(cr, 1, 1, 1, 0.6);
            center_text(cr, "total", 0, 0, HOUR_W, GRID_TOP, false);
            for (int d = 0; d < 7; d++) {
                double bx = HOUR_W + d * cw;
                // header
                if (is_today(d)) set_rgba(cr, 0.30, 0.55, 0.90, 0.22);
                else if (is_weekend(d)) set_rgba(cr, 0, 0, 0, 0.18);
                else set_rgba(cr, 1, 1, 1, 0.04);
                cr.rectangle(bx, 0, cw, HEADER_H); cr.fill();
                draw_cell_border(cr, bx, 0, cw, HEADER_H);
                set_rgba(cr, 1, 1, 1, 1);
                center_text(cr, day_header(d), bx, 0, cw, HEADER_H, true);
                // totals
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
                if (combined()) { x = press_is_jira ? bx : bx + cw / 2; w = cw / 2; }
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

        private void draw_block(Cairo.Context cr, int64 started, int dur_sec, bool is_jira, Object entry) {
            // When this entry is being moved/resized, draw the ghost at the
            // dragged position instead.
            int64 eff_start = started;
            int eff_dur = dur_sec;
            if (drag_entry == entry) {
                if (drag_mode == Mode.MOVE) { eff_start = drag_started; }
                else if (drag_mode == Mode.RESIZE_TOP) { eff_start = drag_started; eff_dur = drag_dur; }
                else if (drag_mode == Mode.RESIZE_BOTTOM) { eff_dur = drag_dur; }
            }
            int d = day_index_of(eff_start);
            if (d < 0) return;
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
            if (y + h < GRID_TOP || y > GRID_TOP + slots_per_day() * ROW_H) { /* still draw, clipped */ }

            // fill + border
            if (is_jira) set_rgba(cr, 155/255.0, 145/255.0, 230/255.0, 0.55);
            else {
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
            if (is_jira) set_rgba(cr, 120/255.0, 110/255.0, 200/255.0, 0.95);
            else set_rgba(cr, 70/255.0, 170/255.0, 100/255.0, 0.95);
            cr.set_line_width(1);
            rounded(cr, x + 0.5, y + 0.5, w - 1, h - 1, 3);
            cr.stroke();

            // text
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
                cr.show_text(is_jira ? Util.fmt_clock(eff_start) + "  " + bottom : Util.fmt_clock(eff_start) + "  " + bottom);
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
            fine = (get_state_shift());
            drag_entry = null;
            drag_mode = Mode.NONE;

            // Hit-test existing blocks (topmost last-drawn wins -> iterate reverse).
            if (hit_test(x, y, out drag_entry, out press_is_jira)) {
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

            // Empty area -> begin a create selection.
            int day = day_index_at(x);
            if (day < 0) { drag_mode = Mode.NONE; return; }
            press_day = day;
            double cw = col_w();
            double bx = HOUR_W + day * cw;
            press_is_jira = combined() ? (x - bx < cw / 2) : (source != "clockify");
            double local_y = y - GRID_TOP;
            sel_top = snap_px(local_y);
            sel_bottom = sel_top + step_px();
            drag_mode = Mode.CREATE;
            area.queue_draw();
        }

        private void on_drag_update(double ox, double oy) {
            fine = get_state_shift();
            cur_dx = ox; cur_dy = oy;
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
                create_requested(press_is_jira, day_ms(press_day), start_ms, end_ms);
                area.queue_draw();
                return;
            }
            if (entry == null) { area.queue_draw(); return; }

            bool moved = Math.fabs(ox) > 3 || Math.fabs(oy) > 3;
            if (!moved && mode == Mode.MOVE) {
                // It was a click -> edit.
                edit_requested(press_is_jira, entry);
                area.queue_draw();
                return;
            }
            // Commit move/resize.
            int64 ns = clamp_start(drag_started, drag_dur);
            int nd = int.max(600, drag_dur);
            if (ns != entry_started(entry) || nd != entry_dur(entry)) {
                move_requested(press_is_jira, entry, ns, nd);
            } else {
                area.queue_draw();
            }
        }

        private void on_right_click(int n, double x, double y) {
            Object? e; bool is_jira;
            if (!hit_test(x, y, out e, out is_jira)) return;
            var pop = new Gtk.Popover();
            pop.set_parent(area);
            var rect = Gdk.Rectangle() { x = (int) x, y = (int) y, width = 1, height = 1 };
            pop.set_pointing_to(rect);
            var box = new Gtk.Box(Gtk.Orientation.VERTICAL, 2);
            box.set_margin_start(6); box.set_margin_end(6); box.set_margin_top(6); box.set_margin_bottom(6);
            var dup = new Gtk.Button.with_label("Duplicar");
            dup.add_css_class("flat");
            dup.clicked.connect(() => { duplicate_requested(is_jira, e); pop.popdown(); });
            box.append(dup);
            var ed = new Gtk.Button.with_label("Editar");
            ed.add_css_class("flat");
            ed.clicked.connect(() => { edit_requested(is_jira, e); pop.popdown(); });
            box.append(ed);
            pop.set_child(box);
            pop.popup();
        }

        // ---- hit testing ----
        private bool hit_test(double x, double y, out Object? entry, out bool is_jira) {
            entry = null; is_jira = true;
            // Iterate in reverse draw order: clockify on top in combined? Both
            // are side-by-side, so order doesn't overlap. Check both.
            if (show_clockify()) {
                for (int i = clockify.entries.size - 1; i >= 0; i--) {
                    var e = clockify.entries.get(i);
                    if (point_in_block(x, y, e.started, e.duration_sec, false)) { entry = e; is_jira = false; return true; }
                }
            }
            if (show_jira()) {
                for (int i = jira.worklogs.size - 1; i >= 0; i--) {
                    var w = jira.worklogs.get(i);
                    if (point_in_block(x, y, w.started, w.duration_sec, true)) { entry = w; is_jira = true; return true; }
                }
            }
            return false;
        }

        private bool point_in_block(double x, double y, int64 started, int dur_sec, bool is_jira) {
            int d = day_index_of(started);
            if (d < 0) return false;
            double cw = col_w();
            double bx = HOUR_W + d * cw;
            double rx, rw;
            if (combined()) { rx = is_jira ? bx + 2 : bx + cw / 2 + 1; rw = cw / 2 - 3; }
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
