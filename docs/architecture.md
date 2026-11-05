# Arquitectura del monorepo

```text
J-SCAN/
├── apps/
│   ├── desktop_app/   Flutter Windows · servidor + QR + bandeja del sistema
│   └── mobile_app/    Flutter Android · descubrimiento + emparejamiento + ping
├── packages/
│   └── jscan_core/    Dart puro · protocolo, cifrado, servidor, cliente y mDNS
├── docs/              protocolo, wireframes y esta guía
├── melos.yaml         scripts del monorepo
└── .github/           CI
```

## Por qué `jscan_core` es Dart puro

Toda la lógica que debe funcionar igual en PC y celular vive en un paquete sin
dependencias de Flutter. Eso permite:

- ejecutar las pruebas con `dart test` (rápido, sin emulador);
- usar la misma implementación de mDNS, protocolo, cifrado y cliente en ambas apps;
- probar el servidor con la herramienta `tool/probe.dart` desde una terminal.

Las apps solo contienen UI, ciclo de vida de la ventana/bandeja y plugins de
plataforma (cámara, almacenamiento seguro, QR).

## Capas

```text
┌────────────── mobile_app ──────────────┐   ┌────────────── desktop_app ─────────────┐
│ DiscoverScreen · QrScanScreen          │   │ HomeScreen · TrayController            │
│ PairedServersScreen · PairCodeDialog   │   │ QR · confirmación · dispositivos       │
│ SendTextScreen · ShareIntentChannel    │   │ InboxCard · historial · portapapeles   │
│ Riverpod (identidad, PCs, sesiones)    │   │ Riverpod (servidor, sesiones, eventos) │
└───────────────────┬────────────────────┘   └───────────────────┬────────────────────┘
                    │                                            │
                    ▼                                            ▼
┌──────────────────────────── jscan_core ────────────────────────────────────────────┐
│ MdnsBrowser   JScanClient   │   LocalServer   MdnsAdvertiser   Protocolo (JSON)    │
│ (dart:io UDP) (WebSocket)   │   (shelf + shelf_web_socket)                        │
│                             │   PairingManager · SessionCipher · HistoryRepository│
│ Crypto: X25519 · HKDF-SHA256 · ChaCha20-Poly1305 · HMAC-SHA256                    │
└────────────────────────────────────────────────────────────────────────────────────┘
```

## Módulos del Sprint 2

| Módulo | Responsabilidad |
|---|---|
| `crypto/identity.dart` | Identidad X25519 persistente (`LocalIdentity`, `LocalIdentityFile`). |
| `crypto/pairing_code.dart` | Codifica/decodifica el QR `jscan://pair?d=...` y valida su contenido. |
| `crypto/secure_channel.dart` | HKDF, HMAC, sellado y apertura de sobres, `SessionCipher`. |
| `pairing/pairing_manager.dart` | Ventana de 3 min, token de un solo uso, confirmación del usuario y prueba de aceptación. |
| `pairing/paired_device.dart` | Modelos `PairedDevice` (PC) y `PairedServer` (celular). |
| `pairing/repositories.dart` | Repositorios en memoria y persistencia JSON para la PC. |

`LocalServer` mantiene una máquina de estados por conexión:

```text
unauthenticated ──hello válido──> challenge ──auth válido──> authenticated
       │                                           ▲
       └──pair_hello──> pairing ──usuario acepta────┘
```

Solo los mensajes `pair_hello`, `pair_request`, `hello` y `auth` se aceptan en
texto plano y solo en el estado correspondiente. En `authenticated` todo debe llegar
como `encrypted`; de lo contrario la sesión se cierra.

## Módulos del Sprint 3

| Módulo | Responsabilidad |
|---|---|
| `text/text_payload.dart` | Valida `text`/`clipboard` (64 KiB máximo) y detecta enlaces. |
| `history/history_entry.dart` | Modelo `HistoryEntry` (`text`/`clipboard`, remitente y fecha). |
| `history/history_repository.dart` | Contrato `HistoryRepository` + implementaciones en memoria y JSON. |
| `LocalServer` (`text`/`clipboard`) | Guarda cada mensaje cifrado y responde `text_ack`/`clipboard_ack`. |
| `desktop_app/history/sqlite_history_repository.dart` | Historial SQLite (`winsqlite3.dll`) con tope de 500 entradas. |
| `mobile_app/platform/share_intent.dart` | Canal `jscan/share` con `MainActivity` para `ACTION_SEND`. |
| `SendTextScreen` | Envío de texto libre, pegado y envío del portapapeles. |

El servidor acepta `text` y `clipboard` únicamente después de `auth_ok`. Cada
mensaje produce un `ServerMessageReceived` con la entrada ya persistida, de modo
que la UI de la PC no necesita consultar el historial en cada evento.

## Descubrimiento sin plugins

El readme propone `bonsoir`. Para el Sprint 1 se implementó mDNS directamente con
`dart:io` (`RawDatagramSocket`) porque:

- funciona igual en Windows, Android y Linux sin plugins nativos;
- se puede probar de extremo a extremo sin emulador;
- evita dependencias con mantenimiento irregular en Windows.

El cliente consulta con el bit **QU** y escucha en un puerto efímero, así que no
necesita recibir multicast (en Android eso exigiría un `MulticastLock`). Si en pruebas
con dispositivos reales el descubrimiento falla por filtrado de multicast, se puede
añadir `multicast_lock` en `mobile_app` sin cambiar el protocolo.

## Decisiones de estado

- **Riverpod** maneja identidad, peers, PCs emparejadas, sesiones y resultados de ping.
- `LocalServer` expone `Stream<ServerEvent>` y una lista inmutable de sesiones; la UI
  se suscribe y reconstruye.
- La confirmación de emparejamiento es un callback asíncrono
  (`PairingConfirmation`). La UI de escritorio lo resuelve con un diálogo; las pruebas
  lo resuelven con `true`/`false`.
- `JScanClient` correlaciona respuestas por `id` de sobre, con `Completer` por request,
  y descifra las respuestas antes de correlacionarlas.

## Persistencia

| Dato | PC | Celular |
|---|---|---|
| Identidad X25519 | `identity.json` en el directorio de soporte de la app | `flutter_secure_storage` |
| Dispositivos autorizados | `paired_devices.json` | — |
| PCs autorizadas | — | `flutter_secure_storage` |
| Textos y portapapeles | `history.sqlite` (SQLite) | memoria de la sesión |
| Preferencias | `settings.json` (copia automática) | — |

Los IDs de servidor y dispositivo son estables desde el Sprint 2. En el Sprint 3
el historial usa SQLite a través del paquete `sqlite3`, cargando `winsqlite3.dll`
(el SQLite incluido en Windows 11). Así no se necesita el plugin nativo
`sqlite3_flutter_libs`, que exige modo desarrollador para enlazar plugins. Si la
carga falla, la PC cae automáticamente a `history.json`.

## Seguridad

- Claves privadas X25519 estáticas por instalación; nunca se transmiten.
- Tres claves HKDF independientes para emparejamiento, autenticación y sesión.
- La clave de sesión incorpora un nonce nuevo del servidor en cada conexión.
- ChaCha20-Poly1305 autentica el contenido; el AAD evita reutilizar sobres en otro
  contexto.
- Comparaciones de tokens, MACs y claves públicas en tiempo constante.
- Revocar un dispositivo cierra sus sesiones activas y borra su autorización.
- Criterio del Sprint 2: un dispositivo no emparejado no puede enviar nada.

Sprint 3:

- `text` y `clipboard` solo se procesan dentro de un sobre `encrypted`; fuera de él
  se responde `not_paired` y se cierra la conexión.
- El texto se valida antes de tocar el disco (no vacío, máximo 64 KiB en UTF-8).
- El historial SQLite se abre con `winsqlite3.dll` del propio Windows; no se
  descargan binarios nativos ni se ejecuta SQL construido con datos del celular
  (todas las consultas usan parámetros).
- Compartir desde Android captura solo `ACTION_SEND` con `text/plain`; el resto de
  tipos se ignora y el intent se consume una sola vez para evitar duplicados.
- Copiar al portapapeles es una preferencia local de la PC; el celular no puede
  activarla ni leer el portapapeles del PC.
