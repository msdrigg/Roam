---
hide_table_of_contents: true
---

<head>
    <meta name="apple-itunes-app" content="app-id=6469834197"/>
</head>

## Sobre o Roam

:::warning

Esta é uma página de suporte para o aplicativo Roam, não para o Roly. Recentemente descobri que o aplicativo Roly copiou meu código-fonte e a página da App Store, inclusive direcionando para esta página de suporte. Isso é fraudulento e incorreto.

:::

:::tip[Apoie com um café]

O Roam é gratuito, sem anúncios e sem planos pagos. Se ele está sendo útil para você, você pode [deixar uma contribuição](/coffee).

:::

Roam oferece tudo o que você quer e nada do que você não quer

-   Funciona no Mac, iPhone, iPad, Apple Watch, Vision Pro ou Apple TV!
-   Integração inteligente com a plataforma: use atalhos de teclado no Mac, ou os botões de volume físico para controlar o volume da TV no iOS
-   Use atalhos e widgets para controlar sua TV sem sequer abrir o app!
-   Suporte ao modo fones de ouvido (também conhecido como escuta privada) no Mac, iPad, iPhone, VisionOS e Apple TV (reproduza o áudio da TV pelo seu dispositivo)
-   Descubra dispositivos na sua rede local assim que abrir o aplicativo
-   Design intuitivo com o sistema de design nativo SwiftUI da Apple
-   Rápido e leve, menos de 8 MB em todos os aparelhos e abre em menos de meio segundo!
-   Código aberto (https://github.com/msdrigg/roam)

## Funcionalidades

-   Controles remotos
    -   Roam inclui os controles remotos tradicionais dos aparelhos Roku, como botões direcionais, selecionar, voltar, home, play/pausa e controles específicos da TV quando o Roku é compatível.
    -   O controle de volume pode não funcionar em Roku Sticks, pois eles são dispositivos apenas HDMI e não podem controlar o volume da TV através dos comandos de rede do Roku via Roam.
-   Entrada via teclado
    -   No macOS, não há botão de teclado. Quando a janela do Roam está em foco, o teclado do Mac já funciona na TV automaticamente.
    -   No iOS e iPadOS, há um botão de teclado no topo do controle remoto.
    -   O watchOS não tem função de teclado neste momento.
    -   Alguns aplicativos do Roku ignoram entradas de teclado enviadas por apps remotos. O Prime Video, por exemplo, pode não funcionar com entrada por teclado porque o aplicativo do Roku não aceita.
-   Atalhos de teclado
    -   O Roam mapeia teclas do seu teclado físico para ações do controle remoto (botões direcionais, selecionar/OK, voltar, home, volume, mudo, play/pausa e outros). Isso é diferente da digitação de texto na tela.
    -   Você pode personalizar esses atalhos em **Configurações -> Atalhos de teclado** no Mac, iPhone, iPad e Vision Pro (o watchOS não possui atalhos de teclado).
    -   Selecione uma linha para alterar o atalho, clique com o botão direito (Mac) ou deslize (iPhone/iPad) uma linha para redefinir, ou use **Restaurar Tudo** / **Limpar Tudo**. O padrão usa o modificador Command (⌘).
-   Cole um link para assistir (macOS)
    -   No Mac, copie um link de vídeo, clique na janela do Roam e pressione **⌘V**. O Roam abre o aplicativo correspondente no seu Roku e inicia a reprodução do conteúdo.
    -   Serviços suportados incluem YouTube, Amazon Prime Video, Netflix, Disney+, Hulu, Max, Paramount+, Peacock, Tubi, Sling e The Roku Channel.
    -   Se um campo de texto da TV estiver selecionado, ⌘V digita o texto da área de transferência no campo em vez de abrir um link.
-   Modo fones de ouvido/escuta privada
    -   A escuta privada reproduz o áudio da TV no seu dispositivo em aparelhos Roku compatíveis.
    -   A escuta privada é suportada no Roam para Mac, iPad, iPhone, VisionOS e Apple TV, mas pode não funcionar em todos os modelos de Roku TV.

## Problemas Comuns

-   O que fazer se o Roam não encontrar minha TV automaticamente?
    -   [Veja aqui](/manually-add-tv)
-   O Roam não está funcionando corretamente no meu Apple Watch
    -   Por favor, vá até **Configurações -> Sistema -> Configurações Avançadas do Sistema -> Controle por aplicativos móveis** e confira se está definido como **Permissivo**
-   Por que o modo fones de ouvido (escuta privada) não funciona na minha TV?
    -   Em alguns modelos a escuta privada pode não funcionar. Se o modo não funcionar no Roam mas funcionar no app oficial do Roku, compartilhe o modelo do seu Roku e outras informações relevantes por e-mail para [roam-support@msd3.io](mailto:roam-support@msd3.io). Sua participação ajudará a identificar o problema.
-   E se eu tiver outro problema ou quiser enviar um feedback?
    -   Se for um bug, o melhor é enviar um relatório de feedback pelo aplicativo:
        -   Abra o app Roam e vá para a página de configurações
        -   Clique em "Enviar feedback". Isso gera um relatório de diagnóstico que pode ser compartilhado com o suporte (roam-support@msd3.io)
        -   Se o app estiver travando, assegure-se de que a análise está ativada em Configurações -> Privacidade e Segurança -> Análise e Melhorias
            -   Ative "Compartilhar análise do iPhone & Watch" e depois "Compartilhar com desenvolvedores" para que a Apple me avise caso o app trave
    -   Se for uma sugestão, pode enviar um e-mail (roam-support@msd3.io), conversar diretamente comigo no app Roam (Configurações -> Converse com o Desenvolvedor) ou entrar no [Roam Discord](https://discord.gg/FqaTNRccbG).
-   Por que às vezes as setas do teclado não funcionam no iPad?
    -   Isso acontece porque, em alguns casos, o iPadOS assume o controle das teclas de seta para navegação pela tela antes do Roam detectar.
    -   Você pode contornar isso em Configurações -> Acessibilidade -> Teclados e desativar "Acesso total ao teclado" ou indo em Configurações -> Acessibilidade -> Teclados -> Acesso total ao teclado -> Comandos -> Básico e desativar os comandos "Mover para cima", "Mover para baixo", "Mover para a esquerda" e "Mover para a direita".
    -   Você também pode remapear os atalhos direcionais do Roam em **Configurações -> Atalhos de teclado**. Manter o modificador Command (⌘) no atalho impede que o Acesso Total ao Teclado intercepte teclas simples como as setas.
-   Por que digitar no meu teclado não aparece na TV?
    -   Em certos aplicativos do Roku, a entrada pelo teclado físico é ignorada. Você pode testar se o problema é do Roam ou do próprio aplicativo usando o recurso no app oficial do Roku e verificando se funciona.
    -   No macOS, não há botão de teclado porque o teclado do Mac já funciona automaticamente na TV quando a janela do Roam está ativa. No iOS e iPadOS, use o botão de teclado no topo do controle. No watchOS, entrada por teclado ainda não é suportada.
    -   Apps com problemas já conhecidos:
        -   Prime Video
-   Por que o Roam funciona no iPhone e Mac, mas não no Apple Watch?
    -   O app no WatchOS conecta à TV pelo ECP API da TV, que pode precisar ser ativado em alguns modelos Roku. Para ativar, acesse **Configurações -> Sistema -> Configurações Avançadas do Sistema -> Controle por aplicativos móveis** e garanta que "Acesso à Rede" esteja definido como "Permissivo".
-   Por que não posso ligar minha TV a partir do Apple Watch?
    -   O Apple Watch não pode usar o API padrão de ativação da TV a menos que o **Fast TV Start** esteja ativado no Roku TV. Para ativar:
        -   No controle remoto do Roku TV, pressione o botão **Home**
        -   Role para cima ou para baixo e selecione **Configurações**
        -   Selecione **Sistema** e em seguida **Energia**
        -   Selecione **Fast TV Start**
        -   Destaque **Ativar Fast TV Start** e pressione **OK** no controle para marcar a opção

## Outros Recursos

Se tiver dúvidas ou problemas, entre em contato pelo e-mail: [roam-support@msd3.io](mailto:roam-support@msd3.io). Você também pode conversar comigo diretamente no app Roam (Configurações -> Converse com o Desenvolvedor) ou participar do [Roam Discord](https://discord.gg/FqaTNRccbG).

-   [Política de Privacidade](/privacy)
-   [Repositório Principal no GitHub](https://github.com/msdrigg/roam)
-   [Roam Discord](https://discord.gg/FqaTNRccbG)
-   [Baixe na App Store](https://apps.apple.com/us/app/roam/6469834197)
-   [Roteiro de Desenvolvimento](/upcoming-work)
-   [Changelog](/changes)
-   [Dispositivos Roku Testados](/tested-tvs)
-   [Apoie com um café](/coffee)