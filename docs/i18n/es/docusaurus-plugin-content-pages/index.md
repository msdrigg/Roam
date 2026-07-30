---
hide_table_of_contents: true
---

<head>
    <meta name="apple-itunes-app" content="app-id=6469834197"/>
</head>

## Acerca de Roam

:::warning

Esta es una página de soporte para la aplicación Roam, no para Roly. Recientemente supe que la app Roly ha copiado mi código fuente y la página de la tienda de aplicaciones, incluso enlazando aquí a mi página de soporte. Esto es fraudulento e incorrecto. 

:::

:::tip[Invítame a un café]

Roam es gratis, sin anuncios y sin niveles de pago. Si te ha resultado útil, puedes [dejar una propina](/coffee).

:::

Roam te ofrece todo lo que necesitas y nada de lo que no necesitas

-   ¡Funciona en Mac, iPhone, iPad, Apple Watch, Vision Pro y Apple TV!
-   Integración inteligente a la plataforma con atajos de teclado en Mac; usa los botones de volumen físico para controlar el volumen del televisor en iOS
-   ¡Utiliza atajos y widgets para controlar tu televisor sin siquiera abrir la app!
-   Modo auriculares (también conocido como escucha privada) compatible en Mac, iPad, iPhone, VisionOS y Apple TV (reproduce el audio de tu TV a través de tu dispositivo)
-   Descubre dispositivos en tu red local tan pronto como abras la app
-   Diseño intuitivo con el sistema nativo SwiftUI de Apple
-   Rápida y liviana, menos de 8 MB en todos los dispositivos y se abre en menos de medio segundo
-   Código abierto (https://github.com/msdrigg/roam)

## Funcionalidades

-   Controles remotos
    -   Roam incluye los controles habituales del mando Roku, incluyendo flechas direccionales, seleccionar, atrás, inicio, reproducir/pausa y controles de TV relacionados cuando el Roku los soporta.
    -   Es posible que los controles de volumen no funcionen en Roku Sticks porque son dispositivos solo HDMI y no pueden controlar el volumen de la TV a través de los comandos de red de Roam.
-   Entrada por teclado
    -   En macOS, no hay botón de teclado. Cuando la ventana de Roam está activa, el teclado de Mac funciona automáticamente con la TV.
    -   En iOS y iPadOS, hay un botón de teclado en la parte superior del control remoto.
    -   Por ahora, watchOS no tiene funcionalidad de teclado.
    -   Algunas aplicaciones de Roku ignoran la entrada de teclado de apps remotas. Prime Video es un ejemplo conocido donde la introducción de texto puede no funcionar porque la app de Roku no la acepta.
-   Atajos de teclado
    -   Roam asigna teclas del teclado físico a acciones del remoto (flechas direccionales, seleccionar/OK, atrás, inicio, volumen, silencio, reproducir/pausa y más). Esto es independiente de la escritura en pantalla.
    -   Puedes personalizar estos atajos en **Configuración -> Atajos de teclado** en Mac, iPhone, iPad y Vision Pro (watchOS no tiene atajos de teclado).
    -   Selecciona una fila para cambiar su atajo, haz clic derecho (Mac) o desliza (iPhone/iPad) una fila para restablecerla, o utiliza **Restablecer todo** / **Borrar todo**. Los atajos por defecto usan el modificador Command (⌘).
-   Pega un enlace para reproducir (macOS)
    -   En Mac, copia un enlace de video, haz clic en la ventana de Roam y pulsa **⌘V**. Roam abrirá la app correspondiente en tu Roku y empezará a reproducir ese contenido.
    -   Los servicios compatibles incluyen YouTube, Amazon Prime Video, Netflix, Disney+, Hulu, Max, Paramount+, Peacock, Tubi, Sling y The Roku Channel.
    -   Si hay un campo de texto activo en la TV, ⌘V escribe el texto del portapapeles en ese campo en lugar de abrir el enlace.
-   Modo auriculares/escucha privada
    -   La escucha privada reproduce el audio de la TV a través de tu dispositivo en los dispositivos Roku compatibles.
    -   La escucha privada es compatible en Roam para Mac, iPad, iPhone, VisionOS y Apple TV, pero no funciona en todos los modelos Roku TV.

## Problemas comunes

-   ¿Qué puedo hacer si Roam no detecta automáticamente mi TV?
    -   [Consulta aquí](/manually-add-tv)
-   Roam no funciona correctamente en mi Apple Watch
    -   Por favor, ve a **Ajustes -> Sistema -> Ajustes avanzados del sistema -> Control por aplicaciones móviles** y asegúrate de que esté configurado en **Permisivo**
-   ¿Por qué no funciona el modo auriculares (escucha privada) en mi TV?
    -   Actualmente el modo auriculares no funciona en algunos televisores. Si no funciona con Roam pero sí con la app oficial de Roku, por favor comparte el nombre del modelo de tu Roku y cualquier otra información relevante en un correo electrónico a [roam-support@msd3.io](mailto:roam-support@msd3.io). Tu informe me ayudará a saber dónde buscar para resolver este error.
-   ¿Qué hago si tengo otro problema o solo quiero dar comentarios?
    -   Si es un error, lo mejor es iniciar un informe de comentarios desde la aplicación
        -   Ve a la app de Roam y abre la página de configuración
        -   Haz clic en "Enviar comentarios". Esto generará un informe de diagnóstico que puedes compartir con el soporte de Roam (roam-support@msd3.io)
        -   Si tu app se está cerrando inesperadamente, también asegúrate de tener activada la analítica en Ajustes -> Privacidad y Seguridad -> Analítica y mejoras
            -   Activa "Compartir analítica de iPhone y Watch" y luego "Compartir con los desarrolladores de aplicaciones" para que Apple me informe cuando tu app se bloquee
    -   Si es una solicitud de nueva función, puedes enviar un correo electrónico (roam-support@msd3.io), chatear directamente conmigo en la app Roam (Ajustes -> Chatear con el desarrollador) o unirte al [Discord de Roam](https://discord.gg/FqaTNRccbG).
-   ¿Por qué algunas veces no funcionan las flechas de dirección en el iPad?
    -   Esto ocurre porque iPadOS a veces toma el control de las teclas de flecha y las usa para navegar entre los botones de la pantalla antes de que podamos detectarlas.
    -   Puedes solucionar esto yendo a Ajustes -> Accesibilidad -> Teclados y desactivando "Acceso completo al teclado" o alternativamente yendo a Ajustes -> Accesibilidad -> Teclados -> Acceso completo al teclado -> Comandos -> Básico y desactivando los comandos "Mover arriba", "Mover abajo", "Mover a la izquierda" y "Mover a la derecha"
    -   También puedes reasignar los atajos direccionales en Roam en **Configuración -> Atajos de teclado**. Mantener un modificador Command (⌘) en un atajo evita que el Acceso completo al teclado intercepte teclas simples como las flechas.
-   ¿Por qué al escribir en mi teclado no aparece nada en la TV?
    -   En algunas apps de Roku, la app ignora la entrada de teclado físico. Puedes probar si es un error de Roam o de la app usando la función de introducción de texto en la app oficial de Roku y comprobando si funciona.
    -   En macOS, no hay botón de teclado porque el teclado de Mac funciona automáticamente con la TV cuando la ventana de Roam está activa. En iOS y iPadOS, usa el botón de teclado en la parte superior del control remoto. watchOS no admite entrada de teclado por el momento.
    -   Apps con errores conocidos:
        -   Prime Video
-   ¿Por qué Roam funciona en mi iPhone y Mac pero no en mi Apple Watch?
    -   La app de WatchOS se conecta a la TV usando la API ECP de la TV, que hay que habilitar en algunos modelos de Roku TV. Para activarla, ve a **Ajustes -> Sistema -> Ajustes avanzados del sistema -> Control por aplicaciones móviles** y asegúrate de que "Acceso a la red" esté en "Permisivo"
-   ¿Por qué no puedo encender mi TV desde el Apple Watch?
    -   El Apple Watch no puede usar la API estándar de encendido a menos que **Inicio rápido del TV** esté habilitado en tu Roku TV. Para activarlo:
        -   Pulsa el botón **Inicio** del control remoto de tu Roku TV
        -   Desplázate hacia arriba o abajo y selecciona **Ajustes**
        -   Selecciona **Sistema** y luego **Energía**
        -   Selecciona **Inicio rápido del TV**
        -   Resalta **Habilitar inicio rápido del TV** y pulsa **OK** en el control remoto para marcar la casilla

## Otros recursos

Si tienes alguna duda o problema, por favor contáctame en: [roam-support@msd3.io](mailto:roam-support@msd3.io). También puedes chatear directamente conmigo en la app de Roam (Ajustes -> Chatear con el desarrollador) o unirte al [Discord de Roam](https://discord.gg/FqaTNRccbG).

-   [Política de privacidad](/privacy)
-   [Repositorio principal en GitHub](https://github.com/msdrigg/roam)
-   [Discord de Roam](https://discord.gg/FqaTNRccbG)
-   [Descargar en la app store](https://apps.apple.com/us/app/roam/6469834197)
-   [Hoja de ruta](/upcoming-work)
-   [Registro de cambios](/changes)
-   [Dispositivos Roku testeados](/tested-tvs)
-   [Invítame a un café](/coffee)
