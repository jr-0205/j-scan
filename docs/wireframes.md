# Wireframes (Sprint 2 + Sprint 3)

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
|  J-SCAN              [🛡 1] [↻]  |
+----------------------------------+
|  Misma red Wi-Fi                 |
|  Emparejamiento se hace una vez  |
|                                  |
|  Emparejar con la PC             |
|  En la PC pulsa «Emparejar       |
|  dispositivo».                   |
|  [ Escanear QR ] [ Pegar código ]|
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

## 9. Escáner (Sprint 5)

```text
+----------------------------------+
|  <   Escanear          [Flash]   |
+----------------------------------+
|                                  |
|      +--------------------+      |
|      |  Bordes detectados |      |
|      |      documento     |      |
|      +--------------------+      |
|                                  |
|  Páginas: [1] [2] [3] [+]        |
|                                  |
|  [ Original ][ Color ][ BN ]     |
|                                  |
|  [       Continuar       ]       |
+----------------------------------+
```

Estados: detectando bordes · capturando · revisando páginas.
