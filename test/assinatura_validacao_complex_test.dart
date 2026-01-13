import 'dart:io';

import 'package:belatuk_code_buffer/belatuk_code_buffer.dart';
import 'package:belatuk_symbol_table/belatuk_symbol_table.dart';
import 'package:file/local.dart';
import 'package:jael3_fork/jael3.dart' as jael;
import 'package:jael3_fork/jael3_preprocessor.dart' as jael_pre;
import 'package:path/path.dart' as p;
import 'package:test/test.dart';

String normalize(String html) {
  return html.replaceAll(RegExp(r'\s+'), ' ').trim();
}

void main() {
  test('assinatura_validacao.html - fluxo completo com dados reais', () async {
    const fs = LocalFileSystem();
    final viewsDir = fs.directory(p.join(
      Directory.current.path,
      'test',
      'assets',
      'views',
    ));
    final file = viewsDir.childFile('assinatura_validacao.html');
    final content = await file.readAsString();

    final doc = jael.parseDocument(content,
        sourceUrl: file.uri, onError: (e) => throw e)!;
    final resolved =
        await jael_pre.resolve(doc, viewsDir, onError: (e) => throw e);
    expect(resolved, isNotNull);

    final data = _assinaturaValidacaoSample();
    final buffer = CodeBuffer();
    const jael.Renderer()
        .render(resolved!, buffer, SymbolTable(values: data));
    final html = normalize(buffer.toString());

    expect(html, contains('Validação de documentos'));
    expect(html, contains('DOCUMENTO VÁLIDO'));
    expect(html, isNot(contains('DOCUMENTO INVÁLIDO')));
    expect(html, contains('3 + 4 = ?'));
    expect(html, contains('Assinatura #1'));
    expect(html, contains('Assinatura #2'));
    expect(html, contains('Maria da Silva'));
    expect(html, contains('Joao Pereira'));
    expect(html, isNot(contains('Nenhuma assinatura encontrada')));

    final assinaturaCount =
        RegExp(r'Assinatura #').allMatches(html).length;
    expect(assinaturaCount, 2);
  });
}

Map<String, dynamic> _assinaturaValidacaoSample() {
  final assinaturas = <Map<String, dynamic>>[
    {
      'numero': 1,
      'nome': 'Maria da Silva',
      'cpf': '***.***.***-11',
      'serial': '4A9F1C2B',
      'data': '13/01/2026 14:30:12',
      'politica': 'ICP-Brasil',
    },
    {
      'numero': 2,
      'nome': 'Joao Pereira',
      'cpf': '***.***.***-22',
      'serial': '9C8B7A6D',
      'data': '13/01/2026 14:31:05',
      'politica': 'ICP-Brasil',
    },
  ];

  return {
    'anoAtual': '2026',
    'captchaQuestion': '3 + 4 = ?',
    'erro': null,
    'validacaoCriptoOk': true,
    'totalAssinaturasPdf': assinaturas.length,
    'assinaturasValidas': assinaturas.length,
    'hashUpload': '3c9f1a2b4d5e6f7081920a1b2c3d4e5f',
    'assinaturas': assinaturas,
    'assinaturasVazias': false,
    'temAssinaturas': true,
    'modoUpload': true,
    'pedidoStatus': 'Upload',
  };
}
