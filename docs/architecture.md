# Arquitectura del monorepo

```text
J-SCAN/
├── apps/
│   ├── desktop_app/   Flutter Windows · servidor + bandeja del sistema
│   └── mobile_app/    Flutter Android · descubrimiento + ping
├── packages/
│   └── jscan_core/    Dart puro · protocolo, servidor, cliente y mDNS
├── docs/              protocolo, wireframes y esta guía
├── melos.yaml         scripts del monorepo
└── .github/           CI
```

## Por qué `jscan_core` es Dart puro

Toda la lógica que debe funcionar igual en PC y celular vive en un paquete sin
dependencias de Flutter. Eso permite:

- ejecutar las pruebas con `dart test` (rápido, sin emulador);
- usar la misma implementación de mDNS, protocolo y cliente en ambas apps;
- probar el servidor con la herramienta `tool/probe.dart` desde una terminal.

Las apps solo contienen UI, ciclo de vida de la ventana/bandeja y plugins de
plataforma.

## Capas

```text
┌────────────── mobile_app ──────────────┐   ┌────────────── desktop_app ─────────────┐
│ DiscoverScreen                         │   │ HomeScreen · TrayController            │
│ Riverpod (peers, ping, conexión)       │   │ Riverpod (servidor, sesiones, eventos) │
└───────────────────┬────────────────────┘   └───────────────────┬────────────────────┘
                    │                                            │
                    ▼                                            ▼
┌──────────────────────────── jscan_core ────────────────────────────────────────────┐
│ MdnsBrowser   JScanClient   │   LocalServer   MdnsAdvertiser   Protocolo (JSON)    │
│ (dart:io UDP) (WebSocket)   │   (shelf + shelf_web_socket)                        │
└────────────────────────────────────────────────────────────────────────────────────┘
```

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

- **Riverpod** maneja sesiones, peers y resultado de ping.
- `LocalServer` expone `Stream<ServerEvent>` y una lista inmutable de sesiones; la UI
  se suscribe y reconstruye.
- `JScanClient` correlaciona respuestas por `id` de sobre, con `Completer` por request.

## Persistencia

Aún no hay base de datos: los IDs de servidor y dispositivo son efímeros en el
Sprint 1. `drift` entra en el Sprint 3 (historial) y el ID estable en el Sprint 2
(emparejamiento).
