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
    }
}
