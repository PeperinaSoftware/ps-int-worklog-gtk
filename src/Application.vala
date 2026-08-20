/*
 * Application.vala - the Adw.Application orchestrating windows, stores and the
 * top-bar indicator.
 *
 * Background behaviour: when "run in background" is on, closing a window hides
 * it (handled in Windows.vala) and the app is kept alive with hold(); the only
 * real exit is the indicator's "Salir" (or the in-app menu's Salir).
 */

namespace Worklog {

    public class App : Adw.Application {
        private Config cfg;
        private Http http;
        private JiraStore jira;
        private JiraStore jira2;
        private ClockifyStore clockify;
        private GoogleStore google;
        private TrayIcon? tray = null;
        private MainWindow? main_window = null;
        private PopupWindow? popup = null;
        private PreferencesWindow? prefs = null;
        private bool held = false;

        public App() {
            Object(application_id: "io.github.peperina.WorklogCalendar",
                   flags: ApplicationFlags.DEFAULT_FLAGS);
        }

        construct {
            cfg = new Config();
            http = new Http();
            jira = new JiraStore(cfg, http, 1);
            jira2 = new JiraStore(cfg, http, 2);
            clockify = new ClockifyStore(cfg, http);
            google = new GoogleStore(cfg, http);
        }

        public override void startup() {
            base.startup();
            load_css();

            // Only run headless (tray-backed) when the indicator is enabled.
            // With the tray off the app behaves like a normal window app:
            // closing the last window quits it (see Windows.vala), so we must
            // NOT hold() — otherwise it would linger with no window and no tray.
            if (cfg.show_tray_icon) {
                setup_tray();
                hold();
                held = true;
            }

            // Application-wide actions.
            var quit = new SimpleAction("quit", null);
            quit.activate.connect(() => quit_app());
            add_action(quit);
            set_accels_for_action("app.quit", { "<Control>q" });
        }

        public override void activate() {
            // Launched normally (or re-activated): show the main window.
            show_main();
        }

        private void setup_tray() {
            tray = new TrayIcon();
            tray.activate.connect(show_clock);       // left click
            tray.show_clock.connect(show_clock);
            tray.open_app.connect(show_main);
            tray.quit.connect(quit_app);
            tray.register();
        }

        public void show_clock() {
            if (popup == null) {
                popup = new PopupWindow(this, cfg, jira, jira2, clockify, google);
            }
            popup.present();
            popup.sync();
        }

        public void show_main() {
            if (main_window == null) {
                main_window = new MainWindow(this, cfg, jira, jira2, clockify, google);
            }
            main_window.present();
            main_window.sync();
        }

        public void open_prefs(Gtk.Window parent) {
            if (prefs == null) {
                prefs = new PreferencesWindow(parent, cfg, jira, jira2, clockify, google);
                prefs.close_request.connect(() => { prefs = null; return false; });
            }
            prefs.present();
        }

        public void quit_app() {
            if (held) { release(); held = false; }
            if (popup != null) popup.destroy();
            if (main_window != null) main_window.destroy();
            quit();
        }

        private void load_css() {
            var provider = new Gtk.CssProvider();
            provider.load_from_string("""
                .dim-line { background: alpha(@theme_fg_color, 0.10); min-height: 1px; }
                .worklog-badge { font-size: 0.8em; border-radius: 6px; padding: 1px 6px; color: white; }
                .wb-green     { background: #2ea043; }
                .wb-yellow    { background: #d29922; }
                .wb-bluegray  { background: #6e7681; }
                .wb-brown     { background: #a36a3d; }
                .wb-warmred   { background: #e5534b; }
                .wb-mediumgray{ background: #8b949e; }
                .error { color: @error_color; }
                /* Frameless drop-down popup: transparent window + rounded card
                   with a soft shadow, so it reads as a floating widget. */
                .worklog-popup { background-color: transparent; }
                .worklog-popup-card {
                    background-color: @window_bg_color;
                    border: 1px solid alpha(@window_fg_color, 0.14);
                    border-radius: 12px;
                    margin: 10px;
                    box-shadow: 0 4px 18px alpha(black, 0.5);
                }
            """);
            Gtk.StyleContext.add_provider_for_display(
                Gdk.Display.get_default(), provider, Gtk.STYLE_PROVIDER_PRIORITY_APPLICATION);
        }
    }
}
