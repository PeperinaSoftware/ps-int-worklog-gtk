project('worklog-calendar', ['vala', 'c'],
  version: '2.0.0',
  meson_version: '>= 0.59.0',
  license: 'MIT',
)

app_id = 'io.github.peperina.WorklogCalendar'

gnome = import('gnome')

# ---- Dependencies -----------------------------------------------------------
deps = [
  dependency('glib-2.0',    version: '>= 2.66'),
  dependency('gobject-2.0'),
  dependency('gio-2.0'),
  dependency('gtk4',        version: '>= 4.10'),
  dependency('libadwaita-1', version: '>= 1.2'),
  dependency('libsoup-3.0'),
  dependency('json-glib-1.0'),
  dependency('gee-0.8'),
  meson.get_compiler('c').find_library('m', required: false),
]

# The top-bar "clock" icon is a StatusNotifierItem implemented directly over
# GDBus (TrayIcon.vala), so there is no GTK3 AppIndicator dependency to clash
# with GTK4. On GNOME/Ubuntu the indicator is rendered by the bundled
# "Ubuntu AppIndicators" extension (a StatusNotifierWatcher host).

# Silence C-side deprecation noise from generated bindings.
add_project_arguments(['-w'], language: 'c')

conf = configuration_data()
conf.set_quoted('APP_ID', app_id)
conf.set_quoted('VERSION', meson.project_version())
conf.set_quoted('GETTEXT_PACKAGE', 'worklog-calendar')
config_h = configure_file(output: 'config.h', configuration: conf)
config_dep = declare_dependency(sources: config_h)

subdir('data')
subdir('src')

gnome.post_install(
  glib_compile_schemas: true,
  gtk_update_icon_cache: true,
)
