# Política de seguridad

J-SCAN maneja datos que no deberían salir de la red local: texto, portapapeles,
archivos y documentos escaneados. Si encuentras una vulnerabilidad, te pedimos
que la reportes de forma privada.

## Cómo reportar

1. Abre el aviso privado en
   [GitHub Security Advisories](https://github.com/jr-0205/J-SCAN/security/advisories/new).
2. Describe el impacto, los pasos para reproducirlo y la versión afectada.
3. Si es posible, incluye una prueba de concepto mínima.

No abras un issue público con detalles explotables. Intentaremos responder en un
plazo razonable y coordinar la publicación del aviso después de corregir el
problema.

## Alcance

Nos interesan especialmente:

- fallos en el emparejamiento o en la verificación del token del QR;
- debilidades en el acuerdo de claves X25519 o en el cifrado ChaCha20-Poly1305;
- saltos de autenticación entre dispositivos emparejados y no emparejados;
- escritura de archivos fuera de la carpeta de destino;
- filtración de claves, historial o archivos temporales.

Quedan fuera del alcance los problemas que dependen de una red ya comprometida,
de un dispositivo con root o de la instalación de APKs o ejecutables modificados
por terceros.

## Modelo de seguridad, en resumen

- La identidad de cada dispositivo es un par de claves X25519 persistente.
- La clave compartida se deriva con HKDF-SHA256 del secreto X25519.
- Todos los mensajes posteriores a `auth_ok` van cifrados y autenticados.
- El QR de emparejamiento contiene un token de un solo uso que caduca a los
  3 minutos y debe confirmarse en la PC.
- No hay servidores, cuentas ni telemetría: todo ocurre en la red local.

Los detalles técnicos están en [`docs/protocol.md`](docs/protocol.md) y en
[`docs/architecture.md`](docs/architecture.md).
