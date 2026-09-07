# Compilar localmente

1. Use um Mac com Xcode completo e iPhoneOS SDK. O build original de referência usou Xcode 26.6 e SDK iPhoneOS 26.5. Essa é a configuração de referência para reproduzir a compilação; o projeto original usa objectVersion 90. Um Xcode que não suporte esse formato deverá ser atualizado, sem converter o projeto às cegas.
2. Extraia o ZIP, abra Terminal e entre na pasta WorkPlot-CanvasTest extraída.
3. Se seu Xcode estiver em outro local, selecione-o apenas para este comando, por exemplo:

```bash
export DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer
xcodebuild -version
xcrun --sdk iphoneos --show-sdk-version
bash scripts/build-unsigned.sh
```

O script usa automaticamente `/Applications/Xcode_26.6.app` se existir e DEVELOPER_DIR não estiver definido. Complete a inicialização/licença do Xcode na interface dele se o próprio Xcode solicitar. Python 3 também é necessário para verificar os hashes. Não são necessárias credenciais GitHub, CocoaPods nem downloads de Swift packages: ZIPFoundation acompanha o projeto.

Saídas após um build bem-sucedido:

- `dist/WorkPlot-CanvasTest.ipa`
- `dist/WorkPlot-CanvasTest.ipa.sha256`
- `dist/WorkPlot-CanvasTest-dSYMs.zip`, quando o archive gerar dSYMs
- `build/run.XXXXXX/build.log` e o archive correspondente

O script verifica hashes do acesso original, identidade, arquitetura arm64 e integridade do ZIP antes de anunciar a geração. Em caso de erro, pare e envie o build.log completo. Não renomeie um ZIP de fonte para .ipa; um IPA exige o executável compilado.

O IPA é unsigned: ele precisa da assinatura/instalação compatível com o método que você já utiliza para o WorkPlot original. Não altere o bundle ID para contornar rejeições. Este pacote não fornece certificado nem provisioning profile. O projeto original não configura CODE_SIGN_ENTITLEMENTS; o build unsigned não adiciona entitlements. Support/Info.plist original está incluído. Se a ferramenta de assinatura alterar identidade ou entitlements, registre isso e devolva o log; não há garantia de Unlocked com assinatura diferente.

Opcional: abra `WorkPlot/WorkPlot.xcodeproj` no Xcode para inspeção, selecione o scheme WorkPlot. Prefira o script para gerar o IPA com as opções unsigned explícitas. Não habilite gerenciamento de assinatura para tentar modificar a identidade.

Validação feita nesta tarefa: hashes e integridade estrutural, sintaxe do script shell, patch aplicável ao checkout original e parsing sintático Swift (se registrado em evidence/LOCAL_VALIDATION.txt). Não equivale a typecheck, link ou execução. O build macOS permanece pendente.
