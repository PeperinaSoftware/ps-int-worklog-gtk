/*
 * JiraStore.vala - Jira Cloud REST v3 client.
 *
 * Async port of the original JiraWorklogStore.qml. Fetches worklogs for a
 * week, lists assignable issues for the picker, discovers the active sprint
 * (three strategies), lists subtasks, aggregates monthly totals and performs
 * worklog create / update / delete plus issue transitions.
 *
 * Auth: HTTP Basic with email + API token, read from Config.
 */

namespace Worklog {

    public class JiraStore : Object {
        private Config cfg;
        private Http http;
        public int instance = 1;   // 1 = primary, 2 = second Jira instance

        public Gee.ArrayList<Worklog> worklogs { get; private set; default = new Gee.ArrayList<Worklog>(); }
        public Gee.ArrayList<Issue> assignable_issues { get; private set; default = new Gee.ArrayList<Issue>(); }
        public Gee.ArrayList<Subtask> subtasks { get; private set; default = new Gee.ArrayList<Subtask>(); }
        public Gee.ArrayList<BreakdownItem> sprint_breakdown { get; private set; default = new Gee.ArrayList<BreakdownItem>(); }

        public string my_account_id = "";
        public Sprint? current_sprint = null;
        public int sprint_available_sec = 0;
        public int sprint_consumed_sec = 0;

        public bool loading { get; private set; default = false; }
        public string last_error { get; set; default = ""; }
        public int64 last_fetched_at = 0;
        public string debug_log { get; private set; default = ""; }

        public signal void changed();

        public JiraStore(Config cfg, Http http, int instance = 1) {
            this.cfg = cfg;
            this.http = http;
            this.instance = instance;
        }

        // ------------------------------------------------------------------
        private bool have_creds() {
            if (!cfg.has_jira_creds_for(instance)) {
                last_error = "Faltan credenciales de Jira (sitio, email o token).";
                return false;
            }
            return true;
        }
        private string auth() { return Http.basic_auth(cfg.jira_email_for(instance), cfg.jira_token_for(instance)); }
        private string site() { return cfg.jira_site_clean_for(instance); }

        private async HttpResponse jget(string url) {
            log("GET " + url);
            return yield http.send("GET", url, auth(), null, null);
        }
        private async HttpResponse send(string method, string url, string? body) {
            log(method + " " + url);
            return yield http.send(method, url, auth(), null, body);
        }

        // ------------------------------------------------------------------
        // Worklogs for a week
        // ------------------------------------------------------------------
        public async void fetch_week(int64 week_start_ms) {
            if (loading) return;
            if (!have_creds()) { changed(); return; }
            loading = true; last_error = ""; changed();

            int64 start = Util.start_of_day_ms(week_start_ms);
            int64 end = start + 7 * Util.DAY_MS;

            if (my_account_id.length == 0) {
                var me = yield jget(site() + "/rest/api/3/myself");
                if (!me.ok()) {
                    last_error = "No se pudo obtener el usuario (HTTP %d).".printf(me.status);
                    loading = false; changed(); return;
                }
                my_account_id = Jx.str(Jx.parse_obj(me.body), "accountId");
            }

            string jql = "worklogAuthor = currentUser() AND worklogDate >= \"%s\" AND worklogDate <= \"%s\""
                .printf(Util.fmt_jql_date(start), Util.fmt_jql_date(end - 1));
            string url = site() + "/rest/api/3/search/jql?jql=" + Uri.escape_string(jql)
                + "&maxResults=200&fields=summary,worklog";
            var r = yield jget(url);
            if (!r.ok()) {
                last_error = "HTTP %d al buscar worklogs.".printf(r.status);
                loading = false; changed(); return;
            }

            var list = new Gee.ArrayList<Worklog>();
            var root = Jx.parse_obj(r.body);
            var issues = Jx.arr(root, "issues");
            if (issues != null) {
                for (uint i = 0; i < issues.get_length(); i++) {
                    var iss = issues.get_object_element(i);
                    var fields = Jx.obj(iss, "fields");
                    string summary = Jx.str(fields, "summary");
                    var wl = Jx.obj(fields, "worklog");
                    var wls = Jx.arr(wl, "worklogs");
                    if (wls == null) continue;
                    for (uint j = 0; j < wls.get_length(); j++) {
                        var w = wls.get_object_element(j);
                        int64 started = Util.parse_iso(Jx.str(w, "started"));
                        if (started < start || started >= end) continue;
                        var author = Jx.obj(w, "author");
                        if (my_account_id.length > 0 && Jx.str(author, "accountId") != my_account_id) continue;
                        var entry = new Worklog();
                        entry.id = Jx.str(w, "id");
                        entry.issue_id = Jx.str(iss, "id");
                        entry.issue_key = Jx.str(iss, "key");
                        entry.issue_summary = summary;
                        entry.started = started;
                        entry.duration_sec = (int) Jx.i64(w, "timeSpentSeconds");
                        entry.comment = extract_adf(w.has_member("comment") ? w.get_member("comment") : null);
                        list.add(entry);
                    }
                }
            }
            list.sort((a, b) => (a.started < b.started) ? -1 : (a.started > b.started ? 1 : 0));
            worklogs = list;
            last_fetched_at = Util.now_ms();
            loading = false;
            log("Worklogs en la semana: %d".printf(list.size));
            changed();
        }

        // ------------------------------------------------------------------
        // Monthly totals (heatmap) -> HashTable<day,int seconds>
        // ------------------------------------------------------------------
        public async Gee.HashMap<int,int> fetch_month_totals(int year, int month0) {
            var totals = new Gee.HashMap<int,int>();
            if (!have_creds()) return totals;
            if (my_account_id.length == 0) {
                var me = yield jget(site() + "/rest/api/3/myself");
                if (me.ok()) my_account_id = Jx.str(Jx.parse_obj(me.body), "accountId");
            }
            var first = new DateTime.local(year, month0 + 1, 1, 0, 0, 0);
            var next = first.add_months(1);
            int64 start_ms = first.to_unix() * 1000;
            int64 end_ms = next.to_unix() * 1000;
            var last = next.add_days(-1);

            string jql = "worklogAuthor = currentUser() AND worklogDate >= \"%s\" AND worklogDate <= \"%s\""
                .printf(Util.fmt_jql_date(start_ms),
                        "%04d-%02d-%02d".printf(last.get_year(), last.get_month(), last.get_day_of_month()));
            string url = site() + "/rest/api/3/search/jql?jql=" + Uri.escape_string(jql)
                + "&maxResults=200&fields=worklog";
            var r = yield jget(url);
            if (!r.ok()) return totals;
            var issues = Jx.arr(Jx.parse_obj(r.body), "issues");
            if (issues == null) return totals;
            for (uint i = 0; i < issues.get_length(); i++) {
                var fields = Jx.obj(issues.get_object_element(i), "fields");
                var wls = Jx.arr(Jx.obj(fields, "worklog"), "worklogs");
                if (wls == null) continue;
                for (uint j = 0; j < wls.get_length(); j++) {
                    var w = wls.get_object_element(j);
                    int64 sm = Util.parse_iso(Jx.str(w, "started"));
                    if (sm < start_ms || sm >= end_ms) continue;
                    var author = Jx.obj(w, "author");
                    if (my_account_id.length > 0 && Jx.str(author, "accountId") != my_account_id) continue;
                    int day = new DateTime.from_unix_local(sm / 1000).get_day_of_month();
                    int cur = totals.has_key(day) ? totals.get(day) : 0;
                    totals.set(day, cur + (int) Jx.i64(w, "timeSpentSeconds"));
                }
            }
            return totals;
        }

        // ------------------------------------------------------------------
        // Issue picker
        // ------------------------------------------------------------------
        public async bool fetch_assignable_issues() {
            if (!have_creds()) { changed(); return false; }
            string jql = cfg.issue_jql.strip();
            if (jql.length == 0) jql = "assignee = currentUser() AND statusCategory != Done";
            int max = int.max(10, int.min(200, cfg.issue_max));
            string url = site() + "/rest/api/3/search/jql?jql=" + Uri.escape_string(jql)
                + "&maxResults=%d".printf(max)
                + "&fields=summary,status,issuetype,timeoriginalestimate,timeestimate,timetracking";
            var r = yield jget(url);
            if (!r.ok()) return false;
            var issues = Jx.arr(Jx.parse_obj(r.body), "issues");
            var list = new Gee.ArrayList<Issue>();
            if (issues != null) {
                for (uint i = 0; i < issues.get_length(); i++) {
                    var iss = issues.get_object_element(i);
                    var f = Jx.obj(iss, "fields");
                    var it = new Issue();
                    it.key = Jx.str(iss, "key");
                    it.summary = Jx.str(f, "summary");
                    it.issuetype = Jx.str(Jx.obj(f, "issuetype"), "name");
                    it.status = Jx.str(Jx.obj(f, "status"), "name");
                    it.remaining_sec = remaining_sec(f);
                    list.add(it);
                }
            }
            assignable_issues = list;
            changed();
            return true;
        }

        // ------------------------------------------------------------------
        // Sprint info
        // ------------------------------------------------------------------
        public async bool fetch_sprint_info() {
            if (!have_creds()) { clear_sprint(); changed(); return false; }
            if (my_account_id.length == 0) {
                var me = yield jget(site() + "/rest/api/3/myself");
                if (me.ok()) my_account_id = Jx.str(Jx.parse_obj(me.body), "accountId");
            }
            string strat = cfg.sprint_strategy;
            if (strat == "agile-board") return yield sprint_agile_board();
            if (strat == "assignee-jql") return yield sprint_assignee_jql();
            return yield sprint_subtask_field();
        }

        private async bool sprint_subtask_field() {
            string field = cfg.sprint_field;
            if (field.length == 0) field = "customfield_10020";
            string jql = "issuetype in subTaskIssueTypes() AND assignee = currentUser()";
            string url = site() + "/rest/api/3/search/jql?jql=" + Uri.escape_string(jql)
                + "&maxResults=200&fields=summary,worklog,timeoriginalestimate,timeestimate,timetracking,"
                + Uri.escape_string(field);
            var r = yield jget(url);
            if (!r.ok()) { clear_sprint(); changed(); return false; }
            var issues = Jx.arr(Jx.parse_obj(r.body), "issues");
            if (issues == null || issues.get_length() == 0) { clear_sprint(); changed(); return true; }
            var active = find_active_sprint(issues, field);
            if (active == null) { clear_sprint(); changed(); return true; }
            set_active_sprint(active);
            compute_sprint_totals(issues, active, field);
            changed();
            return true;
        }

        private async bool sprint_agile_board() {
            int board = cfg.sprint_board_id;
            if (board <= 0) { last_error = "Board ID no configurado."; clear_sprint(); changed(); return false; }
            var r = yield jget(site() + "/rest/agile/1.0/board/%d/sprint?state=active".printf(board));
            if (!r.ok()) { clear_sprint(); changed(); return false; }
            var values = Jx.arr(Jx.parse_obj(r.body), "values");
            if (values == null || values.get_length() == 0) { clear_sprint(); changed(); return true; }
            var active = values.get_object_element(0);
            set_active_sprint(active);
            string jql = "sprint = %s AND assignee = currentUser()".printf(Jx.str(active, "id"));
            var r2 = yield jget(site() + "/rest/api/3/search/jql?jql=" + Uri.escape_string(jql)
                + "&maxResults=200&fields=summary,worklog,timeoriginalestimate,timeestimate,timetracking");
            if (r2.ok()) {
                var issues = Jx.arr(Jx.parse_obj(r2.body), "issues");
                if (issues != null) compute_sprint_totals(issues, active, null);
            }
            changed();
            return true;
        }

        private async bool sprint_assignee_jql() {
            string field = cfg.sprint_field;
            string jql = "sprint in openSprints() AND assignee = currentUser()";
            string url = site() + "/rest/api/3/search/jql?jql=" + Uri.escape_string(jql)
                + "&maxResults=200&fields=summary,worklog,timeoriginalestimate,timeestimate,timetracking,"
                + Uri.escape_string(field);
            var r = yield jget(url);
            if (!r.ok()) { clear_sprint(); changed(); return false; }
            var issues = Jx.arr(Jx.parse_obj(r.body), "issues");
            if (issues == null || issues.get_length() == 0) { clear_sprint(); changed(); return true; }
            var active = find_active_sprint(issues, field);
            if (active == null) { clear_sprint(); changed(); return true; }
            set_active_sprint(active);
            compute_sprint_totals(issues, active, field);
            changed();
            return true;
        }

        private Json.Object? find_active_sprint(Json.Array issues, string field) {
            for (uint i = 0; i < issues.get_length(); i++) {
                var fields = Jx.obj(issues.get_object_element(i), "fields");
                var arr = Jx.arr(fields, field);
                if (arr == null) continue;
                for (uint j = 0; j < arr.get_length(); j++) {
                    var s = arr.get_object_element(j);
                    string st = Jx.str(s, "state").down();
                    if (st == "active") return s;
                }
            }
            return null;
        }

        private void set_active_sprint(Json.Object s) {
            var sp = new Sprint();
            sp.id = Jx.i64(s, "id");
            sp.name = Jx.str(s, "name");
            sp.start_ms = Util.parse_iso(Jx.str(s, "startDate"));
            sp.end_ms = Util.parse_iso(Jx.str(s, "endDate"));
            current_sprint = sp;
        }

        private void clear_sprint() {
            current_sprint = null;
            sprint_available_sec = 0;
            sprint_consumed_sec = 0;
            sprint_breakdown = new Gee.ArrayList<BreakdownItem>();
        }

        private void compute_sprint_totals(Json.Array issues, Json.Object active, string? field) {
            int64 s_start = Util.parse_iso(Jx.str(active, "startDate"));
            int64 s_end = Util.parse_iso(Jx.str(active, "endDate"));
            int64 active_id = Jx.i64(active, "id");
            int available = 0, consumed = 0;
            var breakdown = new Gee.ArrayList<BreakdownItem>();
            for (uint k = 0; k < issues.get_length(); k++) {
                var iss = issues.get_object_element(k);
                var f = Jx.obj(iss, "fields");
                if (field != null) {
                    var arr = Jx.arr(f, field);
                    bool hit = false;
                    if (arr != null) {
                        for (uint x = 0; x < arr.get_length(); x++) {
                            if (Jx.i64(arr.get_object_element(x), "id") == active_id) { hit = true; break; }
                        }
                    }
                    if (!hit) continue;
                }
                int rem = remaining_sec(f);
                available += rem;
                if (rem > 0) {
                    var bi = new BreakdownItem();
                    bi.key = Jx.str(iss, "key");
                    bi.summary = Jx.str(f, "summary");
                    bi.remaining_sec = rem;
                    breakdown.add(bi);
                }
                var wls = Jx.arr(Jx.obj(f, "worklog"), "worklogs");
                if (wls != null) {
                    for (uint w = 0; w < wls.get_length(); w++) {
                        var wo = wls.get_object_element(w);
                        int64 sm = Util.parse_iso(Jx.str(wo, "started"));
                        if (sm < s_start || sm > s_end) continue;
                        var author = Jx.obj(wo, "author");
                        if (my_account_id.length > 0 && Jx.str(author, "accountId") != my_account_id) continue;
                        consumed += (int) Jx.i64(wo, "timeSpentSeconds");
                    }
                }
            }
            breakdown.sort((a, b) => b.remaining_sec - a.remaining_sec);
            sprint_available_sec = available;
            sprint_consumed_sec = consumed;
            sprint_breakdown = breakdown;
        }

        // ------------------------------------------------------------------
        // Subtask table
        // ------------------------------------------------------------------
        public async bool fetch_subtasks() {
            if (!have_creds()) { changed(); return false; }
            string jql = cfg.subtask_jql.strip();
            if (jql.length == 0)
                jql = "issuetype in subTaskIssueTypes() AND assignee = currentUser() AND statusCategory != Done ORDER BY updated DESC";
            string url = site() + "/rest/api/3/search/jql?jql=" + Uri.escape_string(jql)
                + "&maxResults=100&fields=summary,status,parent,timeoriginalestimate,timeestimate,timetracking";
            var r = yield jget(url);
            if (!r.ok()) return false;
            var issues = Jx.arr(Jx.parse_obj(r.body), "issues");
            var list = new Gee.ArrayList<Subtask>();
            if (issues != null) {
                for (uint i = 0; i < issues.get_length(); i++) {
                    var iss = issues.get_object_element(i);
                    var f = Jx.obj(iss, "fields");
                    var st = Jx.obj(f, "status");
                    var sc = Jx.obj(st, "statusCategory");
                    var parent = Jx.obj(f, "parent");
                    var sub = new Subtask();
                    sub.key = Jx.str(iss, "key");
                    sub.summary = Jx.str(f, "summary");
                    sub.status = Jx.str(st, "name");
                    sub.status_category = Jx.str(sc, "key");
                    sub.status_color = Jx.str(sc, "colorName");
                    sub.remaining_sec = remaining_sec(f);
                    sub.parent_key = parent != null ? Jx.str(parent, "key") : "";
                    sub.parent_summary = parent != null ? Jx.str(Jx.obj(parent, "fields"), "summary") : "";
                    list.add(sub);
                }
            }
            subtasks = list;
            changed();
            return true;
        }

        public async Gee.ArrayList<Transition> fetch_transitions(string issue_key) {
            var list = new Gee.ArrayList<Transition>();
            if (!have_creds()) return list;
            var r = yield jget(site() + "/rest/api/3/issue/" + Uri.escape_string(issue_key) + "/transitions");
            if (!r.ok()) return list;
            var arr = Jx.arr(Jx.parse_obj(r.body), "transitions");
            if (arr != null) {
                for (uint i = 0; i < arr.get_length(); i++) {
                    var t = arr.get_object_element(i);
                    var to = Jx.obj(t, "to");
                    var tr = new Transition();
                    tr.id = Jx.str(t, "id");
                    tr.name = Jx.str(t, "name");
                    tr.to_status = Jx.str(to, "name");
                    tr.to_status_color = Jx.str(Jx.obj(to, "statusCategory"), "colorName");
                    list.add(tr);
                }
            }
            return list;
        }

        public async OpResult transition_issue(string issue_key, string transition_id) {
            if (!have_creds()) return new OpResult(false, "no-creds");
            string body = "{\"transition\":{\"id\":\"%s\"}}".printf(transition_id);
            var r = yield send("POST", site() + "/rest/api/3/issue/" + Uri.escape_string(issue_key) + "/transitions", body);
            if (r.status == 204 || r.status == 200) return new OpResult(true);
            return new OpResult(false, "HTTP %d: %s".printf(r.status, extract_error(r.body)));
        }

        public string issue_web_url(string issue_key) {
            if (!cfg.has_jira_creds() || issue_key.length == 0) return "";
            return site() + "/browse/" + Uri.escape_string(issue_key);
        }

        // ------------------------------------------------------------------
        // Create / Update / Delete
        // ------------------------------------------------------------------
        public async OpResult create_worklog(string issue_key, int64 started_ms, int duration_sec, string comment) {
            if (!have_creds()) return new OpResult(false, last_error);
            var b = new Json.Builder();
            b.begin_object();
            b.set_member_name("started"); b.add_string_value(Util.fmt_jira_started(started_ms));
            b.set_member_name("timeSpentSeconds"); b.add_int_value(duration_sec);
            if (comment.length > 0) { b.set_member_name("comment"); add_comment_adf(b, comment); }
            b.end_object();
            string body = to_json(b);
            var r = yield send("POST", site() + "/rest/api/3/issue/" + Uri.escape_string(issue_key) + "/worklog", body);
            if (r.ok()) return new OpResult(true);
            return new OpResult(false, "HTTP %d: %s".printf(r.status, extract_error(r.body)));
        }

        // comment == null keeps the existing comment.
        public async OpResult update_worklog(string issue_key, string worklog_id, int64 started_ms, int duration_sec, string? comment) {
            if (!have_creds()) return new OpResult(false, last_error);
            var b = new Json.Builder();
            b.begin_object();
            b.set_member_name("started"); b.add_string_value(Util.fmt_jira_started(started_ms));
            b.set_member_name("timeSpentSeconds"); b.add_int_value(duration_sec);
            if (comment != null) { b.set_member_name("comment"); add_comment_adf(b, comment); }
            b.end_object();
            string body = to_json(b);
            var r = yield send("PUT", site() + "/rest/api/3/issue/" + Uri.escape_string(issue_key)
                + "/worklog/" + Uri.escape_string(worklog_id), body);
            if (r.status == 200) return new OpResult(true);
            return new OpResult(false, "HTTP %d: %s".printf(r.status, extract_error(r.body)));
        }

        public async OpResult delete_worklog(string issue_key, string worklog_id) {
            if (!have_creds()) return new OpResult(false, last_error);
            var r = yield send("DELETE", site() + "/rest/api/3/issue/" + Uri.escape_string(issue_key)
                + "/worklog/" + Uri.escape_string(worklog_id), null);
            if (r.status == 204 || r.status == 200) return new OpResult(true);
            return new OpResult(false, "HTTP %d: %s".printf(r.status, extract_error(r.body)));
        }

        // ------------------------------------------------------------------
        // Helpers
        // ------------------------------------------------------------------
        private int remaining_sec(Json.Object? f) {
            if (f == null) return 0;
            string mode = cfg.remaining_mode;
            var tt = Jx.obj(f, "timetracking");
            if (mode == "calculated") {
                int orig = Jx.has_num(f, "timeoriginalestimate")
                    ? (int) Jx.i64(f, "timeoriginalestimate")
                    : (tt != null && Jx.has_num(tt, "originalEstimateSeconds") ? (int) Jx.i64(tt, "originalEstimateSeconds") : 0);
                int spent = (tt != null && Jx.has_num(tt, "timeSpentSeconds")) ? (int) Jx.i64(tt, "timeSpentSeconds") : 0;
                return int.max(0, orig - spent);
            }
            if (tt != null && Jx.has_num(tt, "remainingEstimateSeconds")) return (int) Jx.i64(tt, "remainingEstimateSeconds");
            if (Jx.has_num(f, "timeestimate")) return (int) Jx.i64(f, "timeestimate");
            return 0;
        }

        private void add_comment_adf(Json.Builder b, string text) {
            b.begin_object();
            b.set_member_name("type"); b.add_string_value("doc");
            b.set_member_name("version"); b.add_int_value(1);
            b.set_member_name("content");
            b.begin_array();
            b.begin_object();
            b.set_member_name("type"); b.add_string_value("paragraph");
            b.set_member_name("content");
            b.begin_array();
            b.begin_object();
            b.set_member_name("type"); b.add_string_value("text");
            b.set_member_name("text"); b.add_string_value(text);
            b.end_object();
            b.end_array();
            b.end_object();
            b.end_array();
            b.end_object();
        }

        // Concatenate every text node of an ADF tree.
        private string extract_adf(Json.Node? node) {
            if (node == null) return "";
            if (node.get_node_type() == Json.NodeType.VALUE
                && node.get_value_type() == typeof(string)) {
                return node.get_string() ?? "";
            }
            if (node.get_node_type() != Json.NodeType.OBJECT) return "";
            var o = node.get_object();
            string type = Jx.str(o, "type");
            if (type == "text") return Jx.str(o, "text");
            var content = Jx.arr(o, "content");
            var sb = new StringBuilder();
            if (content != null) {
                for (uint i = 0; i < content.get_length(); i++) {
                    sb.append(extract_adf(content.get_element(i)));
                }
            }
            if (type == "paragraph") sb.append("\n");
            return sb.str;
        }

        private string extract_error(string body) {
            if (body.length == 0) return "";
            var o = Jx.parse_obj(body);
            if (o != null) {
                var ems = Jx.arr(o, "errorMessages");
                if (ems != null && ems.get_length() > 0) {
                    var parts = new StringBuilder();
                    for (uint i = 0; i < ems.get_length(); i++) {
                        if (i > 0) parts.append("; ");
                        parts.append(ems.get_string_element(i));
                    }
                    return parts.str;
                }
                if (o.has_member("message")) return Jx.str(o, "message");
            }
            return body.length > 240 ? body.substring(0, 240) : body;
        }

        private string to_json(Json.Builder b) {
            var gen = new Json.Generator();
            gen.set_root(b.get_root());
            return gen.to_data(null);
        }

        private void log(string msg) {
            debug_log += msg + "\n";
            if (debug_log.length > 80000) debug_log = debug_log.substring(debug_log.length - 40000);
            if (cfg.debug) stdout.printf("[JiraWorklog %d] %s\n", instance, msg);
        }
        public void clear_debug_log() { debug_log = ""; changed(); }
    }
}
