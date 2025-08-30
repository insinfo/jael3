import 'dart:collection';
import 'package:charcode/ascii.dart';
import 'package:string_scanner/string_scanner.dart';
import '../ast/ast.dart';

final RegExp _whitespace = RegExp(r'[ \n\r\t]+');

final RegExp _id =
    RegExp(r'@?(([A-Za-z][A-Za-z0-9_]*-)*([A-Za-z][A-Za-z0-9_]*))');
final RegExp _string1 = RegExp(
    r"'((\\(['\\/bfnrt]|(u[0-9a-fA-F][0-9a-fA-F][0-9a-fA-F][0-9a-fA-F])))|([^'\\]))*'");
final RegExp _string2 = RegExp(
    r'"((\\(["\\/bfnrt]|(u[0-9a-fA-F][0-9a-fA-F][0-9a-fA-F][0-9a-fA-F])))|([^"\\]))*"');

Scanner scan(String text, {sourceUrl, bool asDSX = false}) =>
    _Scanner(text, sourceUrl)..scan(asDSX: asDSX);

abstract class Scanner {
  List<JaelError> get errors;

  List<Token> get tokens;
}

final Map<Pattern, TokenType> _expressionPatterns = {
  '{{': TokenType.lDoubleCurly,
  '{{-': TokenType.lDoubleCurly,
  '!DOCTYPE': TokenType.doctype,
  '!doctype': TokenType.doctype,
  '<': TokenType.lt,
  '>': TokenType.gt,
  '/': TokenType.slash,
  '=': TokenType.equals,
  '!=': TokenType.nequ,
  _string1: TokenType.string,
  _string2: TokenType.string,
  _id: TokenType.id,

  '}}': TokenType.rDoubleCurly,
  // Keywords
  'new': TokenType.$new,
  // Misc.
  '*': TokenType.asterisk,
  ':': TokenType.colon,
  ',': TokenType.comma,
  '.': TokenType.dot,
  '??': TokenType.elvis,
  '?': TokenType.question, // <-- adicionado ESTA LINHA
  '?.': TokenType.elvisDot,
  //'=': TokenType.equals,
  '!': TokenType.exclamation,
  '-': TokenType.minus,
  '%': TokenType.percent,
  '+': TokenType.plus,
  '[': TokenType.lBracket,
  ']': TokenType.rBracket,
  '{': TokenType.lCurly,
  '}': TokenType.rCurly,
  '(': TokenType.lParen,
  ')': TokenType.rParen,
  //'/': TokenType.slash,
  //'<': TokenType.lt,
  '<=': TokenType.lte,
  //'>': TokenType.gt,
  '>=': TokenType.gte,
  '==': TokenType.equ,
  //'!=': TokenType.nequ,
  //'=': TokenType.equals,
  RegExp(r'-?[0-9]+(\.[0-9]+)?([Ee][0-9]+)?'): TokenType.number,
  RegExp(r'0x[A-Fa-f0-9]+'): TokenType.hex,
  _string1: TokenType.string,
  _string2: TokenType.string,
  _id: TokenType.id,
};

class _Scanner implements Scanner {
  @override
  final List<JaelError> errors = [];

  @override
  final List<Token> tokens = [];
  _ScannerState state = _ScannerState.html;
  final Queue<String?> openTags = Queue();

  late SpanScanner _scanner;

  _Scanner(String text, sourceUrl) {
    _scanner = SpanScanner(text, sourceUrl: sourceUrl);
  }

  void scan({bool asDSX = false}) {
    while (!_scanner.isDone) {
      if (state == _ScannerState.html) {
        scanHtml(asDSX);
      } else if (state == _ScannerState.freeText) {
        // Consome até aparecer {{ (ou { em DSX) ou até o fechamento real da tag atual (ex: </script>)
        var start = _scanner.state, end = start;

        while (!_scanner.isDone) {
          // 1) Comentários HTML em freeText: ignorar completamente
          if (_scanner.matches('<!--')) {
            final commentStart = _scanner.state;
            _scanner.scan('<!--');
            var closed = false;
            while (!_scanner.isDone) {
              if (_scanner.matches('-->')) {
                _scanner.scan('-->');
                closed = true;
                break;
              }
              _scanner.readChar();
            }
            if (!closed) {
              errors.add(JaelError(
                JaelErrorSeverity.error,
                'Unterminated HTML comment.',
                _scanner.spanFrom(commentStart, _scanner.state),
              ));
            }
            continue;
          }

          // 2) Interpolação: volta ao HTML para o parser lidar
          if (_scanner.matches(asDSX ? '{' : '{{')) {
            state = _ScannerState.html;
            break;
          }

          // 3) Olhar por '<'
          var ch = _scanner.readChar();
          if (ch == $lt) {
            final inScript = openTags.isNotEmpty &&
                (openTags.first?.toLowerCase() == 'script');

            // 3a) Se for um fechamento: </...>
            if (_scanner.matches('/')) {
              final afterLt = _scanner.state; // pos após "<"
              _scanner.readChar(); // consome '/'
              _scanner.scan(_whitespace);
              var shouldBreak = false;

              if (_scanner.matches(_id)) {
                final tagName = _scanner.lastMatch![0]!.toLowerCase();
                // Só quebra se a tag de fechamento for a mesma que abriu o modo freeText
                if (openTags.isNotEmpty &&
                    tagName == openTags.first?.toLowerCase()) {
                  shouldBreak = true;
                }
              }

              _scanner.state = afterLt; // volta para posição logo após "<"

              if (shouldBreak) {
                _scanner.position--; // devolve o '<' para o modo HTML
                state = _ScannerState.html;
                break;
              }
              // Se não for a tag de fechamento correta, continua tratando como texto.
            }
            // 3b) Se for abertura "<foo": só volta ao HTML se NÃO estivermos dentro de <script> ou <style>
            else if (_scanner.matches(_id)) {
              if (!inScript) {
                // Adicionar outras tags como 'style' se necessário
                // devolver o '<' para o modo HTML tokenizar a tag
                _scanner.position--;
                state = _ScannerState.html;
                break;
              }
              // se estamos em script, "<div" etc. é tratado como texto.
            }
          }

          end = _scanner.state;
        }

        var span = _scanner.spanFrom(start, end);
        if (span.text.isNotEmpty == true) {
          tokens.add(Token(TokenType.text, span, null));
        }
      }
    }
  }

  void scanHtml(bool asDSX) {
    var brackets = Queue<Token>();

    do {
      var potential = <Token>[];

      while (true) {
        _scanner.scan(_whitespace);

        // Comentários HTML no modo HTML: emite token
        if (_scanner.matches('<!--')) {
          final start = _scanner.state;
          _scanner.scan('<!--');
          var closed = false;
          while (!_scanner.isDone) {
            if (_scanner.matches('-->')) {
              _scanner.scan('-->');
              closed = true;
              break;
            }
            _scanner.readChar();
          }
          final span = _scanner.spanFrom(start, _scanner.state);
          if (!closed) {
            errors.add(JaelError(
                JaelErrorSeverity.error, 'Unterminated HTML comment.', span));
          } else {
            tokens.add(Token(TokenType.htmlComment, span, null));
          }
          continue;
        }

        // Varredura normal
        _expressionPatterns.forEach((pattern, type) {
          if (_scanner.matches(pattern)) {
            if (_scanner.lastSpan != null) {
              potential
                  .add(Token(type, _scanner.lastSpan!, _scanner.lastMatch));
            }
          }
        });

        potential.sort((a, b) => b.span.length.compareTo(a.span.length));
        if (potential.isEmpty) break;

        var token = potential.first;
        tokens.add(token);
        _scanner.scan(token.span.text);

        if (token.type == TokenType.lt) {
          brackets.addFirst(token);

          // Captura nome da tag para controlar contexto (script)
          var replay = _scanner.state;
          _scanner.scan(_whitespace);
          if (_scanner.matches(_id)) {
            openTags.addFirst(_scanner.lastMatch![0]!.toLowerCase());
          } else {
            _scanner.state = replay;
          }
        } else if (token.type == TokenType.slash) {
          // "</"
          if (brackets.isNotEmpty && brackets.first.type == TokenType.lt) {
            brackets
              ..removeFirst()
              ..addFirst(token);
          }
        } else if (token.type == TokenType.gt) {
          // Fechou ">"
          if (brackets.isNotEmpty && brackets.first.type == TokenType.slash) {
            // Terminou "</...>"
            brackets.removeFirst();
            if (openTags.isNotEmpty) openTags.removeFirst();

            var replay = _scanner.state;
            _scanner.scan(_whitespace);
            if (!_scanner.matches('<') && !_scanner.matches('{{')) {
              _scanner.state = replay;
              state = _ScannerState.freeText;
              break;
            }
          } else if (brackets.isNotEmpty &&
              brackets.first.type == TokenType.lt) {
            // Terminou "<...>"
            brackets.removeFirst();

            final tagName = openTags.isNotEmpty ? openTags.first : '';

            var replay = _scanner.state;
            _scanner.scan(_whitespace);

            // Entra em modo freeText para tags especiais como <script> e <style>
            if (tagName == 'script' || tagName == 'style') {
              if (!_scanner.matches('</')) {
                _scanner.state = replay;
                state = _ScannerState.freeText;
                break;
              }
            } else if (!_scanner.matches('<') && !_scanner.matches('{{')) {
              _scanner.state = replay;
              state = _ScannerState.freeText;
              break;
            }
          }
        } else if (token.type ==
            (asDSX ? TokenType.rCurly : TokenType.rDoubleCurly)) {
          state = _ScannerState.freeText;
          break;
        }

        potential.clear();
      }
    } while (brackets.isNotEmpty && !_scanner.isDone);

    if (brackets.isEmpty) {
      state = _ScannerState.freeText;
    }
  }
}

enum _ScannerState { html, freeText }
