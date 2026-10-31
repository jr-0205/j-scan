# Protocolo J-SCAN v1

Documento del Sprint 0. Define cómo se anuncian, se encuentran y se hablan la PC y el
celular. La versión 1 cubre **descubrimiento local + ping** (Sprint 1). Las extensiones
de texto, portapapeles, archivos y escáner se listan al final para reservar sus tipos.

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
- No se usa TLS: en el Sprint 2 el cifrado será a nivel de aplicación
  (X25519 + ChaCha20-Poly1305), como decide el readme.

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
  "time": "2026-10-31T12:00:00.000Z"
}
```

`GET /api/info` devuelve lo mismo más `addresses` (IPv4 locales) y `uptimeSeconds`.

Cualquier otra ruta responde `404` con un sobre de error.

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

## 4. Tipos de mensaje v1

### `hello` (celular → PC)

```json
{
  "device": {
    "id": "a1b2c3d4",
    "name": "Pixel 8",
    "platform": "android",
    "appVersion": "0.1.0"
  }
}
```

### `hello_ack` (PC → celular)

```json
{
  "server": {
    "id": "3f9a1c2b",
    "name": "DESKTOP-ABC",
    "platform": "windows",
    "appVersion": "0.1.0"
  },
  "protocolVersion": 1,
  "wsPath": "/ws",
  "pairingRequired": false
}
```

`pairingRequired` es siempre `false` en v1; el Sprint 2 lo pondrá en `true` hasta que
el dispositivo esté emparejado.

### `ping` / `pong`

`ping` (cualquier dirección):

```json
{ "nonce": "9f1d0c8e4b7a4e6c" }
```

`pong` responde al mismo `id` y devuelve el `nonce` recibido más la hora del servidor:

```json
{ "nonce": "9f1d0c8e4b7a4e6c", "serverTime": 1793544000031 }
```

El cliente mide el RTT con su propio reloj.

### `error`

```json
{ "code": "invalid_message", "message": "payload.device is required" }
```

Códigos v1: `invalid_message`, `unsupported_version`, `unsupported_type`,
`invalid_payload`, `internal_error`. En el futuro: `not_paired`, `unauthorized`,
`checksum_mismatch`, `file_too_large`, `cancelled`.

## 5. Tipos reservados (no implementados aún)

`text`, `clipboard`, `file_offer`, `file_chunk`, `file_complete`, `cancel`,
`pair_request`, `pair_accept`, `encrypted`.

Se reservan para que clientes v1 puedan rechazarlos de forma controlada con
`unsupported_type` en lugar de romper la conexión.

## 6. Reglas de compatibilidad

1. Un cliente que reciba un `v` distinto de 1 debe cerrar la conexión tras enviar
   `error`.
2. Un tipo desconocido no cierra la conexión: se responde `error` y se continúa.
3. Los campos extra en `payload` se ignoran (forward compatibility).
4. Los `id` de mensaje permiten correlacionar respuestas; no son únicos entre sesiones.
5. Los límites de tamaño llegan con archivos (Sprint 4). En v1 el frame máximo
   aceptado es 1 MiB.

## 7. Flujo del Sprint 1

```text
Celular                                  PC
   |  mDNS PTR _jscan._tcp.local (QU)      |
   |-------------------------------------->|
   |  PTR + SRV + TXT + A (unicast)        |
   |<--------------------------------------|
   |  WebSocket connect /ws                |
   |-------------------------------------->|
   |  hello                                |
   |-------------------------------------->|
   |  hello_ack                            |
   |<--------------------------------------|
   |  ping                                 |
   |-------------------------------------->|
   |  pong (RTT medido en el celular)      |
   |<--------------------------------------|
```

**Criterio de aceptación:** con la PC y el celular en la misma red y sin internet, el
celular lista la PC y recibe un `pong` en menos de 2 s.
