/*
 * Windows.vala - the two top-level windows.
 *
 * MainWindow : full desktop application window (resizable). Header bar with a
 *              hamburger menu (Preferencias / Acerca de / Salir).
 * PopupWindow: the small 1000x700 floating "clock" window opened from the
 *              top-bar indicator. Same WorklogView, plus an "Abrir aplicación"
 *              button in the header.
 *
 * Both hide instead of quitting when "run in background" is on, so the app
 * keeps living in the tray; the only true exit is the indicator's "Salir".
 */

namespace Worklog {

    public class MainWindow : Adw.ApplicationWindow {
        private App app;
        private Config cfg;
        private WorklogView view;

        public MainWindow(App app, Config cfg, JiraStore jira, ClockifyStore clockify) {
            Object(application: app);
            this.app = app;
            this.cfg = cfg;
            set_title("Worklog Calendar");
            set_default_size(cfg.settings.get_int("window-width"), cfg.settings.get_int("window-height"));
            set_icon_name("io.github.peperina.WorklogCalendar");

            var toolbar = new Adw.ToolbarView();
            var header = new Adw.HeaderBar();
            var menu_btn = new Gtk.MenuButton();
            menu_btn.set_icon_name("open-menu-symbolic");
            menu_btn.set_menu_model(build_menu());
            header.pack_end(menu_btn);
            toolbar.add_top_bar(header);

            view = new WorklogView(cfg, jira, clockify, false);
            view.open_prefs_requested.connect(() => app.open_prefs(this));
            toolbar.set_content(view);
            set_content(toolbar);

            // Window actions.
            var prefs_action = new SimpleAction("preferences", null);
            prefs_action.activate.connect(() => app.open_prefs(this));
            add_action(prefs_action);
            var about_action = new SimpleAction("about", null);
            about_action.activate.connect(show_about);
            add_action(about_action);
            var quit_action = new SimpleAction("quit", null);
            quit_action.activate.connect(() => app.quit_app());
            add_action(quit_action);

            close_request.connect(() => {
                cfg.settings.set_int("window-width", get_width());
                cfg.settings.set_int("window-height", get_height());
                if (cfg.run_in_background) { set_visible(false); return true; }
                return false;
            });
        }

        private GLib.MenuModel build_menu() {
            var menu = new GLib.Menu();
            menu.append("Preferencias", "win.preferences");
            menu.append("Acerca de", "win.about");
            menu.append("Salir", "win.quit");
            return menu;
        }

        public void sync() { view.sync_now(); }

        private void show_about() {
            var about = new Adw.AboutWindow();
            about.set_transient_for(this);
            about.set_application_name("Worklog Calendar");
            about.set_application_icon("io.github.peperina.WorklogCalendar");
            about.set_version("1.0.0");
            about.set_developer_name("Peperina");
            about.set_comments("Vista semanal de worklogs de Jira y Clockify para GNOME / Ubuntu 24.");
            about.set_license_type(Gtk.License.MIT_X11);
            about.set_website("https://github.com/lspaninka/kde-todo-1");
            about.present();
        }
    }

    public class PopupWindow : Adw.ApplicationWindow {
        private App app;
        private Config cfg;
        private WorklogView view;

        public PopupWindow(App app, Config cfg, JiraStore jira, ClockifyStore clockify) {
            Object(application: app);
            this.app = app;
            this.cfg = cfg;
            set_title("Worklog");
            set_default_size(cfg.settings.get_int("popup-width"), cfg.settings.get_int("popup-height"));
            set_icon_name("io.github.peperina.WorklogCalendar");

            var toolbar = new Adw.ToolbarView();
            var header = new Adw.HeaderBar();
            header.set_show_title(false);
            toolbar.add_top_bar(header);

            view = new WorklogView(cfg, jira, clockify, true);
            view.open_app_requested.connect(() => { app.show_main(); set_visible(false); });
            view.open_prefs_requested.connect(() => app.open_prefs(this));
            toolbar.set_content(view);
            set_content(toolbar);

            close_request.connect(() => {
                if (cfg.run_in_background) { set_visible(false); return true; }
                return false;
            });
        }

        public void sync() { view.sync_now(); }
    }
}
