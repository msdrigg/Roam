---
hide_table_of_contents: true
---

<head>
    <meta name="apple-itunes-app" content="app-id=6469834197"/>
</head>

## Über Roam

:::warning

Dies ist eine Support-Seite für die Roam-App, nicht für Roly. Ich habe kürzlich erfahren, dass die Roly-App meinen Quellcode und meine App Store-Seite kopiert hat und sogar hierher auf meine Support-Seite verlinkt. Das ist betrügerisch und falsch.

:::

:::tip[Spendier mir einen Kaffee]

Roam ist kostenlos, ohne Werbung und ohne kostenpflichtige Stufen. Wenn es dir hilft, kannst du [ein Trinkgeld hinterlassen](/coffee).

:::

Roam bietet alles, was du willst – und nichts, was du nicht brauchst

-   Läuft auf Mac, iPhone, iPad, Apple Watch, Vision Pro oder Apple TV!
-   Intelligente Plattformintegration mit Tastenkombinationen am Mac, Nutzung der Lautstärketasten zur Steuerung der TV-Lautstärke auf iOS
-   Steuerung deines Fernsehers mit Kurzbefehlen und Widgets, ohne die App öffnen zu müssen!
-   Kopfhörermodus (auch als "Privathören" bekannt) wird unterstützt auf Mac, iPad, iPhone, VisionOS und Apple TV (Spiele den Fernsehton über dein Gerät ab)
-   Erkennt Geräte in deinem lokalen Netzwerk sofort beim Öffnen der App
-   Intuitives Design mit Apples nativer SwiftUI-Designsystematik
-   Schnell und leichtgewichtig, unter 8 MB auf allen Geräten und startet in weniger als einer halben Sekunde!
-   Open Source (https://github.com/msdrigg/roam)

## Features

-   Fernbedienung
    -   Roam enthält alle gängigen Roku-Fernbedienungsfunktionen, einschließlich Richtungstasten, Auswahl, Zurück, Home, Play/Pause und zusätzliche Fernsehfunktionen, wenn dein Roku diese unterstützt.
    -   Die Lautstärkeregelung funktioniert möglicherweise nicht auf Roku Sticks, da diese Geräte nur HDMI verwenden und keine Lautstärkeregelung über Roams Roku-Netzwerkbefehle ermöglichen.
-   Tastatureingabe
    -   Unter macOS gibt es keinen speziellen Tastatur-Button. Ist das Roam-Fenster fokussiert, funktioniert die Mac-Tastatur direkt mit dem Fernseher.
    -   Unter iOS und iPadOS ist oben auf der Fernbedienung ein Tastatur-Button.
    -   watchOS bietet derzeit keine Tastaturfunktionen.
    -   Einige Roku-Apps ignorieren Tastatureingaben von Fremd-Apps. Prime Video ist ein bekanntes Beispiel, bei dem die Tastatureingabe möglicherweise nicht funktioniert, da die Roku-App dies nicht akzeptiert.
-   Tastaturkürzel
    -   Roam ordnet Hardware-Tastenkürzel Fernbedienungsaktionen zu (Richtungstasten, Auswahl/OK, Zurück, Home, Lautstärke, Stummschalten, Play/Pause und mehr). Dies ist getrennt von der Texteingabe am Bildschirm.
    -   Diese Tastaturkürzel kannst du in **Einstellungen -> Tastaturkürzel** auf Mac, iPhone, iPad und Vision Pro anpassen (watchOS unterstützt keine Tastaturkürzel).
    -   Wähle eine Zeile zur Änderung, mache einen Rechtsklick (Mac) oder wische (iPhone/iPad) auf eine Zeile, um sie zurückzusetzen, oder nutze **Alle zurücksetzen** / **Alle löschen**. Standardmäßig wird die Command (⌘)-Taste verwendet.
-   Link einfügen zum Abspielen (macOS)
    -   Am Mac genügt es, einen Videolink zu kopieren, ins Roam-Fenster zu klicken und **⌘V** zu drücken. Roam öffnet die passende App auf deinem Roku und spielt den Inhalt ab.
    -   Unterstützte Dienste sind YouTube, Amazon Prime Video, Netflix, Disney+, Hulu, Max, Paramount+, Peacock, Tubi, Sling und The Roku Channel.
    -   Ist auf dem Fernseher ein Textfeld ausgewählt, tippt ⌘V den Text aus der Zwischenablage stattdessen in dieses Feld.
-   Kopfhörermodus/Privates Hören
    -   Privathören gibt den Ton deines Fernsehers auf deinem Gerät wieder (auf unterstützten Roku-Geräten).
    -   Privathören ist mit Roam auf Mac, iPad, iPhone, VisionOS und Apple TV verfügbar, funktioniert jedoch nicht auf jedem Roku-Fernseher.

## Häufige Probleme

-   Was kann ich tun, wenn Roam meinen Fernseher nicht automatisch findet?
    -   [Siehe hier](/manually-add-tv)
-   Roam funktioniert auf meiner Apple Watch nicht richtig
    -   Bitte gehe zu **Einstellungen -> System -> Erweiterte Systemeinstellungen -> Steuerung durch mobile Apps** und stelle sicher, dass hier **Zulässig** ausgewählt ist
-   Warum funktioniert der Kopfhörermodus („Privathören“) nicht auf meinem Fernseher?
    -   Der Kopfhörermodus funktioniert derzeit auf einigen Fernsehern nicht. Wenn der Modus mit Roam nicht funktioniert, aber mit der offiziellen Roku-App, sende bitte den Modellnamen deines Roku und weitere relevante Infos per E-Mail an [roam-support@msd3.io](mailto:roam-support@msd3.io). Dein Bericht hilft mir, den Fehler gezielt zu finden.
-   Was, wenn ich ein anderes Problem habe oder Feedback geben möchte?
    -   Handelt es sich um einen Fehler, am besten direkt aus der App eine Rückmeldung starten:
        -   Öffne Einstellungen in Roam und gehe auf die Einstellungsseite
        -   Klicke auf „Feedback senden“. Das erzeugt einen Diagnosebericht, der an roam support (roam-support@msd3.io) weitergegeben werden kann
        -   Stürzt deine App ab, stelle sicher, dass die Analytik in den Einstellungen -> Datenschutz & Sicherheit -> Analysen & Verbesserungen aktiviert ist
            -   Aktiviere „iPhone & Watch-Analysen teilen“ und anschließend „Mit App-Entwicklern teilen“, sodass Apple mir beim Absturz deiner App Bericht erstattet
    -   Bei neuen Feature-Wünschen kannst du eine E-Mail schreiben (roam-support@msd3.io), direkt in der Roam-App mit mir chatten (Einstellungen -> Mit Entwickler chatten) oder dem [Roam Discord](https://discord.gg/FqaTNRccbG) beitreten.
-   Warum funktionieren die Pfeiltasten manchmal nicht am iPad?
    -   Das kommt vor, weil iPadOS manchmal die Kontrolle über die Pfeiltasten übernimmt und sie vor Roam abfängt, um zwischen Bildschirm-Buttons zu navigieren.
    -   Du kannst dies umgehen, indem du in die Einstellungen -> Bedienungshilfen -> Tastaturen gehst und „Volle Tastaturzugänglichkeit“ deaktivierst oder alternativ unter Einstellungen -> Bedienungshilfen -> Tastaturen -> Volle Tastaturzugänglichkeit -> Befehle -> Basis die Kommandos „Nach oben bewegen“, „Nach unten bewegen“, „Nach links bewegen“ und „Nach rechts bewegen“ ausschaltest.
    -   Du kannst die Richtungstasten in Roam ebenfalls in **Einstellungen -> Tastaturkürzel** neu zuweisen. Wenn ein Command (⌘)-Modifikator für einen Shortcut benutzt wird, verhindert das, dass „Volle Tastaturzugänglichkeit“ einfache Tasten (wie die Pfeiltasten) abfängt.
-   Warum erscheinen meine Tastatureingaben nicht am TV?
    -   Manche Roku-Apps ignorieren die Tastatureingabe über externe Hardware. Du kannst testen, ob dies ein Roam-Fehler ist, indem du dieselbe Funktion im offiziellen Roku-App ausprobierst.
    -   Auf macOS gibt es keinen Tastatur-Button, denn die Tastatur funktioniert direkt, solange das Roam-Fenster im Vordergrund ist. Auf iOS und iPadOS nutze den Button oben an der Fernbedienung. watchOS unterstützt bis jetzt keine Tastatureingabe.
    -   Bekannte problematische Apps:
        -   Prime Video
-   Warum funktioniert Roam auf meinem iPhone und Mac, aber nicht auf der Apple Watch?
    -   Die WatchOS-App verbindet sich über die ECP-API des Fernsehers, die bei manchen Roku-TVs erst aktiviert werden muss: **Einstellungen -> System -> Erweiterte Systemeinstellungen -> Steuerung durch mobile Apps**, und „Netzwerkzugriff“ auf „Zulässig“ stellen
-   Warum kann ich meinen Fernseher nicht mit der Apple Watch einschalten?
    -   Die Apple Watch kann den normalen Wake-API nicht nutzen, außer auf deinem Roku TV ist **Fast TV Start** aktiviert. Um dies zu aktivieren:
        -   Drücke die **Home**-Taste auf deiner Roku TV-Fernbedienung
        -   Scrolle nach oben oder unten und wähle **Einstellungen**
        -   Wähle **System**, dann **Energie**
        -   Wähle **Fast TV Start**
        -   Markiere **Fast TV Start aktivieren** und drücke **OK** auf der Fernbedienung, um das Feld anzuhaken

## Weitere Ressourcen

Falls du Fragen oder Probleme hast, schreibe mir an: [roam-support@msd3.io](mailto:roam-support@msd3.io). Du kannst auch direkt in der Roam App mit mir chatten (Einstellungen -> Mit Entwickler chatten) oder dem [Roam Discord](https://discord.gg/FqaTNRccbG) beitreten.

-   [Datenschutzerklärung](/privacy)
-   [Core Repository auf GitHub](https://github.com/msdrigg/roam)
-   [Roam Discord](https://discord.gg/FqaTNRccbG)
-   [Im App Store herunterladen](https://apps.apple.com/us/app/roam/6469834197)
-   [Roadmap](/upcoming-work)
-   [Changelog](/changes)
-   [Getestete Roku-Geräte](/tested-tvs)
-   [Spendier mir einen Kaffee](/coffee)
