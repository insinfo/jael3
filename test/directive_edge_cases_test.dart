import 'package:belatuk_code_buffer/belatuk_code_buffer.dart';
import 'package:belatuk_symbol_table/belatuk_symbol_table.dart';
import 'package:jael3_fork/jael3.dart' as jael;
import 'package:test/test.dart';

String renderWithStrict(String template, Map<String, dynamic> values,
    {bool strictResolution = true}) {
  var doc = jael.parseDocument(template, onError: (e) => throw e)!;
  var buffer = CodeBuffer();
  const jael.Renderer()
      .render(doc, buffer, SymbolTable(values: values), strictResolution: strictResolution);
  return buffer.toString().trim();
}

void main() {
  group('Diretivas - casos de canto', () {
    test('if com expressao invalida entre aspas deve falhar', () {
      expect(
        () => renderWithStrict('<p if="a ==">X</p>', {'a': 1}),
        throwsA(isA<jael.JaelError>()),
      );
    });

    test('for-each com valor nao iteravel deve falhar', () {
      expect(
        () => renderWithStrict(
          '<ul><li for-each="items" as="i">{{ i }}</li></ul>',
          {'items': 123},
        ),
        throwsA(isA<jael.JaelError>()),
      );
    });

    test('if com variavel ausente e strictResolution=false nao deve falhar', () {
      var html = renderWithStrict('<p if="missing">X</p>', {},
          strictResolution: false);
      expect(html, isEmpty);
    });
  });
}
