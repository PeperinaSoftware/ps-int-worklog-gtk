/*
 * GoogleStore.vala - read-only Google Calendar API v3 client.
 *
 * Auth: OAuth 2.0 "TV and Limited Input devices" (device-code) flow. The
 * one-time authorization (driven from Preferences) yields a refresh token;
 * this store exchanges it for short-lived access tokens at runtime and fetches
 * events for the visible week from up to 3 calendars. Nothing is written back
 * to Google — only calendar.readonly scope is used.
 */

namespace Worklog {

    // Result of a device-code request (shown by the Preferences page).
    public class DeviceCode : Object {
        public bool ok;
        public string device_code = "";
        public string user_code = "";
        public string verification_url = "";
        public int interval = 5;
        public int expires_in = 600;
        public string error = "";
        public DeviceCode(bool ok) { this.ok = ok; }
    }

    public class GoogleStore : Object {
        private const string TOKEN_URL = "https://oauth2.googleapis.com/token";
        private const string DEVICE_URL = "https://oauth2.googleapis.com/device/code";
        private const string SCOPE = "https://www.googleapis.com/auth/calendar.readonly";

        private Config cfg;
        private Http http;

        public Gee.ArrayList<GEvent> events { get; private set; default = new Gee.ArrayList<GEvent>(); }
        public bool loading { get; private set; default = false; }
        public string last_error { get; set; default = ""; }
        public int64 last_fetched_at = 0;

        private string access_token = "";
        private int64 access_token_exp = 0;

        public signal void changed();

        public GoogleStore(Config cfg, Http http) {
            this.cfg = cfg;
            this.http = http;
        }

        private void log(string msg) {
            if (cfg.debug) stdout.printf("[GoogleCal] %s\n", msg);
        }

        // ------------------------------------------------------------------
        // Runtime: refresh token -> access token -> week events
        // ------------------------------------------------------------------
        private async string? ensure_access_token() {
            int64 now = Util.now_ms();
            if (access_token.length > 0 && now < access_token_exp - 60000) return access_token;

            string id = cfg.google_client_id;
            string secret = cfg.google_client_secret;
            string refresh = cfg.google_refresh_token;
            if (id.length == 0 || secret.length == 0 || refresh.length == 0) {
                last_error = "Falta autorizar Google Calendar (Preferencias → Google).";
                return null;
            }
            string body = "client_id=" + Uri.escape_string(id)
                + "&client_secret=" + Uri.escape_string(secret)
                + "&refresh_token=" + Uri.escape_string(refresh)
                + "&grant_type=refresh_token";
            log("POST oauth2 token (refresh)");
            var r = yield http.send_form("POST", TOKEN_URL, null, body);
            if (r.status != 200) {
                last_error = "No se pudo renovar el token de Google (HTTP %d).".printf(r.status);
                return null;
            }
            var o = Jx.parse_obj(r.body);
            access_token = Jx.str(o, "access_token");
            int64 ttl = (Jx.has_num(o, "expires_in") ? Jx.i64(o, "expires_in") : 3600) * 1000;
            access_token_exp = Util.now_ms() + ttl;
            return access_token.length > 0 ? access_token : null;
        }

        public async void fetch_week(int64 week_start_ms) {
            if (loading) return;
            if (!cfg.google_cal_enabled) return;
            loading = true; last_error = ""; changed();

            string? token = yield ensure_access_token();
            if (token == null) { loading = false; changed(); return; }

            int64 start = Util.start_of_day_ms(week_start_ms);
            int64 end = start + 7 * Util.DAY_MS;
            var ids = calendar_ids();
            var acc = new Gee.ArrayList<GEvent>();
            foreach (string cal_id in ids) {
                string url = "https://www.googleapis.com/calendar/v3/calendars/"
                    + Uri.escape_string(cal_id) + "/events"
                    + "?timeMin=" + Uri.escape_string(iso_utc(start))
                    + "&timeMax=" + Uri.escape_string(iso_utc(end))
                    + "&singleEvents=true&orderBy=startTime&maxResults=250";
                log("GET " + url);
                var r = yield http.send_form("GET", url, token, null);
                if (r.status != 200) {
                    last_error = "HTTP %d al traer eventos de Google (%s).".printf(r.status, cal_id);
                    continue;
                }
                parse_events(r.body, cal_id, start, end, acc);
            }
            acc.sort((a, b) => (a.started < b.started) ? -1 : (a.started > b.started ? 1 : 0));
            events = acc;
            last_fetched_at = Util.now_ms();
            loading = false;
            log("Eventos totales: %d (%d calendario(s)).".printf(acc.size, ids.size));
            changed();
        }

        private Gee.ArrayList<string> calendar_ids() {
            var ids = new Gee.ArrayList<string>();
            foreach (string raw in cfg.google_calendar_ids) {
                string id = raw.strip();
                if (id.length > 0 && ids.size < 3) ids.add(id);
            }
            return ids;
        }

        // Base color (hex) for a calendar id, from the parallel colors list.
        public string calendar_color(string cal_id) {
            var ids = cfg.google_calendar_ids;
            var cols = cfg.google_calendar_colors;
            for (int i = 0; i < ids.length; i++) {
                if (ids[i].strip() == cal_id) {
                    if (i < cols.length && cols[i].strip().length > 0) return cols[i].strip();
                    break;
                }
            }
            return "#e74c3c";
        }

        private void parse_events(string body, string cal_id, int64 start, int64 end, Gee.ArrayList<GEvent> acc) {
            var o = Jx.parse_obj(body);
            var items = Jx.arr(o, "items");
            if (items == null) return;
            for (uint i = 0; i < items.get_length(); i++) {
                var ev = items.get_object_element(i);
                if (Jx.str(ev, "status") == "cancelled") continue;
                var s = Jx.obj(ev, "start");
                var e = Jx.obj(ev, "end");
                string sdt = s != null ? Jx.str(s, "dateTime") : "";
                string edt = e != null ? Jx.str(e, "dateTime") : "";
                if (sdt.length == 0 || edt.length == 0) continue;  // skip all-day
                int64 sm = Util.parse_iso(sdt);
                int64 em = Util.parse_iso(edt);
                if (sm == 0 || em <= sm) continue;
                if (em <= start || sm >= end) continue;
                var g = new GEvent();
                g.id = cal_id + ":" + Jx.str(ev, "id");
                g.summary = Jx.str(ev, "summary");
                if (g.summary.length == 0) g.summary = "(sin título)";
                g.started = sm;
                g.duration_sec = (int) ((em - sm) / 1000);
                g.calendar_id = cal_id;
                acc.add(g);
            }
        }

        private string iso_utc(int64 ms) {
            var d = new DateTime.from_unix_utc(ms / 1000);
            return d.format("%Y-%m-%dT%H:%M:%SZ");
        }

        // ------------------------------------------------------------------
        // Device-code authorization (used by Preferences)
        // ------------------------------------------------------------------
        public async DeviceCode request_device_code() {
            string id = cfg.google_client_id;
            if (id.length == 0) { var dc = new DeviceCode(false); dc.error = "Falta el Client ID."; return dc; }
            string body = "client_id=" + Uri.escape_string(id) + "&scope=" + Uri.escape_string(SCOPE);
            var r = yield http.send_form("POST", DEVICE_URL, null, body);
            if (r.status != 200) {
                var dc = new DeviceCode(false);
                dc.error = "HTTP %d: %s".printf(r.status, r.body.length > 160 ? r.body.substring(0, 160) : r.body);
                return dc;
            }
            var o = Jx.parse_obj(r.body);
            var dc = new DeviceCode(true);
            dc.device_code = Jx.str(o, "device_code");
            dc.user_code = Jx.str(o, "user_code");
            dc.verification_url = Jx.str(o, "verification_url");
            if (dc.verification_url.length == 0) dc.verification_url = Jx.str(o, "verification_uri");
            if (dc.verification_url.length == 0) dc.verification_url = "https://www.google.com/device";
            dc.interval = int.max(2, (int) Jx.i64(o, "interval"));
            dc.expires_in = Jx.has_num(o, "expires_in") ? (int) Jx.i64(o, "expires_in") : 600;
            return dc;
        }

        // Poll once. Returns: "ok" (refresh token stored), "pending",
        // "slow_down", or an error string.
        public async string poll_token(string device_code) {
            string id = cfg.google_client_id;
            string secret = cfg.google_client_secret;
            string body = "client_id=" + Uri.escape_string(id)
                + "&client_secret=" + Uri.escape_string(secret)
                + "&device_code=" + Uri.escape_string(device_code)
                + "&grant_type=urn:ietf:params:oauth:grant-type:device_code";
            var r = yield http.send_form("POST", TOKEN_URL, null, body);
            var o = Jx.parse_obj(r.body);
            if (r.status == 200 && o != null && Jx.str(o, "refresh_token").length > 0) {
                cfg.google_refresh_token = Jx.str(o, "refresh_token");
                return "ok";
            }
            string err = o != null ? Jx.str(o, "error") : "";
            if (err == "authorization_pending") return "pending";
            if (err == "slow_down") return "slow_down";
            if (err.length > 0) return err;
            return "HTTP %d".printf(r.status);
        }

        // GET the account's calendar list -> { id: summary }.
        public async Gee.HashMap<string,string> load_calendars() {
            var outl = new Gee.HashMap<string,string>();
            string? token = yield ensure_access_token();
            if (token == null) return outl;
            var r = yield http.send_form("GET",
                "https://www.googleapis.com/calendar/v3/users/me/calendarList?maxResults=250", token, null);
            if (r.status != 200) return outl;
            var items = Jx.arr(Jx.parse_obj(r.body), "items");
            if (items != null) {
                for (uint i = 0; i < items.get_length(); i++) {
                    var c = items.get_object_element(i);
                    outl.set(Jx.str(c, "id"), Jx.str(c, "summary"));
                }
            }
            return outl;
        }
    }
}
