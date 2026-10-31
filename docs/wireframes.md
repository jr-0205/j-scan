# Wireframes (Sprint 0)

Pantallas mínimas acordadas. Los wireframes son de baja fidelidad: definen jerarquía,
estados y acciones, no el diseño final.

## 1. Emparejar (Sprint 2)

```text
+----------------------------------+
|  J-SCAN                     [X]  |
+----------------------------------+
|                                  |
|      Escanea este código         |
|      con tu celular              |
|                                  |
|      +------------------+         |
|      |                  |         |
|      |       QR         |         |
|      |                  |         |
|      +------------------+         |
|                                  |
|      jscan://3f9a1c2b@           |
|      192.168.1.20:47821          |
|                                  |
|  [ Copiar dirección ]            |
+----------------------------------+
```

Estados: esperando escaneo · dispositivo detectado · confirmar/denegar (Sprint 2).

## 2. Inicio / PC conectada

```text
+----------------------------------+
|  J-SCAN                    [≡]   |
+----------------------------------+
|  Estado                          |
|  (•) Servidor activo             |
|  Puerto 47821 · 192.168.1.20     |
|  Descubrimiento mDNS activo      |
|                                  |
|  Dispositivos conectados         |
|  +----------------------------+  |
|  | Pixel 8 · android          |  |
|  | 192.168.1.35 · hace 2 s    |  |
|  +----------------------------+  |
|                                  |
|  Actividad                       |
|  12:00:03  ping de Pixel 8 (12  |
|            ms)                    |
|                                  |
|  [ Compartir portapapeles ]      |
+----------------------------------+
```

Estados: servidor arrancando · activo · error (puerto ocupado).

## 3. Enviar (celular)

```text
+----------------------------------+
|  <   Enviar a DESKTOP-ABC        |
+----------------------------------+
|  [ Texto ] [ Archivos ] [ Fotos ]|
|                                  |
|  +----------------------------+  |
|  | Escribe o pega aquí...     |  |
|  |                            |  |
|  +----------------------------+  |
|                                  |
|  [        Enviar        ]        |
|                                  |
|  Progreso: ▓▓▓▓▓▓░░░░  62 %      |
+----------------------------------+
```

Estados: sin conexión · enviando · completado · error con reintento.

## 4. Escáner (Sprint 5)

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

## 5. Historial

```text
+----------------------------------+
|  Historial              [Filtro] |
+----------------------------------+
|  Hoy                             |
|  +----------------------------+  |
|  | 12:00  Texto               |  |
|  | "https://ejemplo.com"      |  |
|  | desde Pixel 8              |  |
|  +----------------------------+  |
|  +----------------------------+  |
|  | 11:42  Archivo             |  |
|  | video.mp4 · 1.2 GB · OK    |  |
|  +----------------------------+  |
|                                  |
|  [        Limpiar        ]       |
+----------------------------------+
```

Estados: vacío · con elementos · limpiando.
