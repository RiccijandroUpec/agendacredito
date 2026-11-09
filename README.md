# Agenda de Crédito

App Android para tablet para registrar a los clientes que consultan crédito, en lugar de la libreta de papel.

## Qué hace

- **Registro de clientes** con la cédula ecuatoriana validada (dígito verificador), la fecha de consulta, el resultado (aprobado o negado), el **cupo aprobado** y **cuándo puede venir**.
- **Nombre automático desde el SRI** cuando la persona tiene RUC. Si no tiene RUC, el nombre se escribe a mano.
- **Pendientes de cédula**: para los clientes que no la traen. La app muestra cuántos días llevan esperando y, cuando la traen, se completa su ficha.
- **Burbuja flotante**: mientras revisas el crédito en la app de la empresa, tocas la burbuja y se abre encima un formulario para anotar al cliente sin salir de esa app.
- **Hoy**: quién puede venir hoy, quién quedó en venir y no vino, y los próximos 7 días. Aviso a la mañana, sin nombres en la notificación.
- **Buscador** por cédula, nombre o teléfono. Aviso si una cédula ya está registrada.
- **WhatsApp y llamada** con un toque, con mensajes listos para enviar.
- **Resumen del mes**: clientes consultados, aprobados, negados, tasa de aprobación, cupo aprobado y cuántos vinieron.

## Seguridad

- **Activación por tablet**: el APK solo funciona en las tablets activadas por el autor. Si alguien copia el APK a otra tablet, no le sirve.
- **PIN opcional de 6 dígitos y huella**: se activa en *Ajustes → Seguridad*. Con PIN, la app se bloquea sola al salir, frena a quien intenta adivinar el PIN y lo pide para exportar, restaurar o borrar.
- **Base de datos cifrada** (SQLCipher). La clave se guarda en el Keystore de Android.
- **Sin capturas de pantalla**: la app no se ve en las capturas ni en la vista previa de apps recientes, y la tablet no la incluye en sus copias de seguridad automáticas.
- **Sellos del historial**: cada registro queda encadenado con un hash. La fecha del primer registro (quién llegó primero) no se puede cambiar, y si alguien modifica la base por fuera de la app, la verificación lo detecta.

## Respaldo

- **Copia diaria cifrada** en `Descargas/AgendaCredito`. Se conserva aunque se desinstale la app.
- **Enviar respaldo** a Drive, correo o WhatsApp, para no perder nada aunque se pierda la tablet.
- **Restaurar** en otra tablet con la clave de respaldo.
- **Exportar a Excel** (.csv).

## Compilar (solo el autor)

```bash
flutter test
flutter build apk --release --obfuscate --split-debug-info=build/simbolos
```

`android/key.properties` (no se sube) apunta a la llave de firma.

### Activar una tablet

La tablet muestra su **código de equipo**. En el PC, desde la raíz del proyecto:

```bash
dart run tool/activar.dart ABCDE-FGHIJ-KLM "tablet trabajo"
```

Pega en la tablet el código `AC1-...` que devuelve. La clave privada está en `~/.agenda-credito-licencias`, fuera del repo. **Respáldala**: sin ella no se pueden activar más tablets.

---

© 2026 Riccijandro, Ecuador. Todos los derechos reservados. Código privado: prohibido copiarlo, distribuirlo o modificarlo sin permiso del autor.
