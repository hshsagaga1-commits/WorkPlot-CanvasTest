# Teste no iPhone — WorkPlot CanvasTest diagnóstico 2

Alvo: iPhone 11 / iPhone12,1 / iOS 27.0 / build 24A5380h.
Este diagnóstico não altera a resolução. Seu objetivo é coletar evidência dos destinos gráficos e da geometria atual. Não espere 1125×2436 nesta rodada.

## Preparar e instalar

1. Gere o IPA conforme BUILD_INSTRUCTIONS.md. Se o build falhar, devolva `build/run.XXXXXX/build.log`; ainda não há teste de iPhone a executar.
2. Guarde seu IPA WorkPlot(3) original e os backups existentes. Use o mesmo método de assinatura/instalação que já funciona. Preserve `com.apple.mobile.MobileHouseArrest`. Este diagnóstico tem a mesma identidade e pode substituir a instalação existente; exporte seus backups antes. Não desinstale o app para tentar resolver acesso.
3. Registre o método de assinatura/instalação e se ele alterou entitlements ou identificador. Se falhar, envie o erro exato e o log. Não troque bundle ID nem use spoof de modelo.

## Coleta antes do reboot

1. Abra WorkPlot e aguarde a tentativa automática de acesso original. A tela deve ser “Canvas diagnóstico”, versão diagnóstico 2. Não importe presets.
2. Tire uma captura mostrando Acesso (Unlocked/Locked), Método, Build e Native bounds. Se ficar Locked, registre e prossiga com a coleta; esse resultado também é útil.
3. Deixe “Incluir varredura ampliada de containers” DESLIGADO. Toque “Coletar diagnóstico”. Mantenha o app em primeiro plano.
4. Ao concluir, toque “Exportar JSON”, salve em Arquivos como `antes-reboot.json`. O log também aparece na tela. Se houver erro, exporte mesmo assim; o JSON é salvo incrementalmente.
5. Tire uma captura nativa do app e outra da tela de Início. Envie os PNGs originais como arquivos, sem cortar, redimensionar ou passar por compressão de mensageiro. Anote se Zoom da Tela está ativado e não mude essa configuração entre coletas.
6. Depois de salvar a coleta normal, faça uma coleta com varredura ampliada LIGADA e exporte como `containers-antes.json`. Ela usa a rotina original de enumeração com limite de 2 milhões de inodes e até 64 containers; pode demorar. Se ficar muito tempo no mesmo estágio, exporte o JSON parcial pela interface. Se precisar fechar o app, reabra e exporte o último relatório antes de iniciar outra coleta. Não é necessário insistir indefinidamente.

## Full reboot e segunda coleta

1. Desligue completamente pelo controle “deslizar para desligar”. Espere a tela apagar e então ligue pelo botão lateral, aguardando o logo Apple e desbloqueando com o código. **Respring, fechar o app ou reiniciar apenas a interface não substituem full reboot.**
2. Abra o diagnóstico, aguarde o acesso automático e faça nova coleta normal, com varredura ampliada DESLIGADA.
3. Exporte `depois-reboot.json` e tire novamente as capturas do app e da tela de Início, no mesmo modo de orientação.
4. O app compara o marcador de boot e nativeBounds com a primeira coleta concluída. Um marcador diferente dá evidência de novo boot; não prova que uma resolução foi aplicada. O diagnóstico não escreveu uma resolução, portanto não exige mudança de geometria.

## O que devolver nesta conversa

- `antes-reboot.json`, `containers-antes.json` (mesmo parcial) e `depois-reboot.json`.
- Capturas originais antes/depois e a captura mostrando estado de acesso/build.
- Hash SHA-256 do IPA gerado, método de instalação e alterações de assinatura conhecidas.
- Confirmação do procedimento de desligar/ligar e de que você não alterou resolução/Zoom da Tela por outro app entre as coletas.
- Se houver crash, o relatório .ips de WorkPlot em Ajustes > Privacidade e Segurança > Análise e Melhorias > Dados de Análise, junto com build.log e dSYMs do mesmo build.

O JSON contém caminhos, hashes, tipos e valores de canvas, erros de leitura/abertura, MobileGestalt limitado à chave de canvas, geometria e boot. Não envia dados automaticamente. Snapshots completos dos plists gráficos ficam locais no diretório Documents/CanvasDiagnostics; o exportador compartilha o JSON, não o MobileGestalt completo.

`openReadWrite.success=true` significa apenas que abrir O_RDWR foi permitido; não ocorreu escrita. `withOriginalLease` é uma observação após o lease original, não prova de consumo gráfico. Os snapshots não devem ser tratados como stock nem usados manualmente para Restore Original. Após examinar seus dados, a próxima etapa será decidir se há evidência suficiente para um teste controlado de escrita/restore, ou se ainda falta identificar o consumidor.
