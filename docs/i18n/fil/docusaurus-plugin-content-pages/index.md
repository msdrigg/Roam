---
hide_table_of_contents: true
---

<head>
    <meta name="apple-itunes-app" content="app-id=6469834197"/>
</head>

## Tungkol sa Roam

:::warning

Ito ay support page para sa Roam application, hindi Roly. Kamakailan ko lang nalaman na kinopya ng Roly app ang aking source code at app store page, pati na rin ang pag-link dito sa support page ko. Ito ay panlilinlang at mali.

:::

:::tip[Bilhan mo ako ng kape]

Libreng gamitin ang Roam, walang ads at walang bayad na bersyon. Kung nakatulong ito sa'yo, pwede kang [magbigay ng tip](/coffee).

:::

Lahat ng gusto mo, wala ng hindi mo kailangan - hatid ng Roam

-   Tumakbo sa Mac, iPhone, iPad, Apple Watch, Vision Pro o Apple TV!
-   Smart integration sa platform gamit ang keyboard shortcuts sa Mac, at paggamit ng hardware volume buttons para kontrolin ang TV Volume sa iOS
-   Gumamit ng shortcuts at widgets para kontrolin ang TV mo kahit hindi binubuksan ang app!
-   Sinusuportahan ang Headphones mode (a.k.a. private listening) sa Mac, iPad, iPhone, VisionOS, at Apple TV (ipatugtog ang audio ng TV sa iyong device)
-   Auto-discover ng mga device sa iyong local network agad kapag binuksan ang app
-   Intuitive na disenyo gamit ang native SwiftUI design system ng Apple
-   Mabilis at magaang gamitin-mas mababa pa sa 8 MB sa lahat ng device at bumubukas sa wala pang kalahating segundo!
-   Open source (https://github.com/msdrigg/roam)

## Mga Tampok

-   Remote controls
    -   May standard na Roku remote controls ang Roam gaya ng directional buttons, select, back, home, play/pause, at iba pang TV controls kapag supported ng Roku.
    -   Maaaring hindi gumana ang volume controls sa Roku Sticks dahil HDMI-only ang mga ito at hindi kayang kontrolin ang TV volume gamit ang Roam Roku network commands.
-   Keyboard input
    -   Sa macOS, walang keyboard button. Kapag nakatutok ang Roam window, awtomatikong gumagana ang Mac keyboard sa TV.
    -   Sa iOS at iPadOS, may keyboard button sa itaas ng remote.
    -   Sa watchOS, wala pang keyboard functionality sa ngayon.
    -   May ilang Roku apps na hindi tumatanggap ng keyboard input mula sa remote apps. Halimbawa na dito ang Prime Video, kung saan maaaring hindi gumana ang keyboard entry dahil hindi ina-allow ng app mismo.
-   Keyboard shortcuts
    -   Iniuugnay ng Roam ang mga key ng hardware keyboard sa remote actions (directional buttons, select/OK, back, home, volume, mute, play/pause, at iba pa). Naiiba ito sa on-screen text entry.
    -   Pwede mong i-customize ang mga shortcut na ito sa **Settings -> Keyboard shortcuts** sa Mac, iPhone, iPad, at Vision Pro (hindi ito available sa watchOS).
    -   Piliin ang isang row para palitan ang shortcut, mag-right click (Mac) o mag-swipe (iPhone/iPad) sa row para i-reset, o gamitin ang **Reset All** / **Clear All**. Default na gumagamit ng Command (⌘) modifier.
-   Paste a link to play (macOS)
    -   Sa Mac, kopyahin ang video link, i-click ang Roam window, at pindutin ang **⌘V**. Bubuksan ng Roam ang matching app sa iyong Roku at sisimulan ang pagpapatugtog ng content.
    -   Sinusuportahang mga serbisyo: YouTube, Amazon Prime Video, Netflix, Disney+, Hulu, Max, Paramount+, Peacock, Tubi, Sling, at The Roku Channel.
    -   Kung nakatutok sa TV text field, ang ⌘V ay magta-type ng clipboard text doon imbes na buksan ang link.
-   Headphones mode/private listening
    -   Pinapatugtog ng private listening ang TV audio sa iyong device kapag supported ng iyong Roku device.
    -   Suportado ang private listening sa Roam sa Mac, iPad, iPhone, VisionOS, at Apple TV, ngunit hindi ito gumagana sa lahat ng Roku TV.

## Mga Karaniwang Isyu

-   Ano ang gagawin kung hindi nadedetect ni Roam ang TV ko?
    -   [Tingnan dito](/manually-add-tv)
-   Hindi gumagana nang maayos ang Roam sa Apple Watch ko
    -   Pumunta sa **Settings -> System -> Advanced System Settings -> Control by mobile apps** at tiyaking nasa **Permissive** ito.
-   Bakit hindi gumagana ang headphones mode (private listening) sa TV ko?
    -   Sa ngayon, hindi gumagana ang headphones mode sa ilang TV. Kung hindi gumana ang headphones mode sa Roam pero gumagana sa opisyal na Roku app, paki-share ang modelo ng iyong Roku at iba pang mahalagang detalye sa [roam-support@msd3.io](mailto:roam-support@msd3.io). Makakatulong ito upang malaman ko kung saan magsisimula sa pag-aayos ng bug na ito.
-   Paano kung may iba pa akong problema o gusto ko lang magbigay ng feedback?
    -   Kung bug ito, pinakamabuting magsimula ng feedback report mula mismo sa app:
        -   Buksan ang Roam app at pumunta sa settings page
        -   I-click ang "Send feedback". Magge-generate ito ng diagnostic report na maaaring ipadala sa roam support (roam-support@msd3.io)
        -   Kung bumabagsak/crash ang app, siguraduhing nakabukas ang analytics sa Settings -> Privacy & Security -> Analytics & Improvments
            -   I-on ang "Share iPhone & Watch Analytics" at pagkatapos ay i-on ang "Share With App Developers" upang i-report ng apple kapag bumagsak/crash ang app mo.
    -   Kung request para sa bagong feature, maaari kang magpadala ng email (roam-support@msd3.io), mag-chat diretso sa akin sa Roam app (Settings -> Chat with the Developer) o sumali sa [Roam Discord](https://discord.gg/FqaTNRccbG).
-   Bakit paminsan hindi gumagana ang arrow keys sa iPad?
    -   Ito ay dahil minsan kinukuha ng iPadOS ang arrow keys at ginagamit ito sa pag-navigate ng mga buton sa screen bago pa ito madetect ng app
    -   Pwede mo itong lampasan sa pamamagitan ng Settings -> Accessiblity -> Keyboards at i-off ang "Full Keyboard Access" o kaya pumunta sa Settings -> Accessiblity -> Keyboards -> Full Keyboard Access -> Commands -> Basic at i-off ang "Move Up", "Move Down", "Move Left" at "Move Right" na commands.
    -   Pwede mo rin i-remap ang directional shortcuts sa Roam sa ilalim ng **Settings -> Keyboard shortcuts**. Kung may Command (⌘) modifier ang shortcut, hihinto ang Full Keyboard Access sa pag-intercept ng plain keys gaya ng arrow keys.
-   Bakit hindi lumalabas sa TV ang tina-type ko sa keyboard?
    -   Sa ilang Roku Apps, hindi tinatanggap ng app ang hardware keyboard entry. Pwede mong subukan kung bug ito sa Roam o sa app mismo sa pamamagitan ng paggamit ng keyboard entry feature sa opisyal na Roku App at silipin kung gumagana ito.
    -   Sa macOS, walang keyboard button dahil awtomatikong gumagana ang Mac keyboard sa TV kapag nakatutok ang Roam window. Sa iOS at iPadOS, gamitin ang keyboard button sa taas ng remote. Hindi sumusuporta ng keyboard input ang watchOS sa ngayon.
    -   Apps na kilala ang bug:
        -   Prime Video
-   Bakit gumagana ang Roam sa iPhone at Mac app ko pero hindi sa Apple Watch?
    -   Ang WatchOS app ay kumokonekta sa TV gamit ang TV's ECP API na dapat naka-enable sa ilang Roku TV. Para ma-enable ito, pumunta sa **Settings -> System -> Advanced System Settings -> Control by mobile apps** at tiyaking naka-set sa "Permissive" ang "Network Access".
-   Bakit hindi ko mapatay o mabuksan ang TV gamit ang Apple Watch?
    -   Hindi magagamit ng Apple Watch ang standard wake API para buksan ang TV maliban na lang kung naka-on ang **Fast TV Start** sa Roku TV. Para i-enable ito:
        -   Pindutin ang **Home** button sa Roku TV remote
        -   Umakyat o bumaba gamit ang remote at piliin ang **Settings**
        -   Piliin ang **System**, pagkatapos **Power**
        -   Piliin ang **Fast TV Start**
        -   I-highlight ang **Enable Fast TV Start** at pindutin ang **OK** sa remote para i-check ang kahon

## Iba Pang Resources

Kung may mga tanong o problema ka, maaari mo akong kontakin sa: [roam-support@msd3.io](mailto:roam-support@msd3.io). Pwede ka rin makipag-chat sa akin direkta sa Roam app (Settings -> Chat with the Developer) o sumali sa [Roam Discord](https://discord.gg/FqaTNRccbG).

-   [Privacy Policy](/privacy)
-   [Core Repository on GitHub](https://github.com/msdrigg/roam)
-   [Roam Discord](https://discord.gg/FqaTNRccbG)
-   [Download on the app store](https://apps.apple.com/us/app/roam/6469834197)
-   [Roadmap](/upcoming-work)
-   [Changelog](/changes)
-   [Roku Devices Tested](/tested-tvs)
-   [Bilhan mo ako ng kape](/coffee)