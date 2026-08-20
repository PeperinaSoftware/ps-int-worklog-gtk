/*
 * SubtaskTable.vala - bottom-panel subtask list (key + summary, status badge,
 * remaining hours, optional parent). Inline search; per-row menu offers status
 * transitions (fetched lazily) and "Abrir en Jira".
 */

namespace Worklog {

    public class SubtaskTable : Gtk.Box {
        private JiraStore jira;
        private Config cfg;
        private Gtk.SearchEntry search;
        private Gtk.ListBox list;
        private string filter = "";

        public signal void status_message(string msg, bool error);

        public SubtaskTable(JiraStore jira, Config cfg) {
            Object(orientation: Gtk.Orientation.VERTICAL, spacing: 4);
            this.jira = jira;
            this.cfg = cfg;
            build();
            jira.changed.connect(rebuild);
        }

        private void build() {
            var header = new Gtk.Box(Gtk.Orientation.HORIZONTAL, 6);
            var title = new Gtk.Label("Subtareas");
            title.add_css_class("heading");
            title.set_halign(Gtk.Align.START);
            header.append(title);
            var sp = new Gtk.Box(Gtk.Orientation.HORIZONTAL, 0); sp.hexpand = true;
            header.append(sp);
            search = new Gtk.SearchEntry();
            search.set_placeholder_text("Buscar…");
            search.set_width_chars(18);
            search.search_changed.connect(() => { filter = search.text.down(); rebuild(); });
            header.append(search);
            var refresh_btn = new Gtk.Button.from_icon_name("view-refresh-symbolic");
            refresh_btn.add_css_class("flat");
            refresh_btn.set_tooltip_text("Actualizar subtareas");
            refresh_btn.clicked.connect(refresh);
            header.append(refresh_btn);
            append(header);

            var scroller = new Gtk.ScrolledWindow();
            // Fixed, compact, scrolled — must NOT vexpand or it would inflate
            // the whole bottom panel and steal the calendar's vertical space.
            scroller.vexpand = false;
            scroller.set_min_content_height(96);
            scroller.set_max_content_height(150);
            scroller.set_propagate_natural_height(false);
            scroller.set_policy(Gtk.PolicyType.NEVER, Gtk.PolicyType.AUTOMATIC);
            list = new Gtk.ListBox();
            list.add_css_class("boxed-list");
            list.set_selection_mode(Gtk.SelectionMode.NONE);
            scroller.set_child(list);
            append(scroller);
            rebuild();
        }

        public void refresh() {
            jira.fetch_subtasks.begin((obj, res) => { jira.fetch_subtasks.end(res); });
        }

        private string status_class(string color_name) {
            switch (color_name) {
                case "green": return "wb-green";
                case "yellow": return "wb-yellow";
                case "blue-gray": return "wb-bluegray";
                case "brown": return "wb-brown";
                case "warm-red": return "wb-warmred";
                case "medium-gray": return "wb-mediumgray";
                default: return "wb-bluegray";
            }
        }

        private void rebuild() {
            Gtk.Widget? child = list.get_first_child();
            while (child != null) {
                var next = child.get_next_sibling();
                list.remove(child);
                child = next;
            }
            bool show_parent = cfg.subtask_show_parent;
            foreach (var s in jira.subtasks) {
                if (filter.length > 0) {
                    string hay = (s.key + " " + s.summary + " " + s.status + " " + s.parent_key + " " + s.parent_summary).down();
                    if (!hay.contains(filter)) continue;
                }
                list.append(make_row(s, show_parent));
            }
        }

        private Gtk.Widget make_row(Subtask s, bool show_parent) {
            var row = new Gtk.ListBoxRow();
            var box = new Gtk.Box(Gtk.Orientation.HORIZONTAL, 8);
            box.set_margin_start(8); box.set_margin_end(8);
            box.set_margin_top(4); box.set_margin_bottom(4);

            var keylbl = new Gtk.Label(s.key);
            keylbl.add_css_class("monospace");
            keylbl.set_width_chars(9);
            keylbl.set_xalign(0);
            box.append(keylbl);

            var sumlbl = new Gtk.Label(s.summary);
            sumlbl.set_xalign(0);
            sumlbl.set_ellipsize(Pango.EllipsizeMode.END);
            sumlbl.hexpand = true;
            box.append(sumlbl);

            if (show_parent && s.parent_key.length > 0) {
                var par = new Gtk.Label(s.parent_key);
                par.add_css_class("dim-label");
                par.set_tooltip_text(s.parent_summary);
                box.append(par);
            }

            var badge = new Gtk.Label(s.status);
            badge.add_css_class("worklog-badge");
            badge.add_css_class(status_class(s.status_color));
            box.append(badge);

            var rem = new Gtk.Label(s.remaining_sec > 0 ? Util.fmt_hm(s.remaining_sec) : "—");
            rem.set_width_chars(7);
            rem.set_xalign(1);
            box.append(rem);

            var menu_btn = new Gtk.MenuButton();
            menu_btn.set_icon_name("view-more-symbolic");
            menu_btn.add_css_class("flat");
            menu_btn.set_popover(make_row_menu(s));
            box.append(menu_btn);

            row.set_child(box);
            return row;
        }

        private Gtk.Popover make_row_menu(Subtask s) {
            var pop = new Gtk.Popover();
            var vb = new Gtk.Box(Gtk.Orientation.VERTICAL, 2);
            vb.set_margin_start(6); vb.set_margin_end(6);
            vb.set_margin_top(6); vb.set_margin_bottom(6);

            var open_btn = new Gtk.Button.with_label("Abrir en Jira");
            open_btn.add_css_class("flat");
            open_btn.set_halign(Gtk.Align.FILL);
            open_btn.clicked.connect(() => {
                string url = jira.issue_web_url(s.key);
                if (url.length > 0) {
                    try { AppInfo.launch_default_for_uri(url, null); } catch (Error e) {}
                }
                pop.popdown();
            });
            vb.append(open_btn);

            var trans_lbl = new Gtk.Label("Cambiar estado:");
            trans_lbl.add_css_class("caption");
            trans_lbl.set_halign(Gtk.Align.START);
            trans_lbl.set_margin_top(4);
            vb.append(trans_lbl);

            var trans_box = new Gtk.Box(Gtk.Orientation.VERTICAL, 2);
            var loading = new Gtk.Label("…");
            loading.add_css_class("dim-label");
            trans_box.append(loading);
            vb.append(trans_box);

            // Fetch transitions when the popover is shown.
            pop.show.connect(() => {
                jira.fetch_transitions.begin(s.key, (obj, res) => {
                    var trs = jira.fetch_transitions.end(res);
                    Gtk.Widget? c = trans_box.get_first_child();
                    while (c != null) { var n = c.get_next_sibling(); trans_box.remove(c); c = n; }
                    if (trs.size == 0) {
                        var none = new Gtk.Label("(sin transiciones)");
                        none.add_css_class("dim-label");
                        trans_box.append(none);
                        return;
                    }
                    foreach (var t in trs) {
                        var btn = new Gtk.Button.with_label(t.to_status.length > 0 ? t.to_status : t.name);
                        btn.add_css_class("flat");
                        btn.set_halign(Gtk.Align.FILL);
                        string tid = t.id;
                        string key = s.key;
                        btn.clicked.connect(() => {
                            pop.popdown();
                            status_message("Cambiando estado de %s…".printf(key), false);
                            jira.transition_issue.begin(key, tid, (o, r) => {
                                var res2 = jira.transition_issue.end(r);
                                if (res2.ok) { status_message("Estado de %s actualizado.".printf(key), false); refresh(); }
                                else status_message("No se pudo cambiar el estado: %s".printf(res2.err), true);
                            });
                        });
                        trans_box.append(btn);
                    }
                });
            });

            pop.set_child(vb);
            return pop;
        }
    }
}
