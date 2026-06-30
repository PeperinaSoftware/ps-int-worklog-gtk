/*
 * SprintGauges.vala - twin RingGauge widget (Sprint % elapsed + Horas % logged)
 * shown at the bottom of the calendar.
 */

namespace Worklog {

    public class SprintGauges : Gtk.Box {
        private JiraStore jira;
        private RingGauge sprint_ring;
        private RingGauge hours_ring;
        private Gtk.Label sprint_dates;
        private Gtk.Label avail_label;
        private Gtk.Label burned_label;

        public SprintGauges(JiraStore jira) {
            Object(orientation: Gtk.Orientation.HORIZONTAL, spacing: 12);
            this.jira = jira;
            build();
            jira.changed.connect(refresh);
            refresh();
        }

        private Gtk.Widget hline() {
            var sep = new Gtk.Separator(Gtk.Orientation.HORIZONTAL);
            sep.set_valign(Gtk.Align.CENTER);
            sep.hexpand = true;
            sep.add_css_class("dim-line");
            return sep;
        }

        private void build() {
            append(hline());

            // Sprint column
            var col1 = new Gtk.Box(Gtk.Orientation.VERTICAL, 4);
            col1.set_valign(Gtk.Align.CENTER);
            var t1 = new Gtk.Label("Sprint");
            t1.add_css_class("heading");
            col1.append(t1);
            sprint_ring = new RingGauge(110);
            sprint_ring.set_halign(Gtk.Align.CENTER);
            col1.append(sprint_ring);
            sprint_dates = new Gtk.Label("Sin sprint activo");
            sprint_dates.add_css_class("caption");
            sprint_dates.set_justify(Gtk.Justification.CENTER);
            col1.append(sprint_dates);
            append(col1);

            append(hline());

            // Horas column
            var col2 = new Gtk.Box(Gtk.Orientation.VERTICAL, 4);
            col2.set_valign(Gtk.Align.CENTER);
            var t2 = new Gtk.Label("Horas");
            t2.add_css_class("heading");
            col2.append(t2);
            hours_ring = new RingGauge(110);
            hours_ring.set_halign(Gtk.Align.CENTER);
            hours_ring.pale_color = Util.hex_rgba("#C8E6C9");
            hours_ring.use_fade_loop = true;
            col2.append(hours_ring);
            avail_label = new Gtk.Label("");
            avail_label.add_css_class("caption");
            col2.append(avail_label);
            burned_label = new Gtk.Label("");
            burned_label.add_css_class("caption");
            col2.append(burned_label);
            append(col2);

            append(hline());
        }

        public void start_fill_animation() {
            sprint_ring.start_fill();
            hours_ring.start_fill();
        }

        private bool has_sprint() {
            return jira.current_sprint != null && jira.current_sprint.start_ms > 0;
        }

        private double sprint_pct() {
            if (!has_sprint()) return 0;
            int64 s = jira.current_sprint.start_ms;
            int64 e = jira.current_sprint.end_ms;
            int64 now = Util.now_ms();
            if (e <= s) return 0;
            if (now <= s) return 0;
            if (now >= e) return 100;
            return (double) (now - s) / (double) (e - s) * 100.0;
        }

        private double hours_pct() {
            int avail = jira.sprint_available_sec;
            int consumed = jira.sprint_consumed_sec;
            int total = avail + consumed;
            if (total <= 0) return 0;
            return double.max(0, double.min(100, (double) consumed / total * 100.0));
        }

        private string sprint_color(double pct) {
            if (pct >= 100) return "#B71C1C";
            if (pct >= 90) return "#E53935";
            if (pct >= 85) return "#FB8C00";
            if (pct >= 75) return "#FBC02D";
            return "#29B6F6";
        }

        private string fmt_date(int64 ms) {
            if (ms == 0) return "—";
            var d = new DateTime.from_unix_local(ms / 1000);
            return "%d/%d".printf(d.get_day_of_month(), d.get_month());
        }

        public void refresh() {
            double sp = sprint_pct();
            double hp = hours_pct();
            sprint_ring.value = sp;
            sprint_ring.base_color = Util.hex_rgba(sprint_color(sp));
            hours_ring.value = hp;
            hours_ring.base_color = Util.hex_rgba(hp >= 100 ? "#4CAF50" : "#81C784");
            hours_ring.intermittent = sp >= 85 && hp < 99;

            if (has_sprint()) {
                sprint_dates.label = "Inicio: %s\nFin: %s".printf(
                    fmt_date(jira.current_sprint.start_ms), fmt_date(jira.current_sprint.end_ms));
            } else {
                sprint_dates.label = "Sin sprint activo";
            }
            avail_label.label = "Disponible: %s".printf(Util.fmt_hm(jira.sprint_available_sec));
            burned_label.label = "Quemadas: %s".printf(Util.fmt_hm(jira.sprint_consumed_sec));

            string tip = breakdown_text();
            avail_label.set_tooltip_text(tip.length > 0 ? tip : null);
        }

        private string breakdown_text() {
            if (jira.sprint_breakdown.size == 0) return "";
            var sb = new StringBuilder();
            int max = int.min(jira.sprint_breakdown.size, 20);
            for (int i = 0; i < max; i++) {
                var bi = jira.sprint_breakdown.get(i);
                if (i > 0) sb.append("\n");
                sb.append("%s: %s".printf(bi.key, Util.fmt_hm(bi.remaining_sec)));
            }
            if (jira.sprint_breakdown.size > max)
                sb.append("\n…y %d más".printf(jira.sprint_breakdown.size - max));
            return sb.str;
        }
    }
}
