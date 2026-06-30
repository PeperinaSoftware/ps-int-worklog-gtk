# Configuración

Toda la configuración vive en **GSettings** bajo el esquema
`io.github.peperina.WorklogCalendar` (ruta
`/io/github/peperina/WorklogCalendar/`). Se edita desde la ventana de
**Preferencias** (menú hamburguesa de la app, o el ⚙ del pie de cualquiera de
las dos ventanas), o a mano con `gsettings` / `dconf-editor`.

```bash
# Ver un valor
gsettings get io.github.peperina.WorklogCalendar jira-site
# Cambiarlo
gsettings set io.github.peperina.WorklogCalendar view-mode '24h'
```

## Pestaña General

| Preferencia | Clave GSettings | Default | Notas |
|---|---|---|---|
| Modo de vista | `view-mode` | `9h` | `9h` = 09:00–18:00, `24h` = 00:00–24:00 |
| Fuente por defecto | `worklog-source` | `jira` | `jira`, `jira-clockify`, `clockify` |
| Objetivo diario (horas) | `daily-target-hours` | `8.0` | Para el diff de la fila de totales |
| Mostrar título del issue | `show-issue-summary` | `false` | Si está on, los bloques Jira muestran `CP-123: título` |
| Mostrar panel inferior | `show-bottom-panel` | `true` | Anillos / subtareas / heatmap |
| Habilitar tabla de subtareas | `show-subtask-table` | `true` | |
| Mostrar columna del padre | `subtask-show-parent` | `true` | |
| JQL de subtareas | `subtask-jql` | *(mis subtareas abiertas)* | |
| JQL del picker | `issue-jql` | *(mis issues no-Done)* | Para el modal de crear worklog |
| Máximo de issues | `issue-max` | `50` | 10–200 |
| Reloj en la barra | `show-tray-icon` | `true` | Mostrar/ocultar el indicador |
| Seguir en segundo plano | `run-in-background` | `true` | Cerrar oculta en vez de salir |
| Ancho de la ventanita | `popup-width` | `1000` | px |
| Alto de la ventanita | `popup-height` | `700` | px |
| Debug | `debug` | `true` | Loguea cada petición a stdout |

`window-width` / `window-height` guardan el tamaño de la ventana principal
(se persiste al cerrarla).

## Pestaña Jira

| Preferencia | Clave | Notas |
|---|---|---|
| Site URL | `jira-site` | p.ej. `https://tu-empresa.atlassian.net` |
| Email | `jira-email` | el de tu cuenta Atlassian |
| API token | `jira-token` | **no** es la contraseña — generalo en id.atlassian.com |

Ver [JIRA.md](JIRA.md) para detalles de los endpoints.

## Pestaña Clockify

| Preferencia | Clave | Notas |
|---|---|---|
| API key | `clockify-api-key` | Clockify → Profile → Settings → API |
| Workspace ID | `clockify-workspace-id` | opcional; se autoresuelve |
| Facturable por defecto | `clockify-billable-default` | nuevas entradas |

`clockify-user-id` y `clockify-default-project-id` se completan solos. Ver
[CLOCKIFY.md](CLOCKIFY.md).

## Pestaña Sprint

| Preferencia | Clave | Default | Notas |
|---|---|---|---|
| Estrategia | `sprint-strategy` | `subtask-customfield` | `subtask-customfield`, `agile-board`, `assignee-jql` |
| Campo del sprint | `sprint-field` | `customfield_10020` | id del custom field que tiene el array de sprints |
| Board ID | `sprint-board-id` | `0` | sólo para `agile-board` |
| Cálculo de horas restantes | `remaining-mode` | `api` | `api` (remainingEstimate) o `calculated` (original − spent) |

## Reset

```bash
gsettings reset-recursively io.github.peperina.WorklogCalendar
```
