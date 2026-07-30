---
hide_table_of_contents: true
---

<head>
    <meta name="apple-itunes-app" content="app-id=6469834197"/>
</head>

## À propos de Roam

:::warning

Ceci est une page de support pour l’application Roam, et non pour Roly. J’ai récemment appris que l’application Roly a copié mon code source et la page App Store, et renvoie même ici vers ma page de soutien. Ceci est frauduleux et inapproprié.

:::

:::tip[Offrez-moi un café]

Roam est gratuit, sans publicités ni forfait payant. Si l’application vous est utile, vous pouvez [laisser un pourboire](/coffee).

:::

Roam offre tout ce dont vous avez besoin, sans le superflu

-   Fonctionne sur Mac, iPhone, iPad, Apple Watch, Vision Pro ou Apple TV!
-   Intégration intelligente à la plateforme, avec raccourcis clavier sur Mac et contrôle du volume de la télévision via les boutons volume matériels sur iOS
-   Contrôlez votre télévision avec des raccourcis et widgets, sans même ouvrir l'application!
-   Mode écoute privée (aussi appelé "écoute au casque") pris en charge sur Mac, iPad, iPhone, VisionOS et Apple TV (écoutez le son de votre télévision sur votre appareil)
-   Découverte automatique des appareils sur votre réseau local dès que vous ouvrez l’application
-   Design intuitif avec le système natif SwiftUI d’Apple
-   Rapide et léger, moins de 8 Mo sur tous les appareils et ouverture en moins d’une demi-seconde!
-   Code source ouvert (https://github.com/msdrigg/roam)

## Fonctionnalités

-   Télécommande
    -   Roam propose toutes les commandes classiques d'une télécommande Roku, incluant les boutons directionnels, sélectionner, retour, maison, lecture/pause et les contrôles de la télé s’ils sont pris en charge par le Roku.
    -   Les contrôles de volume peuvent ne pas fonctionner avec les Roku Stick car ces appareils HDMI uniquement ne peuvent pas contrôler le volume du téléviseur via les commandes réseau de Roam.
-   Saisie au clavier
    -   Sur macOS, il n’y a pas de bouton clavier. Lorsque la fenêtre Roam est active, le clavier du Mac fonctionne automatiquement avec la télévision.
    -   Sur iOS et iPadOS, un bouton clavier se trouve en haut de la télécommande.
    -   Il n’y a pas de fonctionnalité clavier sur watchOS pour l’instant.
    -   Certaines applications Roku ignorent la saisie clavier depuis des applications distantes. Prime Video est un exemple connu où la saisie clavier pourrait ne pas fonctionner car l’app Roku la refuse.
-   Raccourcis clavier
    -   Roam associe certaines touches du clavier physique avec des actions de la télécommande (directionnelles, sélectionner/OK, retour, maison, volume, sourdine, lecture/pause, etc.). Ceci est distinct de la saisie de texte à l’écran.
    -   Vous pouvez personnaliser ces raccourcis dans **Réglages -> Raccourcis clavier** sur Mac, iPhone, iPad et Vision Pro (watchOS ne supporte pas les raccourcis clavier).
    -   Sélectionnez une rangée pour la modifier, faites un clic droit (Mac) ou glissez (iPhone/iPad) pour la réinitialiser, ou utilisez **Réinitialiser tout** / **Effacer tout**. Les raccourcis par défaut utilisent la touche Commande (⌘).
-   Coller un lien pour lire (macOS)
    -   Sur Mac, copiez un lien vidéo, cliquez dans la fenêtre Roam et appuyez sur **⌘V**. Roam ouvrira l’application correspondante sur votre Roku et lancera la lecture du contenu.
    -   Services pris en charge : YouTube, Amazon Prime Video, Netflix, Disney+, Hulu, Max, Paramount+, Peacock, Tubi, Sling, et The Roku Channel.
    -   Si un champ texte sur la TV est sélectionné, ⌘V inscrira le texte du presse-papier dans ce champ au lieu d’ouvrir un lien.
-   Mode écoute privée
    -   L’écoute privée transmet le son du téléviseur vers votre appareil sur les Roku compatibles.
    -   L’écoute privée est disponible dans Roam sur Mac, iPad, iPhone, VisionOS et Apple TV, mais ne fonctionne pas sur tous les modèles de Roku TV.

## Problèmes fréquents

-   Que faire si Roam ne détecte pas automatiquement ma TV
    -   [Consultez ici](/manually-add-tv)
-   Roam ne fonctionne pas correctement sur mon Apple Watch
    -   Veuillez aller dans **Réglages -> Système -> Paramètres système avancés -> Contrôle par applications mobiles** et vérifiez que c'est réglé à **Permissif**
-   Pourquoi le mode écoute privée ne fonctionne-t-il pas sur ma TV?
    -   L’écoute privée ne fonctionne pas actuellement sur certains téléviseurs. Si le mode écoute privée ne fonctionne pas avec Roam, mais fonctionne avec l’application officielle Roku, merci d’envoyer le modèle de votre Roku et toute information pertinente à [roam-support@msd3.io](mailto:roam-support@msd3.io). Votre rapport aidera à cibler la cause du problème.
-   Que faire si j’ai un autre problème ou si je veux simplement donner mon avis?
    -   En cas de bogue, il est préférable d’envoyer un rapport de rétroaction via l’application :
        -   Ouvrez l’application Roam et accédez à la page des réglages
        -   Cliquez sur « Envoyer un retour ». Un rapport de diagnostic pourra alors être partagé à roam support (roam-support@msd3.io)
        -   Si l’application plante, assurez-vous aussi d’avoir activé l’analytique dans Réglages -> Confidentialité et sécurité -> Analyse et amélioration
            -   Activez « Partager l’analyse iPhone et Watch » et ensuite « Partager avec les développeurs d’apps » pour qu’Apple me signale quand votre app plante
    -   Pour une nouvelle fonctionnalité, vous pouvez envoyer un courriel (roam-support@msd3.io), discuter avec moi directement dans l’application (Réglages -> Discuter avec le développeur) ou encore joindre le [Discord de Roam](https://discord.gg/FqaTNRccbG).
-   Pourquoi les flèches directionnelles ne fonctionnent-elles pas parfois sur iPad?
    -   Cela arrive parce qu’iPadOS prend parfois la main sur les flèches pour naviguer entre les boutons de l’interface avant que nous puissions les détecter
    -   Vous pouvez contourner le problème : allez dans Réglages -> Accessibilité -> Claviers et désactivez « Accès clavier complet » ou encore dans Réglages -> Accessibilité -> Claviers -> Accès clavier complet -> Commandes -> de base et désactivez les commandes « Monter », « Descendre », « Aller à gauche » et « Aller à droite »
    -   Vous pouvez aussi réassigner les raccourcis directionnels dans Roam sous **Réglages -> Raccourcis clavier**. Garde la touche Commande (⌘) comme modificateur pour éviter que le système n’intercepte les touches fléchées simples.
-   Pourquoi la saisie au clavier ne s’affiche-t-elle pas sur la TV
    -   Dans certaines applications Roku, la saisie via le clavier matériel est ignorée. Vous pouvez tester si le problème vient de Roam ou de l’app en utilisant la saisie clavier dans l’application Roku officielle pour voir si ça fonctionne
    -   Sur macOS, il n’y a pas de bouton clavier parce que le clavier Mac fonctionne directement avec la TV quand la fenêtre Roam est active. Sur iOS et iPadOS, utilisez le bouton clavier en haut de la télécommande. Le clavier n’est pas disponible sur watchOS pour l’instant.
    -   Applications connues comme problématiques
        -   Prime Video
-   Pourquoi Roam fonctionne-t-il sur mon iPhone et mon Mac, mais pas sur mon Apple Watch?
    -   L’application WatchOS communique avec la TV via l’API ECP, qui doit être activée sur certains Roku. Pour l’activer, allez dans **Réglages -> Système -> Paramètres système avancés -> Contrôle par applications mobiles** et assurez-vous que « Accès réseau » est réglé à « Permissif »
-   Pourquoi je ne peux pas allumer ma TV à partir de l’Apple Watch?
    -   L’Apple Watch ne peut pas utiliser l’API d’allumage standard sauf si le **Démarrage TV rapide** est activé sur le Roku. Pour l’activer :
        -   Appuyez sur le bouton **Accueil** de la télécommande Roku TV
        -   Faites défiler et sélectionnez **Réglages**
        -   Sélectionnez **Système**, puis **Énergie**
        -   Sélectionnez **Démarrage TV rapide**
        -   Sélectionnez **Activer Démarrage TV rapide** et appuyez sur **OK** pour cocher la case

## Autres ressources

Pour toute question ou problème, contactez-moi à [roam-support@msd3.io](mailto:roam-support@msd3.io). Vous pouvez aussi discuter avec moi directement dans l’application Roam (Réglages -> Discuter avec le développeur) ou rejoindre le [Discord de Roam](https://discord.gg/FqaTNRccbG).

-   [Politique de confidentialité](/privacy)
-   [Dépôt principal sur GitHub](https://github.com/msdrigg/roam)
-   [Discord Roam](https://discord.gg/FqaTNRccbG)
-   [Télécharger sur l’App Store](https://apps.apple.com/us/app/roam/6469834197)
-   [Feuille de route](/upcoming-work)
-   [Notes de version](/changes)
-   [Appareils Roku testés](/tested-tvs)
-   [Offrez-moi un café](/coffee)