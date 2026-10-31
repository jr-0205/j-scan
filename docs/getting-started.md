# Cómo ejecutar J-SCAN (Sprint 0 + 1 + 2)

## Requisitos

- Flutter 3.47 o superior (Dart incluido).
- Windows 10/11 para la app de escritorio.
- Android 8+ para el celular (compilar requiere Android SDK; no incluido en el repo).
- PC y celular en la **misma red Wi-Fi/LAN**, sin necesidad de internet.
- Cámara en el celular para escanear el QR (también se puede pegar el código).

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
3. muestra la IP, el puerto, las sesiones, los dispositivos emparejados y la actividad;
4. genera el QR de emparejamiento con **Emparejar dispositivo**;
5. pide confirmación cuando un celular nuevo intenta emparejarse;
6. se oculta a la bandeja del sistema al cerrar la ventana (salir desde el menú
   del icono).

Para compilar el `.exe`:

```bash
flutter build windows --release
```

El artefacto queda en
`apps/desktop_app/build/windows/x64/runner/Release/desktop_app.exe`.

## Emparejar el celular (Sprint 2)

1. En la PC pulsa **Emparejar dispositivo**. Aparece un QR válido durante 3 minutos.
2. En el celular abre J-SCAN y pulsa **Escanear QR** (o **Pegar código** si copiaste
   el texto desde la PC).
3. Apunta la cámara al QR. El celular envía el token cifrado.
4. La PC muestra un diálogo con el nombre y la plataforma del celular. Pulsa
   **Aceptar**.
5. El celular guarda la PC y reconecta autenticado. Desde ese momento todos los
   mensajes van cifrados y el ping funciona.

El QR es de un solo uso: al aceptar, la ventana se cierra. Para otro celular, genera
un QR nuevo. Puedes revisar y revocar equipos en **Dispositivos emparejados** de la PC.

## Ejecutar la app del celular

```bash
cd apps/mobile_app
flutter run -d <id-del-dispositivo>
```

En la pantalla principal:

- pulsa el icono de refrescar o desliza hacia abajo para buscar PCs;
- cada PC encontrada muestra IP, puerto y protocolo;
- si la PC no está emparejada, **Emparejar** abre la cámara;
- si ya está emparejada, **Conectar** autentica y mide 3 pings cifrados;
- el icono de escudo abre **PCs emparejadas**, donde puedes probar o olvidar una PC.

La primera vez Android pedirá permiso de cámara. Si lo deniegas, usa **Pegar código**.

## Verificar desde la terminal

Con la app de escritorio abierta, busca PCs por mDNS:

```bash
cd packages/jscan_core
dart run tool/probe.dart
```

Para emparejar y medir el ping cifrado, copia el QR desde la PC con **Copiar código**:

```bash
dart run tool/probe.dart --pair-code "jscan://pair?d=..."
```

La PC pedirá confirmación. La herramienta guarda su identidad en
`.dart_tool/jscan_probe_identity.json`, así que la segunda vez no hace falta volver a
emparejar.

Salida esperada:

```text
Emparejando con DESKTOP-ABC (192.168.1.20:47821)...
  Emparejado. La PC guardó este dispositivo.
  auth_ok: DESKTOP-ABC (windows), cifrado activo
  ping 1: 3 ms
  ping 2: 2 ms
  ping 3: 3 ms
OK: la PC respondió con mensajes cifrados.
```

También puedes comprobar el estado sin autenticarte:

```bash
curl http://192.168.1.20:47821/health
```

Debe incluir `"pairingRequired": true`.

## Pruebas

```bash
# Protocolo, cifrado, emparejamiento, servidor/cliente y mDNS E2E
cd packages/jscan_core
dart test

# Widgets
cd apps/desktop_app && flutter test
cd ../mobile_app && flutter test

# Análisis estático
dart analyze            # en jscan_core
flutter analyze         # en cada app
```

La prueba `test/mdns_test.dart` levanta un servidor, lo anuncia por mDNS, lo descubre
con un navegador real, empareja un cliente y hace un ping cifrado. Es la verificación
automática del criterio del Sprint 2.

## Problemas frecuentes

| Síntoma | Causa probable | Solución |
|---|---|---|
| La PC no aparece | Firewall de Windows bloquea UDP 5353 o TCP 47821 | Permitir J-SCAN en el firewall o crear la regla de entrada |
| La PC no aparece | El router tiene aislamiento de clientes (AP isolation) | Desactivarlo o usar el emparejamiento pegando el código |
| Aparece “Servidor detenido” | Otra instancia ocupa el puerto 47821 | Cerrar la otra instancia; la app muestra el error |
| El QR caducó | Pasaron más de 3 minutos | Generar uno nuevo en la PC |
| `pairing_closed` al emparejar | El QR ya se usó o se cerró la ventana | Generar un QR nuevo |
| `not_paired` al conectar | La PC revocó el dispositivo o cambió su identidad | Volver a emparejar |
| `bad_proof` o `unauthorized` | Claves desincronizadas o mensaje manipulado | Olvidar la PC en el celular y emparejar de nuevo |
| La cámara no abre | Permiso denegado o sin cámara | Revisar permisos de Android o usar **Pegar código** |

## Estructura del monorepo

- `packages/jscan_core`: protocolo, cifrado, servidor (shelf), cliente WebSocket y mDNS.
- `apps/desktop_app`: UI de Windows, QR, confirmación, bandeja y control del servidor.
- `apps/mobile_app`: descubrimiento, emparejamiento, lista de PCs y ping cifrado.
- `docs/protocol.md`: contrato del protocolo v1 y del Sprint 2.
- `docs/architecture.md`: decisiones técnicas.
- `docs/wireframes.md`: pantallas de los sprints 2 a 6.
