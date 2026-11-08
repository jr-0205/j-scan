Con tu aprobación, avanzo con lo siguiente. Como aún no me dijiste tus sistemas, asumo **Android + Windows** primero, y iOS/Mac/Linux después (Flutter lo permite sin rehacer nada).

# Propuesta de tecnologías

| Área | Tecnología | Uso |
|---|---|---|
| Lenguaje y framework | **Flutter + Dart** | Un solo código para móvil y PC |
| Organización | **Melos** (monorepo) | Paquetes `core`, `mobile_app`, `desktop_app` |
| Estado | **Riverpod** | Estado de conexión, transferencias, historial |
| Servidor en la PC | `shelf` + `shelf_web_socket` | Recibe archivos y mensajes |
| Cliente en el celular | `dio` + `web_socket_channel` | Envío por partes con progreso |
| Descubrimiento | **bonsoir** (mDNS) | Anunciar y encontrar la PC en la red |
| Emparejamiento | `qr_flutter` (PC) + `mobile_scanner` (celular) | QR con IP, puerto y clave |
| Cifrado | `cryptography` (X25519 + ChaCha20-Poly1305) | Cifrado extremo a extremo sin certificados |
| Recibir de "Compartir" | `receive_sharing_intent` | Enviar desde cualquier app |
| Portapapeles | `flutter/services` (móvil), `super_clipboard` (PC) | Leer y escribir texto/imágenes |
| Escáner | `cunning_document_scanner` (ML Kit en Android, VisionKit en iOS) | Bordes, recorte y filtros |
| Procesar imagen | `image` (+ OpenCV si hace falta) | Filtros y compresión |
| PDF | `pdf` + `printing` | PDFs de varias páginas |
| OCR (opcional) | `google_mlkit_text_recognition` | PDF con texto buscable |
| Base de datos | **drift** (SQLite) | Dispositivos emparejados e historial |
| Segundo plano | `flutter_foreground_task` | Envíos largos con pantalla apagada |
| Ventana de PC | `window_manager`, `tray_manager`, `launch_at_startup` | Bandeja del sistema e inicio automático |
| Instalador | MSIX o Inno Setup | Distribución en Windows |
| Pruebas y CI | `flutter_test`, `integration_test`, `mocktail`, GitHub Actions | Calidad automática |

**Decisión clave de seguridad:** usar cifrado a nivel de aplicación (clave compartida en el QR) en vez de TLS con certificados autofirmados, porque es mucho más simple de implementar en Dart y igual de seguro para este caso.

# Sprints (2 semanas cada uno)

## Sprint 0: Preparación (1 semana)
- Crear repositorio, monorepo con Melos y CI básico.
- Definir el **protocolo** en un documento: tipos de mensaje (texto, archivo, ping), formato de partes, errores.
- Wireframes de 5 pantallas: emparejar, inicio, enviar, escáner, historial.
- **Listo cuando:** compila "hola mundo" en Android y Windows desde el mismo repo.

## Sprint 1: Conexión local
- Servidor en la PC en un puerto fijo, con ícono en bandeja.
- Anuncio y descubrimiento por mDNS.
- Celular lista las PCs encontradas y envía un "ping".
- **Listo cuando:** el celular ve la PC y recibe respuesta, sin internet.

## Sprint 2: Emparejamiento y seguridad
- PC muestra QR; el celular lo escanea y guarda la clave.
- Intercambio de claves y cifrado de todos los mensajes.
- Pantalla para ver y borrar dispositivos emparejados.
- La PC pide confirmación al aceptar un dispositivo nuevo.
- **Listo cuando:** un dispositivo no emparejado no puede enviar nada.

## Sprint 3: Texto y portapapeles
- Botón "enviar portapapeles" y campo de texto libre.
- Opción en el menú "Compartir" del celular para enviar texto o enlaces.
- La PC copia al portapapeles o lo muestra en una lista, según configuración.
- Historial guardado en SQLite.
- **Listo cuando:** compartes un texto desde el navegador del celular y aparece en la PC en menos de 2 segundos.

## Sprint 4: Archivos y multimedia
- Envío por partes con progreso, cancelación y verificación SHA-256.
- Reanudación si se corta la conexión.
- Selección múltiple de archivos, fotos y videos; "Compartir" para archivos.
- Carpeta de destino configurable en la PC y notificación al terminar.
- Servicio en primer plano para envíos largos.
- **Listo cuando:** un video de 1 GB llega íntegro y se reanuda tras desconectar el Wi-Fi.

## Sprint 5: Escáner (parte 1)
- Captura con detección automática de bordes y corrección de perspectiva.
- Varias páginas, recorte manual, rotar, reordenar y eliminar.
- Filtros: original, color mejorado, escala de grises, blanco y negro.
- **Listo cuando:** escaneas 3 páginas de un documento y se ven rectas y legibles.

## Sprint 6: Escáner (parte 2) y PDF
- Generación de PDF de varias páginas, con nombre editable y control de calidad/tamaño.
- Botón "Enviar a la PC" directo desde el escáner.
- Importar imágenes desde la galería.
- OCR opcional para PDF buscable.
- **Listo cuando:** del celular al PC, de la hoja física al PDF recibido, en menos de 30 segundos.

## Sprint 7: Pulido y lanzamiento beta
- Pruebas en al menos 5 modelos de celular y 2 tipos de red.
- Manejo de errores claros, reconexión automática, permisos bien explicados.
- Instalador de Windows y APK de prueba.
- Guía rápida de uso para los primeros usuarios.
- **Listo cuando:** 5 personas ajenas al desarrollo logran emparejar y enviar sin ayuda.

# Resumen

| Sprint | Entregable principal |
|---|---|
| 0 | Base del proyecto y protocolo |
| 1 | Celular encuentra la PC |
| 2 | Emparejamiento cifrado |
| 3 | Texto y portapapeles |
| 4 | Archivos y multimedia |
| 5 | Escáner básico |
| 6 | PDF y envío desde el escáner |
| 7 | Beta lista |

**Total: unas 15 semanas (≈ 3.5 meses)** para una sola persona. Con dos desarrolladores se puede hacer en paralelo la app de PC y el escáner a partir del Sprint 3.

Si quieres, puedo pasar todo esto a un documento editable, o detallar las tareas técnicas del Sprint 1 para que arranques de inmediato.

---

# Estado del repositorio

Sprint 0, Sprint 1, Sprint 2, Sprint 3 y Sprint 4 implementados:

- monorepo con Melos (`packages/jscan_core`, `apps/desktop_app`, `apps/mobile_app`);
- protocolo v1 documentado en [docs/protocol.md](docs/protocol.md), incluidos el
  emparejamiento, el cifrado, `text`/`clipboard` y la transferencia de archivos;
- servidor local con puerto fijo, mDNS, bandeja del sistema y UI de actividad;
- app móvil que descubre PCs, lista IP/puerto y prueba la conexión con ping;
- **Sprint 2**: QR de un solo uso, identidades X25519 persistentes, HKDF-SHA256,
  ChaCha20-Poly1305 en todos los mensajes autenticados, confirmación en la PC y
  gestión/revocación de dispositivos emparejados;
- un dispositivo no emparejado recibe `not_paired` y la conexión se cierra;
- **Sprint 3**: envío cifrado de texto libre y portapapeles desde el celular,
  confirmación `text_ack`/`clipboard_ack`, recepción de `ACTION_SEND` («Compartir»),
  historial SQLite en la PC (máximo 500 entradas) y copia automática al portapapeles
  de Windows;
- **Sprint 4**: envío por partes con progreso, cancelación y verificación SHA-256;
  reanudación desde `.jscan-partial` tras cortar la conexión; selección múltiple de
  archivos/fotos/videos en el celular; carpeta de destino configurable y recordada en
  la PC; notificación al terminar; «Compartir» de archivos en Android y servicio en
  primer plano para envíos largos (video de 1 GB);
- instalador de Windows con Inno Setup (por usuario, sin administrador) generado por
  `apps/desktop_app/tool/build_installer.ps1`;
- CI en GitHub Actions y pruebas automáticas (incluidas la prueba mDNS E2E con
  emparejamiento y ping cifrado, el envío cifrado de texto, el historial SQLite y la
  transferencia de archivos con reanudación y hash).

> **Instalador de Windows:** `apps/desktop_app/build/installer/JScan-Setup-0.1.0.exe`
> (Inno Setup, instalación por usuario sin administrador). Se regenera con
> `powershell -ExecutionPolicy Bypass -File apps/desktop_app/tool/build_installer.ps1`.
> El build portable sigue disponible en
> `apps/desktop_app/build/windows/x64/runner/Release/`.

Guía de ejecución: [docs/getting-started.md](docs/getting-started.md).


 opencode -s ses_e6ca0e5e8ffeEncD11sHKrx3Zs