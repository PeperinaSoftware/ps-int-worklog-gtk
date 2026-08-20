/*
 * Models.vala - plain data carriers used by the stores and the UI.
 *
 * All "started" timestamps are Unix epoch milliseconds. Durations are seconds.
 * The Worklog and ClockifyEntry share the (started, duration_sec) shape so the
 * calendar grid can render both with the same code.
 */

namespace Worklog {

    public class Worklog : Object {
        public string id = "";
        public string issue_id = "";
        public string issue_key = "";
        public string issue_summary = "";
        public int64 started = 0;       // epoch ms
        public int duration_sec = 0;
        public string comment = "";
    }

    public class ClockifyEntry : Object {
        public string id = "";
        public int64 started = 0;
        public int duration_sec = 0;
        public string description = "";
        public string project_id = "";
        public string project_name = "";
        public string project_color = "";
        public string[] tag_ids = {};
        public string[] tag_names = {};
        public bool billable = false;
    }

    public class Project : Object {
        public string id = "";
        public string name = "";
        public string color = "";
        public bool billable = false;
    }

    public class Tag : Object {
        public string id = "";
        public string name = "";
    }

    public class Issue : Object {
        public string key = "";
        public string summary = "";
        public string issuetype = "";
        public string status = "";
        public int remaining_sec = 0;
    }

    public class Subtask : Object {
        public string key = "";
        public string summary = "";
        public string status = "";
        public string status_category = "";  // new, indeterminate, done
        public string status_color = "";      // blue-gray, yellow, green, ...
        public int remaining_sec = 0;
        public string parent_key = "";
        public string parent_summary = "";
    }

    public class Sprint : Object {
        public int64 id = 0;
        public string name = "";
        public int64 start_ms = 0;
        public int64 end_ms = 0;
    }

    public class BreakdownItem : Object {
        public string key = "";
        public string summary = "";
        public int remaining_sec = 0;
    }

    // Result of a create / update / delete / transition call.
    public class OpResult : Object {
        public bool ok;
        public string err;
        public OpResult(bool ok, string err = "") {
            this.ok = ok;
            this.err = err;
        }
    }

    public class Transition : Object {
        public string id = "";
        public string name = "";
        public string to_status = "";
        public string to_status_color = "";
    }

    // Read-only Google Calendar event rendered as a background block.
    public class GEvent : Object {
        public string id = "";
        public string summary = "";
        public int64 started = 0;
        public int duration_sec = 0;
        public string calendar_id = "";
    }
}
