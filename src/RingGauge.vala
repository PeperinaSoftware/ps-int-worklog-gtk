/*
 * RingGauge.vala - circular donut gauge with a center percentage label.
 *
 * Cairo-drawn arc with a fill-in animation (0 -> value) triggered by
 * start_fill(), plus an optional slow fade-loop on the ring color (used by
 * the "Horas" ring to draw the eye).
 */

namespace Worklog {

    public class RingGauge : Gtk.DrawingArea {
        public double value { get; set; default = 0; }           // target 0..100
        public Gdk.RGBA base_color { get; set; }
        public Gdk.RGBA pale_color { get; set; }
        public Gdk.RGBA track_color { get; set; }
        public double thickness { get; set; default = 12; }
        public bool use_fade_loop { get; set; default = false; }
        public bool intermittent { get; set; default = false; }

        private double display_value = 0;
        private double fade_t = 0;              // 0..1 fade phase
        private int64 fill_start_us = 0;
        private bool filling = false;
        private uint tick_id = 0;

        public RingGauge(int diameter = 110) {
            set_content_width(diameter);
            set_content_height(diameter);
            base_color = Util.hex_rgba("#81C784");
            pale_color = Util.hex_rgba("#C8E6C9");
            track_color = Util.hex_rgba("#2a2a2a");
            set_draw_func(draw);
            notify["value"].connect(() => {
                if (!filling) { display_value = value; queue_draw(); }
            });
            // Drive the fade loop / fill animation off a single tick callback.
            tick_id = add_tick_callback(on_tick);
        }

        public void start_fill() {
            display_value = 0;
            fill_start_us = get_frame_clock() != null ? get_frame_clock().get_frame_time() : GLib.get_monotonic_time();
            filling = true;
            queue_draw();
        }

        private bool on_tick(Gtk.Widget w, Gdk.FrameClock clock) {
            int64 now = clock.get_frame_time();
            bool redraw = false;

            if (filling) {
                double elapsed = (now - fill_start_us) / 1000000.0;
                double dur = 1.5;
                double t = elapsed / dur;
                if (t >= 1.0) { t = 1.0; filling = false; }
                // OutQuart easing.
                double e = 1 - Math.pow(1 - t, 4);
                display_value = value * e;
                redraw = true;
            }

            if (use_fade_loop) {
                double cycle = intermittent ? 2.0 : 4.5;  // seconds
                double phase = ((now / 1000000.0) % cycle) / cycle;
                fade_t = 0.5 - 0.5 * Math.cos(phase * 2 * Math.PI);  // 0..1..0
                redraw = true;
            }

            if (redraw) queue_draw();
            return GLib.Source.CONTINUE;
        }

        private Gdk.RGBA lerp(Gdk.RGBA a, Gdk.RGBA b, double t) {
            var c = Gdk.RGBA();
            c.red = (float) (a.red + (b.red - a.red) * t);
            c.green = (float) (a.green + (b.green - a.green) * t);
            c.blue = (float) (a.blue + (b.blue - a.blue) * t);
            c.alpha = 1;
            return c;
        }

        private void draw(Gtk.DrawingArea da, Cairo.Context cr, int width, int height) {
            double cx = width / 2.0;
            double cy = height / 2.0;
            double r = (double.min(width, height) - thickness) / 2.0;
            cr.set_line_cap(Cairo.LineCap.ROUND);
            cr.set_line_width(thickness);

            // Track.
            cr.set_source_rgba(track_color.red, track_color.green, track_color.blue, track_color.alpha);
            cr.arc(cx, cy, r, 0, 2 * Math.PI);
            cr.stroke();

            // Foreground arc.
            double v = double.max(0, double.min(100, display_value));
            if (v > 0) {
                Gdk.RGBA col = base_color;
                if (use_fade_loop) col = lerp(base_color, pale_color, fade_t);
                double start_a = -Math.PI / 2;
                double end_a = start_a + (v / 100.0) * 2 * Math.PI;
                cr.set_source_rgba(col.red, col.green, col.blue, 1);
                cr.arc(cx, cy, r, start_a, end_a);
                cr.stroke();
            }

            // Center label.
            string label = "%d%%".printf((int) Math.round(display_value));
            cr.select_font_face("Sans", Cairo.FontSlant.NORMAL, Cairo.FontWeight.BOLD);
            cr.set_font_size(Math.round(double.min(width, height) * 0.22));
            Cairo.TextExtents te;
            cr.text_extents(label, out te);
            // Use the widget's themed foreground color for the label.
            var sc = get_color();
            cr.set_source_rgba(sc.red, sc.green, sc.blue, sc.alpha);
            cr.move_to(cx - te.width / 2 - te.x_bearing, cy - te.height / 2 - te.y_bearing);
            cr.show_text(label);
        }
    }
}
