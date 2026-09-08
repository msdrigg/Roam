---
hide_table_of_contents: true
---

<head>
    <meta name="apple-itunes-app" content="app-id=6469834197"/>
</head>

## Acerca de Roam

:::tip[Invítame un café]

Roam es gratis, sin anuncios y sin niveles de pago. Si te resulta útil, puedes [dejar una propina](/coffee).

:::

Roam te ofrece todo lo que quieres y nada que no necesitas

-   ¡Funciona en Mac, iPhone, iPad, Apple Watch, Vision Pro o Apple TV!
-   Integración inteligente con atajos de teclado en Mac y uso de los botones de volumen físico para controlar el volumen de la TV en iOS
-   Usa atajos y widgets para controlar tu TV ¡sin abrir la app!
-   Modo audífonos (también conocido como "escucha privada") disponible en Mac, iPad, iPhone, VisionOS y Apple TV (puedes escuchar el audio de la TV en tu dispositivo)
-   Descubre dispositivos en tu red local tan pronto abres la app
-   Diseño intuitivo con el sistema nativo de SwiftUI de Apple
-   Rápida y ligera, menos de 8 MB en todos los dispositivos y se abre en menos de medio segundo
-   Código abierto (https://github.com/msdrigg/roam)

## Funciones

-   Controles remotos
    -   Roam incluye los controles de mando Roku normales, incluyendo botones direccionales, seleccionar, atrás, inicio, reproducir/pausar y controles de TV relacionados cuando el Roku los soporta.
    -   Es posible que los controles de volumen no funcionen en los Roku Stick porque son dispositivos solo HDMI y no pueden controlar el volumen de la TV a través de los comandos de red de Roam.
-   Entrada de teclado
    -   En macOS, no hay botón de teclado. Cuando la ventana de Roam está activa, el teclado de tu Mac funciona automáticamente con la TV.
    -   En iOS y iPadOS, hay un botón de teclado en la parte superior del control remoto.
    -   watchOS no tiene funcionalidad de teclado en este momento.
    -   Algunas aplicaciones de Roku ignoran la entrada del teclado desde apps remotas. Prime Video es un ejemplo conocido donde la entrada del teclado podría no funcionar porque la app de Roku no lo acepta.
-   Atajos de teclado
    -   Roam asigna teclas del teclado físico para acciones del control remoto (botones direccionales, seleccionar/OK, atrás, inicio, volumen, silencio, reproducir/pausar y más). Esto es independiente de la entrada de texto en pantalla.
    -   Puedes personalizar estos atajos en **Configuración -> Atajos de teclado** en Mac, iPhone, iPad y Vision Pro (watchOS no tiene atajos de teclado).
    -   Selecciona una fila para cambiar su atajo, haz clic derecho (Mac) o desliza (iPhone/iPad) una fila para restablecerla, o usa **Restablecer todo** / **Limpiar todo**. Los atajos por defecto usan el modificador Command (⌘).
-   Pega un enlace para reproducir (macOS)
    -   En Mac, copia un enlace de video, haz clic en la ventana de Roam y presiona **⌘V**. Roam abre la app correspondiente en tu Roku y comienza a reproducir ese contenido.
    -   Los servicios compatibles incluyen YouTube, Amazon Prime Video, Netflix, Disney+, Hulu, Max, Paramount+, Peacock, Tubi, Sling y The Roku Channel.
    -   Si hay un campo de texto enfocado en la TV, ⌘V escribe el texto del portapapeles en ese campo en vez de abrir un enlace.
-   Modo audífonos/escucha privada
    -   La escucha privada reproduce el audio de la TV a través de tu dispositivo en Roku compatibles.
    -   La escucha privada es compatible con Roam en Mac, iPad, iPhone, VisionOS y Apple TV, pero no funciona en todos los Roku TV.

## Problemas comunes

-   ¿Qué hago si Roam no detecta automáticamente mi TV?
    -   [Ver aquí](/manually-add-tv)
-   Roam no funciona correctamente en mi Apple Watch
    -   Ve a **Configuración -> Sistema -> Opciones de sistema avanzadas -> Control por apps móviles** y asegúrate que esté en **Permisivo**
-   ¿Por qué no funciona el modo audífonos (escucha privada) en mi TV?
    -   Actualmente el modo audífonos no funciona en algunos televisores. Si el modo audífonos no funciona con Roam pero sí con la app oficial de Roku, por favor comparte el modelo de tu Roku y cualquier información relevante en un correo a [roam-support@msd3.io](mailto:roam-support@msd3.io). Tu reporte ayudará a encontrar y corregir este error.
-   ¿Qué hago si tengo otro problema o solo quiero dar comentarios?
    -   Si es un error, lo mejor es iniciar un reporte de retroalimentación desde la aplicación
        -   Entra a la app de Roam y abre la página de configuración
        -   Haz clic en "Enviar retroalimentación". Esto generará un informe de diagnóstico que puedes compartir con el soporte de Roam (roam-support@msd3.io)
        -   Si tu app se cierra inesperadamente, asegúrate de que la analítica esté activada en Configuración -> Privacidad y seguridad -> Analítica y mejoras
            -   Activa "Compartir analítica de iPhone y Watch" y luego activa "Compartir con desarrolladores" para que Apple me informe si tu app falla
    -   Si es una solicitud de nueva función, puedes enviar un email (roam-support@msd3.io), chatear directamente conmigo en la app Roam (Configuración -> Chatea con el desarrollador) o unirte al [Roam Discord](https://discord.gg/FqaTNRccbG).
-   ¿Por qué a veces no funcionan las teclas de flecha en iPad?
    -   Esto sucede porque a veces iPadOS toma el control de las teclas de flecha y las usa para navegar botones en pantalla antes de que podamos detectarlas
    -   Puedes solucionar esto yendo a Configuración -> Accesibilidad -> Teclados y desactivando "Acceso total al teclado" o, alternativamente, yendo a Configuración -> Accesibilidad -> Teclados -> Acceso total al teclado -> Comandos -> Básico y desactivando los comandos "Mover arriba", "Mover abajo", "Mover a la izquierda" y "Mover a la derecha"
    -   También puedes reasignar los atajos direccionales en Roam desde **Configuración -> Atajos de teclado**. Si mantienes un modificador Command (⌘) en un atajo, esto evita que Acceso total al teclado intercepte teclas simples como las flechas.
-   ¿Por qué lo que escribo en mi teclado no aparece en la TV?
    -   En algunas apps de Roku, la app ignora la entrada por teclado físico. Puedes probar si este es un error de Roam o de la app intentando la función de teclado en la app oficial de Roku y viendo si funciona
    -   En macOS, no hay botón de teclado porque el teclado del Mac funciona automáticamente con la TV cuando la ventana de Roam está activa. En iOS y iPadOS, usa el botón de teclado en la parte superior del control remoto. watchOS no soporta entrada de teclado actualmente.
    -   Apps con errores conocidos
        -   Prime Video
-   ¿Por qué Roam funciona en mi iPhone y app de Mac pero no en mi Apple Watch?
    -   La app de watchOS se conecta a la TV a través del API ECP de la TV, que debe estar habilitado en algunos televisores Roku. Para habilitarlo, ve a **Configuración -> Sistema -> Opciones de sistema avanzadas -> Control por apps móviles** y asegúrate que el "Acceso de red" esté en "Permisivo"
-   ¿Por qué no puedo encender mi TV desde mi Apple Watch?
    -   Apple Watch no puede usar la API estándar para encender la TV a menos que **Inicio rápido de TV** esté habilitado en el Roku TV. Para habilitarlo:
        -   Presiona el botón **Inicio** en el control remoto del Roku TV
        -   Desplázate hacia arriba o abajo y selecciona **Configuración**
        -   Selecciona **Sistema**, luego **Energía**
        -   Selecciona **Inicio rápido de TV**
        -   Resalta **Habilitar inicio rápido de TV** y presiona **OK** en el control remoto para marcar la casilla

## Otros recursos

Si tienes dudas o problemas, contáctame en: [roam-support@msd3.io](mailto:roam-support@msd3.io). También puedes chatear directamente conmigo en la app Roam (Configuración -> Chatea con el desarrollador) o unirte al [Roam Discord](https://discord.gg/FqaTNRccbG).

-   [Política de privacidad](/privacy)
-   [Repositorio principal en GitHub](https://github.com/msdrigg/roam)
-   [Roam Discord](https://discord.gg/FqaTNRccbG)
-   [Descargar en la app store](https://apps.apple.com/us/app/roam/6469834197)
-   [Hoja de ruta](/upcoming-work)
-   [Registro de cambios](/changes)
-   [Dispositivos Roku probados](/tested-tvs)
-   [Invítame un café](/coffee)
