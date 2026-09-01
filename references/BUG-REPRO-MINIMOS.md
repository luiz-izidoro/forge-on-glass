# Bug reports — repro mínimos para swiftlang/swift

> Registro histórico de reproduções. As decisões vigentes e a ordem de
> diagnóstico estão em [`BEST-PRACTICES.md`](BEST-PRACTICES.md). Não usar este
> arquivo para inferir que um caminho experimental está validado.

Casos reduzidos a partir de falhas reais desta skill. Todos medidos no iSH
(Alpine/aarch64) com toolchain swift.org Linux compilando para
`arm64-apple-ios26.0` contra um SDK iOS 26.5 com `.swiftinterface` patchados.

> ⚠️ Antes de reportar upstream, considere que o SDK usado é **patchado**
> (`/var/minis/shared/darwin-sdk/patchset/`). Um mantenedor pedirá reprodução
> com SDK limpo. Os casos abaixo estão prontos para essa verificação — o valor
> aqui é o **caso mínimo**, não a conclusão sobre culpa.

---

## Caso 1 — whole-module: CoreGraphics faz Foundation sumir de outro arquivo

**Severidade:** alta (mensagem de erro aponta para o arquivo errado)
**Toolchain:** swift.org 6.3.3 Linux → arm64-apple-ios26.0
**Modo:** whole-module (sem `-primary-file`)

### Repro (2 arquivos)

`main.swift`:
```swift
import Foundation
import UIKit
class AppDelegate: UIResponder, UIApplicationDelegate {
    var window: UIWindow?
    func applicationDidFinishLaunching(_ a: UIApplication) {
        let w = UIWindow(frame: CGRect(origin: CGPoint(x: 0, y: 0),
                                       size: CGSize(width: 100, height: 100)))
        window = w
    }
}
UIApplicationMain(CommandLine.argc, CommandLine.unsafeArgv, nil,
                  NSStringFromClass(AppDelegate.self))
```

`Helper.swift`:
```swift
import Foundation
import UIKit
public enum Helper {
    public static func b() -> String {
        return Bundle.main.bundleIdentifier ?? "?"   // ❌
    }
}
```

### Esperado
Compila.

### Obtido
```
Helper.swift:5: error: cannot find 'Bundle' in scope
```

`Helper.swift` **importa Foundation** e não contém uma linha de CoreGraphics.
Quem usa CoreGraphics é o *outro* arquivo. A degradação é **cross-file**.

### Observações
- Determinístico: 3/3 execuções.
- Compilando `Helper.swift` sozinho: **passa**.
- Com `-primary-file` (arquivo-a-arquivo): **passa**, 6 s, sem alterar código.
- Também ocorre **intra-file** se a declaração que usa CoreGraphics vier antes
  da que usa Foundation; inverter a ordem resolve.
- Afeta `Bundle`, `NotificationCenter`, `OperationQueue`.
- **Não** é causado por: `public`, `import Darwin`, ordem alfabética dos
  arquivos, string literal grande, tamanho do arquivo, ordem dos imports.

### Workaround
`-primary-file` (adotado como padrão pela skill em 2026-08-23).

---

## Caso 2 — módulo importado degrada bridging String↔NSString

**Severidade:** alta (o app compila "quase" e abre com tela preta)
**Modo:** dois módulos (`-emit-module` para a dep, depois `-swift-module-file`)

### Repro

Módulo `DepMod` (`Lib.swift`, compilado com `-parse-as-library`):
```swift
import Foundation
import UIKit
public enum DepKit {
    public static func greeting() -> String { return "ok" }
    public static func numero() -> Int { return 42 }
}
```

App (`main.swift`, compilado com `-swift-module-file=DepMod=...`):
```swift
import Foundation
import UIKit
import DepMod                       // <- remover esta linha faz compilar
class AppDelegate: UIResponder, UIApplicationDelegate {
    var window: UIWindow?
    func applicationDidFinishLaunching(_ a: UIApplication) {
        let l = UILabel()
        l.text = "literal direto"   // ❌
    }
}
UIApplicationMain(CommandLine.argc, CommandLine.unsafeArgv, nil,
                  NSStringFromClass(AppDelegate.self))
```

### Obtido
```
main.swift: error: cannot assign value of type 'String' to type 'NSString'
```

### Chave do caso
O erro é numa **string literal**, que nada tem a ver com o módulo importado.
Removendo apenas `import DepMod` (e o uso), o mesmo arquivo compila, linka e
empacota normalmente. O `DepKit` sequer precisa ser usado.

### Impacto observado
Todos os apps gerados por esse caminho abriam com **tela preta**. O
`build-multimodule.sh` foi deprecado por causa disso.

---

## Caso 3 — SILGen crash (histórico)

`emitCBridgedToNativeValue`, ao compilar o `.swiftinterface` do UIKit com
swift.org 6.3.3 — thunk de bridging de um método `@objc` com tipo patchado
não-bridgeable. Ver `references/linux-vm/ESTADO-E-NEXT-STEPS.md` §3.
Contornado pelo patch-set; não re-verificado desde 2026-08-19.
