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

## Módulos del Sprint 4

| Módulo | Responsabilidad |
|---|---|
| `files/file_transfer.dart` | Modelos (`FileOffer`, `FileAccept`, `FileTransferProgress`, `ReceivedFile`), validación, hash incremental y saneamiento de nombres. |
| `files/file_receiver.dart` | Recibe trozos, reanuda desde `.jscan-partial/<sha256>.part`, verifica SHA-256 y cancela. |
| `LocalServer` (`file_offer`/`file_chunk`/`file_complete`/`cancel`) | Responde `file_accept` con `offset`, guarda en la carpeta destino y responde `file_ack`/`file_done`. |
| `JScanClient.sendFile` | Calcula el hash, ofrece el archivo, envía trozos de 256 KiB, reporta progreso y se reanuda con el `offset`. |
| `desktop_app/server_controller.dart` | Carpeta de destino persistida, lista de archivos, progreso y avisos. |
| `desktop_app/screens/files_card.dart` | Progreso, archivos recibidos, abrir carpeta y cambiar destino con `file_selector`. |
| `mobile_app/screens/send_file_screen.dart` | Selección múltiple con `file_picker`, tareas, progreso, cancelación y reintento. |
| `mobile_app/platform/foreground_service.dart` + `FileTransferService.kt` | Servicio en primer plano con notificación para envíos largos. |
| `MainActivity` (`ACTION_SEND`/`ACTION_SEND_MULTIPLE`) | Copia los archivos compartidos a la caché y los entrega al controlador. |

Decisiones clave:

- **Transferencias secuenciales** en el celular: una sesión WebSocket por archivo,
  procesadas de una en una. Prioriza el ancho de banda del Wi-Fi y evita mezclar
  progresos; la cola permite cancelar sin afectar al resto.
- **Hash como identidad**: el `transferId` es el SHA-256 completo. No hace falta un
  registro en la PC para reanudar: el nombre del `.part` identifica el contenido.
- **Verificación al final**: los trozos se escriben en el `.part`; solo al recibir
  `file_complete` se comprueba tamaño y SHA-256 y se mueve al nombre definitivo.
- Los archivos recibidos se anuncian con `ServerFileProgress` y `ServerFileReceived`;
  la UI de la PC no hace polling.

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
| Archivos recibidos | carpeta configurable (por defecto `Descargas`) + `.jscan-partial/` | — |
| Preferencias | `settings.json` (copia automática y carpeta de archivos) | — |

Los IDs de servidor y dispositivo son estables desde el Sprint 2. En el Sprint 3
el historial usa SQLite a través del paquete `sqlite3`, cargando `winsqlite3.dll`
(el SQLite incluido en Windows 11). Así no se necesita el plugin nativo
`sqlite3_flutter_libs`, que exige modo desarrollador para enlazar plugins. Si la
carga falla, la PC cae automáticamente a `history.json`.

## Distribución en Windows

Se eligió **Inno Setup 6** en lugar de MSIX:

- genera un único `setup.exe` que no exige firma, certificado instalado ni modo
  desarrollador;
- se instala por usuario en `%LOCALAPPDATA%\Programs\J-SCAN` sin UAC;
- reutiliza tal cual el build portable de Flutter (DLLs + `data/`);
- incluye desinstalador, accesos directos y arranque opcional con Windows.

El script `apps/desktop_app/tool/build_installer.ps1` lee la versión de
`pubspec.yaml`, compila `flutter build windows --release`, ejecuta `ISCC.exe` y
valida el resultado con una instalación y desinstalación silenciosa en una carpeta
temporal. MSIX queda como opción futura si se necesita distribución desde la
Microsoft Store o actualizaciones administradas.

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
- Compartir desde Android captura `ACTION_SEND` y `ACTION_SEND_MULTIPLE`; el intent
  se consume una sola vez para evitar duplicados.
- Copiar al portapapeles es una preferencia local de la PC; el celular no puede
  activarla ni leer el portapapeles del PC.

Sprint 4:

- `file_offer`, `file_chunk`, `file_complete` y `cancel` solo se procesan dentro de
  un sobre `encrypted`; fuera de una sesión autenticada se responde `not_paired` y
  se cierra.
- El nombre recibido se sanea (sin rutas, caracteres reservados de Windows ni
  nombres de dispositivo) y se resuelve una ruta única dentro de la carpeta destino.
  La PC nunca escribe fuera de esa carpeta.
- El tamaño se valida antes de aceptar (máximo 8 GiB) y cada trozo se limita a
  512 KiB para no superar el frame máximo de 1 MiB.
- El SHA-256 se calcula incrementalmente en el celular y se vuelve a calcular en la
  PC mientras escribe; un hash distinto borra el `.part` y responde
  `checksum_mismatch`.
- Los `.part` se conservan solo para reanudar; al completar o cancelar se eliminan.
- Los archivos compartidos desde otras apps se copian a la caché privada de la app
  antes de leerlos; no se envían `content://` fuera del proceso.
- El servicio en primer plano de Android solo muestra una notificación de progreso;
  no mueve bytes ni concede permisos adicionales.
