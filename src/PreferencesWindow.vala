/*
 * PreferencesWindow.vala - Adwaita preferences with General / Jira / Clockify /
 * Sprint pages bound to GSettings.
 */

namespace Worklog {

    public class PreferencesWindow : Adw.PreferencesWindow {
        private Config cfg;
        private JiraStore jira;
        private ClockifyStore clockify;

        public PreferencesWindow(Gtk.Window parent, Config cfg, JiraStore jira, ClockifyStore clockify) {
            Object(transient_for: parent, modal: false);
            this.cfg = cfg;
            this.jira = jira;
            this.clockify = clockify;
            set_title("Preferencias");
            set_default_size(620, 720);
            add(build_general());
            add(build_jira());
            add(build_clockify());
            add(build_sprint());
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
            g.set_title("Credenciales de Jira Cloud");
            g.set_description("Generá un API token en id.atlassian.com → Security → API tokens.");
            g.add(entry_row("Site URL", "jira-site"));
            g.add(entry_row("Email", "jira-email"));
            g.add(password_row("API token", "jira-token"));

            var test = new Adw.ActionRow();
            test.set_title("Probar conexión");
            var test_btn = new Gtk.Button.with_label("Probar");
            test_btn.set_valign(Gtk.Align.CENTER);
            var test_lbl = new Gtk.Label("");
            test_btn.clicked.connect(() => {
                test_lbl.label = "Probando…";
                jira.fetch_assignable_issues.begin((o, r) => {
                    bool ok = jira.fetch_assignable_issues.end(r);
                    test_lbl.label = ok ? "✓ OK (%d issues)".printf(jira.assignable_issues.size) : "✗ " + jira.last_error;
                });
            });
            test.add_suffix(test_lbl);
            test.add_suffix(test_btn);
            g.add(test);
            page.add(g);
            return page;
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
            return page;
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
