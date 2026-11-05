# Protocolo J-SCAN v1

Define cómo se anuncian, se encuentran, se emparejan y se hablan la PC y el celular.
La versión de cable sigue siendo **v1**; el Sprint 2 hace obligatorio el
emparejamiento y cifra todos los mensajes posteriores a la autenticación.

## 1. Descubrimiento (mDNS / DNS-SD)

- Tipo de servicio: `_jscan._tcp.local`
- Dominio: `local`
- Grupo multicast: `224.0.0.251:5353` (solo IPv4 en v1)
- Instancia: `J-SCAN-<id8>._jscan._tcp.local`, donde `<id8>` son los primeros 8
  caracteres hexadecimales del identificador del servidor.
- Host: `jscan-<id8>.local`
- Registros publicados por la PC:

| Registro | Contenido |
|---|---|
| `PTR` | `_jscan._tcp.local` → `J-SCAN-<id8>._jscan._tcp.local` |
| `SRV` | instancia → `jscan-<id8>.local`, puerto `47821` |
| `TXT` | `id`, `name`, `proto=1`, `path=/ws`, `os` |
| `A` | una entrada por cada IPv4 local distinta de loopback |

Los clientes envían la consulta `PTR _jscan._tcp.local` con el bit **QU**
(respuesta unicast) activado y escuchan en un puerto efímero. El anunciante responde
en unicast al origen de la consulta; cuando la consulta llega por multicast
(puerto 5353) responde por multicast. También se envían anuncios no solicitados al
arrancar, cada 60 s y un "goodbye" (TTL 0) al detenerse.

TTL: 4500 s para PTR/SRV/TXT y 120 s para A.

## 2. Transporte

- HTTP en `http://<host>:47821`
- WebSocket en `ws://<host>:47821/ws`
- Puerto fijo por defecto: **47821** (`JScanDefaults.port`).
- Codificación: JSON UTF-8, un mensaje por frame de texto.
- No se usa TLS: el cifrado es a nivel de aplicación con **X25519 + HKDF-SHA256 +
  ChaCha20-Poly1305**. La red local se considera hostil.

### Endpoints HTTP

`GET /health` (sin autenticación, solo informativo):

```json
{
  "status": "ok",
  "id": "3f9a1c2b",
  "name": "DESKTOP-ABC",
  "platform": "windows",
  "appVersion": "0.1.0",
  "protocolVersion": 1,
  "wsPath": "/ws",
  "time": "2026-10-31T12:00:00.000Z",
  "addresses": ["192.168.1.20"],
  "uptimeSeconds": 42,
  "sessions": 1,
  "pairingRequired": true,
  "pairingOpen": false,
  "pairedDevices": 1
}
```

`GET /api/info` devuelve exactamente la misma información que `/health`. Cualquier
otra ruta responde `404` con un sobre de error.

`pairingOpen` indica si la ventana de emparejamiento está abierta; `pairedDevices`
cuenta los dispositivos autorizados. `pairingRequired` es siempre `true` desde el
Sprint 2.

## 3. Sobre de mensaje (envelope)

Todos los frames WebSocket usan la misma forma:

```json
{
  "v": 1,
  "id": "9f1d0c8e4b7a4e6c",
  "type": "ping",
  "ts": 1793544000000,
  "payload": { "nonce": "9f1d0c8e4b7a4e6c" }
}
```

| Campo | Tipo | Descripción |
|---|---|---|
| `v` | int | Versión del protocolo. Si no es `1`, se responde `error` con `unsupported_version`. |
| `id` | string | Identificador único del mensaje (hex). Las respuestas usan el mismo `id`. |
| `type` | string | Tipo de mensaje (tabla siguiente). |
| `ts` | int | Milisegundos desde epoch UTC. |
| `payload` | object | Datos del tipo. Puede ser `{}`. |

## 4. Código QR y claves

La PC genera un QR con este formato:

```text
jscan://pair?d=<base64url(JSON sin relleno)>
```

El JSON contiene:

| Campo | Descripción |
|---|---|
| `v` | Versión del contenido del QR. Actualmente `1`. |
| `sid` | ID del servidor (el mismo de mDNS y `/health`). |
| `name` | Nombre visible de la PC. |
| `host` | IPv4 local que debe usar el celular. |
| `port` | Puerto WebSocket. |
| `spk` | Clave pública X25519 del servidor, 32 bytes en base64url. |
| `tok` | Token de emparejamiento de un solo uso, 32 bytes en base64url. |
| `exp` | Caducidad del código en milisegundos epoch UTC. |

Reglas:

- La ventana de emparejamiento dura **3 minutos** por defecto.
- El token es de un solo uso: al aceptar un dispositivo la ventana se cierra y el
  QR deja de ser válido.
- La PC pide confirmación al usuario antes de autorizar un dispositivo nuevo. La
  confirmación caduca en **1 minuto** y, si no hay respuesta, se rechaza.
- La clave privada X25519 nunca sale del dispositivo.

### Derivación de claves

El secreto compartido es `X25519(privada_local, pública_del_par)`. Sobre él se
aplican tres derivaciones HKDF-SHA256 independientes:

| Uso | Salt | Info |
|---|---|---|
| Emparejamiento | `serverId` UTF-8 | `jscan-pair-v1` |
| Prueba de identidad | `serverId` UTF-8 | `jscan-auth-v1` |
| Sesión | nonce de 32 bytes del servidor | `jscan-session-v1\|<serverId>\|<deviceId>` |

Cada conexión autenticada usa un nonce nuevo, así que la clave de sesión cambia
aunque las identidades sean estáticas.

## 5. Emparejamiento

```text
Celular                                         PC
   |  pair_hello {device, publicKey}              |
   |--------------------------------------------->|
   |  pair_challenge {nonce, serverId, ...}       |
   |<---------------------------------------------|
   |  pair_request {challenge, nonce, box}        |
   |  (token cifrado con la clave de emparejamiento)
   |--------------------------------------------->|
   |                       usuario confirma       |
   |  pair_accept {deviceId, server, proof}       |
   |<---------------------------------------------|
   |  (la PC cierra la sesión)                    |
   |  hello + challenge + auth (ver sección 6)    |
```

### `pair_hello` (celular → PC)

```json
{
  "device": {
    "id": "a1b2c3d4",
    "name": "Pixel 8",
    "platform": "android",
    "appVersion": "0.1.0"
  },
  "publicKey": "<base64url de 32 bytes>"
}
```

La PC solo acepta este mensaje si la ventana de emparejamiento está abierta.

### `pair_challenge` (PC → celular)

```json
{
  "nonce": "<base64url de 32 bytes>",
  "serverId": "3f9a1c2b",
  "serverName": "DESKTOP-ABC",
  "protocolVersion": 1,
  "expiresAt": 1793544180000
}
```

### `pair_request` (celular → PC)

```json
{
  "challenge": "<nonce del pair_challenge>",
  "nonce": "<nonce ChaCha20 de 12 bytes>",
  "box": "<ciphertext||tag en base64url>"
}
```

El texto cifrado es el JSON `{"token":"<tok del QR>"}`. Se cifra con la clave de
emparejamiento y el AAD:

```text
jscan-pair-v1|<serverId>|<challenge base64url>
```

La PC verifica el token en tiempo constante, pide confirmación al usuario y, si se
acepta, guarda el dispositivo (`deviceId`, nombre, plataforma, clave pública,
fechas). Si el token no coincide responde `invalid_token`; si el usuario rechaza o
vence la confirmación, `pairing_rejected`.

### `pair_accept` (PC → celular)

```json
{
  "deviceId": "a1b2c3d4",
  "server": {
    "id": "3f9a1c2b",
    "name": "DESKTOP-ABC",
    "platform": "windows",
    "appVersion": "0.1.0"
  },
  "proof": "<HMAC-SHA256 base64url>",
  "pairedAt": 1793544030000
}
```

`proof` autentica a la PC y evita que un intermediario falsifique la aceptación:

```text
HMAC-SHA256(pairingKey, "accept|<serverId>|<deviceId>|<challenge base64url>")
```

### `pair_reject` (PC → celular)

```json
{ "code": "pairing_rejected", "message": "El usuario de la PC rechazó el emparejamiento" }
```

Después de `pair_accept` o `pair_reject` la PC cierra la conexión. El celular guarda
la PC y vuelve a conectar con el flujo de autenticación.

## 6. Autenticación y sesión cifrada

```text
Celular                                      PC
   |  hello {device, publicKey}                |
   |------------------------------------------>|
   |  challenge {nonce, serverId, deviceId}    |
   |<------------------------------------------|
   |  auth {proof}                             |
   |------------------------------------------>|
   |  auth_ok {server, protocolVersion, ...}   |
   |<------------------------------------------|  (cifrado)
   |  encrypted(ping)                          |
   |------------------------------------------>|
   |  encrypted(pong)                          |
   |<------------------------------------------|
```

### `hello` (celular → PC)

Igual que en el Sprint 1: `device` + `publicKey`. La PC busca el `deviceId` en su
lista; si no existe o la clave pública no coincide responde `not_paired` y cierra.

### `challenge` (PC → celular)

```json
{
  "nonce": "<base64url de 32 bytes>",
  "serverId": "3f9a1c2b",
  "deviceId": "a1b2c3d4"
}
```

### `auth` (celular → PC)

```json
{ "proof": "<HMAC-SHA256 base64url>" }
```

```text
HMAC-SHA256(authKey, "auth|<serverId>|<deviceId>|<nonce base64url>")
```

La PC compara en tiempo constante. Si falla responde `bad_proof` y cierra. Si es
correcta deriva la clave de sesión y responde `auth_ok` ya cifrado.

### `auth_ok` (PC → celular, cifrado)

```json
{
  "server": {
    "id": "3f9a1c2b",
    "name": "DESKTOP-ABC",
    "platform": "windows",
    "appVersion": "0.1.0"
  },
  "protocolVersion": 1,
  "wsPath": "/ws"
}
```

### `encrypted`

Todo mensaje posterior a `auth_ok` viaja dentro de un sobre `encrypted`:

```json
{
  "v": 1,
  "id": "9f1d0c8e4b7a4e6c",
  "type": "encrypted",
  "ts": 1793544000000,
  "payload": {
    "nonce": "<base64url de 12 bytes>",
    "box": "<ciphertext||tag en base64url>"
  }
}
```

- Algoritmo: ChaCha20-Poly1305 con la clave de sesión.
- `box` es el texto cifrado seguido del tag Poly1305 de 16 bytes.
- AAD fijo: `jscan-encrypted-v1`.
- El texto plano es un sobre completo (`v`, `id`, `type`, `ts`, `payload`). El
  sobre exterior reutiliza el `id` interior para facilitar la correlación.

Reglas de la sesión autenticada:

- El servidor **cierra la conexión** si recibe un sobre no cifrado.
- Un `ping` sin emparejar responde `error` con `not_paired` y cierra la conexión.
- Cualquier `error` con `unauthorized`, `bad_proof` o `not_paired` también cierra.
- Revocar un dispositivo en la PC cierra sus sesiones activas y le impide volver a
  autenticarse.

## 7. `ping` / `pong`

`ping` (cifrado, cualquier dirección):

```json
{ "nonce": "9f1d0c8e4b7a4e6c" }
```

`pong` responde al mismo `id` y devuelve el `nonce` recibido más la hora del servidor:

```json
{ "nonce": "9f1d0c8e4b7a4e6c", "serverTime": 1793544000031 }
```

El cliente mide el RTT con su propio reloj.

## 8. `text` y `clipboard` (Sprint 3)

Texto libre y portapapeles. Viajan **siempre dentro de un sobre `encrypted`**;
un `text` o `clipboard` sin cifrar se rechaza con `not_paired` y se cierra la
conexión.

`text` (celular → PC):

```json
{
  "text": "Hola desde el móvil",
  "kind": "plain"
}
```

`clipboard` (celular → PC) usa el mismo payload:

```json
{
  "text": "https://example.com/guia",
  "kind": "link"
}
```

Reglas:

- `text` es obligatorio, no vacío y de hasta 64 KiB en UTF-8
  (`JScanDefaults.maxTextBytes`). Si se excede, se responde
  `error`/`invalid_payload` y la sesión continúa.
- `kind` es opcional (`plain` o `link`); si falta, la PC lo infiere: una única
  URL `http(s)` se marca como `link`.
- La PC guarda cada mensaje en su historial persistente y lo emite a la UI.
- La PC confirma con el mismo `id` del mensaje:

`text_ack` / `clipboard_ack` (PC → celular, cifrado):

```json
{
  "historyId": "9f1d0c8e4b7a4e6c",
  "kind": "link",
  "receivedAt": 1793544000123
}
```

`historyId` identifica la entrada guardada en la PC y `receivedAt` es la hora
del servidor. El celular considera entregado el mensaje al recibir el ack.

## 9. `error`

```json
{ "code": "invalid_message", "message": "payload.device is required" }
```

Códigos implementados:

| Código | Significado |
|---|---|
| `invalid_message` | JSON o sobre mal formado. |
| `unsupported_version` | `v` distinto de `1`; se cierra la conexión. |
| `unsupported_type` | Tipo desconocido o fuera de orden. |
| `invalid_payload` | Faltan campos o tienen un formato inválido. |
| `internal_error` | Fallo inesperado del servidor. |
| `not_paired` | El dispositivo no está autorizado. |
| `unauthorized` | Mensaje no cifrado, MAC inválido o descifrado fallido. |
| `pairing_closed` | La ventana de emparejamiento está cerrada. |
| `pairing_expired` | El QR caducó. |
| `pairing_rejected` | El usuario de la PC rechazó el dispositivo. |
| `invalid_token` | El token del QR no coincide. |
| `bad_proof` | La prueba HMAC no es válida. |

Reservados para sprints posteriores: `checksum_mismatch`, `file_too_large`,
`cancelled`.

## 10. Tipos reservados (no implementados aún)

`file_offer`, `file_chunk`, `file_complete`, `cancel`,
`hello_ack` (obsoleto desde el Sprint 2).

Se reservan para que clientes v1 puedan rechazarlos de forma controlada con
`unsupported_type` en lugar de romper la conexión.

## 11. Reglas de compatibilidad

1. Un cliente que reciba un `v` distinto de 1 debe cerrar la conexión tras enviar
   `error`.
2. Un tipo desconocido no cierra la conexión: se responde `error` y se continúa,
   salvo que viole una regla de seguridad.
3. Los campos extra en `payload` se ignoran (forward compatibility).
4. Los `id` de mensaje permiten correlacionar respuestas; no son únicos entre sesiones.
5. En v1 el frame máximo aceptado es 1 MiB.
6. Desde el Sprint 2 el emparejamiento es obligatorio: no existe un modo "sin
   seguridad" en la misma versión de protocolo.
7. `text` y `clipboard` solo se aceptan dentro de una sesión autenticada y
   cifrada; un cliente v1 que no los implemente puede responder
   `unsupported_type` y seguir conectado.

## 12. Criterio de aceptación del Sprint 2

Con la PC y el celular en la misma red y sin internet:

1. La PC muestra un QR de un solo uso.
2. El celular lo escanea, la PC pide confirmación y guarda el dispositivo.
3. Las conexiones posteriores se autentican con X25519 y todos los mensajes viajan
   cifrados.
4. Un dispositivo no emparejado que intenta `ping`, `hello` con otro ID o enviar
   mensajes recibe `not_paired` y la conexión se cierra.
5. La PC puede listar y revocar dispositivos; la revocación corta sus sesiones.

## 13. Criterio de aceptación del Sprint 3

Con la PC y el celular emparejados en la misma red y sin internet:

1. El celular escribe texto libre y la PC lo muestra en su bandeja en menos de
   2 segundos, con confirmación `text_ack`.
2. El botón «Enviar portapapeles» envía el contenido copiado en el celular y la
   PC lo guarda como `clipboard`.
3. Compartir un enlace desde el navegador del celular con J-SCAN lo envía
   automáticamente si hay una sola PC emparejada.
4. La PC guarda todo en su historial SQLite (`history.sqlite`) y puede copiar,
   borrar o vaciar entradas.
5. Con «Copiar automáticamente» activo, el último texto queda en el
   portapapeles de Windows.
6. Sin emparejar, el servidor responde `not_paired` y cierra la conexión.
