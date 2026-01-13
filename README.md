# Jael 3 Fork

This fork was created to remove the dependency on `dart:mirrors` and runtime
reflection, and to deliver additional stability and parser/renderer fixes from
versions > 8.2.

For a detailed history, see `CHANGELOG.md`.

A simple server-side HTML templating engine for Dart.

## Installation

In your `pubspec.yaml`:

```yaml
dependencies:
  jael3_fork: ^8.4.1
```

## Usage

```dart
import 'package:belatuk_code_buffer/belatuk_code_buffer.dart';
import 'package:belatuk_symbol_table/belatuk_symbol_table.dart';
import 'package:jael3_fork/jael3.dart' as jael;

void main() {
  const template = '''
<html>
  <body>
    <h1>Hello</h1>
    <img src=profile['avatar']>
  </body>
</html>
''';

  var buffer = CodeBuffer();
  var document = jael.parseDocument(template, sourceUrl: 'example.html')!;
  var scope = SymbolTable(values: {
    'profile': {
      'avatar': 'thosakwe.png',
    }
  });

  const jael.Renderer().render(document, buffer, scope);
  print(buffer.toString());
}
```

## Templates and directives

- Interpolation: `{{ name }}` and raw: `{{- html }}`
- Conditionals: `<div if="status == 200">...</div>`
- Loops: `<li for-each="items" as="item">{{ item['name'] }}</li>`
- Switch: `<switch value="status"> <case value="200">OK</case> </switch>`

Quoted expressions are supported in `if`, `for-each`, and `switch`/`case`.

## Member access without dart:mirrors

Property access (`obj.prop`/`obj?.prop`) works for `Map` values by default.
For objects, provide a resolver in the scope:

```dart
scope.define('!memberResolver!', (Object? target, String name) {
  if (target is Map) {
    return jael.MemberResolution.handled(target[name]);
  }
  return const jael.MemberResolution.unresolved();
});
```

## Preprocessing (includes, extend, block)

The preprocessor is available in `package:jael3_fork/jael3_preprocessor.dart`.

## Angel3 integration

Full reference for the Angel3 integration (as used in this fork):

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
