# Cómo ejecutar J-SCAN (Sprint 0 + 1)

## Requisitos

- Flutter 3.47 o superior (Dart incluido).
- Windows 10/11 para la app de escritorio.
- Android 8+ para el celular (compilar requiere Android SDK; no incluido en el repo).
- PC y celular en la **misma red Wi-Fi/LAN**, sin necesidad de internet.

## Instalación

```bash
# En la raíz del repo
dart pub global activate melos
melos bootstrap
```

O sin Melos:

```bash
cd packages/jscan_core && dart pub get
cd ../../apps/desktop_app && flutter pub get
cd ../mobile_app && flutter pub get
```

## Ejecutar la app de la PC

```bash
cd apps/desktop_app
flutter run -d windows
```

La app:

1. abre el puerto fijo **47821**;
2. publica `_jscan._tcp.local` por mDNS;
3. muestra la IP, el puerto, los dispositivos conectados y la actividad;
4. se oculta a la bandeja del sistema al cerrar la ventana (salir desde el menú
   del icono).

Para compilar el `.exe`:

```bash
flutter build windows --release
```

## Ejecutar la app del celular

```bash
cd apps/mobile_app
flutter run -d <id-del-dispositivo>
```

En la pantalla principal:

- pulsa el icono de refrescar o desliza hacia abajo para buscar PCs;
- cada PC encontrada muestra IP, puerto y protocolo;
- **Probar** conecta por WebSocket, hace `hello` y mide 3 pings;
- si el router bloquea multicast, usa **Conectar por IP manualmente**.

## Verificar el Sprint 1 desde la terminal

Con la app de escritorio abierta:

```bash
cd packages/jscan_core
dart run tool/probe.dart
# o contra una IP concreta:
dart run tool/probe.dart --host 192.168.1.20 --port 47821
```

Salida esperada:

```text
Buscando PCs J-SCAN en la red local...
Encontradas 1:
  • DESKTOP-ABC — 192.168.1.20:47821 (proto 1)
Conectando con DESKTOP-ABC...
  hello_ack: DESKTOP-ABC (windows), protocolo 1
  ping 1: 3 ms
  ...
OK: la PC respondió.
```

## Pruebas

```bash
# Protocolo, servidor/cliente y mDNS de extremo a extremo
cd packages/jscan_core
dart test

# Widgets
cd apps/desktop_app && flutter test
cd ../mobile_app && flutter test
```

La prueba `test/mdns_test.dart` levanta un servidor, lo anuncia por mDNS, lo
descubre con un navegador mDNS real y le hace ping. Es la verificación automática
del criterio de aceptación del Sprint 1.

## Problemas frecuentes

| Síntoma | Causa probable | Solución |
|---|---|---|
| La PC no aparece | Firewall de Windows bloquea UDP 5353 o TCP 47821 | Permitir J-SCAN en el firewall o crear la regla de entrada |
| La PC no aparece | El router tiene aislamiento de clientes (AP isolation) | Desactivarlo o usar la conexión manual por IP |
| Aparece “Servidor detenido” | Otra instancia ocupa el puerto 47821 | Cerrar la otra instancia; la app muestra el error |
| La app de PC no anuncia | Otro servicio mDNS ocupa el puerto 5353 | La app avisa en Actividad; reiniciar el servicio conflictivo |
| El celular ve la PC pero no conecta | Red distinta o firewall | Verificar IP/puerto con la conexión manual |

## Estructura del monorepo

- `packages/jscan_core`: protocolo, servidor (shelf), cliente WebSocket y mDNS.
- `apps/desktop_app`: UI de Windows, bandeja del sistema y control del servidor.
- `apps/mobile_app`: descubrimiento, lista de PCs y prueba de conexión.
- `docs/protocol.md`: contrato del protocolo v1.
- `docs/architecture.md`: decisiones técnicas.
- `docs/wireframes.md`: pantallas de los sprints 2 a 6.
