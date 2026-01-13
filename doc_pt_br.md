# Guia completo: Jael + Angel3 Framework (pt-BR)

Este documento descreve como usar o Jael com `angel3_framework` no backend,
com foco no setup real do projeto e nas correcoes feitas (sem `dart:mirrors`).

## Estrutura basica do projeto

- Views: `C:\MyDartProjects\app\backend\views`
- Configuracao Jael: `C:\MyDartProjects\app\backend\lib\src\shared\dependencies\angel3_jael\angel3_jael.dart`
- Bootstrap do servidor: `C:\MyDartProjects\app\backend\lib\src\shared\bootstrap.dart`
- Exemplo de controller: `C:\MyDartProjects\app\backend\lib\src\modules\example_module\controllers\example_controller.dart`

## Configurando o Jael no Angel

A configuracao base fica no bootstrap do servidor:

```dart
await app.configure(
  jael(
    fileSystem.directory('views'),
    fileExtension: '.html',
    cacheViews: false,
    minified: false,
  ),
);
```

Pontos importantes:

- `fileExtension`: deve bater com os arquivos da pasta `views` (ex.: `.html`).
- `cacheViews`: em dev geralmente `false`; em prod pode ser `true`.
- `minified`: `false` em dev para HTML legivel.

## Pipeline de renderizacao no angel3_jael.dart

O `angel3_jael.dart` define o `app.viewGenerator`:

```dart
app.viewGenerator = (String name, [Map? locals]) async {
  var errors = <JaelError>[];
  Document? processed;

  if (cacheViews && localCache.containsKey(name)) {
    processed = localCache[name];
  } else {
    processed = await _loadViewTemplate(
      viewsDirectory,
      name,
      fileExtension: fileExtension,
      asDSX: asDSX,
      patch: patch,
    );
    if (cacheViews) localCache[name] = processed!;
  }

  var buf = bufferFunc();
  var scope = SymbolTable(
      values: locals?.keys.fold<Map<String, dynamic>>(
            <String, dynamic>{},
            (out, k) => out..[k.toString()] = locals[k],
          ) ??
          <String, dynamic>{});

  const Renderer().render(
    processed!,
    buf,
    scope,
    strictResolution: strictResolution,
  );
  return buf.toString();
};
```

## Conteudo completo de referencia (angel3_jael.dart)

O trecho abaixo reflete o arquivo real:

```dart
import 'package:angel3_framework/angel3_framework.dart';
import 'package:belatuk_code_buffer/belatuk_code_buffer.dart';
import 'package:file/file.dart';
import 'package:jael3_fork/jael3.dart';
//import 'package:jael3_preprocessor/jael3_preprocessor.dart';
import 'package:jael3_fork/jael3_preprocessor.dart';
import 'package:belatuk_symbol_table/belatuk_symbol_table.dart';

/// Configures an Angel server to use Jael to render templates.
///
/// To enable "minified" output, set minified to true
///
/// For custom HTML formating, you need to override the [createBuffer] parameter
/// with a function that returns a new instance of [CodeBuffer].
///
/// To apply additional transforms to parsed documents, provide a set of [patch] functions.
AngelConfigurer jael(Directory viewsDirectory,
    {String fileExtension = '.jael',
    bool strictResolution = false,
    bool cacheViews = true,
    Map<String, Document>? cache,
    Iterable<Patcher> patch = const [],
    bool asDSX = false,
    bool minified = true,
    CodeBuffer Function()? createBuffer}) {
  var localCache = cache ?? <String, Document>{};

  var bufferFunc = createBuffer ?? () => CodeBuffer();

  if (minified) {
    bufferFunc = () => CodeBuffer(space: '', newline: '');
  }

  return (Angel app) async {
    app.viewGenerator = (String name, [Map? locals]) async {
      var errors = <JaelError>[];
      Document? processed;

      //var stopwatch = Stopwatch()..start();

      if (cacheViews && localCache.containsKey(name)) {
        processed = localCache[name];
      } else {
        processed = await _loadViewTemplate(viewsDirectory, name,
            fileExtension: fileExtension, asDSX: asDSX, patch: patch);

        if (cacheViews) {
          localCache[name] = processed!;
        }
      }
      //print('Time executed: ${stopwatch.elapsed.inMilliseconds}');
      //stopwatch.stop();

      var buf = bufferFunc();
      var scope = SymbolTable(
          values: locals?.keys.fold<Map<String, dynamic>>(<String, dynamic>{},
                  (out, k) => out..[k.toString()] = locals[k]) ??
              <String, dynamic>{});

      if (errors.isEmpty) {
        try {
          const Renderer().render(processed!, buf, scope,
              strictResolution: strictResolution);
          return buf.toString();
        } on JaelError catch (e) {
          errors.add(e);
        }
      }

      Renderer.errorDocument(errors, buf..clear());
      return buf.toString();
    };
  };
}

/// Preload all of Jael templates into a cache
///
///
/// To apply additional transforms to parsed documents, provide a set of [patch] functions.
Future<void> jaelTemplatePreload(
    Directory viewsDirectory, Map<String, Document> cache,
    {String fileExtension = '.jael',
    bool asDSX = false,
    Iterable<Patcher> patch = const []}) async {
  await viewsDirectory.list(recursive: true).forEach((f) async {
    if (f.basename.endsWith(fileExtension)) {
      var name = f.basename.split(".");
      if (name.length > 1) {
        //print("View: ${name[0]}");
        Document? processed = await _loadViewTemplate(viewsDirectory, name[0],
            fileExtension: fileExtension);
        if (processed != null) {
          cache[name[0]] = processed;
        }
      }
    }
  });
}

Future<Document?> _loadViewTemplate(Directory viewsDirectory, String name,
    {String fileExtension = '.jael',
    bool asDSX = false,
    Iterable<Patcher> patch = const []}) async {
  final errors = <JaelError>[];
  Document? processed;

  final file = viewsDirectory.childFile(name + fileExtension);

  // Verifica se o arquivo existe ANTES de tentar ler
  if (!await file.exists()) {
    throw ArgumentError("File '${file.path}' does not exist.");
  }

  final contents = await file.readAsString();

  final doc = parseDocument(contents,
      sourceUrl: file.uri, asDSX: asDSX, onError: errors.add);

  if (errors.isNotEmpty) {
    // Se houver erros de parse, lance-os para um debug mais claro
    throw AngelHttpException(
      message: 'Jael parse error in ${file.basename}',
      errors: errors.map((e) => e.toString()).toList(),
    );
  }

  if (doc == null) {
    throw ArgumentError("Could not parse ${file.basename}.");
  }

  try {
    processed =
        await (resolve(doc, viewsDirectory, patch: patch, onError: errors.add));
  } catch (e) {
    // Ignore these errors, so that we can show syntax errors.
  }
  if (processed == null) {
    throw ArgumentError("${file.basename} does not exists");
  }
  return processed;
}
```

## Renderizando no controller

No controller, use `res.render('nome_da_view', data)`:

```dart
static Future<void> _render(ResponseContext res, Map<String, dynamic> data) {
  return res.render('example_page_template', data);
}
```

O Jael vai procurar `views/example_page_template.html` (com base no `fileExtension`).

## Includes, extend e block

O Jael suporta includes e heranca (quando o preprocessor esta ativo):

- `<include src="partials/styles.html" />`
- `<extend src="layout.html">`
- `<block name="content">`

No `angel3_jael.dart`, o preprocessor ja e chamado em `_loadViewTemplate`.

## Diretrizes suportadas no template

Principais diretivas:

- `if` (condicional)
- `for-each` (iteracao)
- `switch` / `case` / `default`
- `declare`

Exemplos:

```html
<div if="erro != null">...</div>
<div for-each="assinaturas" as="sig">...</div>
<switch value="status_code">
  <case value="200">OK</case>
  <default>Erro</default>
</switch>
```

Observacao: a engine aceita expressoes entre aspas (ex.: `if="a == b"`).

## Member access sem dart:mirrors

Este projeto nao usa `dart:mirrors`. Para suportar `obj.campo` no template,
o Jael permite um resolvedor no escopo: `!memberResolver!`.

### Quando e necessario

- Se os dados passados para a view sao `Map`, `obj.campo` ja funciona.
- Se os dados forem objetos, o resolvedor permite mapear para `toJson()` ou `toMap()`.

### Exemplo de configuracao

Adicione o resolvedor no `SymbolTable`:

```dart
var scope = SymbolTable(
  values: locals?.keys.fold<Map<String, dynamic>>(
        <String, dynamic>{},
        (out, k) => out..[k.toString()] = locals[k],
      ) ??
      <String, dynamic>{},
);

scope.define('!memberResolver!', (Object? target, String name) {
  if (target is Map) {
    return MemberResolution.handled(target[name]);
  }

  try {
    final dyn = target as dynamic;
    final json = dyn.toJson();
    if (json is Map) return MemberResolution.handled(json[name]);
  } catch (_) {}

  try {
    final dyn = target as dynamic;
    final map = dyn.toMap();
    if (map is Map) return MemberResolution.handled(map[name]);
  } catch (_) {}

  return const MemberResolution.unresolved();
});
```

## Exemplo real: assinatura_validacao.html

No `ValidacaoAssinaturaController`, `assinaturas` e montado como `List<Map<String, dynamic>>`:

```dart
final assinaturas = validationReport.signatures
    .asMap()
    .entries
    .map((entry) {
      final vm = _buildAssinaturaViewModel(
        sig: entry.value,
        policyOidMap: policyOidMap,
      );
      return {
        ...vm,
        'numero': entry.key + 1,
      };
    })
    .toList(growable: false);
```

Por isso, no template `views/assinatura_validacao.html`:

- `{{ sig.numero }}`
- `{{ sig.nome }}`
- `{{ sig.cpf }}`

funcionam sem reflexao.

## Strict resolution e erros

`strictResolution` controla se variaveis ausentes geram erro:

- `true`: erro se o nome nao existe no escopo.
- `false`: retorna `null` silenciosamente.

Se a aplicacao for renderizar templates com dados parciais, considere
habilitar `strictResolution: false` no `jael(...)`.

## Dicas para diagnostico

- Use `scripts/check_jael.dart` para validar templates localmente.
- Use `--render` para forcar renderizacao completa.
- Passe `--views-dir` para apontar para a pasta de views correta.

Exemplo:

```bash
dart run scripts/check_jael.dart --render --views-dir C:\MyDartProjects\jael3\test\assets\views
```
