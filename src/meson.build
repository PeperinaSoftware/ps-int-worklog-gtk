sources = files(
  'main.vala',
  'Application.vala',
  'Config.vala',
  'Util.vala',
  'Http.vala',
  'Models.vala',
  'JiraStore.vala',
  'ClockifyStore.vala',
  'GoogleStore.vala',
  'RingGauge.vala',
  'SprintGauges.vala',
  'MonthHeatmap.vala',
  'SubtaskTable.vala',
  'CalendarGrid.vala',
  'JiraEditDialog.vala',
  'ClockifyEditDialog.vala',
  'WorklogView.vala',
  'PreferencesWindow.vala',
  'Windows.vala',
  'TrayIcon.vala',
)

executable(
  app_id,
  sources,
  dependencies: deps + [config_dep],
  install: true,
)
