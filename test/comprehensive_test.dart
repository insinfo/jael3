// test/comprehensive_test.dart

// ignore_for_file: unnecessary_brace_in_string_interps

import 'package:belatuk_code_buffer/belatuk_code_buffer.dart';
import 'package:jael3_fork/jael3.dart' as jael;
import 'package:jael3_fork/jael3_preprocessor.dart' as jael_pre;
import 'package:belatuk_symbol_table/belatuk_symbol_table.dart';
import 'package:file/file.dart';
import 'package:file/memory.dart';
import 'package:test/test.dart';

// Helper para normalizar o HTML removendo recuos e quebras de linha excessivas.
// Isso torna os testes menos frágeis a pequenas alterações na formatação.
String normalize(String html) {
  return html.replaceAll(RegExp(r'\s+'), ' ').trim();
}

// Helper para renderização simples, ideal para testes de sintaxe e renderização básica.
String render(String template, [Map<String, dynamic> values = const {}]) {
  var doc = jael.parseDocument(template, onError: (e) => throw e);
  if (doc == null) return ''; // Retorna string vazia se o parsing falhar

  var buffer = CodeBuffer();
  const jael.Renderer().render(doc, buffer, SymbolTable(values: values));
  return buffer.toString().trim();
}

// Helper para testes de pré-processamento que lida com o sistema de arquivos em memória.
Future<String> renderWithPreprocessor(String entryPointPath, FileSystem fs,
    [Map<String, dynamic> values = const {}]) async {
  final currentDirectory = fs.directory('/views');
  final entryFile = currentDirectory.childFile(entryPointPath);
  final content = await entryFile.readAsString();

  var doc = jael.parseDocument(content,
      sourceUrl: entryFile.uri, onError: (e) => throw e)!;
  var resolvedDoc =
      await jael_pre.resolve(doc, currentDirectory, onError: (e) => throw e);

  if (resolvedDoc == null) return '';

  var buffer = CodeBuffer();
  const jael.Renderer()
      .render(resolvedDoc, buffer, SymbolTable(values: values));
  return buffer.toString().trim();
}

void main() {
  group('Renderização Básica & Expressões', () {
    test('renderiza interpolação de variável simples', () {
      var html = render('<h1>Olá, {{ name }}!</h1>', {'name': 'Mundo'});
      expect(normalize(html), '<h1> Olá, Mundo! </h1>');
    });

    test('avalia expressões matemáticas', () {
      var html = render('<p>Resultado: {{ 2 * (3 + 4) }}</p>'); // 2 * 7 = 14
      expect(normalize(html), '<p> Resultado: 14 </p>');
    });

    test('vincula atributos de variáveis e mapas', () {
      const template = '''
        <div>
          <input type="text" value=user_info['name']>
          <img src=user_info['avatar_url']>
        </div>
      ''';
      var values = {
        'user_info': {
          'name': 'Jubarte',
          'avatar_url': 'logo.png',
        }
      };
      var html = render(template, values);
      expect(html, contains('<input type="text" value="Jubarte">'));
      expect(html, contains('<img src="logo.png">'));
    });

    test('escapa HTML na interpolação padrão', () {
      var html = render('<div>{{ content }}</div>',
          {'content': '<script>alert("xss")</script>'});
      // Corresponde à saída real de htmlEscape, que converte " para &quot; e / para &#47;
      var expectedEscapedString =
          '&lt;script&gt;alert(&quot;xss&quot;)&lt;&#47;script&gt;';
      expect(normalize(html), '<div> ${expectedEscapedString} </div>');
    });

    test('não escapa HTML com interpolação raw', () {
      var html =
          render('<div>{{- content }}</div>', {'content': '<b>Raw HTML</b>'});
      expect(normalize(html), '<div> <b>Raw HTML</b> </div>');
    });

    test('chama uma função Dart do template', () {
      String toUpperCase(String s) => s.toUpperCase();
      var html = render('<span>{{ shouting("olá mundo") }}</span>',
          {'shouting': toUpperCase});
      expect(normalize(html), '<span> OLÁ MUNDO </span>');
    });

    test('avalia expressões condicionais (operador ternário)', () {
      var template = "<p>Resultado: {{ condition ? if_true : if_false }}</p>";
      var values = {
        'condition': 5 > 3,
        'if_true': 'Cinco é maior',
        'if_false': 'Três é maior'
      };

      //A linha a seguir irá falhar devido ao bug do parser.
      var html = render(template, values);
      expect(normalize(html), '<p> Resultado: Cinco é maior </p>');
    });
  });

  group('Operador Ternário (?:)', () {
    test('básico: true/false', () {
      const tpl = "<p>{{ condition ? 'sim' : 'não' }}</p>";

      var html = render(tpl, {'condition': true});
      expect(normalize(html), '<p> sim </p>');

      html = render(tpl, {'condition': false});
      expect(normalize(html), '<p> não </p>');
    });

    test('associatividade à direita (aninhado sem parênteses)', () {
      // Deve ler como: false ? 1 : (false ? 2 : 3) => 3
      const tpl = "<p>{{ false ? 1 : false ? 2 : 3 }}</p>";
      var html = render(tpl);
      expect(normalize(html), '<p> 3 </p>');
    });

    test('sem parênteses vs com parênteses (mudando o agrupamento)', () {
      // Sem parênteses: true ? (false ? 'A' : 'B') : 'C' => 'B'
      var html = render("<span>{{ true ? false ? 'A' : 'B' : 'C' }}</span>");
      expect(normalize(html), '<span> B </span>');

      // Forçando agrupamento à esquerda: (false ? 'A' : true) ? 'B' : 'C' => 'B'
      html = render("<span>{{ (false ? 'A' : true) ? 'B' : 'C' }}</span>");
      expect(normalize(html), '<span> B </span>');
    });

    test('precedência acima de igualdade', () {
      var html = render("<p>{{ 1 == 1 ? 'y' : 'n' }}</p>");
      expect(normalize(html), '<p> y </p>');

      html = render("<p>{{ 2 == 3 ? 'y' : 'n' }}</p>");
      expect(normalize(html), '<p> n </p>');
    });

    test('precedência em relação ao elvis (??): ?: > ??', () {
      // Como ?: tem precedência MAIOR que ??, isto é: name ?? (cond ? 'A' : 'B')
      var html = render("<span>{{ name ?? (cond ? 'A' : 'B') }}</span>",
          {'name': null, 'cond': true});
      expect(normalize(html), "<span> A </span>");

      html = render("<span>{{ name ?? cond ? 'A' : 'B' }}</span>",
          {'name': null, 'cond': false});
      expect(normalize(html), '<span> B </span>');

      // Quando name não é null, o ?? retorna name e o ternário nem é avaliado
      html = render("<span>{{ name ?? cond ? 'A' : 'B' }}</span>",
          {'name': 'X', 'cond': false});
      expect(normalize(html), '<span> X </span>');
    });

    test('meu teste map', () {
      var html = render("<span>{{ name['chave'] }}</span>", {
        'name': {'chave': 'valor'}
      });
      expect(normalize(html), "<span> valor </span>");
    });

    test('uso em atributo', () {
      const tplTrue = '<div><img src=cond ? "a.png" : "b.png"></div>';
      var html = render(tplTrue, {'cond': true});
      expect(html, contains('src="a.png"'));

      html = render(tplTrue, {'cond': false});
      expect(html, contains('src="b.png"'));
    });
  });

  group('Estruturas de Dados (Mapas & Listas)', () {
    test('acessa valores de mapa usando sintaxe de indexador', () {
      var values = {
        'product': {'id': 123, 'name': 'Super Gadget'}
      };
      // Um elemento raiz é necessário
      var html = render("<p>Produto: {{ product['name'] }}</p>", values);
      expect(normalize(html), '<p> Produto: Super Gadget </p>');
    });

    test('acessa itens de lista usando sintaxe de indexador', () {
      var values = {
        'colors': ['Vermelho', 'Verde', 'Azul']
      };
      // Um elemento raiz é necessário
      var html = render("<p>Primeira cor: {{ colors[0] }}</p>", values);
      expect(normalize(html), '<p> Primeira cor: Vermelho </p>');
    });
  });

  group('Diretivas de Controle de Fluxo', () {
    test('diretiva "if" renderiza conteúdo condicionalmente', () {
      var html = render('<b if=show_it>Visível</b>', {'show_it': true});
      expect(normalize(html), '<b> Visível </b>');

      html = render('<b if=show_it>Visível</b>', {'show_it': false});
      expect(html, isEmpty);
    });

    test('diretiva "for-each" itera sobre uma lista de mapas', () {
      const template = '''
        <ul>
          <li for-each=items as="item" index-as="i">
            {{ i }}: {{ item['name'] }}
          </li>
        </ul>
      ''';
      var values = {
        'items': [
          {'name': 'Maçã'},
          {'name': 'Banana'},
        ]
      };
      var html = render(template, values);
      var normalized = normalize(html);
      expect(normalized, contains('<li> 0: Maçã </li>'));
      expect(normalized, contains('<li> 1: Banana </li>'));
    });

    test('diretiva "switch" seleciona o "case" correto', () {
      const template = '''
        <div>
          <switch value=status_code>
            <case value=200>OK</case>
            <case value=404>Não Encontrado</case>
            <default>Erro</default>
          </switch>
        </div>
      ''';
      var html = render(template, {'status_code': 404});
      expect(normalize(html), '<div> Não Encontrado </div>');
    });

    test('diretiva "switch" recorre ao "default"', () {
      const template = '''
        <div>
          <switch value=status_code>
            <case value=200>OK</case>
            <case value=404>Não Encontrado</case>
            <default>Status Desconhecido</default>
          </switch>
        </div>
      ''';
      var html = render(template, {'status_code': 500});
      expect(normalize(html), '<div> Status Desconhecido </div>');
    });
  });

  group('Funcionalidades Avançadas', () {
    test('diretiva "declare" cria variáveis de escopo', () {
      const template = '''
        <declare message="Olá">
          <span>{{ message }}</span>
          <declare message="Mundo">
            <span>{{ message }}</span>
          </declare>
          <span>{{ message }}</span>
        </declare>
      ''';
      var html = render(template);
      expect(normalize(html),
          '<span> Olá </span> <span> Mundo </span> <span> Olá </span>');
    });

    test('elemento customizado renderiza com dados passados', () {
      const template = '''
        <div>
          <element name="user-card">
            <div class="card">
              <h3>{{ user_data['name'] }}</h3>
              <p>ID: {{ user_data['id'] }}</p>
            </div>
          </element>
          <user-card @user_data=user_a />
          <user-card @user_data=user_b />
        </div>
      ''';
      var values = {
        'user_a': {'id': 1, 'name': 'Alice'},
        'user_b': {'id': 2, 'name': 'Bob'},
      };
      var html = render(template, values);
      var normalized = normalize(html);
      expect(normalized, contains('<h3> Alice </h3> <p> ID: 1 </p>'));
      expect(normalized, contains('<h3> Bob </h3> <p> ID: 2 </p>'));
    });

    test('elemento customizado repassa atributos padrão', () {
      const template = '''
        <div>
          <element name="custom-input">
            <input type="text" value=default_value>
          </element>
          <custom-input id="user-name" class="form-control" @default_value="guest" />
        </div>
      ''';
      var html = render(template);
      expect(html, contains('<div id="user-name" class="form-control"'));
      expect(html, contains('value="guest"'));
    });
  });

  group('Pré-processador (Includes & Herança)', () {
    late MemoryFileSystem fs;

    setUp(() {
      fs = MemoryFileSystem();
      fs.directory('/views').createSync();
    });

    test('a diretiva <include> renderiza o conteúdo de outro arquivo',
        () async {
      await fs
          .file('/views/_header.jael')
          .writeAsString('<h1>{{ title }}</h1>');
      await fs.file('/views/main.jael').writeAsString(
          '<div><include src="_header.jael" /><p>Conteúdo principal.</p></div>');

      var html =
          await renderWithPreprocessor('main.jael', fs, {'title': 'Meu Site'});
      var normalized = normalize(html);

      expect(normalized, contains('<h1> Meu Site </h1>'));
      expect(normalized, contains('<p> Conteúdo principal. </p>'));
    });

    test('a diretiva <extend> herda de um layout base e sobrescreve blocos',
        () async {
      await fs.file('/views/layout.jael').writeAsString('''
        <!DOCTYPE html>
        <html>
          <head><title>{{ page_title }}</title></head>
          <body>
            <block name="content">
              <p>Conteúdo Padrão.</p>
            </block>
          </body>
        </html>
      ''');
      await fs.file('/views/page.jael').writeAsString('''
        <extend src="layout.jael">
          <block name="content">
            <h2>Bem-vindo!</h2>
          </block>
        </extend>
      ''');

      var html = await renderWithPreprocessor(
          'page.jael', fs, {'page_title': 'Página Inicial'});

      var normalized = normalize(html);
      expect(normalized, contains('<title> Página Inicial </title>'));
      expect(normalized, contains('<h2> Bem-vindo! </h2>'));
      expect(normalized, isNot(contains('Conteúdo Padrão.')));
    });
  });
}
