/*
 * PreferencesWindow.vala - Adwaita preferences with General / Jira / Clockify /
 * Sprint pages bound to GSettings.
 */

namespace Worklog {

    public class PreferencesWindow : Adw.PreferencesWindow {
        private Config cfg;
        private JiraStore jira;
        private JiraStore jira2;
        private ClockifyStore clockify;
        private GoogleStore google;
        private string google_device_code = "";
        private uint google_poll_id = 0;

        public PreferencesWindow(Gtk.Window parent, Config cfg, JiraStore jira, JiraStore jira2, ClockifyStore clockify, GoogleStore google) {
            Object(transient_for: parent, modal: false);
            this.cfg = cfg;
            this.jira = jira;
            this.jira2 = jira2;
            this.clockify = clockify;
            this.google = google;
            set_title("Preferencias");
            set_default_size(640, 760);
            add(build_general());
            add(build_jira());
            add(build_clockify());
            add(build_sprint());
            add(build_google());
            close_request.connect(() => {
                if (google_poll_id != 0) { Source.remove(google_poll_id); google_poll_id = 0; }
                return false;
            });
        }

        private Adw.PreferencesPage build_general() {
            var page = new Adw.PreferencesPage();
            page.set_title("General");
            page.set_icon_name("preferences-system-symbolic");

            var view = new Adw.PreferencesGroup();
            view.set_title("Vista");

            var mode = new Adw.ComboRow();
            mode.set_title("Modo de vista");
            mode.set_subtitle("Rango horario del grid");
            var mm = new Gtk.StringList({"9h (09:00–18:00)", "24h (00:00–24:00)"});
            mode.set_model(mm);
            mode.set_selected(cfg.view_mode == "24h" ? 1 : 0);
            mode.notify["selected"].connect(() => cfg.settings.set_string("view-mode", mode.get_selected() == 1 ? "24h" : "9h"));
            view.add(mode);

            var src = new Adw.ComboRow();
            src.set_title("Fuente por defecto");
            var sm = new Gtk.StringList({"Jira", "Jira / Clockify", "Clockify"});
            src.set_model(sm);
            src.set_selected(cfg.source == "clockify" ? 2 : (cfg.source == "jira-clockify" ? 1 : 0));
            src.notify["selected"].connect(() => {
                string[] v = {"jira", "jira-clockify", "clockify"};
                cfg.settings.set_string("worklog-source", v[src.get_selected()]);
            });
            view.add(src);

            view.add(spin_row("Objetivo diario (horas)", "daily-target-hours", 0, 24, 0.5, true));
            view.add(switch_row("Mostrar título del issue en los bloques", "show-issue-summary"));
            page.add(view);

            var panel = new Adw.PreferencesGroup();
            panel.set_title("Panel inferior");
            panel.add(switch_row("Mostrar panel inferior (anillos / tabla / heatmap)", "show-bottom-panel"));
            panel.add(switch_row("Habilitar la tabla de subtareas", "show-subtask-table"));
            panel.add(switch_row("Mostrar columna del issue padre", "subtask-show-parent"));
            panel.add(entry_row("JQL de subtareas", "subtask-jql"));
            page.add(panel);

            var picker = new Adw.PreferencesGroup();
            picker.set_title("Picker de issues (modal de Jira)");
            picker.add(entry_row("JQL del picker", "issue-jql"));
            picker.add(spin_row("Máximo de issues", "issue-max", 10, 200, 5, false));
            page.add(picker);

            var win = new Adw.PreferencesGroup();
            win.set_title("Ventana y comportamiento");
            win.add(switch_row("Mostrar el reloj en la barra superior", "show-tray-icon"));
            win.add(switch_row("Seguir en segundo plano al cerrar", "run-in-background"));
            win.add(spin_row("Ancho de la ventanita (popup)", "popup-width", 600, 2200, 10, false));
            win.add(spin_row("Alto de la ventanita (popup)", "popup-height", 400, 1500, 10, false));
            win.add(switch_row("Registrar peticiones en stdout (debug)", "debug"));
            page.add(win);

            return page;
        }

        private Adw.PreferencesPage build_jira() {
            var page = new Adw.PreferencesPage();
            page.set_title("Jira");
            page.set_icon_name("network-server-symbolic");

            var g = new Adw.PreferencesGroup();
            g.set_title("Jira 1 — credenciales");
            g.set_description("Generá un API token en id.atlassian.com → Security → API tokens.");
            g.add(entry_row("Site URL", "jira-site"));
            g.add(entry_row("Email", "jira-email"));
            g.add(password_row("API token", "jira-token"));
            g.add(entry_row("Color de bloques (hex)", "jira1-block-color"));
            g.add(jira_test_row(jira));
            page.add(g);

            var g2 = new Adw.PreferencesGroup();
            g2.set_title("Jira 2 — segunda instancia");
            g2.set_description("Una segunda cuenta de Jira con su propio color; comparte la grilla y puede solaparse con la primera.");
            g2.add(switch_row("Habilitar la segunda instancia", "jira2-enabled"));
            g2.add(entry_row("Site URL", "jira2-site"));
            g2.add(entry_row("Email", "jira2-email"));
            g2.add(password_row("API token", "jira2-token"));
            g2.add(entry_row("Color de bloques (hex)", "jira2-block-color"));
            g2.add(jira_test_row(jira2));
            page.add(g2);
            return page;
        }

        private Adw.ActionRow jira_test_row(JiraStore store) {
            var test = new Adw.ActionRow();
            test.set_title("Probar conexión");
            var btn = new Gtk.Button.with_label("Probar");
            btn.set_valign(Gtk.Align.CENTER);
            var lbl = new Gtk.Label("");
            btn.clicked.connect(() => {
                lbl.label = "Probando…";
                store.fetch_assignable_issues.begin((o, r) => {
                    bool ok = store.fetch_assignable_issues.end(r);
                    lbl.label = ok ? "✓ OK (%d issues)".printf(store.assignable_issues.size) : "✗ " + store.last_error;
                });
            });
            test.add_suffix(lbl);
            test.add_suffix(btn);
            return test;
        }

        private Adw.PreferencesPage build_clockify() {
            var page = new Adw.PreferencesPage();
            page.set_title("Clockify");
            page.set_icon_name("alarm-symbolic");

            var g = new Adw.PreferencesGroup();
            g.set_title("Credenciales de Clockify");
            g.set_description("Generá tu API key en Clockify → Profile → Settings → API.");
            g.add(password_row("API key", "clockify-api-key"));
            g.add(entry_row("Workspace ID (opcional)", "clockify-workspace-id"));
            g.add(switch_row("Facturable por defecto", "clockify-billable-default"));

            var test = new Adw.ActionRow();
            test.set_title("Probar conexión");
            var test_btn = new Gtk.Button.with_label("Probar");
            test_btn.set_valign(Gtk.Align.CENTER);
            var test_lbl = new Gtk.Label("");
            test_btn.clicked.connect(() => {
                test_lbl.label = "Probando…";
                clockify.ensure_context.begin((o, r) => {
                    bool ok = clockify.ensure_context.end(r);
                    test_lbl.label = ok ? "✓ OK (%d proyectos)".printf(clockify.projects.size) : "✗ " + clockify.last_error;
                });
            });
            test.add_suffix(test_lbl);
            test.add_suffix(test_btn);
            g.add(test);
            page.add(g);

            // Per-instance Jira -> Clockify project mapping.
            var map = new Adw.PreferencesGroup();
            map.set_title("Mapeo Jira → Clockify");
            map.set_description("Cada instancia de Jira se sincroniza en su propio proyecto de Clockify (evita que se pisen).");
            map.add(switch_row("Envolver el código en corchetes ([CP-3526]: título)", "sync-bracket-key"));
            var c1 = new Adw.ComboRow(); c1.set_title("Proyecto para Jira 1");
            var c2 = new Adw.ComboRow(); c2.set_title("Proyecto para Jira 2");
            var ids = new Gee.ArrayList<string>();
            var load = new Adw.ActionRow();
            load.set_title("Proyectos de Clockify");
            var load_btn = new Gtk.Button.with_label("Cargar proyectos");
            load_btn.set_valign(Gtk.Align.CENTER);
            var load_lbl = new Gtk.Label("");
            load_btn.clicked.connect(() => {
                load_lbl.label = "Cargando…";
                clockify.ensure_context.begin((o, r) => {
                    bool ok = clockify.ensure_context.end(r);
                    if (!ok) { load_lbl.label = "✗ " + clockify.last_error; return; }
                    load_lbl.label = "✓ %d".printf(clockify.projects.size);
                    fill_project_combo(c1, ids, cfg.jira_clockify_project(1), "jira1-clockify-project-id");
                    fill_project_combo(c2, ids, cfg.jira_clockify_project(2), "jira2-clockify-project-id");
                });
            });
            load.add_suffix(load_lbl);
            load.add_suffix(load_btn);
            map.add(load);
            map.add(c1);
            map.add(c2);
            page.add(map);
            return page;
        }

        private void fill_project_combo(Adw.ComboRow row, Gee.ArrayList<string> ids, string current, string key) {
            var model = new Gtk.StringList(null);
            ids.clear();
            model.append("(sin proyecto)"); ids.add("");
            int sel = 0, i = 1;
            foreach (var p in clockify.projects) {
                model.append(p.name); ids.add(p.id);
                if (p.id == current) sel = i;
                i++;
            }
            row.set_model(model);
            row.set_selected(sel);
            // Capture ids by copying, since the shared list is reused.
            var snapshot = ids.to_array();
            row.notify["selected"].connect(() => {
                uint s = row.get_selected();
                if (s < snapshot.length) cfg.settings.set_string(key, snapshot[s]);
            });
        }

        private Adw.PreferencesPage build_sprint() {
            var page = new Adw.PreferencesPage();
            page.set_title("Sprint");
            page.set_icon_name("office-chart-ring-symbolic");

            var g = new Adw.PreferencesGroup();
            g.set_title("Anillos de Sprint / Horas");

            var strat = new Adw.ComboRow();
            strat.set_title("Estrategia de descubrimiento");
            var sl = new Gtk.StringList({"subtask-customfield", "agile-board", "assignee-jql"});
            strat.set_model(sl);
            string cur = cfg.sprint_strategy;
            strat.set_selected(cur == "agile-board" ? 1 : (cur == "assignee-jql" ? 2 : 0));
            strat.notify["selected"].connect(() => {
                string[] v = {"subtask-customfield", "agile-board", "assignee-jql"};
                cfg.settings.set_string("sprint-strategy", v[strat.get_selected()]);
            });
            g.add(strat);
            g.add(entry_row("Campo del sprint (customfield)", "sprint-field"));
            g.add(spin_row("Board ID (estrategia agile-board)", "sprint-board-id", 0, 9999999, 1, false));

            var rem = new Adw.ComboRow();
            rem.set_title("Cálculo de horas restantes");
            var rl = new Gtk.StringList({"api (remainingEstimate)", "calculated (original - spent)"});
            rem.set_model(rl);
            rem.set_selected(cfg.remaining_mode == "calculated" ? 1 : 0);
            rem.notify["selected"].connect(() => cfg.settings.set_string("remaining-mode", rem.get_selected() == 1 ? "calculated" : "api"));
            g.add(rem);
            page.add(g);
            return page;
        }

        private const string[] PALETTE = {"#e74c3c", "#e67e22", "#f1c40f", "#2ecc71",
                                          "#1abc9c", "#3498db", "#9b59b6", "#e84393", "#95a5a6"};

        private Adw.PreferencesPage build_google() {
            var page = new Adw.PreferencesPage();
            page.set_title("Google");
            page.set_icon_name("x-office-calendar-symbolic");

            var g = new Adw.PreferencesGroup();
            g.set_title("Google Calendar (solo lectura)");
            g.set_description("Muestra tus eventos como bloques translúcidos detrás del worklog. Autorización de una sola vez con código de dispositivo (sin servidor local). Ver docs/GOOGLE_CALENDAR.md.");
            g.add(switch_row("Mostrar los eventos de Google Calendar", "google-cal-enabled"));
            g.add(entry_row("Client ID", "google-client-id"));
            g.add(password_row("Client secret", "google-client-secret"));
            g.add(password_row("Refresh token", "google-refresh-token"));
            page.add(g);

            var auth = new Adw.PreferencesGroup();
            auth.set_title("Autorizar");
            var status_row = new Adw.ActionRow();
            status_row.set_title("Estado");
            status_row.set_subtitle("Cargá Client ID + secret y tocá «Conectar».");
            var connect_btn = new Gtk.Button.with_label("Conectar");
            connect_btn.set_valign(Gtk.Align.CENTER);
            connect_btn.add_css_class("suggested-action");
            connect_btn.clicked.connect(() => start_google_auth(status_row));
            status_row.add_suffix(connect_btn);
            auth.add(status_row);

            var cal_status = new Adw.ActionRow();
            cal_status.set_title("Mis calendarios");
            cal_status.set_subtitle("Pegá abajo los IDs (o «primary»).");
            var load_btn = new Gtk.Button.with_label("Cargar");
            load_btn.set_valign(Gtk.Align.CENTER);
            load_btn.clicked.connect(() => {
                cal_status.set_subtitle("Cargando…");
                google.load_calendars.begin((o, r) => {
                    var list = google.load_calendars.end(r);
                    if (list.size == 0) { cal_status.set_subtitle("No pude cargar (¿autorizaste?)."); return; }
                    var sb = new StringBuilder();
                    int n = 0;
                    foreach (var e in list.entries) {
                        if (n++ > 0) sb.append("\n");
                        sb.append("%s  (%s)".printf(e.value, e.key));
                        if (n >= 8) break;
                    }
                    cal_status.set_subtitle(sb.str);
                });
            });
            cal_status.add_suffix(load_btn);
            auth.add(cal_status);
            page.add(auth);

            var cals = new Adw.PreferencesGroup();
            cals.set_title("Calendarios a mostrar (hasta 3)");
            for (int i = 0; i < 3; i++) cals.add(calendar_row(i));
            page.add(cals);
            return page;
        }

        // One calendar slot: an EntryRow for the id + a color dropdown suffix.
        private Adw.EntryRow calendar_row(int idx) {
            var row = new Adw.EntryRow();
            row.set_title("Calendar ID %d".printf(idx + 1));
            row.set_text(strv_at("google-calendar-ids", idx));
            row.changed.connect(() => set_strv_at("google-calendar-ids", idx, row.get_text().strip()));

            var drop = new Gtk.DropDown(new Gtk.StringList(PALETTE), null);
            drop.set_valign(Gtk.Align.CENTER);
            string cur = strv_at("google-calendar-colors", idx);
            for (int i = 0; i < PALETTE.length; i++) if (PALETTE[i] == cur) { drop.set_selected(i); break; }
            drop.notify["selected"].connect(() => {
                uint s = drop.get_selected();
                if (s < PALETTE.length) set_strv_at("google-calendar-colors", idx, PALETTE[s]);
            });
            row.add_suffix(drop);
            return row;
        }

        private string strv_at(string key, int idx) {
            var a = cfg.settings.get_strv(key);
            return (idx < a.length) ? a[idx] : "";
        }
        private void set_strv_at(string key, int idx, string val) {
            var a = cfg.settings.get_strv(key);
            string[] three = { idx == 0 ? val : (0 < a.length ? a[0] : ""),
                               idx == 1 ? val : (1 < a.length ? a[1] : ""),
                               idx == 2 ? val : (2 < a.length ? a[2] : "") };
            cfg.settings.set_strv(key, three);
        }

        private void start_google_auth(Adw.ActionRow status_row) {
            if (google_poll_id != 0) { Source.remove(google_poll_id); google_poll_id = 0; }
            status_row.set_subtitle("Solicitando código de dispositivo…");
            google.request_device_code.begin((o, r) => {
                var dc = google.request_device_code.end(r);
                if (!dc.ok) { status_row.set_subtitle("Error: " + dc.error); return; }
                google_device_code = dc.device_code;
                status_row.set_subtitle("Abrí %s e ingresá el código «%s». Esperando aprobación…"
                    .printf(dc.verification_url, dc.user_code));
                try { AppInfo.launch_default_for_uri(dc.verification_url, null); } catch (Error e) {}
                int64 deadline = Util.now_ms() + (int64) dc.expires_in * 1000;
                google_poll_id = Timeout.add_seconds(dc.interval, () => {
                    if (Util.now_ms() > deadline) {
                        status_row.set_subtitle("El código expiró. Volvé a intentar.");
                        google_poll_id = 0;
                        return Source.REMOVE;
                    }
                    google.poll_token.begin(google_device_code, (o2, r2) => {
                        string res = google.poll_token.end(r2);
                        if (res == "ok") {
                            status_row.set_subtitle("¡Listo! Google Calendar autorizado.");
                            if (google_poll_id != 0) { Source.remove(google_poll_id); google_poll_id = 0; }
                        } else if (res == "pending" || res == "slow_down") {
                            // keep polling
                        } else {
                            status_row.set_subtitle("Error autorizando: " + res);
                            if (google_poll_id != 0) { Source.remove(google_poll_id); google_poll_id = 0; }
                        }
                    });
                    return Source.CONTINUE;
                });
            });
        }

        // ---- row factories ----
        private Adw.SwitchRow switch_row(string title, string key) {
            var r = new Adw.SwitchRow();
            r.set_title(title);
            cfg.settings.bind(key, r, "active", SettingsBindFlags.DEFAULT);
            return r;
        }
        private Adw.EntryRow entry_row(string title, string key) {
            var r = new Adw.EntryRow();
            r.set_title(title);
            cfg.settings.bind(key, r, "text", SettingsBindFlags.DEFAULT);
            return r;
        }
        private Adw.PasswordEntryRow password_row(string title, string key) {
            var r = new Adw.PasswordEntryRow();
            r.set_title(title);
            cfg.settings.bind(key, r, "text", SettingsBindFlags.DEFAULT);
            return r;
        }
        private Adw.SpinRow spin_row(string title, string key, double min, double max, double step, bool is_double) {
            var adj = new Gtk.Adjustment(min, min, max, step, step, 0);
            var r = new Adw.SpinRow(adj, step, is_double ? 1 : 0);
            r.set_title(title);
            if (is_double) {
                // Double 'd' keys bind directly.
                cfg.settings.bind(key, adj, "value", SettingsBindFlags.DEFAULT);
            } else {
                // Int 'i' keys: GSettings.bind can't map i<->double, so wire it
                // by hand in both directions.
                adj.value = cfg.settings.get_int(key);
                adj.value_changed.connect(() => cfg.settings.set_int(key, (int) adj.value));
                cfg.settings.changed[key].connect(() => {
                    int v = cfg.settings.get_int(key);
                    if ((int) adj.value != v) adj.value = v;
                });
            }
            return r;
        }
    }
}
