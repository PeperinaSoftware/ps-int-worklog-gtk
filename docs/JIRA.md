# Jira

`JiraStore.vala` habla con la **Jira Cloud REST API v3** usando autenticación
**HTTP Basic** (email + API token, codificados en base64). Todo el I/O es
asíncrono (libsoup3).

## Credenciales

1. Andá a <https://id.atlassian.com/manage-profile/security/api-tokens>.
2. *Create API token*, copiá el valor.
3. En **Preferencias → Jira** cargá *Site URL*, *Email* y *API token*.
4. Tocá **Probar** — debería listar tus issues.

## Endpoints usados

| Acción | Endpoint |
|---|---|
| Usuario actual | `GET /rest/api/3/myself` |
| Worklogs de la semana | `GET /rest/api/3/search/jql?jql=worklogAuthor = currentUser() AND worklogDate >= … AND worklogDate <= …&fields=summary,worklog` |
| Totales del mes (heatmap) | igual, filtrado por mes |
| Picker de issues | `GET /rest/api/3/search/jql?jql=<issue-jql>&fields=summary,status,issuetype,timeoriginalestimate,timeestimate,timetracking` |
| Subtareas | `GET /rest/api/3/search/jql?jql=<subtask-jql>&fields=summary,status,parent,…` |
| Transiciones | `GET /rest/api/3/issue/<key>/transitions` y `POST` con `{transition:{id}}` |
| Crear worklog | `POST /rest/api/3/issue/<key>/worklog` |
| Editar worklog | `PUT /rest/api/3/issue/<key>/worklog/<id>` |
| Borrar worklog | `DELETE /rest/api/3/issue/<key>/worklog/<id>` |

Los worklogs se filtran del lado del cliente: sólo los **propios** (por
`accountId`) y dentro de la semana visible. Los comentarios se envían/reciben
como **ADF** de texto plano (un párrafo).

## Anillos de Sprint

El anillo **Sprint** muestra el % de tiempo transcurrido del sprint activo; el
anillo **Horas** muestra `quemadas / (disponibles + quemadas)`.

Hay tres estrategias para descubrir el sprint activo (`sprint-strategy`):

- **`subtask-customfield`** (default): busca tus subtareas y toma el sprint con
  `state = active` dentro del custom field `sprint-field` (por defecto
  `customfield_10020`). Funciona aunque las historias padre no estén asignadas
  a vos.
- **`agile-board`**: consulta
  `GET /rest/agile/1.0/board/<sprint-board-id>/sprint?state=active`. Necesita el
  *Board ID* (visible en la URL del board).
- **`assignee-jql`**: usa `sprint in openSprints() AND assignee = currentUser()`.

### Horas restantes (`remaining-mode`)

- **`api`**: confía en `remainingEstimateSeconds` de Jira.
- **`calculated`**: `max(0, originalEstimate − timeSpent)`, útil si no mantenés
  el *Remaining* al día.

## Debug

Con `debug` en `true` (default), cada request se imprime en stdout:

```bash
io.github.peperina.WorklogCalendar 2>&1 | grep '\[JiraWorklog\]'
```
