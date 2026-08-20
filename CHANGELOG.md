# Changelog

## 2.0.0

Port de las features que la versión KDE sumó después del primer port
(ver [NOTES_REL_2.md](NOTES_REL_2.md)):

- **Segunda instancia de Jira**: dos cuentas con color propio, modal con
  pestañas *Jira 1 / Jira 2*, ruteo por `kind` en el calendario.
- **Sync Jira → Clockify por proyecto**: cada instancia mapea a su proyecto de
  Clockify; dedup + creación acotados al proyecto; el botón sincroniza ambas
  instancias y reporta totales combinados.
- **Google Calendar (solo lectura)**: eventos como bloques translúcidos detrás
  del worklog, hasta 3 calendarios con color, toggle en el header y
  autorización OAuth por device-code en Preferencias → Google.
- **Contornos de solape**: naranja (Jira/Jira 2) / dorado (Clockify).
- También: la ventanita flotante pasó a ser un widget desplegable que se cierra
  al perder foco, y el panel inferior se achicó a la mitad.
- **Se eliminó el hueco vacío** del layout: la grilla del calendario ahora
  **estira las filas para llenar** el alto disponible (con un mínimo, así el modo
  24h sigue scrolleando), y el panel inferior dejó de robar espacio vertical
  (`vexpand` explícito en off + `Gtk.Stack` `vhomogeneous = false` + tabla de
  subtareas acotada + heatmap más chico). El panel queda pegado al pie, sin
  bandas vacías arriba ni abajo.
- **Indicador de bandeja desactivado por defecto** (`show-tray-icon = false`) por
  ahora, hasta pulir el comportamiento del app-indicator. Con la bandeja apagada
  la app funciona como un programa normal: cerrar la ventana la cierra de verdad
  (no queda en segundo plano). Se puede reactivar en Preferencias → General.

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
