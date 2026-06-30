# Clockify

`ClockifyStore.vala` habla con la **Clockify REST API v1**
(`https://api.clockify.me/api/v1`) usando el header **`X-Api-Key`**.

## API key

1. En Clockify: **Profile → Settings → API → Generate**.
2. Pegala en **Preferencias → Clockify → API key**.
3. Tocá **Probar** — resuelve tu usuario, workspace y lista de proyectos.

El **Workspace ID** y el **User ID** se resuelven automáticamente vía
`GET /user` la primera vez y se cachean en GSettings
(`clockify-workspace-id`, `clockify-user-id`). Si dejás el workspace vacío se
usa tu workspace por defecto. Un valor inválido (p.ej. el *nombre* del
workspace en vez del id de 24 hex) se descarta y se reemplaza por el default.

## Endpoints usados

| Acción | Endpoint |
|---|---|
| Usuario + workspace | `GET /user` |
| Proyectos (con colores) | `GET /workspaces/{wid}/projects?archived=false` |
| Tags | `GET /workspaces/{wid}/tags?archived=false` |
| Entries de la semana | `GET /workspaces/{wid}/user/{uid}/time-entries?start=…&end=…` |
| Crear | `POST /workspaces/{wid}/time-entries` |
| Editar | `PUT /workspaces/{wid}/time-entries/{id}` |
| Borrar | `DELETE /workspaces/{wid}/time-entries/{id}` |

Las fechas se mandan en UTC ISO con milisegundos
(`2026-05-12T15:00:00.000Z`). Los timers en curso (sin `end`) se ignoran.

En modo **Clockify puro**, cada bloque se tiñe con el **color del proyecto** si
lo tiene; en modo **combinado** todos los bloques de Clockify son verde claro
para distinguirlos de Jira.

## Sync Jira → Clockify

En modo **Jira / Clockify** aparece el botón **Jira → Clockify** en el pie:

1. Por cada worklog de Jira de la semana, busca si ya existe una entrada de
   Clockify con la misma `description` (`CP-123: título`) cuyo rango de tiempo
   **se solape** con el del worklog.
2. Si no existe, crea una entrada nueva con el mismo `start`/`end`,
   `description`, el `projectId` elegido en el combo del pie y el `billable`
   por defecto.
3. Muestra `creadas / ya existían / fallaron` y refresca la semana.

La deduplicación por **solape** evita duplicar cuando un bloque de Jira se
alargó unos minutos.

## Debug

```bash
io.github.peperina.WorklogCalendar 2>&1 | grep '\[Clockify\]'
```
