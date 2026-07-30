---
hide_table_of_contents: true
---

<head>
    <meta name="apple-itunes-app" content="app-id=6469834197"/>
</head>

## Informazioni su Roam

:::warning

Questa è una pagina di supporto per l'applicazione Roam, non per Roly. Recentemente ho scoperto che l'app Roly ha copiato il mio codice sorgente e la pagina dell'app store, addirittura collegando qui a questa pagina di supporto. Questo è fraudolento e scorretto.

:::

:::tip[Offrimi un caffè]

Roam è gratuito, senza pubblicità e senza livelli a pagamento. Se ti è utile, puoi [lasciare una mancia](/coffee).

:::

Roam offre tutto ciò che desideri e niente che non vuoi

-   Funziona su Mac, iPhone, iPad, Apple Watch, Vision Pro o Apple TV!
-   Integrazione intelligente con scorciatoie da tastiera su Mac, utilizzo dei tasti volume hardware per controllare il volume della TV su iOS
-   Usa scorciatoie e widget per controllare la tua TV senza dover mai aprire l'app!
-   Supporto per la modalità cuffie (ovvero ascolto privato) su Mac, iPad, iPhone, VisionOS e Apple TV (riproduci l'audio della TV attraverso il tuo dispositivo)
-   Scopri i dispositivi sulla tua rete locale non appena apri l'app
-   Design intuitivo con il sistema nativo SwiftUI di Apple
-   Veloce e leggero, meno di 8 MB su tutti i dispositivi e si apre in meno di mezzo secondo!
-   Open source (https://github.com/msdrigg/roam)

## Funzionalità

-   Comandi remoti
    -   Roam include i normali controlli remoti Roku, inclusi i tasti direzionali, selezione, indietro, home, play/pausa e i comandi TV relativi quando supportati dal Roku.
    -   I controlli del volume potrebbero non funzionare sui Roku Stick perché sono dispositivi solo HDMI e non possono controllare il volume della TV tramite i comandi di rete di Roam su Roku.
-   Inserimento da tastiera
    -   Su macOS non c’è un pulsante tastiera. Quando la finestra Roam è attiva, la tastiera del Mac funziona automaticamente con la TV.
    -   Su iOS e iPadOS, c’è un pulsante tastiera in alto nel telecomando.
    -   watchOS non dispone attualmente di funzionalità tastiera.
    -   Alcune app Roku ignorano l’input da tastiera dalle app remote. Prime Video è un esempio noto in cui l’inserimento da tastiera potrebbe non funzionare perché l’app Roku non lo accetta.
-   Scorciatoie da tastiera
    -   Roam associa i tasti della tastiera hardware alle azioni del telecomando (tasti direzionali, seleziona/OK, indietro, home, volume, muto, play/pausa e altro). Questo è separato dall’inserimento di testo a schermo.
    -   Puoi personalizzare queste scorciatoie in **Impostazioni -> Scorciatoie da tastiera** su Mac, iPhone, iPad e Vision Pro (watchOS non dispone di scorciatoie).
    -   Seleziona una riga per modificarne la scorciatoia, clicca con il tasto destro (Mac) o scorri (iPhone/iPad) su una riga per reimpostarla, oppure utilizza **Ripristina tutto** / **Cancella tutto**. Le scorciatoie predefinite usano il tasto modificatore Command (⌘).
-   Incolla un link per avviare la riproduzione (macOS)
    -   Su Mac, copia un link video, fai clic sulla finestra di Roam e premi **⌘V**. Roam apre l’app corrispondente sul tuo Roku e avvia la riproduzione di quel contenuto.
    -   I servizi supportati includono YouTube, Amazon Prime Video, Netflix, Disney+, Hulu, Max, Paramount+, Peacock, Tubi, Sling e The Roku Channel.
    -   Se è attivo un campo di testo sulla TV, ⌘V inserirà il testo degli appunti in quel campo invece di aprire un link.
-   Modalità cuffie/ascolto privato
    -   L’ascolto privato riproduce l’audio della TV attraverso il tuo dispositivo sui Roku supportati.
    -   L’ascolto privato è supportato su Roam per Mac, iPad, iPhone, VisionOS e Apple TV, ma non funziona su tutte le TV Roku.

## Problemi comuni

-   Cosa posso fare se Roam non trova automaticamente la mia TV
    -   [Vedi qui](/manually-add-tv)
-   Roam non funziona correttamente sul mio Apple Watch
    -   Vai in **Impostazioni -> Sistema -> Impostazioni di sistema avanzate -> Controllo tramite app mobili** e assicurati che sia impostato su **Permissivo**
-   Perché la modalità cuffie (ascolto privato) non funziona sulla mia TV?
    -   Al momento la modalità cuffie non funziona su alcune TV. Se non funziona con Roam, ma funziona con l’app ufficiale Roku, ti prego di inviare il modello della tua Roku e qualsiasi altra informazione utile via email a [roam-support@msd3.io](mailto:roam-support@msd3.io). La tua segnalazione mi aiuterà a risolvere questo bug.
-   Se ho un altro problema o voglio semplicemente dare un feedback?
    -   Se si tratta di un bug, il modo migliore è avviare una segnalazione feedback dall’applicazione
        -   Entra nell’app Roam e apri la pagina impostazioni
        -   Fai clic su "Invia feedback". Questo genererà un report diagnostico condivisibile con il supporto Roam (roam-support@msd3.io)
        -   Se la tua app si blocca, assicurati anche che le analisi siano attive in Impostazioni -> Privacy e Sicurezza -> Analisi e miglioramenti
            -   Attiva "Condividi analisi iPhone & Watch" e poi "Condividi con gli sviluppatori" così Apple mi segnalerà se l’app si arresta in modo anomalo
    -   Se si tratta di una richiesta di nuova funzionalità, puoi inviare una email (roam-support@msd3.io), scrivermi direttamente in chat nell’app Roam (Impostazioni -> Chatta con lo sviluppatore) oppure unirti al [Roam Discord](https://discord.gg/FqaTNRccbG).
-   Perché i tasti freccia a volte non funzionano su iPad?
    -   Questo succede perché iPadOS a volte intercetta i tasti freccia per navigare tra i pulsanti a schermo prima che l’app possa rilevarli
    -   Puoi risolvere andando su Impostazioni -> Accessibilità -> Tastiere e disattivando "Accesso completo alla tastiera" oppure andando su Impostazioni -> Accessibilità -> Tastiere -> Accesso completo alla tastiera -> Comandi -> Base e disattivando i comandi “Sposta in su”, “Sposta in giù”, “Sposta a sinistra” e “Sposta a destra”
    -   Puoi anche rimappare i tasti direzionali in Roam sotto **Impostazioni -> Scorciatoie da tastiera**. Utilizzando il modificatore Command (⌘) in una scorciatoia si previene l’intercettazione dei tasti freccia semplici da parte di Accesso completo alla tastiera.
-   Perché quello che scrivo sulla tastiera non appare sulla TV?
    -   Alcune app Roku ignorano l’input dalla tastiera hardware. Puoi verificare se si tratta di un bug di Roam o dell’app provando la funzione tastiera nell’app ufficiale Roku e vedere se funziona
    -   Su macOS non c’è il pulsante tastiera perché la tastiera del Mac funziona automaticamente con la TV quando la finestra Roam è attiva. Su iOS e iPadOS usa invece il pulsante tastiera nel telecomando. watchOS non supporta l’inserimento da tastiera in questo momento.
    -   App con bug noti
        -   Prime Video
-   Perché Roam funziona su iPhone e Mac ma non su Apple Watch?
    -   L’app WatchOS si connette alla TV tramite l’API ECP della TV, che deve essere abilitata su alcune TV Roku. Per abilitarla, vai su **Impostazioni -> Sistema -> Impostazioni di sistema avanzate -> Controllo tramite app mobili** e assicurati che "Accesso di rete" sia impostato su "Permissivo"
-   Perché non posso accendere la TV dal mio Apple Watch?
    -   Apple Watch non può usare la normale API di riattivazione per accendere la TV a meno che **Avvio rapido TV** non sia abilitato sulla Roku TV. Per abilitarlo:
        -   Premi il tasto **Home** sul telecomando della tua Roku TV
        -   Scorri su o giù e seleziona **Impostazioni**
        -   Seleziona **Sistema**, poi **Alimentazione**
        -   Seleziona **Avvio rapido TV**
        -   Evidenzia **Attiva Avvio rapido TV** e premi **OK** sul telecomando per selezionare la casella

## Altre risorse

Se hai domande o problemi, contattami a: [roam-support@msd3.io](mailto:roam-support@msd3.io). Puoi anche scrivermi direttamente in chat nell’app Roam (Impostazioni -> Chatta con lo sviluppatore) o unirti al [Roam Discord](https://discord.gg/FqaTNRccbG).

-   [Informativa sulla privacy](/privacy)
-   [Repository principale su GitHub](https://github.com/msdrigg/roam)
-   [Roam Discord](https://discord.gg/FqaTNRccbG)
-   [Scarica dall'app store](https://apps.apple.com/us/app/roam/6469834197)
-   [Roadmap](/upcoming-work)
-   [Changelog](/changes)
-   [Dispositivi Roku testati](/tested-tvs)
-   [Offrimi un caffè](/coffee)
