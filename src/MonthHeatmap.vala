/*
 * MonthHeatmap.vala - month-at-a-glance hours table (Clockify + Jira rows).
 *
 * Cairo-drawn grid: weekday letter row, day-number row, a Clockify hours row
 * and a Jira hours row. Cells grade gray(0) -> red -> yellow -> green from 0
 * to 4h. Clicking a day emits day_selected so the calendar can jump to that
 * week. Two months are reachable via the prev/next buttons (current + last).
 */

namespace Worklog {

    public class MonthHeatmap : Gtk.Box {
        private ClockifyStore clockify;
        private JiraStore jira;
        private int month_offset = 0;   // 0 = current, -1 = last

        private Gtk.Label month_label;
        private Gtk.Button prev_btn;
        private Gtk.Button next_btn;
        private Gtk.DrawingArea grid;
        private Gtk.Label footer_label;

        private Gee.HashMap<int,int> clk_totals = new Gee.HashMap<int,int>();
        private Gee.HashMap<int,int> jira_totals = new Gee.HashMap<int,int>();
        private string clk_key = "";
        private string jira_key = "";
        private int req_id = 0;

        private const int LETTER_H = 11;
        private const int NUMBER_H = 12;
        private const int CELL_H = 15;
        private const int ICON_COL = 22;

        public signal void day_selected(int64 day_ms);

        public MonthHeatmap(ClockifyStore clockify, JiraStore jira) {
            Object(orientation: Gtk.Orientation.VERTICAL, spacing: 2);
            this.clockify = clockify;
            this.jira = jira;
            build();
            refresh();
        }

        private void build() {
            var header = new Gtk.Box(Gtk.Orientation.HORIZONTAL, 6);
            var title = new Gtk.Label("Horas del mes");
            title.add_css_class("heading");
            header.append(title);
            var spacer = new Gtk.Box(Gtk.Orientation.HORIZONTAL, 0);
            spacer.hexpand = true;
            header.append(spacer);
            prev_btn = new Gtk.Button.from_icon_name("go-previous-symbolic");
            prev_btn.add_css_class("flat");
            prev_btn.set_tooltip_text("Mes anterior");
            prev_btn.clicked.connect(() => { if (month_offset > -1) { month_offset = -1; refresh(); } });
            header.append(prev_btn);
            month_label = new Gtk.Label("");
            month_label.add_css_class("heading");
            month_label.set_width_chars(14);
            header.append(month_label);
            next_btn = new Gtk.Button.from_icon_name("go-next-symbolic");
            next_btn.add_css_class("flat");
            next_btn.set_tooltip_text("Mes actual");
            next_btn.clicked.connect(() => { if (month_offset < 0) { month_offset = 0; refresh(); } });
            header.append(next_btn);
            append(header);

            grid = new Gtk.DrawingArea();
            grid.set_content_height(LETTER_H + NUMBER_H + CELL_H * 2 + 6);
            grid.hexpand = true;
            grid.set_draw_func(draw_grid);
            append(grid);

            var click = new Gtk.GestureClick();
            click.released.connect((n, x, y) => on_click(x, y));
            grid.add_controller(click);

            footer_label = new Gtk.Label("");
            footer_label.add_css_class("caption");
            footer_label.set_halign(Gtk.Align.START);
            append(footer_label);
        }

        private DateTime ref_date() {
            var d = new DateTime.now_local();
            d = new DateTime.local(d.get_year(), d.get_month(), 1, 0, 0, 0);
            return d.add_months(month_offset);
        }
        private int cur_year() { return ref_date().get_year(); }
        private int cur_month0() { return ref_date().get_month() - 1; }
        private string cur_key() { return "%d-%d".printf(cur_year(), cur_month0()); }
        private int days_in_month() {
            var r = ref_date();
            return r.add_months(1).add_days(-1).get_day_of_month();
        }

        public void refresh() {
            prev_btn.sensitive = month_offset > -1;
            next_btn.sensitive = month_offset < 0;
            month_label.label = "%s %d".printf(Util.month_name(cur_month0()), cur_year());

            clk_totals = new Gee.HashMap<int,int>();
            jira_totals = new Gee.HashMap<int,int>();
            clk_key = ""; jira_key = "";
            grid.queue_draw();
            update_footer();

            int req = ++req_id;
            int y = cur_year();
            int m = cur_month0();
            string key = "%d-%d".printf(y, m);

            clockify.fetch_month_totals.begin(y, m, (obj, res) => {
                var t = clockify.fetch_month_totals.end(res);
                if (req != req_id) return;
                clk_totals = t; clk_key = key;
                grid.queue_draw(); update_footer();
            });
            jira.fetch_month_totals.begin(y, m, (obj, res) => {
                var t = jira.fetch_month_totals.end(res);
                if (req != req_id) return;
                jira_totals = t; jira_key = key;
                grid.queue_draw(); update_footer();
            });
        }

        private int dow(int day) {
            return new DateTime.local(cur_year(), cur_month0() + 1, day, 0, 0, 0).get_day_of_week() % 7; // Sun=0
        }
        private bool is_weekend(int day) { int d = dow(day); return d == 0 || d == 6; }
        private string weekday_letter(int day) {
            string[] l = {"D","L","M","Mi","J","V","S"};
            return l[dow(day)];
        }

        private double clk_hours(int day) {
            if (clk_key != cur_key()) return 0;
            int sec = clk_totals.has_key(day) ? clk_totals.get(day) : 0;
            return Math.round((sec / 3600.0) * 10) / 10;
        }
        private double jira_hours(int day) {
            if (jira_key != cur_key()) return 0;
            int sec = jira_totals.has_key(day) ? jira_totals.get(day) : 0;
            return Math.round((sec / 3600.0) * 10) / 10;
        }

        private Gdk.RGBA lerp(Gdk.RGBA a, Gdk.RGBA b, double t) {
            var c = Gdk.RGBA();
            c.red = (float) (a.red + (b.red - a.red) * t);
            c.green = (float) (a.green + (b.green - a.green) * t);
            c.blue = (float) (a.blue + (b.blue - a.blue) * t);
            c.alpha = 1;
            return c;
        }
        private Gdk.RGBA cell_color(double h) {
            if (h <= 0) { var g = Gdk.RGBA(); g.red = 1; g.green = 1; g.blue = 1; g.alpha = 0.06f; return g; }
            var red = Util.hex_rgba("#e74c3c");
            var yellow = Util.hex_rgba("#f1c40f");
            var green = Util.hex_rgba("#81C784");
            double c = double.min(4, h);
            if (c <= 2) return lerp(red, yellow, c / 2);
            return lerp(yellow, green, (c - 2) / 2);
        }

        private void draw_grid(Gtk.DrawingArea da, Cairo.Context cr, int width, int height) {
            int days = days_in_month();
            double col_w = (width - ICON_COL) / (double) days;
            if (col_w <= 0) return;

            cr.select_font_face("Sans", Cairo.FontSlant.NORMAL, Cairo.FontWeight.NORMAL);
            cr.set_font_size(9);

            // icon column labels
            draw_text(cr, "⏱", 2, LETTER_H + NUMBER_H + CELL_H * 0 + CELL_H / 2 + 3, "#cccccc", false);
            draw_text(cr, "J", 2, LETTER_H + NUMBER_H + CELL_H * 1 + CELL_H / 2 + 3, "#cccccc", false);

            for (int i = 0; i < days; i++) {
                int day = i + 1;
                double x = ICON_COL + i * col_w;
                bool we = is_weekend(day);
                string txtcol = we ? "#888888" : "#dddddd";

                draw_text_centered(cr, weekday_letter(day), x, 0, col_w, LETTER_H, txtcol);
                draw_text_centered(cr, day.to_string(), x, LETTER_H, col_w, NUMBER_H, txtcol);

                draw_cell(cr, x, LETTER_H + NUMBER_H, col_w, CELL_H, clk_hours(day));
                draw_cell(cr, x, LETTER_H + NUMBER_H + CELL_H, col_w, CELL_H, jira_hours(day));
            }
        }

        private void draw_cell(Cairo.Context cr, double x, double y, double w, double h, double hours) {
            var c = cell_color(hours);
            rounded(cr, x + 1, y + 1, w - 2, h - 2, 2);
            cr.set_source_rgba(c.red, c.green, c.blue, c.alpha);
            cr.fill();
            if (hours > 0) {
                string t = (hours == Math.floor(hours)) ? "%d".printf((int) hours) : "%.1f".printf(hours);
                draw_text_centered(cr, t, x, y, w, h, "#1a1a1a", true);
            }
        }

        private void rounded(Cairo.Context cr, double x, double y, double w, double h, double r) {
            cr.new_sub_path();
            cr.arc(x + w - r, y + r, r, -Math.PI/2, 0);
            cr.arc(x + w - r, y + h - r, r, 0, Math.PI/2);
            cr.arc(x + r, y + h - r, r, Math.PI/2, Math.PI);
            cr.arc(x + r, y + r, r, Math.PI, 3*Math.PI/2);
            cr.close_path();
        }

        private void draw_text(Cairo.Context cr, string s, double x, double y, string hex, bool bold) {
            var c = Util.hex_rgba(hex);
            cr.set_source_rgba(c.red, c.green, c.blue, 1);
            cr.move_to(x, y);
            cr.show_text(s);
        }

        private void draw_text_centered(Cairo.Context cr, string s, double x, double y, double w, double h, string hex, bool bold = false) {
            cr.select_font_face("Sans", Cairo.FontSlant.NORMAL, bold ? Cairo.FontWeight.BOLD : Cairo.FontWeight.NORMAL);
            Cairo.TextExtents te;
            cr.text_extents(s, out te);
            var c = Util.hex_rgba(hex);
            cr.set_source_rgba(c.red, c.green, c.blue, 1);
            cr.move_to(x + (w - te.width) / 2 - te.x_bearing, y + (h - te.height) / 2 - te.y_bearing);
            cr.show_text(s);
        }

        private void on_click(double x, double y) {
            int days = days_in_month();
            int width = grid.get_width();
            double col_w = (width - ICON_COL) / (double) days;
            if (x < ICON_COL || col_w <= 0) return;
            int i = (int) ((x - ICON_COL) / col_w);
            if (i < 0 || i >= days) return;
            var d = new DateTime.local(cur_year(), cur_month0() + 1, i + 1, 0, 0, 0);
            day_selected(d.to_unix() * 1000);
        }

        private void update_footer() {
            int clk = (clk_key == cur_key()) ? sum(clk_totals) : 0;
            int jr = (jira_key == cur_key()) ? sum(jira_totals) : 0;
            footer_label.label = "Total del mes — ⏱ %s · Jira %s".printf(Util.fmt_hm(clk), Util.fmt_hm(jr));
        }
        private int sum(Gee.HashMap<int,int> m) {
            int s = 0;
            foreach (var e in m.entries) s += e.value;
            return s;
        }
    }
}
