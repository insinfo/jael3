import 'package:source_span/source_span.dart';
import 'package:belatuk_symbol_table/belatuk_symbol_table.dart';
import 'expression.dart';
import 'identifier.dart';
import 'token.dart';

class MemberExpression extends Expression {
  final Expression expression;
  final Token op;
  final Identifier name;

  MemberExpression(this.expression, this.op, this.name);

  @override
  dynamic compute(SymbolTable? scope) {
    var target = expression.compute(scope);
    if (op.span.text == '?.' && target == null) return null;
    if (target == null) return null;

    var key = name.name;
    var resolver = scope?.resolve('!memberResolver!')?.value;
    if (resolver is Function) {
      var resolved = resolver(target, key);
      if (resolved is MemberResolution) {
        if (resolved.handled) return resolved.value;
      } else if (resolved != null) {
        return resolved;
      }
    }

    if (target is Map) return target[key];

    if (target is Iterable || target is String) {
      switch (key) {
        case 'length':
          return (target as dynamic).length;
        case 'isEmpty':
          return (target as dynamic).isEmpty;
        case 'isNotEmpty':
          return (target as dynamic).isNotEmpty;
      }
    }

    if (scope?.resolve('!strict!')?.value == false) return null;
    throw ArgumentError('The name "$key" does not exist in this scope.');
  }

  @override
  FileSpan get span => expression.span.expand(op.span).expand(name.span);
}

class MemberResolution {
  final bool handled;
  final dynamic value;

  const MemberResolution.handled([this.value]) : handled = true;

  const MemberResolution.unresolved() : handled = false, value = null;
}
