# Cómo ejecutar J-SCAN (Sprint 0 a 7)

> Para instalar la beta y probarla sin entrar en detalles técnicos, usa la
> [guía rápida](guia-rapida.md). Esta página explica el desarrollo y las pruebas.

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
6. muestra la bandeja **Textos y portapapeles** con el historial SQLite, permite
   copiar, borrar o vaciar entradas y, si está activo, copia automáticamente el
   último texto recibido al portapapeles de Windows;
7. se oculta a la bandeja del sistema al cerrar la ventana (salir desde el menú
   del icono).

Para compilar el `.exe`:

```bash
flutter build windows --release
```

El artefacto queda en
`apps/desktop_app/build/windows/x64/runner/Release/desktop_app.exe`.

### Instalador de Windows (recomendado)

El instalador usa **Inno Setup 6** y se genera por usuario, sin pedir permisos de
administrador:

```bash
# Instalar Inno Setup una sola vez
winget install JRSoftware.InnoSetup

# Desde la raíz del repo: compila la app y el instalador
powershell -ExecutionPolicy Bypass -File apps/desktop_app/tool/build_installer.ps1
```

El resultado queda en:

```text
apps/desktop_app/build/installer/JScan-Setup-0.2.0.exe
```

El script lee la versión de `pubspec.yaml`, compila la app, genera el instalador y
hace una instalación/desinstalación silenciosa de prueba en una carpeta temporal.
Con `-SkipBuild` reutiliza el build existente y con `-NoTestInstall` omite la
prueba.

El instalador:

- copia la app a `%LOCALAPPDATA%\Programs\J-SCAN`;
- crea accesos en el menú Inicio y, opcionalmente, en el escritorio;
- puede iniciar J-SCAN al iniciar sesión (desmarcado por defecto);
- registra el desinstalador en **Aplicaciones instaladas**;
- cierra una instancia abierta antes de actualizar.

La primera vez que se abre, Windows Firewall preguntará si J-SCAN puede escuchar
en la red local. Hay que permitirlo para TCP 47821 y mDNS (UDP 5353).

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

## Enviar texto y portapapeles (Sprint 3)

Con una PC ya emparejada:

1. En el celular pulsa el icono de avión de papel o la tarjeta **Texto y
   portapapeles**.
2. Escribe un mensaje o pega una URL y pulsa **Enviar texto**. La pantalla muestra
   la confirmación (`text_ack`) con el tiempo que tardó la PC.
3. **Enviar portapapeles** toma lo que tengas copiado y lo manda como
   `clipboard`; **Pegar portapapeles** solo lo trae al campo de texto.
4. En la PC, la tarjeta **Textos y portapapeles** lista cada mensaje con su
   remitente y la hora. Con **Copiar automáticamente al portapapeles** activo, el
   último texto queda listo para pegar en Windows. El historial se guarda en
   `history.sqlite` (hasta 500 entradas).

### Compartir desde otras apps

Desde Chrome, YouTube o cualquier app con **Compartir → J-SCAN**:

- si hay **una sola PC emparejada**, el texto se envía al instante y aparece en la
  PC;
- si hay cero o varias PCs, la app muestra una tarjeta con el texto compartido para
  que elijas el destino.

## Enviar archivos, fotos y videos (Sprint 4)

Con una PC ya emparejada:

1. En el celular pulsa el icono de subir archivo o la tarjeta **Archivos, fotos y
   videos**.
2. Elige **Fotos y videos** o **Cualquier archivo**. Puedes seleccionar varios a la
   vez.
3. Cada archivo aparece como una tarea con su progreso, tamaño y estado. El envío
   es secuencial para no saturar el Wi-Fi; puedes cancelar una tarea o reintentarla.
4. La PC guarda los archivos en la carpeta configurada (por defecto **Descargas**).
   La tarjeta **Archivos recibidos** muestra el progreso, la lista y dos botones:
   **Abrir** la carpeta y **Cambiar** el destino.
5. Al terminar, la PC verifica el SHA-256 y muestra un aviso. Si el Wi-Fi se corta,
   vuelve a enviar el mismo archivo: la PC responde con el `offset` recibido y el
   envío continúa desde ahí.

Para envíos largos (por ejemplo un video de 1 GB), Android mantiene un servicio en
primer plano con una notificación de progreso. Puedes cambiar de app o apagar la
pantalla sin que se cancele la transferencia.

### Compartir archivos desde otras apps

Desde Galería, Archivos o cualquier app con **Compartir → J-SCAN**:

- si hay **una sola PC emparejada**, los archivos se copian a la caché de J-SCAN y
  se encolan automáticamente;
- si hay cero o varias PCs, la app muestra una tarjeta para elegir el destino.

## Escanear documentos (Sprint 5)

No hace falta emparejar una PC: el escáner funciona solo en el celular.

1. En la pantalla principal pulsa el icono de escáner de la barra superior o la
   tarjeta **Escanear documento**.
2. Pulsa **Escanear documento**. La cámara detecta los bordes de la hoja; puedes
   ajustar el recorte a mano antes de confirmar. Repite para cada página (hasta 12
   por sesión).
3. Cada página aparece en una lista con su miniatura. Toca una para seleccionarla y
   usar la barra de filtros: **Original**, **Color** (contraste y saturación
   mejorados), **Gris** o **B/N**.
4. Usa los botones de cada página para **rotar 90°** o **eliminar**. Arrastra desde
   el icono de la izquierda para reordenar.
5. **Vista previa** abre las páginas a pantalla completa con zoom por pellizco y
   deslizamiento entre páginas.
6. El icono de la papelera en la barra superior descarta todo el escaneo tras
   confirmarlo. Al salir de la pantalla también se borran los archivos temporales.

El filtro y la rotación se aplican siempre desde la foto original, así que puedes
cambiar de filtro sin perder calidad.

## Crear el PDF y enviarlo a la PC (Sprint 6)

1. Con una o varias páginas revisadas, pulsa **Crear PDF y enviar**.
2. Escribe el nombre del archivo. Se limpian los caracteres que Android o Windows
   no permiten (`<>:"/\|?*`).
3. Elige la calidad:
   - **Alta**: 2600 px y JPEG 92, para imprimir o archivar.
   - **Equilibrada**: 1800 px y JPEG 82 (recomendada).
   - **Compacta**: 1200 px y JPEG 68, para correo o mensajería.
4. Pulsa **Crear PDF**. El PDF se genera en un isolate con una página A4 por hoja;
   las páginas horizontales usan A4 apaisado.
5. Cuando esté listo, pulsa **Enviar a la PC**. Se abre la pantalla de envío con el
   PDF ya seleccionado, el progreso, la cancelación y la reanudación del Sprint 4.
6. La PC lo muestra en **Archivos recibidos** y lo guarda con el nombre elegido.

El PDF se escribe en `jscan_exports/export_<id>/` (fuera de la carpeta de páginas)
para que siga disponible mientras se envía; las exportaciones de más de un día se
borran al crear el siguiente PDF.

También puedes añadir fotos existentes con **Importar de galería** (barra superior
o pantalla vacía). La galería no aplica detección de bordes: las imágenes se copian
tal cual y luego se les puede aplicar filtro, rotación y PDF.

> **OCR:** el PDF del Sprint 6 contiene imágenes JPEG, no texto seleccionable. El
> OCR con ML Kit queda como mejora opcional: añade una dependencia nativa de varios
> MB y debe probarse en los 5 modelos de la beta antes de incluirlo. El protocolo
> no cambia porque el PDF se envía como un archivo normal.

### Probar el flujo completo sin celular

Las pruebas automáticas cubren la generación real del PDF, la orientación, el
nombre seguro y el controlador:

```bash
cd apps/mobile_app
flutter test test/scan_pdf_test.dart test/scan_controller_test.dart
```

El criterio de «menos de 30 segundos» y la captura física solo se validan con un
celular real; usa la lista de verificación de [guia-rapida.md](guia-rapida.md).

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
# Protocolo, cifrado, emparejamiento, servidor/cliente, archivos, mDNS E2E e historial
cd packages/jscan_core
dart test

# Widgets y SQLite
cd apps/desktop_app && flutter test
cd ../mobile_app && flutter test

# Análisis estático
dart analyze            # en jscan_core
flutter analyze         # en cada app
```

La prueba `test/mdns_test.dart` levanta un servidor, lo anuncia por mDNS, lo descubre
con un navegador real, empareja un cliente y hace un ping cifrado. Es la verificación
automática del criterio del Sprint 2. `packages/jscan_core/test/server_client_test.dart`
cubre el envío cifrado de `text`/`clipboard`, su rechazo sin emparejar y el límite de
64 KiB; `apps/desktop_app/test/sqlite_history_test.dart` comprueba el historial SQLite
real sobre `winsqlite3.dll`. `packages/jscan_core/test/file_transfer_test.dart` cubre
el envío completo, la reanudación desde `.part`, el SHA-256 incorrecto, la
cancelación y el rechazo sin emparejar. En el celular,
`apps/mobile_app/test/scan_pipeline_test.dart` verifica los filtros, la rotación y la
escala; `scan_controller_test.dart` cubre la captura, la galería, el orden, los
archivos temporales, la creación real del PDF en un isolate y la limpieza;
`scan_pdf_test.dart` comprueba el nombre seguro, el número de páginas y la
orientación A4; `error_messages_test.dart` valida los mensajes claros y qué errores
se reintentan; `scan_screen_test.dart` comprueba la pantalla del escáner y el
diálogo de nombre/calidad. Los tests de widgets que usan archivos reales envuelven
la E/S en `tester.runAsync`, porque el reloj de `testWidgets` es falso.

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
| «No se pudo guardar el mensaje» | La carpeta de datos no es escribible o SQLite falló | La app cae a `history.json`; revisar permisos de la carpeta |
| El texto no aparece en la PC | La PC está en otra red o el dispositivo fue revocado | Revisar la misma Wi-Fi y volver a emparejar |
| El archivo no llega completo | El `.part` quedó de una prueba anterior o el hash no coincide | Reintentar el envío; la PC reanuda o descarta la parte inválida |
| «No se pudo crear la carpeta» | La ruta elegida no es escribible | Elegir otra carpeta con **Cambiar** |
| El envío se corta al apagar la pantalla | Android suspendió el proceso o negó la notificación | Aceptar el permiso de notificaciones y mantener el servicio en primer plano |
| «Compartir» no muestra J-SCAN | Android aún no registró el intent | Reinstalar/actualizar el APK y reiniciar el celular |
| El escáner no abre la cámara | Permiso de cámara denegado | Activarlo en Ajustes → Apps → J-SCAN → Permisos → Cámara |
| «No se pudo aplicar el filtro» | Poca memoria al procesar una foto muy grande | Cerrar otras apps y reintentar; el escáner limita el lado mayor a 2600 px |
| «No se pudo crear el PDF» | Falta de espacio o memoria al generar muchas páginas | Usar el preset **Compacta**, cerrar otras apps y comprobar el espacio libre |
| «No se pudo importar ninguna imagen» | El selector devolvió un `content://` que no se pudo copiar | Volver a elegir la imagen o probar con otra app de galería |
| El envío falla y no se reintenta solo | El error no es de red (permiso, protocolo o disco) | Leer el mensaje: si es `not_paired` o de checksum, hay que intervenir; los cortes de red se reintentan una vez |
| «No se pudo leer o escribir el archivo» | El archivo temporal se borró o falta espacio | Volver a escanear o elegir otro destino en la PC |
| El APK no se instala | Android bloquea apps desconocidas o hay una versión anterior con otra firma | Permitir la instalación para esa app y desinstalar la versión anterior si la firma cambió |
| `ISCC.exe` no encontrado al generar el instalador | Inno Setup no está instalado | `winget install JRSoftware.InnoSetup` |
| Windows muestra «aplicación desconocida» al abrir el instalador | El `.exe` no está firmado | Es esperado sin certificado de code signing; usar «Más información → Ejecutar de todas formas» |

## Estructura del monorepo

- `packages/jscan_core`: protocolo, cifrado, servidor (shelf), cliente WebSocket,
  mDNS e historial (`HistoryRepository`, JSON en memoria).
- `apps/desktop_app`: UI de Windows, QR, confirmación, bandeja, control del servidor,
  historial SQLite (`winsqlite3.dll`) y recepción de archivos con carpeta
  configurable. El instalador está en `installer/jscan.iss` y se compila con
  `tool/build_installer.ps1`.
- `apps/mobile_app`: descubrimiento, emparejamiento, lista de PCs, ping cifrado,
  envío de texto/portapapeles y de archivos, recepción de «Compartir», servicio en
  primer plano, escáner con filtros y varias páginas, importación de galería, PDF
  A4 con nombre y calidad, mensajes de error accionables y reintento automático de
  transferencias ante cortes de red.
- `docs/protocol.md`: contrato del protocolo v1 y criterios de los sprints 2, 3 y 4
  (los sprints 5, 6 y 7 no cambian el protocolo: el escáner y el PDF son locales y
  el PDF se envía como un archivo normal).
- `docs/guia-rapida.md`: instalación, flujo completo, permisos, solución de
  problemas y lista de verificación de la beta.
- `docs/architecture.md`: decisiones técnicas.
- `docs/wireframes.md`: pantallas de los sprints 2 a 6.
