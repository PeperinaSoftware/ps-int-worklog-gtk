# GSettings schema
install_data(
  '@0@.gschema.xml'.format(app_id),
  install_dir: get_option('datadir') / 'glib-2.0' / 'schemas',
)

# Desktop entry (APP_ID substituted into the .desktop.in template)
configure_file(
  input: 'app.desktop.in',
  output: '@0@.desktop'.format(app_id),
  configuration: { 'APP_ID': app_id },
  install: true,
  install_dir: get_option('datadir') / 'applications',
)

# Application icon (scalable, "white clock")
install_data(
  '@0@.svg'.format(app_id),
  install_dir: get_option('datadir') / 'icons' / 'hicolor' / 'scalable' / 'apps',
)

# Symbolic icon used by the top-bar tray indicator.
install_data(
  '@0@-symbolic.svg'.format(app_id),
  install_dir: get_option('datadir') / 'icons' / 'hicolor' / 'symbolic' / 'apps',
)
