/*
 * ClockifyStore.vala - Clockify REST v1 client (async port of ClockifyStore.qml).
 *
 * Resolves the user + default workspace via /user (cached into Config),
 * loads projects + tags once, fetches the week's time entries and supports
 * create / update / delete plus a Jira->Clockify sync.
 *
 * Auth: X-Api-Key header.
 */

namespace Worklog {

    public class ClockifyStore : Object {
        private const string BASE = "https://api.clockify.me/api/v1";

        private Config cfg;
        private Http http;

        public string workspace_id = "";
        public string user_id = "";
        public Gee.ArrayList<Project> projects { get; private set; default = new Gee.ArrayList<Project>(); }
        public Gee.ArrayList<Tag> tags { get; private set; default = new Gee.ArrayList<Tag>(); }
        public Gee.ArrayList<ClockifyEntry> entries { get; private set; default = new Gee.ArrayList<ClockifyEntry>(); }

        public bool loading { get; private set; default = false; }
        public string last_error { get; set; default = ""; }
        public int64 last_fetched_at = 0;
        public string debug_log { get; private set; default = ""; }

        public signal void changed();

        public ClockifyStore(Config cfg, Http http) {
            this.cfg = cfg;
            this.http = http;
            workspace_id = valid_oid(cfg.clockify_workspace_id) ? cfg.clockify_workspace_id : "";
            user_id = valid_oid(cfg.clockify_user_id) ? cfg.clockify_user_id : "";
        }

        private string api_key() { return cfg.clockify_api_key; }
        public bool ready() { return api_key().length > 0; }

        private bool valid_oid(string s) {
            if (s.length != 24) return false;
            foreach (char c in s.to_utf8()) {
                bool hex = (c >= '0' && c <= '9') || (c >= 'a' && c <= 'f') || (c >= 'A' && c <= 'F');
                if (!hex) return false;
            }
            return true;
        }

        private async HttpResponse req(string method, string url, string? body) {
            log(method + " " + url);
            return yield http.send(method, url, null, api_key(), body);
        }

        // Resolve user + workspace + projects + tags.
        public async bool ensure_context() {
            if (!ready()) {
                last_error = "Falta la API key de Clockify.";
                changed();
                return false;
            }
            workspace_id = valid_oid(cfg.clockify_workspace_id) ? cfg.clockify_workspace_id : workspace_id;
            user_id = valid_oid(cfg.clockify_user_id) ? cfg.clockify_user_id : user_id;
            if (valid_oid(workspace_id) && valid_oid(user_id) && projects.size > 0) return true;

            var u = yield req("GET", BASE + "/user", null);
            if (!u.ok()) {
                last_error = "HTTP %d contra /user.".printf(u.status);
                changed();
                return false;
            }
            var obj = Jx.parse_obj(u.body);
            user_id = Jx.str(obj, "id");
            if (!valid_oid(workspace_id)) {
                workspace_id = Jx.str(obj, "defaultWorkspace");
                if (!valid_oid(workspace_id)) workspace_id = Jx.str(obj, "activeWorkspace");
            }
            cfg.clockify_user_id = user_id;
            cfg.clockify_workspace_id = workspace_id;
            if (!valid_oid(workspace_id)) {
                last_error = "No pude resolver un workspace válido.";
                changed();
                return false;
            }
            yield load_projects();
            yield load_tags();
            return true;
        }

        private async void load_projects() {
            var r = yield req("GET", BASE + "/workspaces/" + workspace_id + "/projects?archived=false&page-size=200", null);
            var list = new Gee.ArrayList<Project>();
            if (r.ok()) {
                var arr = Jx.parse_arr(r.body);
                if (arr != null) {
                    for (uint i = 0; i < arr.get_length(); i++) {
                        var p = arr.get_object_element(i);
                        var pr = new Project();
                        pr.id = Jx.str(p, "id");
                        pr.name = Jx.str(p, "name");
                        pr.color = Jx.str(p, "color");
                        pr.billable = Jx.boolean(p, "billable");
                        list.add(pr);
                    }
                }
            }
            projects = list;
            log("Proyectos: %d".printf(list.size));
        }

        private async void load_tags() {
            var r = yield req("GET", BASE + "/workspaces/" + workspace_id + "/tags?archived=false&page-size=200", null);
            var list = new Gee.ArrayList<Tag>();
            if (r.ok()) {
                var arr = Jx.parse_arr(r.body);
                if (arr != null) {
                    for (uint i = 0; i < arr.get_length(); i++) {
                        var t = arr.get_object_element(i);
                        var tg = new Tag();
                        tg.id = Jx.str(t, "id");
                        tg.name = Jx.str(t, "name");
                        list.add(tg);
                    }
                }
            }
            tags = list;
        }

        public async void fetch_week(int64 week_start_ms) {
            if (loading) return;
            loading = true; last_error = ""; changed();
            if (!yield ensure_context()) { loading = false; changed(); return; }

            int64 start = Util.start_of_day_ms(week_start_ms);
            int64 end = start + 7 * Util.DAY_MS;
            string url = BASE + "/workspaces/" + workspace_id + "/user/" + user_id + "/time-entries"
                + "?start=" + Uri.escape_string(Util.fmt_utc_iso(start))
                + "&end=" + Uri.escape_string(Util.fmt_utc_iso(end))
                + "&page-size=200";
            var r = yield req("GET", url, null);
            if (!r.ok()) {
                last_error = "HTTP %d al traer time entries.".printf(r.status);
                loading = false; changed(); return;
            }
            entries = parse_entries(r.body);
            last_fetched_at = Util.now_ms();
            loading = false;
            log("Entries: %d".printf(entries.size));
            changed();
        }

        private Gee.ArrayList<ClockifyEntry> parse_entries(string body) {
            var list = new Gee.ArrayList<ClockifyEntry>();
            var arr = Jx.parse_arr(body);
            if (arr == null) return list;
            for (uint i = 0; i < arr.get_length(); i++) {
                var e = arr.get_object_element(i);
                var ti = Jx.obj(e, "timeInterval");
                string s = Jx.str(ti, "start");
                string en = Jx.str(ti, "end");
                if (s.length == 0 || en.length == 0) continue;
                int64 sm = Util.parse_iso(s);
                int64 em = Util.parse_iso(en);
                if (sm == 0 || em <= sm) continue;
                var ce = new ClockifyEntry();
                ce.id = Jx.str(e, "id");
                ce.started = sm;
                ce.duration_sec = (int) ((em - sm) / 1000);
                ce.description = Jx.str(e, "description");
                ce.project_id = Jx.str(e, "projectId");
                var p = project_by_id(ce.project_id);
                ce.project_name = p != null ? p.name : "";
                ce.project_color = p != null ? p.color : "";
                ce.billable = Jx.boolean(e, "billable");
                var tids = new Gee.ArrayList<string>();
                var tnames = new Gee.ArrayList<string>();
                var ta = Jx.arr(e, "tagIds");
                if (ta != null) {
                    for (uint j = 0; j < ta.get_length(); j++) {
                        string tid = ta.get_string_element(j);
                        tids.add(tid);
                        var tg = tag_by_id(tid);
                        if (tg != null) tnames.add(tg.name);
                    }
                }
                ce.tag_ids = tids.to_array();
                ce.tag_names = tnames.to_array();
                list.add(ce);
            }
            list.sort((a, b) => (a.started < b.started) ? -1 : (a.started > b.started ? 1 : 0));
            return list;
        }

        public async Gee.HashMap<int,int> fetch_month_totals(int year, int month0) {
            var totals = new Gee.HashMap<int,int>();
            if (!yield ensure_context()) return totals;
            var first = new DateTime.local(year, month0 + 1, 1, 0, 0, 0);
            var next = first.add_months(1);
            int page = 1;
            const int page_size = 200;
            while (true) {
                string url = BASE + "/workspaces/" + workspace_id + "/user/" + user_id + "/time-entries"
                    + "?start=" + Uri.escape_string(Util.fmt_utc_iso(first.to_unix() * 1000))
                    + "&end=" + Uri.escape_string(Util.fmt_utc_iso(next.to_unix() * 1000))
                    + "&page-size=%d&page=%d".printf(page_size, page);
                var r = yield req("GET", url, null);
                if (!r.ok()) break;
                var arr = Jx.parse_arr(r.body);
                if (arr == null) break;
                for (uint i = 0; i < arr.get_length(); i++) {
                    var ti = Jx.obj(arr.get_object_element(i), "timeInterval");
                    int64 sm = Util.parse_iso(Jx.str(ti, "start"));
                    int64 em = Util.parse_iso(Jx.str(ti, "end"));
                    if (sm == 0 || em <= sm) continue;
                    var d = new DateTime.from_unix_local(sm / 1000);
                    if (d.get_year() == year && d.get_month() == month0 + 1) {
                        int day = d.get_day_of_month();
                        int cur = totals.has_key(day) ? totals.get(day) : 0;
                        totals.set(day, cur + (int) ((em - sm) / 1000));
                    }
                }
                if (arr.get_length() < page_size) break;
                page++;
            }
            return totals;
        }

        private Project? project_by_id(string id) {
            if (id.length == 0) return null;
            foreach (var p in projects) if (p.id == id) return p;
            return null;
        }
        private Tag? tag_by_id(string id) {
            foreach (var t in tags) if (t.id == id) return t;
            return null;
        }

        // ------------------------------------------------------------------
        // Create / Update / Delete
        // ------------------------------------------------------------------
        public async OpResult create_entry(int64 start_ms, int64 end_ms, string description,
                                           string project_id, string[] tag_ids, bool billable) {
            if (!context_ready()) return new OpResult(false, last_error);
            var b = new Json.Builder();
            b.begin_object();
            b.set_member_name("start"); b.add_string_value(Util.fmt_utc_iso(start_ms));
            b.set_member_name("end"); b.add_string_value(Util.fmt_utc_iso(end_ms));
            b.set_member_name("description"); b.add_string_value(description);
            b.set_member_name("billable"); b.add_boolean_value(billable);
            if (project_id.length > 0) { b.set_member_name("projectId"); b.add_string_value(project_id); }
            if (tag_ids.length > 0) {
                b.set_member_name("tagIds"); b.begin_array();
                foreach (var t in tag_ids) b.add_string_value(t);
                b.end_array();
            }
            b.end_object();
            var r = yield req("POST", BASE + "/workspaces/" + workspace_id + "/time-entries", to_json(b));
            if (r.ok()) return new OpResult(true);
            return new OpResult(false, "HTTP %d: %s".printf(r.status, extract_error(r.body)));
        }

        public async OpResult update_entry(string entry_id, int64 start_ms, int64 end_ms, string description,
                                           string project_id, string[] tag_ids, bool billable) {
            if (!context_ready()) return new OpResult(false, last_error);
            var b = new Json.Builder();
            b.begin_object();
            b.set_member_name("start"); b.add_string_value(Util.fmt_utc_iso(start_ms));
            b.set_member_name("end"); b.add_string_value(Util.fmt_utc_iso(end_ms));
            b.set_member_name("description"); b.add_string_value(description);
            b.set_member_name("billable"); b.add_boolean_value(billable);
            if (project_id.length > 0) { b.set_member_name("projectId"); b.add_string_value(project_id); }
            b.set_member_name("tagIds"); b.begin_array();
            foreach (var t in tag_ids) b.add_string_value(t);
            b.end_array();
            b.end_object();
            var r = yield req("PUT", BASE + "/workspaces/" + workspace_id + "/time-entries/" + Uri.escape_string(entry_id), to_json(b));
            if (r.ok()) return new OpResult(true);
            return new OpResult(false, "HTTP %d: %s".printf(r.status, extract_error(r.body)));
        }

        public async OpResult delete_entry(string entry_id) {
            if (!context_ready()) return new OpResult(false, last_error);
            var r = yield req("DELETE", BASE + "/workspaces/" + workspace_id + "/time-entries/" + Uri.escape_string(entry_id), null);
            if (r.status == 204 || r.status == 200) return new OpResult(true);
            return new OpResult(false, "HTTP %d: %s".printf(r.status, extract_error(r.body)));
        }

        private bool context_ready() {
            if (!valid_oid(workspace_id) || !valid_oid(user_id)) {
                last_error = "Sincronizá primero (workspace/usuario no resueltos).";
                return false;
            }
            return true;
        }

        // ------------------------------------------------------------------
        // Sync from Jira: create a Clockify entry per Jira worklog of the week
        // not already present (overlap-based dedup by description).
        // Returns {created, skipped, failed}.
        // ------------------------------------------------------------------
        public async int[] sync_from_jira(Gee.ArrayList<Worklog> jira_worklogs, string default_project_id, bool default_billable) {
            int created = 0, skipped = 0, failed = 0;
            if (jira_worklogs.size == 0) return { 0, 0, 0 };
            if (!yield ensure_context()) return { 0, 0, 0 };

            // Dedup + creation are BOTH scoped to default_project_id so two
            // Jira instances that map to different Clockify projects can't
            // interfere with each other's sync.
            string target_project = default_project_id;
            var to_create = new Gee.ArrayList<Worklog>();
            foreach (var j in jira_worklogs) {
                string desc = sync_description(j);
                int64 js = j.started;
                int64 je = j.started + (int64) j.duration_sec * 1000;
                bool hit = false;
                foreach (var c in entries) {
                    if (c.project_id != target_project) continue;
                    if (c.description != desc) continue;
                    int64 cs = c.started;
                    int64 ce_end = c.started + (int64) c.duration_sec * 1000;
                    if (js < ce_end && cs < je) { hit = true; break; }
                }
                if (hit) skipped++;
                else to_create.add(j);
            }
            foreach (var j in to_create) {
                string desc = sync_description(j);
                int64 je = j.started + (int64) j.duration_sec * 1000;
                var r = yield create_entry(j.started, je, desc, default_project_id, {}, default_billable);
                if (r.ok) created++; else failed++;
            }
            return { created, skipped, failed };
        }

        // Clockify description for a synced Jira worklog. With sync-bracket-key
        // on it wraps the issue key in [brackets], e.g. "[CP-3526]: título".
        private string sync_description(Worklog j) {
            string key = cfg.sync_bracket_key ? "[" + j.issue_key + "]" : j.issue_key;
            return key + (j.issue_summary.length > 0 ? ": " + j.issue_summary : "");
        }

        // ------------------------------------------------------------------
        private string to_json(Json.Builder b) {
            var gen = new Json.Generator();
            gen.set_root(b.get_root());
            return gen.to_data(null);
        }
        private string extract_error(string body) {
            var o = Jx.parse_obj(body);
            if (o != null && o.has_member("message")) return Jx.str(o, "message");
            return body.length > 240 ? body.substring(0, 240) : body;
        }
        private void log(string msg) {
            debug_log += msg + "\n";
            if (debug_log.length > 80000) debug_log = debug_log.substring(debug_log.length - 40000);
            if (cfg.debug) stdout.printf("[Clockify] %s\n", msg);
        }
        public void clear_debug_log() { debug_log = ""; changed(); }
    }
}
