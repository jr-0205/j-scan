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
│ Riverpod (identidad, PCs, sesiones)    │   │ Riverpod (servidor, sesiones, eventos) │
└───────────────────┬────────────────────┘   └───────────────────┬────────────────────┘
                    │                                            │
                    ▼                                            ▼
┌──────────────────────────── jscan_core ────────────────────────────────────────────┐
│ MdnsBrowser   JScanClient   │   LocalServer   MdnsAdvertiser   Protocolo (JSON)    │
│ (dart:io UDP) (WebSocket)   │   (shelf + shelf_web_socket)                        │
│                             │   PairingManager · SessionCipher                    │
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

Los IDs de servidor y dispositivo son estables desde el Sprint 2. `drift` entra en
el Sprint 3 para el historial de transferencias.

## Seguridad

- Claves privadas X25519 estáticas por instalación; nunca se transmiten.
- Tres claves HKDF independientes para emparejamiento, autenticación y sesión.
- La clave de sesión incorpora un nonce nuevo del servidor en cada conexión.
- ChaCha20-Poly1305 autentica el contenido; el AAD evita reutilizar sobres en otro
  contexto.
- Comparaciones de tokens, MACs y claves públicas en tiempo constante.
- Revocar un dispositivo cierra sus sesiones activas y borra su autorización.
- Criterio del Sprint 2: un dispositivo no emparejado no puede enviar nada.
