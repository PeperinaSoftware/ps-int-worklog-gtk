/*
 * Util.vala - small date / formatting helpers shared across the app.
 *
 * Times are kept as Unix epoch milliseconds (int64). Display always uses the
 * machine's local timezone, mirroring the original plasmoid which worked off
 * JavaScript Date objects.
 */

namespace Worklog.Util {

    // Milliseconds in a day.
    public const int64 DAY_MS = 86400000;

    public static int64 now_ms() {
        return GLib.get_real_time() / 1000;
    }

    public static DateTime local(int64 ms) {
        return new DateTime.from_unix_local(ms / 1000).add_seconds((ms % 1000) / 1000.0);
    }

    // Local midnight (00:00) of the given ms.
    public static int64 start_of_day_ms(int64 ms) {
        var d = new DateTime.from_unix_local(ms / 1000);
        var midnight = new DateTime.local(d.get_year(), d.get_month(), d.get_day_of_month(), 0, 0, 0);
        return midnight.to_unix() * 1000;
    }

    // Local midnight of the Sunday that opens the week containing `ms`.
    public static int64 sunday_of(int64 ms) {
        var midnight = start_of_day_ms(ms);
        var d = new DateTime.from_unix_local(midnight / 1000);
        // GLib day_of_week: 1=Mon .. 7=Sun. We want Sunday=0 offset.
        int dow = d.get_day_of_week() % 7; // Sun -> 0, Mon -> 1, ... Sat -> 6
        return midnight - (int64) dow * DAY_MS;
    }

    public static bool same_day(int64 a, int64 b) {
        var da = new DateTime.from_unix_local(a / 1000);
        var db = new DateTime.from_unix_local(b / 1000);
        return da.get_year() == db.get_year()
            && da.get_day_of_year() == db.get_day_of_year();
    }

    // "3h 30m", "45m", "2h".
    public static string fmt_hm(int sec) {
        if (sec <= 0) return "0";
        int h = sec / 3600;
        int m = (sec % 3600) / 60;
        if (h > 0 && m > 0) return "%dh %dm".printf(h, m);
        if (h > 0) return "%dh".printf(h);
        return "%dm".printf(m);
    }

    public static string fmt_clock(int64 ms) {
        var d = new DateTime.from_unix_local(ms / 1000);
        return "%02d:%02d".printf(d.get_hour(), d.get_minute());
    }

    public static string short_month(int m0) { // 0-based
        string[] names = {"Ene","Feb","Mar","Abr","May","Jun","Jul","Ago","Sep","Oct","Nov","Dic"};
        if (m0 < 0 || m0 > 11) return "";
        return names[m0];
    }

    public static string month_name(int m0) { // 0-based
        string[] names = {"Enero","Febrero","Marzo","Abril","Mayo","Junio",
                          "Julio","Agosto","Septiembre","Octubre","Noviembre","Diciembre"};
        if (m0 < 0 || m0 > 11) return "";
        return names[m0];
    }

    // Jira "started" format: 2026-05-12T15:00:00.000+0000 (local offset).
    public static string fmt_jira_started(int64 ms) {
        var d = new DateTime.from_unix_local(ms / 1000);
        var off = d.get_utc_offset(); // microseconds
        bool neg = off < 0;
        int64 abs_min = (neg ? -off : off) / 1000000 / 60;
        return "%04d-%02d-%02dT%02d:%02d:%02d.000%s%02d%02d".printf(
            d.get_year(), d.get_month(), d.get_day_of_month(),
            d.get_hour(), d.get_minute(), d.get_second(),
            neg ? "-" : "+", (int)(abs_min / 60), (int)(abs_min % 60));
    }

    // Jira JQL date: yyyy-MM-dd (local).
    public static string fmt_jql_date(int64 ms) {
        var d = new DateTime.from_unix_local(ms / 1000);
        return "%04d-%02d-%02d".printf(d.get_year(), d.get_month(), d.get_day_of_month());
    }

    // Clockify wants UTC ISO with millis: 2026-05-12T15:00:00.000Z.
    public static string fmt_utc_iso(int64 ms) {
        var d = new DateTime.from_unix_utc(ms / 1000);
        return "%04d-%02d-%02dT%02d:%02d:%02d.%03dZ".printf(
            d.get_year(), d.get_month(), d.get_day_of_month(),
            d.get_hour(), d.get_minute(), d.get_second(), (int)(ms % 1000));
    }

    // Parse an ISO-8601 timestamp (Jira/Clockify) into epoch ms. 0 on failure.
    public static int64 parse_iso(string? s) {
        if (s == null || s.length == 0) return 0;
        var dt = new DateTime.from_iso8601(s, null);
        if (dt == null) {
            // Jira uses +0000 (no colon) offsets that GLib's parser rejects;
            // splice a colon into the offset and retry.
            string fixed = fix_offset(s);
            dt = new DateTime.from_iso8601(fixed, null);
        }
        if (dt == null) return 0;
        return dt.to_unix() * 1000 + (dt.get_microsecond() / 1000);
    }

    private static string fix_offset(string s) {
        // Turn ...+0000 / ...-0300 into ...+00:00 / ...-03:00.
        if (s.length < 5) return s;
        string tail = s.substring(s.length - 5);
        if ((tail.has_prefix("+") || tail.has_prefix("-")) && !tail.contains(":")) {
            return s.substring(0, s.length - 2) + ":" + s.substring(s.length - 2);
        }
        return s;
    }

    // Parse a "#rrggbb" hex string to a Gdk.RGBA with the given alpha.
    public static Gdk.RGBA hex_rgba(string? hex, double alpha = 1.0) {
        var c = Gdk.RGBA();
        c.red = 0.5f; c.green = 0.5f; c.blue = 0.5f; c.alpha = (float) alpha;
        if (hex == null) return c;
        string h = hex.strip();
        if (!h.has_prefix("#") || h.length < 7) return c;
        c.red   = (float) (parse_hex2(h, 1) / 255.0);
        c.green = (float) (parse_hex2(h, 3) / 255.0);
        c.blue  = (float) (parse_hex2(h, 5) / 255.0);
        c.alpha = (float) alpha;
        return c;
    }

    private static int parse_hex2(string s, int idx) {
        int v = 0;
        for (int i = idx; i < idx + 2 && i < s.length; i++) {
            v = v * 16 + hexval(s[i]);
        }
        return v;
    }
    private static int hexval(char c) {
        if (c >= '0' && c <= '9') return c - '0';
        if (c >= 'a' && c <= 'f') return c - 'a' + 10;
        if (c >= 'A' && c <= 'F') return c - 'A' + 10;
        return 0;
    }
}

// Null-safe accessors over json-glib's Json.Object / Json.Array. Every getter
// tolerates a missing or wrong-typed member and returns a sensible default.
namespace Worklog.Jx {

    public static Json.Object? parse_obj(string body) {
        try {
            var parser = new Json.Parser();
            parser.load_from_data(body, -1);
            var root = parser.get_root();
            if (root == null || root.get_node_type() != Json.NodeType.OBJECT) return null;
            return root.get_object();
        } catch (Error e) {
            return null;
        }
    }

    public static Json.Array? parse_arr(string body) {
        try {
            var parser = new Json.Parser();
            parser.load_from_data(body, -1);
            var root = parser.get_root();
            if (root == null || root.get_node_type() != Json.NodeType.ARRAY) return null;
            return root.get_array();
        } catch (Error e) {
            return null;
        }
    }

    public static string str(Json.Object? o, string key) {
        if (o == null || !o.has_member(key)) return "";
        var n = o.get_member(key);
        if (n == null || n.get_node_type() != Json.NodeType.VALUE) return "";
        if (n.get_value_type() == typeof(string)) return n.get_string() ?? "";
        if (n.get_value_type() == typeof(int64)) return n.get_int().to_string();
        return "";
    }

    public static int64 i64(Json.Object? o, string key) {
        if (o == null || !o.has_member(key)) return 0;
        var n = o.get_member(key);
        if (n == null || n.get_node_type() != Json.NodeType.VALUE) return 0;
        var t = n.get_value_type();
        if (t == typeof(int64)) return n.get_int();
        if (t == typeof(double)) return (int64) n.get_double();
        if (t == typeof(string)) return int64.parse(n.get_string());
        return 0;
    }

    public static bool has_num(Json.Object? o, string key) {
        if (o == null || !o.has_member(key)) return false;
        var n = o.get_member(key);
        if (n == null || n.get_node_type() != Json.NodeType.VALUE) return false;
        var t = n.get_value_type();
        return t == typeof(int64) || t == typeof(double);
    }

    public static bool boolean(Json.Object? o, string key) {
        if (o == null || !o.has_member(key)) return false;
        var n = o.get_member(key);
        if (n == null || n.get_node_type() != Json.NodeType.VALUE) return false;
        if (n.get_value_type() == typeof(bool)) return n.get_boolean();
        return false;
    }

    public static Json.Object? obj(Json.Object? o, string key) {
        if (o == null || !o.has_member(key)) return null;
        var n = o.get_member(key);
        if (n == null || n.get_node_type() != Json.NodeType.OBJECT) return null;
        return n.get_object();
    }

    public static Json.Array? arr(Json.Object? o, string key) {
        if (o == null || !o.has_member(key)) return null;
        var n = o.get_member(key);
        if (n == null || n.get_node_type() != Json.NodeType.ARRAY) return null;
        return n.get_array();
    }
}
