---
hide_table_of_contents: true
---

<head>
    <meta name="apple-itunes-app" content="app-id=6469834197"/>
</head>

## À propos de Roam

:::warning

Ceci est une page de support pour l'application Roam, pas Roly. J'ai récemment découvert que l'application Roly a copié mon code source et la page de mon application sur l'App Store, en redirigeant même ici vers ma page de support. Ceci est frauduleux et incorrect.

:::

:::tip[Offrez-moi un café]

Roam est gratuit, sans publicité et sans formule payante. Si l'application vous est utile, vous pouvez [laisser un pourboire](/coffee).

:::

Roam offre tout ce dont vous avez besoin, sans superflu

-   Fonctionne sur Mac, iPhone, iPad, Apple Watch, Vision Pro et Apple TV !
-   Intégration intelligente à la plateforme : raccourcis clavier sur Mac, boutons de volume matériel pour contrôler le volume de la TV sur iOS.
-   Utilisez les raccourcis et widgets pour contrôler votre TV sans jamais ouvrir l’application !
-   Prise en charge du mode écouteurs (aussi appelé écoute privée) sur Mac, iPad, iPhone, VisionOS et Apple TV (écoutez le son de votre TV depuis votre appareil)
-   Détection automatique des appareils sur votre réseau local dès l’ouverture de l’application
-   Design intuitif reposant sur le système natif SwiftUI d’Apple
-   Rapide et léger, moins de 8 Mo sur tous les appareils et s'ouvre en moins d’une demi-seconde !
-   Open source (https://github.com/msdrigg/roam)

## Fonctionnalités

-   Télécommande
    -   Roam propose toutes les commandes habituelles d'une télécommande Roku : boutons directionnels, sélection, retour, accueil, lecture/pause et autres commandes de TV lorsque le Roku les prend en charge.
    -   Les commandes de volume peuvent ne pas fonctionner avec les Roku Stick car ces appareils ne sont compatibles HDMI et ne peuvent pas contrôler le volume de la TV via les commandes réseau Roku de Roam.
-   Saisie au clavier
    -   Sur macOS, pas de bouton clavier. Lorsque la fenêtre Roam est active, le clavier du Mac fonctionne automatiquement avec la TV.
    -   Sur iOS et iPadOS, un bouton clavier se trouve en haut de la télécommande.
    -   watchOS ne propose pas de fonctionnalité clavier actuellement.
    -   Certaines applications Roku ignorent la saisie clavier des applis de télécommande. Prime Video en est un exemple connu où la saisie via le clavier peut ne pas fonctionner car l’application Roku ne l'accepte pas.
-   Raccourcis clavier
    -   Roam associe les touches physiques du clavier à des actions sur la télécommande (touches directionnelles, sélection/OK, retour, accueil, volume, muet, lecture/pause, etc). Ceci est indépendant de la saisie de texte à l'écran.
    -   Vous pouvez personnaliser ces raccourcis dans **Réglages -> Raccourcis clavier** sur Mac, iPhone, iPad et Vision Pro (watchOS n’a pas de raccourcis clavier).
    -   Sélectionnez une ligne pour modifier son raccourci, faites un clic droit (Mac) ou un balayage (iPhone/iPad) sur une ligne pour la réinitialiser, ou utilisez **Tout réinitialiser** / **Tout effacer**. Les raccourcis par défaut utilisent la touche Commande (⌘).
-   Coller un lien à lire (macOS)
    -   Sur Mac, copiez un lien vidéo, cliquez sur la fenêtre Roam, puis appuyez sur **⌘V**. Roam ouvrira l’application correspondante sur votre Roku et commencera la lecture du contenu.
    -   Services pris en charge : YouTube, Amazon Prime Video, Netflix, Disney+, Hulu, Max, Paramount+, Peacock, Tubi, Sling et The Roku Channel.
    -   Si un champ de saisie texte est sélectionné sur la TV, ⌘V saisira le texte du presse-papiers dans ce champ au lieu d’ouvrir un lien.
-   Mode écouteurs / écoute privée
    -   L’écoute privée fait passer le son de la TV par votre appareil sur les Roku compatibles.
    -   L’écoute privée est possible dans Roam sur Mac, iPad, iPhone, VisionOS et Apple TV, mais ne fonctionne pas sur tous les modèles Roku TV.

## Problèmes courants

-   Que faire si Roam ne découvre pas automatiquement ma TV
    -   [Voir ici](/manually-add-tv)
-   Roam ne fonctionne pas correctement sur mon Apple Watch
    -   Rendez-vous dans **Réglages -> Système -> Paramètres système avancés -> Contrôle par applications mobiles** et vérifiez que l’option est réglée sur **Permissif**
-   Pourquoi le mode écouteurs (appelé aussi écoute privée) ne fonctionne pas sur ma TV ?
    -   Le mode écouteurs ne fonctionne pas encore sur certains téléviseurs. Si ce mode fonctionne avec l’application Roku officielle mais pas avec Roam, merci de communiquer le modèle exact de votre Roku ainsi que tout renseignement pertinent par email à [roam-support@msd3.io](mailto:roam-support@msd3.io). Votre retour m’aidera à repérer l’origine du problème pour le corriger.
-   Que faire si j’ai un autre problème ou si je souhaite simplement donner mon avis ?
    -   S’il s’agit d’un bug, il est préférable de lancer un rapport de feedback directement depuis l’application :
        -   Ouvrez l’application Roam et allez sur la page des réglages
        -   Cliquez sur "Envoyer des retours". Cela générera un rapport de diagnostic à partager avec le support (roam-support@msd3.io)
        -   Si votre appli plante, assurez-vous aussi que les analyses sont activées dans Réglages -> Confidentialité & sécurité -> Analyses et améliorations
            -   Activez "Partager les analyses d’iPhone & Watch" puis "Partager avec les développeurs d’applications" pour qu’Apple me signale les crashs de votre application
    -   Pour une demande de fonctionnalité, vous pouvez envoyer un email (roam-support@msd3.io), discuter directement avec moi dans l’app Roam (Réglages -> Discuter avec le développeur) ou rejoindre le [Roam Discord](https://discord.gg/FqaTNRccbG).
-   Pourquoi les flèches directionnelles ne fonctionnent-elles pas toujours sur iPad ?
    -   Cela vient du fait qu’iPadOS intercepte parfois les flèches du clavier et les utilise pour naviguer dans les boutons d’écran avant qu’elles ne soient détectées par Roam
    -   Vous pouvez contourner ce problème en allant dans Réglages -> Accessibilité -> Claviers et en désactivant "Accès clavier complet" ou en allant dans Réglages -> Accessibilité -> Claviers -> Accès clavier complet -> Commandes -> Basique et en désactivant les commandes "Déplacer vers le haut", "Déplacer vers le bas", "Déplacer vers la gauche" et "Déplacer vers la droite"
    -   Vous pouvez aussi réaffecter les raccourcis directionnels dans Roam sous **Réglages -> Raccourcis clavier**. Garder la touche Commande (⌘) sur un raccourci empêche "Accès clavier complet" d’intercepter les touches simples comme les flèches.
-   Pourquoi la saisie au clavier ne s’affiche-t-elle pas sur la TV ?
    -   Sur certaines applications Roku, la saisie clavier matérielle est ignorée. Pour savoir si le problème vient de Roam ou de l’application, essayez la saisie clavier sur l’application officielle Roku et vérifiez si cela fonctionne.
    -   Sur macOS, il n’y a pas de bouton clavier car le clavier du Mac fonctionne automatiquement avec la TV quand la fenêtre Roam est active. Sur iOS et iPadOS, utilisez le bouton clavier en haut de la télécommande. watchOS ne prend pas en charge la saisie clavier pour le moment.
    -   Applications avec problèmes connus
        -   Prime Video
-   Pourquoi Roam fonctionne sur mon iPhone et mon Mac mais pas sur mon Apple Watch ?
    -   L’application WatchOS se connecte à la TV via l’API ECP de la TV, qui doit être activée sur certains modèles Roku TV. Pour l’activer, rendez-vous dans **Réglages -> Système -> Paramètres système avancés -> Contrôle par applications mobiles** et assurez-vous que "Accès réseau" soit réglé sur "Permissif"
-   Pourquoi est-ce que je ne peux pas allumer ma TV depuis mon Apple Watch ?
    -   L’Apple Watch ne peut pas utiliser l’API standard pour allumer la TV sauf si **Démarrage rapide TV** est activé sur la Roku TV. Pour l’activer :
        -   Appuyez sur le bouton **Accueil** de la télécommande Roku TV
        -   Naviguez vers le haut ou le bas et sélectionnez **Réglages**
        -   Allez dans **Système**, puis **Alimentation**
        -   Sélectionnez **Démarrage rapide TV**
        -   Mettez en surbrillance **Activer le démarrage rapide TV** et appuyez sur **OK** sur la télécommande pour cocher la case

## Autres ressources

Pour toute question ou problème, contactez-moi à : [roam-support@msd3.io](mailto:roam-support@msd3.io). Vous pouvez aussi discuter directement avec moi dans l’app Roam (Réglages -> Discuter avec le développeur) ou rejoindre le [Roam Discord](https://discord.gg/FqaTNRccbG).

-   [Politique de confidentialité](/privacy)
-   [Dépôt principal sur GitHub](https://github.com/msdrigg/roam)
-   [Roam Discord](https://discord.gg/FqaTNRccbG)
-   [Télécharger sur l’App Store](https://apps.apple.com/us/app/roam/6469834197)
-   [Feuille de route](/upcoming-work)
-   [Historique des changements](/changes)
-   [Appareils Roku testés](/tested-tvs)
-   [Offrez-moi un café](/coffee)
