# Changelog

## 1.0.0

Primera versión de **Worklog Calendar** para GTK 4 / libadwaita (Vala),
reescritura nativa para Ubuntu 24.04 del plasmoide KDE
`Jira / Clockify Worklog Calendar`.

### Añadido

- **Aplicación de escritorio** (Adw.Application) con ventana principal
  redimensionable.
- **Ventanita flotante** de 1000×700 abierta desde el **reloj blanco** de la
  barra superior (StatusNotifierItem + com.canonical.dbusmenu, sin AppIndicator
  GTK3), con botón para saltar a la app completa.
- **Ejecución en segundo plano**: cerrar oculta las ventanas; salir sólo desde
  *clic derecho en el reloj → Salir* (o `Ctrl+Q`).
- **La planilla**: grilla semanal Cairo con modo 9h/24h, drag-to-create,
  clic-para-editar, mover y redimensionar bloques, duplicar.
- **Tres fuentes**: Jira, Clockify y combinado (día partido).
- **Anillos** de Sprint y Horas con animación de llenado.
- **Heatmap mensual** Clockify + Jira con navegación de mes.
- **Tabla de subtareas** con búsqueda, badges de estado y transiciones.
- **Sync Jira → Clockify** con deduplicación por solape.
- **Stores async** sobre libsoup3 + json-glib (Jira REST v3, Clockify REST v1).
- **Preferencias** completas (Adw.PreferencesWindow) sobre **GSettings**.
- **Instalación** con Meson + `install.sh`, esquema/desktop/iconos incluidos.
- Documentación en `docs/` (configuración, Jira, Clockify).
