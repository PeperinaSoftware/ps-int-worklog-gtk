# Worklog Calendar (GTK) — Release 2 · Notas del port

Esta segunda release **porta a la versión GTK 4 / libadwaita (Vala)** las
features que la versión KDE (`worklog-plasmoid`, branch
`claude/github-projects-integration-7Nm8D`) sumó después del primer port. Se
tomaron los cambios de estos commits del plasmoide:

- `feat(worklog): read-only Google Calendar integration`
- `feat(worklog): up to 3 Google calendars with per-calendar colors`
- `feat(worklog): overlap-based Jira→Clockify dedup + overlap outlines`
- `feat(worklog): second Jira instance with color, tabs, per-project sync`

Todo compila limpio (`ninja`) y se probó bajo Xvfb con
`G_DEBUG=fatal-criticals` (sin *criticals*): ventana principal, ventanita
flotante y Preferencias con las nuevas páginas; y la bandeja validada por
D-Bus.

---

## 1. Segunda instancia de Jira

Ahora se pueden usar **dos cuentas de Jira a la vez**, con su propio color, que
comparten la misma región de la grilla (pueden solaparse).

- **`JiraStore` parametrizado por instancia** (`src/JiraStore.vala`): el store
  toma un `instance` (1 ó 2) y lee sus credenciales de las claves correctas
  (`jira-*` vs `jira2-*`). `Application` instancia dos stores.
- **Color por instancia**, configurable en hex: `jira1-block-color`
  (por defecto lila `#9b91e6`) y `jira2-block-color` (por defecto azul
  `#4aa3df`). Los bloques se dibujan translúcidos con ese color.
- **Ruteo por `kind`** en `CalendarGrid`: las señales pasaron de `bool is_jira`
  a `string kind` (`"jira" | "jira2" | "clockify"`). El calendario dibuja un
  segundo set de bloques Jira, y el hit-testing / mover / redimensionar /
  duplicar / editar rutean a la instancia correcta.
- **Modal de nuevo worklog con pestañas**: cuando la segunda instancia está
  habilitada, el modal de Jira muestra un selector **Jira 1 / Jira 2**; cada
  pestaña lista y registra contra su propio store. Al **editar** un bloque, el
  modal queda **bloqueado** a la instancia de ese bloque.
- **Configuración** (Preferencias → Jira): grupo *Jira 1* y grupo *Jira 2 —
  segunda instancia* (habilitar + site/email/token + color + botón *Probar*).

## 2. Sync Jira → Clockify por proyecto (mapeo por instancia)

- Se **quitó el selector de proyecto del pie**. Ahora **cada instancia de Jira
  mapea a un proyecto de Clockify** (`jira1-clockify-project-id` /
  `jira2-clockify-project-id`), configurable en **Preferencias → Clockify →
  Mapeo Jira → Clockify** (botón *Cargar proyectos* + dos combos).
- El **dedup y la creación están acotados al proyecto destino** de cada
  instancia (`ClockifyStore.sync_from_jira`): dos instancias que mapean a
  proyectos distintos **no se pisan**.
- El botón **Jira → Clockify** sincroniza **ambas instancias secuencialmente** y
  reporta los totales combinados (`creadas / ya existían / fallaron`).
- **Opción de formato con corchetes** (`sync-bracket-key`, Preferencias →
  Clockify): cuando está activada, la descripción en Clockify envuelve el código
  del issue entre corchetes → `[CP-3526]: título` en vez de `CP-3526: título`.
  El dedup usa el mismo formato, así que es consistente dentro de una misma
  configuración.

## 3. Google Calendar (solo lectura)

Integración read-only para ver tus reuniones detrás del worklog mientras cargás
horas.

- **`GoogleStore` nuevo** (`src/GoogleStore.vala`): OAuth 2.0 device-code flow.
  El *refresh token* se cambia por *access tokens* de corta vida en runtime
  (`POST /token`), y se traen los eventos de la semana de **hasta 3 calendarios**
  (`GET /calendars/{id}/events`, `singleEvents=true`). Solo scope
  `calendar.readonly`. Se ignoran eventos all-day y cancelados.
- **Bloques de fondo** en `CalendarGrid`: translúcidos, **inamovibles**, dibujados
  **detrás** de los worklogs y a **ancho completo** de la columna. La etiqueta se
  oculta cuando un bloque de worklog los tapa. **Color por calendario** (paleta).
- **Botón de toggle** en el header (calendario) para prender/apagar los eventos.
- **Autorización desde Preferencias → Google**: Client ID/secret, botón
  *Conectar* que pide el device code, abre la URL de Google, muestra el código y
  **hace polling** hasta obtener el refresh token; botón *Cargar* para listar tus
  calendarios; 3 filas de *Calendar ID* + selector de color.
- `Http` ganó `send_form()` para POST `application/x-www-form-urlencoded`
  (lo que exige el endpoint OAuth de Google).

## 4. Contornos de solape (overlap outlines)

- `CalendarGrid` calcula, **por fuente**, qué bloques se solapan en tiempo el
  mismo día y les dibuja un **contorno más grueso**: **naranja** para Jira/Jira 2,
  **dorado** para Clockify. Ayuda a detectar de un vistazo un duplicado
  (p. ej. el sync Jira → Clockify creó una entrada encima de otra).

---

## Claves de configuración nuevas (GSettings)

`jira2-enabled`, `jira2-site`, `jira2-email`, `jira2-token`,
`jira1-block-color`, `jira2-block-color`,
`jira1-clockify-project-id`, `jira2-clockify-project-id`, `sync-bracket-key`,
`google-cal-enabled`, `google-client-id`, `google-client-secret`,
`google-refresh-token`, `google-calendar-ids`, `google-calendar-colors`.

## Archivos tocados

- **Nuevo**: `src/GoogleStore.vala`, `NOTES_REL_2.md`, `docs/GOOGLE_CALENDAR.md`.
- **Modificados**: `data/…gschema.xml`, `src/Config.vala`, `src/Http.vala`,
  `src/Models.vala`, `src/JiraStore.vala`, `src/ClockifyStore.vala`,
  `src/CalendarGrid.vala`, `src/WorklogView.vala`, `src/JiraEditDialog.vala`,
  `src/PreferencesWindow.vala`, `src/Windows.vala`, `src/Application.vala`,
  `src/meson.build`, `README.md`.

## Qué NO cambió (a propósito)

- El **panel inferior** (anillos Sprint/Horas, tabla de subtareas, heatmap) sigue
  usando la **primera** instancia de Jira, igual que en el plasmoide.
- La fila de **totales por día** del grid usa la instancia 1 (la de facturación).

## Notas / limitaciones

- La autorización de Google requiere crear un cliente OAuth tipo *"TV and Limited
  Input devices"* en Google Cloud (plan gratuito). Paso a paso en
  [`docs/GOOGLE_CALENDAR.md`](docs/GOOGLE_CALENDAR.md).
- El device-flow de Google no se pudo probar de punta a punta en el entorno de
  build (requiere credenciales reales), pero el flujo replica exactamente el del
  plasmoide y la construcción de la UI se validó sin *criticals*.
