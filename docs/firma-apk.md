# Firma de los APK con la clave propia de RutaSur

## Por qué

Android solo instala una versión nueva **encima** de la anterior si las dos están firmadas
con la misma clave. Sin clave propia, GitHub Actions firma con una clave de depuración que
se crea de nuevo en cada máquina, así que para actualizar habría que desinstalar la app y
perder los favoritos o la sesión del conductor. Una clave propia también identifica a
RutaSur como autor de los instalables.

La clave es **privada**: no se sube al repositorio (`.gitignore` excluye `*.jks` y
`key.properties`) ni se pega en el chat. GitHub la guarda cifrada como secreto.

## 1. Crear la clave (una sola vez, en la PC)

En PowerShell:

```powershell
keytool -help          # si dice que no existe:  winget install EclipseAdoptium.Temurin.17.JDK
                       # y luego cierra y vuelve a abrir PowerShell

mkdir $HOME\claves-rutasur
cd $HOME\claves-rutasur
keytool -genkeypair -v -keystore rutasur.jks -storetype PKCS12 -keyalg RSA -keysize 2048 `
  -validity 10000 -alias rutasur `
  -dname "CN=Pierre Nunez, OU=Ingenieria de Sistemas, O=UCSM, L=Arequipa, C=PE"
```

`keytool` pide una contraseña dos veces (no se ve al escribirla). Usa una de al menos
12 caracteres y guárdala en tu gestor de contraseñas.

**Copia de seguridad.** Guarda `rutasur.jks` y su contraseña en dos lugares distintos,
por ejemplo tu Drive y una memoria USB. Si se pierde la clave, las próximas versiones ya no
se podrán instalar encima de las actuales.

## 2. Darle la clave a GitHub

1. Convierte la clave a texto:

   ```powershell
   [Convert]::ToBase64String([IO.File]::ReadAllBytes("$HOME\claves-rutasur\rutasur.jks")) |
     Set-Content "$HOME\claves-rutasur\rutasur.b64"
   notepad "$HOME\claves-rutasur\rutasur.b64"
   ```

2. En GitHub: **PFC-rutasur → Settings → Secrets and variables → Actions → New repository
   secret**. Crea dos secretos:

   | Nombre | Valor |
   |---|---|
   | `RUTASUR_KEYSTORE_BASE64` | todo el texto de `rutasur.b64` (Ctrl+A, Ctrl+C en el Bloc de notas) |
   | `RUTASUR_KEYSTORE_PASSWORD` | la contraseña de la clave |

3. Borra el archivo de texto, que ya no hace falta:

   ```powershell
   Remove-Item "$HOME\claves-rutasur\rutasur.b64"
   ```

## 3. Comprobar

En **Actions → APK → Run workflow** (rama `main` o `develop`). Al terminar, el resumen de
la ejecución dice **«✅ Firmados con la clave propia de RutaSur»** y muestra el certificado
`CN=Pierre Nunez, OU=Ingenieria de Sistemas, O=UCSM…`. Si dice «⚠️ Firmados con la clave
de depuración», revisa el nombre de los dos secretos.

La primera vez que instales en un teléfono un APK con la clave propia, desinstala antes la
versión anterior (firmada con la de depuración). Desde entonces, cada versión nueva se
instala encima.

## Compilar firmado en la PC (opcional)

Crea `app/android/key.properties` (no se sube al repositorio):

```properties
storeFile=C:/Users/NatsukiKenn/claves-rutasur/rutasur.jks
storePassword=la-contraseña
```

y compila con `flutter build apk --release --flavor pasajero -t lib/entrypoints/main_pasajero.dart --dart-define=API_URL=https://rutasur-api.onrender.com`.
