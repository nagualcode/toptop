# TopTop

A barra do [Omarchy](https://omarchy.org/) transformada em um notch no topo central da tela.

Fica recolhida mostrando apenas a seção central do layout, e se expande automaticamente ao passar o mouse por cima.

## Instalação

Instale com o gerenciador de plugins do Omarchy:

```bash
omarchy plugin add https://github.com/nagualcode/toptop.git --enable
```

Depois, linke os comandos de linha de comando:

```bash
~/.config/omarchy/plugins/nagualcode.toptop/scripts/install.sh
```

Isso permite usar todos os comandos abaixo diretamente no terminal.

## Desinstalação

Para voltar para a barra padrão do Omarchy:

```bash
omarchy-shell shell enablePlugin omarchy.bar '{}'
omarchy plugin remove nagualcode.toptop --yes
```

## Comandos de linha de comando

Configure a aparência da barra diretamente pelo terminal.

| Comando | O que faz | Valores | Padrão |
|---|---|---|---|
| `omarchy-toptop-align` | Alinha o notch na tela | `left`, `center`, `right` | `center` |
| `omarchy-toptop-transparency` | Define a transparência do preenchimento | `0` a `100` (0 = sólido, 100 = sem preenchimento) | `0` |
| `omarchy-toptop-icons` | Define a cor dos ícones | `theme` (segue o tema) ou `#RRGGBB` (cor fixa) | `theme` |
| `omarchy-toggle-toptop-hover` | Ativa/desativa o recolhimento ao passar o mouse | `on` (recolhe ao sair), `off` (sempre aberto). Sem argumento, inverte o estado | `on` |
| `omarchy-toptop-widgets` | Abre o menu para gerenciar widgets | Sem argumentos | — |

### Exemplos de uso

```bash
omarchy-toptop-align right
omarchy-toptop-transparency 30
omarchy-toptop-icons '#faa968'
omarchy-toggle-toptop-hover off
omarchy-toptop-widgets
```

## Como funciona

- **O que fica visível quando recolhido:** Apenas os widgets que estão na **seção central** do `bar.layout`. Para alterar isso, basta arrastar os ícones para dentro ou fora da seção central.
- **Sempre aberto:** Use `omarchy-toggle-toptop-hover off` para deixar a barra sempre expandida.
- **Mudanças instantâneas:** Todos os comandos aplicam as alterações imediatamente, sem precisar reiniciar nada.