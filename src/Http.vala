/*
 * Http.vala - tiny async HTTP helper over libsoup3.
 *
 * The stores call `yield http.send(...)` and get back an HttpResponse with the
 * status code and the raw body. All network I/O is asynchronous so the UI
 * never blocks.
 */

namespace Worklog {

    public class HttpResponse : Object {
        public int status;
        public string body;
        public HttpResponse(int status, string body) {
            this.status = status;
            this.body = body;
        }
        public bool ok() { return status >= 200 && status < 300; }
    }

    public class Http : Object {
        private Soup.Session session;

        public Http() {
            session = new Soup.Session();
            session.timeout = 45;
            session.user_agent = "WorklogCalendar/1.0 ";
        }

        // method: GET/POST/PUT/DELETE. auth_header: full "Authorization" value
        // or null. api_key: X-Api-Key value or null. body: JSON string or null.
        public async HttpResponse send(string method, string url,
                                       string? auth_header, string? api_key,
                                       string? body) {
            var msg = new Soup.Message(method, url);
            if (msg == null) return new HttpResponse(0, "URL inválida: " + url);

            var h = msg.request_headers;
            h.append("Accept", "application/json");
            if (auth_header != null) h.append("Authorization", auth_header);
            if (api_key != null) h.append("X-Api-Key", api_key);
            if (body != null) {
                var bytes = new Bytes(body.data);
                msg.set_request_body_from_bytes("application/json", bytes);
            }

            try {
                var resp = yield session.send_and_read_async(msg, Priority.DEFAULT, null);
                int status = (int) msg.status_code;
                return new HttpResponse(status, bytes_to_string(resp));
            } catch (Error e) {
                return new HttpResponse(0, e.message);
            }
        }

        private static string bytes_to_string(Bytes? b) {
            if (b == null) return "";
            unowned uint8[] data = b.get_data();
            if (data == null || data.length == 0) return "";
            var sb = new StringBuilder();
            sb.append_len((string) data, (ssize_t) data.length);
            return sb.str;
        }

        // Build the Jira Basic auth header from email + token.
        public static string basic_auth(string email, string token) {
            string raw = "%s:%s".printf(email, token);
            return "Basic " + GLib.Base64.encode(raw.data);
        }
    }
}
