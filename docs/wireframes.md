# Wireframes (Sprint 2 a 6)

Pantallas mínimas acordadas. Los wireframes son de baja fidelidad: definen jerarquía,
estados y acciones, no el diseño final. Las pantallas de los sprints 3 a 6 se
mantienen como referencia.

## 1. PC · Emparejar dispositivo (Sprint 2)

```text
+------------------------------------------+
|  J-SCAN  Servidor local      [2 emparejados] |
+------------------------------------------+
|  (•) Servidor activo        mDNS activo  |
|  DESKTOP-ABC · 192.168.1.20:47821        |
|                                          |
|  Emparejamiento         [Hasta 12:03:40] |
|  +------------------+  Escanea este QR   |
|  |                  |  con J-SCAN en el  |
|  |       QR         |  celular.          |
|  |                  |                    |
|  +------------------+  jscan://pair?d=…  |
|                        [Copiar código]   |
|                                          |
|  Dispositivos emparejados            [1] |
|  Pixel 8 · android · visto 12:00         |
|                              [Eliminar]  |
+------------------------------------------+
```

Estados: ventana cerrada · QR abierto con cuenta atrás · esperando confirmación ·
dispositivo aceptado · error.

## 2. PC · Confirmación de dispositivo nuevo

```text
+----------------------------------+
|           [teléfono + candado]   |
|   ¿Aceptar este dispositivo?     |
|                                  |
|   Pixel 8 quiere emparejarse     |
|   con esta PC.                   |
|                                  |
|   Plataforma   android           |
|   ID           a1b2c3d4          |
|   Solicitud    12:00:03          |
|                                  |
|   Acepta solo si tú abriste el   |
|   emparejamiento y reconoces     |
|   este dispositivo.              |
|                                  |
|   [ Rechazar ]      [ Aceptar ]  |
+----------------------------------+
```

La confirmación caduca en 1 minuto y se rechaza automáticamente.

## 3. Celular · Descubrimiento y emparejamiento

```text
+----------------------------------+
|  J-SCAN        [📄] [🛡 1] [↻]  |
+----------------------------------+
|  Misma red Wi-Fi                 |
|  Emparejamiento se hace una vez  |
|                                  |
|  Emparejar con la PC             |
|  En la PC pulsa «Emparejar       |
|  dispositivo».                   |
|  [ Escanear QR ] [ Pegar código ]|
|                                  |
|  Escanear documento        [Abrir]|
|  Detecta los bordes, corrige la  |
|  perspectiva y admite varias     |
|  páginas. No necesita una PC.    |
|                                  |
|  1 PC emparejada       [ Ver ]   |
|                                  |
|  PCs en la red        1 encontrada|
|  +----------------------------+  |
|  | 🔒 DESKTOP-ABC             |  |
|  | 192.168.1.20:47821 ·       |  |
|  | emparejada                 |  |
|  |                 [Conectar] |  |
|  +----------------------------+  |
+----------------------------------+
```

El icono 📄 y la tarjeta **Escanear documento** abren el escáner del Sprint 5 sin
necesidad de emparejar la PC.

Estados: preparando identidad · buscando · sin PCs · PC sin emparejar (**Emparejar**)
· PC emparejada (**Conectar**) · prueba en curso · error.

## 4. Celular · Escanear QR

```text
+----------------------------------+
|  <  Escanear QR de la PC   [⚡]  |
+----------------------------------+
|                                  |
|        +----------------+        |
|        |                |        |
|        |   vista cámara |        |
|        |                |        |
|        +----------------+        |
|                                  |
|   Apunta al QR que muestra       |
|   J-SCAN en la PC                |
|                                  |
|   [ Pegar código en su lugar ]   |
+----------------------------------+
```

Estados: pidiendo permiso · escaneando · emparejando (espera confirmación de la PC) ·
error de cámara con opción de pegar el código.

## 5. Celular · PCs emparejadas

```text
+----------------------------------+
|  <  PCs emparejadas        [QR]  |
+----------------------------------+
|  Solo puedes enviar a estas PCs. |
|                                  |
|  +----------------------------+  |
|  | 🖥 DESKTOP-ABC             |  |
|  | 192.168.1.20:47821 ·       |  |
|  | emparejada 31/10/2026      |  |
|  | [Probar conexión]  [🗑]    |  |
|  | 🔒 3 ms de promedio        |  |
|  +----------------------------+  |
+----------------------------------+
```

Estados: vacío · con PCs · probando · sesión cifrada · PC inalcanzable · confirmación
para olvidar.

## 6. Celular · Enviar texto y portapapeles (Sprint 3)

```text
+----------------------------------+
|  <   Enviar a la PC        [📋]  |
+----------------------------------+
|  PC de destino                   |
|  [ 🖥 DESKTOP-ABC · 192.168.1.20 ]|
|                                  |
|  Texto o enlace                  |
|  +----------------------------+  |
|  | Hola, mira esto:           |  |
|  | https://ejemplo.com        |  |
|  +----------------------------+  |
|                                  |
|  [ Enviar texto ]                |
|  [ Pegar portapapeles ]          |
|  [ Enviar portapapeles ]         |
|                                  |
|  ✅ Entregado a DESKTOP-ABC      |
|     Confirmado en 140 ms         |
|                                  |
|  Enviados en esta sesión     2   |
|  12:04  Texto · DESKTOP-ABC 140ms|
|  12:03  Portapapeles · 98 ms     |
+----------------------------------+
```

Estados: sin PCs emparejadas · listo · enviando · entregado (con `historyId`) ·
error de red o `not_paired`.

## 7. Celular · Texto compartido desde otra app (Sprint 3)

```text
+----------------------------------+
|  J-SCAN              [🛡 1] [↻]  |
+----------------------------------+
|  Texto compartido desde otra app |
|  https://ejemplo.com/articulo    |
|  [ Elegir PC y enviar ] [Descartar]|
+----------------------------------+
```

Se envía solo si hay exactamente una PC emparejada; si no, aparece esta tarjeta.

## 8. PC · Textos y portapapeles (Sprint 3)

```text
+--------------------------------------------------+
|  ✉ Textos y portapapeles                     [3] |
|  [x] Copiar automáticamente al portapapeles      |
|  -------------------------------------------------|
|  📋 "https://ejemplo.com"                        |
|     Pixel 8 · portapapeles · 03/11 12:03         |
|                              [Copiar] [Eliminar] |
|  📝 "Hola desde el celular"                      |
|     Pixel 8 · texto · 03/11 12:00                |
|                              [Copiar] [Eliminar] |
|                                                  |
|  [ Copiar último ]   [ Vaciar historial ]        |
+--------------------------------------------------+
```

Estados: vacío · con entradas · copiado · historial vaciado. El historial persiste
en `history.sqlite` con un máximo de 500 entradas.

## 9. Celular · Enviar archivos, fotos y videos (Sprint 4)

```text
+----------------------------------+
|  <   Enviar archivos             |
+----------------------------------+
|  PC de destino                   |
|  [ 🖥 DESKTOP-ABC · 192.168.1.20 ]|
|                                  |
|  ¿Qué quieres enviar?            |
|  [ Fotos y videos ] [ Archivo ]  |
|                                  |
|  Transferencias         2 activas|
|  🎬 video.mp4                    |
|     1.0 GB · DESKTOP-ABC     [x] |
|     [██████████░░░░░░]           |
|     Enviando · 62% · 640 MB de 1GB|
|  🖼 foto.jpg                     |
|     3.2 MB · En cola         [x] |
+----------------------------------+
```

Estados: sin PCs · eligiendo · en cola · calculando SHA-256 · enviando · cancelando ·
completado · error · reintento. El envío es secuencial y se puede cancelar por
archivo.

## 10. Celular · Archivos compartidos desde otra app (Sprint 4)

```text
+----------------------------------+
|  J-SCAN              [🛡 1] [↻]  |
+----------------------------------+
|  2 archivos compartidos          |
|  video.mp4, foto.jpg             |
|  [ Elegir PC y enviar ] [Descartar]|
+----------------------------------+
```

Se envían automáticamente solo si hay exactamente una PC emparejada; si no, aparece
esta tarjeta.

## 11. PC · Archivos recibidos (Sprint 4)

```text
+--------------------------------------------------+
|  📁 Archivos recibidos                       [3] |
|  C:\Users\...\Downloads    [Abrir] [Cambiar]     |
|  ----------------------------------------------  |
|  🎬 video.mp4                                    |
|     [████████████░░░░░░]  Enviando · 74%         |
|     760 MB de 1.0 GB · calculando SHA-256        |
|  ----------------------------------------------  |
|  🖼 foto.jpg                                     |
|     3.2 MB · 12:04 · Pixel 8 · SHA 4f2a91c3…     |
|                                   [📂 Mostrar]   |
+--------------------------------------------------+
```

Estados: sin carpeta · sin archivos · recibiendo (hash/envío) · verificado ·
cancelado · nombre duplicado renombrado. La carpeta se recuerda en `settings.json`.

## 12. Escáner y PDF (Sprint 5 + 6)

```text
+--------------------------------------------------+
|  ←  Escáner                    [🖼]  [🗑 Descartar]|
+--------------------------------------------------+
|  Página 2 de 2                      Original · 90° |
|  (Original) (Color) (Gris) (B/N)                  |
|  ----------------------------------------------  |
|  ⠿  [miniatura]  Página 1          [↻] [🗑]      |
|      Original                                     |
|  ----------------------------------------------  |
|  ⠿  [miniatura]  Página 2          [↻] [🗑]      |
|      Original · 90°                               |
|                                                   |
|  [ + Añadir páginas ]   [ 🔍 Vista previa ]       |
|  [ 📄 Crear PDF y enviar                        ] |
+--------------------------------------------------+
```

La cámara nativa hace la detección de bordes, el recorte manual y la corrección de
perspectiva antes de devolver cada página. La app muestra hasta 12 páginas por sesión;
cada una se puede rotar, reordenar (arrastrando desde ⠿) o eliminar. Al elegir una
página, la barra superior de filtros cambia solo esa página. **Vista previa** abre
las páginas a pantalla completa con zoom y deslizamiento. El icono 🖼 importa
imágenes de la galería y las añade como páginas.

Estado vacío: tarjeta «Escanea un documento» con la explicación de bordes, filtros,
orden y PDF, y los botones **Escanear documento** e **Importar de galería**.

Estados: sin páginas · capturando (cámara nativa) · procesando (filtro/rotación con
overlay) · revisando páginas · vista previa · confirmación de descarte · generando
PDF · PDF listo para enviar.

## 13. Celular · Diálogo de PDF (Sprint 6)

```text
+------------------------------------------+
|  Crear PDF                               |
|                                          |
|  2 páginas en un solo PDF.               |
|                                          |
|  Nombre del archivo           .pdf       |
|  [ Escaneo 2026-11-08 14.30          ]   |
|                                          |
|  Calidad                                 |
|  ( ) Alta                                |
|      Máxima nitidez para archivar...     |
|  (•) Equilibrada                         |
|      Buena calidad y tamaño razonable    |
|  ( ) Compacta                            |
|      Más liviana para correo...          |
|                                          |
|           [ Cancelar ]  [ Crear PDF ]    |
+------------------------------------------+
```

Al terminar, un segundo diálogo resume «2 páginas · 1,4 MB» y ofrece **Enviar a la
PC**. Si no hay una PC emparejada, explica que puede emparejarla desde el inicio y
volver a escanear; el PDF queda disponible en la carpeta de exportaciones.
