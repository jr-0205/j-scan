# Contribuir a J-SCAN

Gracias por tomarte el tiempo de mejorar J-SCAN. Estas pautas mantienen el
proyecto fácil de revisar y de mantener.

## Antes de empezar

- Revisa los [issues abiertos](https://github.com/jr-0205/j-scan/issues) para ver
  si alguien ya está trabajando en lo mismo.
- Para cambios grandes, abre un issue primero y describe el problema y la
  propuesta.
- Para fallos, incluye modelo de celular, versión de Android, versión de Windows,
  tipo de red y el mensaje de error completo.

## Preparar el entorno

```bash
git clone https://github.com/jr-0205/j-scan.git
cd J-SCAN
dart pub global activate melos
melos bootstrap
```

Sin Melos:

```bash
cd packages/jscan_core && dart pub get
cd ../../apps/desktop_app && flutter pub get
cd ../mobile_app && flutter pub get
```

La guía completa de ejecución está en [`docs/getting-started.md`](docs/getting-started.md).

## Reglas del proyecto

- **Protocolo v1:** no cambies el contrato de [`docs/protocol.md`](docs/protocol.md)
  sin documentarlo y añadir pruebas. Los mensajes autenticados siempre van
  cifrados.
- **Lógica compartida:** si el código debe funcionar igual en Android y Windows,
  va en `packages/jscan_core` (sin Flutter).
- **Estilo visual:** usa `packages/jscan_ui`; evita duplicar colores, radios o
  componentes entre apps.
- **Sin dependencias innecesarias:** justifica cualquier paquete nuevo.
- **Idioma:** la interfaz y la documentación están en español.

## Antes de abrir un pull request

Ejecuta lo que corresponda al área que tocaste:

```bash
# Paquete de protocolo
cd packages/jscan_core
dart format --output=none --set-exit-if-changed .
dart analyze
dart test

# Cada app o paquete Flutter
cd apps/desktop_app
dart format --output=none --set-exit-if-changed lib test
flutter analyze
flutter test
```

Repite el bloque de Flutter en `apps/mobile_app` y `packages/jscan_ui`.

El pull request debe explicar:

1. qué problema resuelve;
2. cómo lo resolviste;
3. cómo lo verificaste (pruebas, builds, capturas si aplica).

## Commits

Usa mensajes claros, en imperativo y con un prefijo cuando aporte contexto:

```text
feat: escáner con detección de bordes
fix: reanudar archivos tras reconectar
docs: explicar el emparejamiento por código
```

## Licencia

Al contribuir aceptas que tu aporte se distribuya bajo la licencia
[MIT](LICENSE) del proyecto.
