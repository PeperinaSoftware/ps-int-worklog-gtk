# Integración con Google Calendar

La aplicación puede mostrar tus eventos de Google Calendar como **bloques
rojos translúcidos detrás del worklog**, para que veas tus reuniones
mientras cargás horas. Es **solo lectura**: nunca escribe nada en Google
(solo se pide el scope `calendar.readonly`).

Los bloques de eventos son **inamovibles** y **no seleccionables**; quedan
**por detrás** de los bloques de Jira/Clockify, así que podés cargar horas
"encima" de un evento sin problema. En modo **Jira/Clockify** el bloque
ocupa el **ancho completo** de la columna del día (las dos mitades como un
solo bloque).

Se prende/apaga con el **botón de calendario en el header**
(o desde Preferencias → Google).

---

## Por qué OAuth de "dispositivo" (sin servidor local)

Google Calendar de calendarios privados **requiere OAuth 2.0** (una API
key sola no alcanza). Como la app no levanta un
servidor web local para el `redirect_uri`, usamos el flujo **"TV and
Limited Input devices"** (device code):

1. Autorizás **una sola vez** ingresando un código corto en una página de
   Google.
2. Google devuelve un **refresh token** que la app guarda.
3. En cada sincronización, la app cambia ese refresh token por un
   **access token** de corta duración y lee los eventos.

Todo esto entra en el **plan gratuito** de Google Cloud. La API de
Calendar no tiene costo para este uso.

---

## Paso 1 — Crear el proyecto y habilitar la API (gratis)

1. Entrá a <https://console.cloud.google.com/> con tu cuenta.
2. Arriba, **Select a project → New Project**. Ponele un nombre (ej.
   `worklog-plasmoid`) y crealo.
3. Con el proyecto seleccionado, andá a **APIs & Services → Library**,
   buscá **Google Calendar API** y tocá **Enable**.

## Paso 2 — Configurar la pantalla de consentimiento

1. **APIs & Services → OAuth consent screen**.
2. Elegí **External** y **Create**.
3. Completá lo mínimo (nombre de la app, tu email de soporte, tu email de
   contacto). Guardá.
4. En **Scopes** no hace falta agregar nada (lo pide la app en runtime).
   Continuá.
5. En **Test users** agregá **tu propia dirección de Gmail**. Mientras la
   app esté en modo *Testing* solo los test users pueden autorizarla —
   con vos alcanza.
6. Guardá. **No** hace falta publicar la app ni pasar verificación de
   Google para uso personal.

## Paso 3 — Crear el cliente OAuth de tipo "dispositivo"

1. **APIs & Services → Credentials → Create Credentials → OAuth client ID**.
2. En **Application type** elegí **TVs and Limited Input devices**.
   - Si no ves esa opción, asegurate de haber completado la pantalla de
     consentimiento primero.
3. Te da un **Client ID** y un **Client secret**. Copialos.

## Paso 4 — Autorizar en el plasmoide

1. Clic derecho en el widget → **Configurar… → Google Calendar**.
2. Pegá el **Client ID** y el **Client secret**.
3. Tocá **Conectar con Google**. Se abre `google.com/device` (o se muestra
   el link) y aparece un **código corto**.
4. En la página de Google: ingresá el código, elegí tu cuenta y aceptá los
   permisos de **solo lectura** del calendario.
   - Si ves "Google no verificó esta app", entrá en **Avanzado → Ir a
     (app, no segura)**. Es tu propia app en modo testing; es esperable.
5. Al aprobar, el plasmoide completa solo el **Refresh token**. Listo.

## Paso 5 — Elegir los calendarios (hasta 3)

- Tocá **Cargar mis calendarios** y elegí hasta **3** en las filas del
  desplegable. Podés mezclar el principal y secundarios.
  - `primary` = tu calendario principal.
  - Un calendario secundario aparece con su nombre; si lo querés a mano, su
    **Calendar ID** está en Google Calendar (web) → **Configuración** del
    calendario → **Integrar calendario** → **ID del calendario** (algo como
    `...@group.calendar.google.com`).
- **Color por calendario:** al lado de cada fila hay un cuadradito de
  color. El color por defecto es el **rojo translúcido** de siempre; podés
  cambiarlo eligiendo otro de la paleta. El bloque siempre se dibuja en
  **tono translúcido** detrás del worklog, sin importar el color elegido.

## Paso 6 — Activar la vista

- En el popup, tocá el **botón de tilde arriba a la derecha** para mostrar
  u ocultar los bloques de eventos. Tocá **↻** para re-sincronizar la
  semana.

---

## Qué se guarda y dónde

Las credenciales de Google viven en el mismo `~/.config/categorizedtodorc`
que el resto de la config del plasmoide (kcfg):

| Clave kcfg            | Qué es |
| --------------------- | ------ |
| `googleCalEnabled`    | Mostrar / ocultar los bloques de eventos |
| `googleClientId`      | Client ID del cliente OAuth de dispositivo |
| `googleClientSecret`  | Client secret |
| `googleRefreshToken`  | Refresh token obtenido al autorizar |
| `googleCalendarId`    | Calendar ID legacy (solo migración; usá la lista) |
| `googleCalendarIds`   | Hasta 3 Calendar IDs a leer (lista) |
| `googleCalendarColors`| Color base por calendario (hex), dibujado translúcido |
| `googleCalDebug`      | Loggear las llamadas a Google en stdout |

La aplicación **nunca** ve tu contraseña de Google y **solo** pide el scope
`https://www.googleapis.com/auth/calendar.readonly`. Podés revocar el
acceso cuando quieras desde
<https://myaccount.google.com/permissions>.

---

## Notas y límites

- Se muestran solo eventos **con hora** (los de "todo el día" se omiten,
  no mapean a un bloque horario).
- Si un bloque de Jira/Clockify queda **encima** de un evento, el bloque
  de calendario se mantiene translúcido por detrás pero **oculta su
  texto**, para que no se solapen las letras.
- Los eventos fuera de la franja visible (modo 9h) quedan recortados
  arriba/abajo; pasá a modo 24h para verlos completos.
- La sincronización es **manual** (botón ↻) o automática al cambiar de
  semana / calendario, igual que Jira y Clockify.

## Debugging

Con `debug` activado (Preferencias → General), cada llamada a Google se
imprime en stdout:

```bash
io.github.peperina.WorklogCalendar 2>&1 | grep '\[GoogleCal\]'
```
