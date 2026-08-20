/*
 * Config.vala - thin wrapper over the GSettings schema.
 *
 * A single instance is created by the Application and injected into the
 * stores and views. It exposes the schema's GSettings directly (so widgets
 * can `bind` against it) plus convenience getters used by the stores.
 */

namespace Worklog {

    public class Config : Object {
        public GLib.Settings settings { get; private set; }

        public Config() {
            settings = new GLib.Settings("io.github.peperina.WorklogCalendar");
        }

        // ---- Jira ----
        public string jira_site {
            owned get { return settings.get_string("jira-site").strip().chomp().replace("\\", ""); }
        }
        public string jira_site_clean {
            owned get {
                string s = settings.get_string("jira-site").strip();
                while (s.has_suffix("/")) s = s.substring(0, s.length - 1);
                return s;
            }
        }
        public string jira_email { owned get { return settings.get_string("jira-email").strip(); } }
        public string jira_token { owned get { return settings.get_string("jira-token").strip(); } }

        public bool has_jira_creds() {
            return jira_site_clean.length > 0 && jira_email.length > 0 && jira_token.length > 0;
        }

        // ---- Per-instance Jira accessors (instance 1 or 2) ----
        public bool jira2_enabled { get { return settings.get_boolean("jira2-enabled"); } }

        public string jira_site_clean_for(int inst) {
            string s = settings.get_string(inst == 2 ? "jira2-site" : "jira-site").strip();
            while (s.has_suffix("/")) s = s.substring(0, s.length - 1);
            return s;
        }
        public string jira_email_for(int inst) {
            return settings.get_string(inst == 2 ? "jira2-email" : "jira-email").strip();
        }
        public string jira_token_for(int inst) {
            return settings.get_string(inst == 2 ? "jira2-token" : "jira-token").strip();
        }
        public bool has_jira_creds_for(int inst) {
            return jira_site_clean_for(inst).length > 0
                && jira_email_for(inst).length > 0
                && jira_token_for(inst).length > 0;
        }
        public string jira_block_color(int inst) {
            return settings.get_string(inst == 2 ? "jira2-block-color" : "jira1-block-color").strip();
        }
        public string jira_clockify_project(int inst) {
            return settings.get_string(inst == 2 ? "jira2-clockify-project-id" : "jira1-clockify-project-id").strip();
        }

        // ---- Clockify ----
        public string clockify_api_key { owned get { return settings.get_string("clockify-api-key").strip(); } }
        public string clockify_workspace_id {
            owned get { return settings.get_string("clockify-workspace-id").strip(); }
            set { settings.set_string("clockify-workspace-id", value); }
        }
        public string clockify_user_id {
            owned get { return settings.get_string("clockify-user-id").strip(); }
            set { settings.set_string("clockify-user-id", value); }
        }
        public string clockify_default_project_id {
            owned get { return settings.get_string("clockify-default-project-id").strip(); }
            set { settings.set_string("clockify-default-project-id", value); }
        }
        public bool clockify_billable_default { get { return settings.get_boolean("clockify-billable-default"); } }
        public bool sync_bracket_key { get { return settings.get_boolean("sync-bracket-key"); } }

        // ---- View / behaviour ----
        public string source {
            owned get { return settings.get_string("worklog-source"); }
            set { settings.set_string("worklog-source", value); }
        }
        public string view_mode {
            owned get { return settings.get_string("view-mode"); }
            set { settings.set_string("view-mode", value); }
        }
        public double daily_target_hours { get { return settings.get_double("daily-target-hours"); } }
        public bool show_issue_summary { get { return settings.get_boolean("show-issue-summary"); } }
        public string issue_jql { owned get { return settings.get_string("issue-jql"); } }
        public int issue_max { get { return settings.get_int("issue-max"); } }

        public bool show_bottom_panel { get { return settings.get_boolean("show-bottom-panel"); } }
        public string bottom_view {
            owned get { return settings.get_string("bottom-view"); }
            set { settings.set_string("bottom-view", value); }
        }
        public bool show_subtask_table { get { return settings.get_boolean("show-subtask-table"); } }
        public string subtask_jql { owned get { return settings.get_string("subtask-jql"); } }
        public bool subtask_show_parent { get { return settings.get_boolean("subtask-show-parent"); } }

        public string sprint_strategy { owned get { return settings.get_string("sprint-strategy"); } }
        public string sprint_field { owned get { return settings.get_string("sprint-field"); } }
        public int sprint_board_id { get { return settings.get_int("sprint-board-id"); } }
        public string remaining_mode { owned get { return settings.get_string("remaining-mode"); } }

        public bool run_in_background { get { return settings.get_boolean("run-in-background"); } }
        public bool show_tray_icon { get { return settings.get_boolean("show-tray-icon"); } }
        public bool debug { get { return settings.get_boolean("debug"); } }

        // ---- Google Calendar ----
        public bool google_cal_enabled {
            get { return settings.get_boolean("google-cal-enabled"); }
            set { settings.set_boolean("google-cal-enabled", value); }
        }
        public string google_client_id { owned get { return settings.get_string("google-client-id").strip(); } }
        public string google_client_secret { owned get { return settings.get_string("google-client-secret").strip(); } }
        public string google_refresh_token {
            owned get { return settings.get_string("google-refresh-token").strip(); }
            set { settings.set_string("google-refresh-token", value); }
        }
        public string[] google_calendar_ids { owned get { return settings.get_strv("google-calendar-ids"); } }
        public string[] google_calendar_colors { owned get { return settings.get_strv("google-calendar-colors"); } }
    }
}
