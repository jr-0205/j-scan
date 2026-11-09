# Guía rápida de J-SCAN (beta 0.2.0)

Esta guía está pensada para instalar J-SCAN y probarlo sin ayuda técnica. Si algo
no coincide con lo que ves en pantalla, anota el mensaje exacto y avísanos: los
mensajes de error están escritos para decir qué revisar.

## Qué necesitas

- Una PC con **Windows 10 u 11** y una red Wi-Fi o cable a la que también se
  conecte el celular.
- Un celular **Android 8 o superior** con cámara.
- Ambos equipos en la **misma red**. No hace falta internet.
- El instalador `JScan-Setup-0.2.0.exe` y el APK de prueba `app-debug.apk`.

## 1. Instalar la PC

1. Ejecuta `JScan-Setup-0.2.0.exe` y acepta. Se instala en tu usuario, sin pedir
   contraseña de administrador.
2. Abre **J-SCAN** desde el menú Inicio.
3. La primera vez, Windows Firewall preguntará si J-SCAN puede comunicarse en
   redes privadas. Marca **Redes privadas** y pulsa **Permitir acceso**.
4. Comprueba que la tarjeta superior diga **Servidor activo** y muestre un puerto
   (normalmente `47821`). Si dice **Servidor detenido**, cierra otra copia de
   J-SCAN y vuelve a abrirla.

La app se queda en la bandeja del sistema al cerrar la ventana. Para salir del
todo, usa el menú del icono de J-SCAN → **Salir**.

## 2. Instalar el celular

1. Copia `app-debug.apk` al celular (cable, Google Drive o el método que prefieras).
2. Abre el archivo y acepta **Instalar apps desconocidas** para esa aplicación.
   Es normal: el APK de prueba no está publicado en Play Store.
3. Abre **J-SCAN**. La primera vez pedirá permiso de **cámara** (para el QR y el
   escáner) y de **notificaciones** (para el progreso de envíos largos).
   - Si deniegas la cámara, todavía puedes emparejar con **Pegar código** y enviar
     archivos; solo no podrás escanear ni leer el QR.
   - Si deniegas las notificaciones, los envíos siguen funcionando, pero Android
     puede pausarlos con la pantalla apagada.

## 3. Emparejar el celular con la PC

1. En la PC pulsa **Emparejar dispositivo**. Aparece un QR válido 3 minutos.
2. En el celular, con J-SCAN abierto, pulsa **Escanear QR** y apunta al código.
3. La PC muestra un aviso con el nombre del celular. Pulsa **Aceptar**.
4. El celular vuelve al inicio y la PC aparece como **Emparejada**. Pulsa
   **Conectar** para ver los tres pings cifrados.

Si el QR caduca, genera otro en la PC. Si la PC no aparece en la lista, revisa que
estén en la misma red y que el firewall permita J-SCAN.

## 4. Enviar texto, enlaces y archivos

- **Texto o enlace:** abre **Texto y portapapeles**, escribe o pega y pulsa
  **Enviar texto**. La PC lo muestra en su historial y, si está activado, lo copia
  al portapapeles.
- **Archivos, fotos o videos:** abre **Archivos, fotos y videos**, elige uno o
  varios y espera el progreso. La PC los guarda en **Descargas** o en la carpeta
  que hayas elegido. Si el Wi-Fi se corta, J-SCAN reintenta una vez; si sigue
  fallando, pulsa **Reintentar** y la PC continúa desde donde quedó.
- **Desde otra app:** usa **Compartir → J-SCAN**. Con una sola PC emparejada se
  envía al instante; con varias, la app pregunta el destino.

## 5. Escanear una hoja y recibir el PDF en la PC

Este es el flujo completo del Sprint 6. Objetivo: **menos de 30 segundos** desde
que pulsas **Escanear documento** hasta que el PDF aparece en la PC.

1. En el celular, abre **Escanear documento** (tarjeta o icono 📄).
2. Pulsa **Escanear documento**, encuadra la hoja y confirma el recorte. Puedes
   repetir para varias páginas.
3. Ajusta el filtro si hace falta: **Original**, **Color**, **Gris** o **B/N**.
   También puedes rotar, reordenar o eliminar páginas.
4. Pulsa **Crear PDF y enviar**.
5. Escribe el nombre del archivo y elige la calidad:
   - **Alta**: mejor para imprimir o archivar.
   - **Equilibrada**: buena calidad y tamaño razonable (recomendada).
   - **Compacta**: más liviana para correo o mensajería.
6. Pulsa **Crear PDF** y luego **Enviar a la PC**.
7. La PC muestra el PDF en **Archivos recibidos**. Pulsa **Abrir** para verlo.

También puedes importar fotos que ya tengas: **Importar de galería** en la barra
superior o en la pantalla vacía. Se añaden como páginas y reciben el mismo
tratamiento (filtro, rotación y PDF).

### Tiempos de referencia

| Paso | Tiempo esperado |
|---|---|
| Captura y recorte de una hoja | 5–10 s |
| Generación del PDF (1–3 páginas) | 1–4 s |
| Envío por Wi-Fi y verificación SHA-256 | 1–5 s |

Si superas los 30 segundos, revisa la calidad de la señal Wi-Fi y usa el preset
**Compacta** para documentos de muchas páginas.

## 6. Permisos explicados

| Permiso | Para qué se usa | Qué pasa si lo niegas |
|---|---|---|
| Cámara | Leer el QR de emparejamiento y escanear hojas | Puedes pegar el código y enviar archivos; no puedes escanear |
| Notificaciones | Mostrar el progreso de envíos largos | El envío puede pausarse con la pantalla apagada |
| Red / Wi-Fi | Descubrir la PC y transferir datos | J-SCAN no puede encontrar ni conectar con la PC |

J-SCAN no pide acceso a contactos, ubicación, micrófono ni almacenamiento
completo. Los archivos se leen solo cuando tú los eliges.

## 7. Problemas frecuentes

| Síntoma | Qué revisar |
|---|---|
| La PC no aparece | Misma red Wi-Fi, J-SCAN abierto y firewall con J-SCAN permitido |
| «No se pudo conectar con la PC» | Que la PC esté encendida, despierta y con J-SCAN abierto |
| «La PC ya no reconoce este celular» | Vuelve a emparejar con un QR nuevo |
| «El código QR caducó» | Genera un QR nuevo en la PC (dura 3 minutos) |
| El QR no enfoca | Acerca el celular, evita reflejos y usa **Pegar código** |
| El PDF tarda o falla | Usa **Compacta**, cierra otras apps y verifica el espacio libre |
| El envío se corta con la pantalla apagada | Acepta las notificaciones y deja J-SCAN en primer plano |
| Windows muestra «aplicación desconocida» | El instalador no está firmado; usa **Más información → Ejecutar de todas formas** |

Los mensajes de J-SCAN incluyen una primera frase con la solución y, entre
paréntesis, el detalle técnico. Si necesitas reportar un fallo, copia el mensaje
completo y el modelo del celular.

## 8. Lista de verificación de la beta

Antes de dar la beta por buena, el equipo debe completar esta tabla:

- [ ] Instalación limpia en Windows 11 y actualización sobre una versión anterior.
- [ ] Emparejamiento en **5 modelos de celular** distintos (Android 8–15).
- [ ] Pruebas en **2 redes**: Wi-Fi doméstico y red con aislamiento de clientes o
      punto de acceso móvil.
- [ ] Envío de texto, enlace, foto, video y PDF en cada red.
- [ ] Reconexión: apagar el Wi-Fi a mitad de un envío y volver a encenderlo.
- [ ] Escaneo de 3 hojas y recepción del PDF en menos de 30 segundos.
- [ ] **5 personas ajenas al desarrollo** emparejan y envían sin ayuda.
- [ ] Revisión de permisos: cámara denegada, notificaciones denegadas y modo avión.

Los tres últimos puntos no se pueden verificar solo con pruebas automáticas: hacen
falta dispositivos y personas reales. El repositorio incluye pruebas de lógica,
widgets y un E2E de red; esta lista cubre lo que queda para la validación manual.

### Cómo reportar un fallo

Incluye:

1. modelo de celular y versión de Android;
2. versión de Windows y si el instalador era nuevo o una actualización;
3. tipo de red (Wi-Fi 2,4 GHz, 5 GHz, punto de acceso móvil);
4. pasos exactos y el mensaje de error completo;
5. si el fallo se repite al reintentar.

## 9. Privacidad y seguridad

- El emparejamiento y todos los mensajes posteriores viajan cifrados con
  ChaCha20-Poly1305; la clave se acuerda con X25519 y nunca se envía por la red.
- La PC solo acepta dispositivos que tú confirmaste. Puedes revocarlos en
  **Dispositivos emparejados**.
- Nada sale a internet: J-SCAN usa la red local y no tiene servidores en la nube.
- Los PDFs y las páginas escaneadas se guardan en carpetas temporales privadas de
  la app; las exportaciones de más de un día se borran automáticamente.
