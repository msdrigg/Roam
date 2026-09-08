---
hide_table_of_contents: true
---

<head>
    <meta name="apple-itunes-app" content="app-id=6469834197"/>
</head>

## Sobre o Roam

:::tip[Ofereça-me um café]

O Roam é gratuito, sem anúncios e sem modo pago. Se lhe for útil, pode [deixar uma gorjeta](/coffee).

:::

O Roam oferece tudo o que quer e nada do que não precisa

-   Compatível com Mac, iPhone, iPad, Apple Watch, Vision Pro ou Apple TV!
-   Integração inteligente com o sistema, incluindo atalhos de teclado no Mac e uso dos botões físicos de volume para controlar o volume da TV no iOS
-   Utilize atalhos e widgets para controlar a sua TV sem sequer abrir a app!
-   Modo auscultadores (também conhecido por escuta privada) disponível no Mac, iPad, iPhone, VisionOS e Apple TV (ouça o áudio da sua TV através do seu dispositivo)
-   Descubra dispositivos na sua rede local assim que abrir a aplicação
-   Design intuitivo, recorrendo ao sistema nativo SwiftUI da Apple
-   Rápida e leve, com menos de 8 MB em todos os dispositivos e abre em menos de meio segundo!
-   Código aberto (https://github.com/msdrigg/roam)

## Funcionalidades

-   Controlo remoto
    -   O Roam inclui comandos normais do comando Roku, com botões direcionais, seleção, retroceder, início, play/pausa e outros controlos da TV quando suportados pelo Roku.
    -   Os controlos de volume podem não funcionar em dispositivos Roku Stick, uma vez que são só HDMI e por isso não conseguem controlar o volume da TV pelos comandos de rede da Roam.
-   Introdução de texto pelo teclado
    -   No macOS, não há botão de teclado. Quando a janela do Roam está ativa, o teclado do Mac funciona automaticamente com a TV.
    -   No iOS e iPadOS, existe um botão de teclado no topo do comando remoto.
    -   O watchOS não tem, de momento, suporte para teclado.
    -   Algumas apps Roku ignoram a introdução de caracteres pelo teclado por parte de apps remotas. O Prime Video é um exemplo conhecido onde esta funcionalidade pode não funcionar, pois a app Roku não a aceita.
-   Atalhos de teclado
    -   O Roam atribui teclas físicas do teclado a ações do comando remoto (botões direcionais, selecionar/OK, voltar, início, volume, silenciar, play/pausa, entre outros). Isto é independente da introdução de texto no ecrã.
    -   Pode personalizar estes atalhos em **Definições -> Atalhos de teclado** no Mac, iPhone, iPad e Vision Pro (o watchOS não tem atalhos de teclado).
    -   Selecione uma linha para mudar o atalho, clique com o botão direito (Mac) ou deslize (iPhone/iPad) numa linha para repor o valor, ou use **Repor Tudo** / **Limpar Tudo**. Os atalhos por defeito usam o modificador Command (⌘).
-   Colar um link para reproduzir (macOS)
    -   No Mac, copie um link de vídeo, clique na janela do Roam e pressione **⌘V**. O Roam abre a app correspondente no seu Roku e começa a reprodução desse conteúdo.
    -   Os serviços suportados incluem YouTube, Amazon Prime Video, Netflix, Disney+, Hulu, Max, Paramount+, Peacock, Tubi, Sling e The Roku Channel.
    -   Se um campo de texto da TV estiver ativo, o comando ⌘V escreve o texto da área de transferência nesse campo em vez de abrir o link.
-   Modo auscultadores/escuta privada
    -   A escuta privada permite ouvir o som da TV através do seu dispositivo, em dispositivos Roku suportados.
    -   A escuta privada é suportada no Roam para Mac, iPad, iPhone, VisionOS e Apple TV, mas pode não funcionar em todas as Roku TV.

## Problemas Comuns

-   O que posso fazer se o Roam não detetar automaticamente a minha TV?
    -   [Veja aqui](/manually-add-tv)
-   O Roam não está a funcionar corretamente no meu Apple Watch
    -   Vá por favor a **Definições -> Sistema -> Definições Avançadas do Sistema -> Controlo por apps móveis** e confirme que está selecionada a opção **Permissivo**
-   Porque é que o modo auscultadores (escuta privada) não funciona na minha TV?
    -   O modo auscultadores atualmente não funciona em algumas TVs. Se não funcionar com o Roam mas funcionar com a aplicação oficial da Roku, por favor envie um email com o modelo do seu Roku e qualquer informação relevante para [roam-support@msd3.io](mailto:roam-support@msd3.io). O seu feedback ajudará a encontrar soluções para corrigir este erro.
-   E se tiver outro problema ou quiser enviar feedback?
    -   Se for um erro, o melhor é iniciar um relatório de feedback a partir da aplicação:
        -   Entre na aplicação Roam e vá à página de definições
        -   Carregue em "Enviar feedback". Isto vai gerar um relatório de diagnóstico que pode ser partilhado com o suporte Roam (roam-support@msd3.io)
        -   Se a app estiver a fechar inesperadamente, confirme também que a análise está ligada em Definições -> Privacidade & Segurança -> Análise & Melhorias
            -   Ative "Partilhar Análise do iPhone & Watch" e depois "Partilhar com Programadores de Apps" para que a Apple me envie relatórios quando a aplicação for encerrada inesperadamente
    -   Se for um pedido de nova funcionalidade, pode enviar email (roam-support@msd3.io), falar diretamente comigo através do chat da app Roam (Definições -> Chat com o Programador) ou juntar-se ao [Roam Discord](https://discord.gg/FqaTNRccbG).
-   Porque é que, por vezes, as teclas de seta não funcionam no iPad?
    -   Isto acontece porque o iPadOS, por vezes, assume o controlo das teclas de seta para navegação no ecrã antes que as possamos detetar
    -   Para contornar isto, vá a Definições -> Acessibilidade -> Teclados e desligue o "Acesso Total ao Teclado" ou, em alternativa, vá a Definições -> Acessibilidade -> Teclados -> Acesso Total ao Teclado -> Comandos -> Básico e desative os comandos "Mover para Cima", "Mover para Baixo", "Mover para a Esquerda" e "Mover para a Direita"
    -   Também pode remapear as teclas direcionais nos atalhos do Roam, em **Definições -> Atalhos de teclado**. Manter um modificador Command (⌘) num atalho impede que o Acesso Total ao Teclado intercepte as teclas simples, como as setas.
-   Porque não aparece o texto que escrevo no teclado na TV?
    -   Em algumas aplicações Roku, a app ignora a introdução de texto feita através do teclado físico. Pode testar se é um erro do Roam ou da app usando a funcionalidade equivalente na aplicação oficial da Roku e verificar se funciona.
    -   No macOS, não existe botão de teclado, porque ele funciona automaticamente com a TV quando a janela do Roam está ativa. No iOS e iPadOS, use o botão de teclado no topo do comando remoto. O watchOS não suporta entrada por teclado de momento.
    -   Apps com erros conhecidos
        -   Prime Video
-   Porque é que o Roam funciona no meu iPhone e Mac mas não no meu Apple Watch?
    -   A app WatchOS liga-se à TV através da API ECP da própria TV, que por vezes precisa de ser ativada em algumas Roku TV. Para ativar: **Definições -> Sistema -> Definições Avançadas do Sistema -> Controlo por apps móveis** e selecione "Acesso de Rede" como "Permissivo"
-   Porque não consigo ligar a TV a partir do meu Apple Watch?
    -   O Apple Watch não pode usar a API standard de ativação para ligar a TV a menos que a opção **Arranque Rápido da TV** esteja ativa na Roku TV. Para ativar:
        -   Prima o botão **Início** do comando remoto da sua Roku TV
        -   Percorra para cima ou para baixo e selecione **Definições**
        -   Selecione **Sistema**, depois **Energia**
        -   Selecione **Arranque Rápido da TV**
        -   Realce **Ativar Arranque Rápido da TV** e pressione **OK** no comando para marcar a caixa

## Outros Recursos

Se tiver alguma dúvida ou problema, por favor contacte-me para: [roam-support@msd3.io](mailto:roam-support@msd3.io). Também pode falar comigo diretamente na aplicação Roam (Definições -> Chat com o Programador) ou juntar-se ao [Roam Discord](https://discord.gg/FqaTNRccbG).

-   [Política de Privacidade](/privacy)
-   [Repositório core no GitHub](https://github.com/msdrigg/roam)
-   [Roam Discord](https://discord.gg/FqaTNRccbG)
-   [Descarregar na App Store](https://apps.apple.com/us/app/roam/6469834197)
-   [Roteiro](/upcoming-work)
-   [Registo de Alterações](/changes)
-   [Dispositivos Roku testados](/tested-tvs)
-   [Ofereça-me um café](/coffee)