import 'dart:io' as io;

import 'package:belatuk_code_buffer/belatuk_code_buffer.dart';
import 'package:belatuk_symbol_table/belatuk_symbol_table.dart';
import 'package:file/file.dart' as file;
import 'package:file/local.dart';
import 'package:jael3_fork/jael3.dart';
import 'package:jael3_fork/jael3_preprocessor.dart';
import 'package:path/path.dart' as p;

Future<void> main(List<String> args) async {
  final renderOutput = args.contains('--render');
  final viewDirArg = _readOption(args, '--views-dir');
  final filteredArgs = _stripArgs(args, {'--render', '--views-dir'});
  final file.Directory viewsDir = _resolveViewsDir(viewDirArg);
  final targets = await _collectTargets(filteredArgs, viewsDir);

  if (targets.isEmpty) {
    io.stdout.writeln('Nenhum arquivo alvo encontrado.');
    io.exitCode = 1;
    return;
  }

  var failures = 0;
  for (final file in targets) {
    io.stdout.writeln('--- ${p.relative(file.path, from: viewsDir.path)}');

    final content = await file.readAsString();
    final errors = <JaelError>[];

    Document? doc;
    try {
      doc = parseDocument(
        content,
        sourceUrl: file.uri,
        asDSX: false,
        onError: errors.add,
      );
    } catch (e, st) {
      failures++;
      io.stdout.writeln('Falha em parseDocument: $e');
      io.stdout.writeln(st);
      continue;
    }

    Document? resolvedDoc;
    if (doc != null) {
      try {
        resolvedDoc = await resolve(doc, viewsDir, onError: errors.add);
      } catch (_) {
        // Ignora: jael3_fork preenche "errors" via callback.
      }
    }

    if (renderOutput && doc != null) {
      final locals = _buildRenderLocals(file.path);
      final buffer = CodeBuffer();
      final scope = SymbolTable(values: {
        ...locals,
        '!memberResolver!': (Object? target, String name) {
          if (target is Map) {
            return MemberResolution.handled(target[name]);
          }
          return const MemberResolution.unresolved();
        }
      });
      try {
        const Renderer().render(resolvedDoc ?? doc, buffer, scope);
        io.stdout.writeln('RENDER OK');
      } catch (e, st) {
        failures++;
        io.stdout.writeln('Falha em render: $e');
        io.stdout.writeln(st);
        continue;
      }
    }

    if (errors.isEmpty) {
      io.stdout.writeln('OK');
      continue;
    }

    failures++;
    for (final error in errors) {
      final span = error.span;
      final line = span.start.line;
      final column = span.start.column;
      io.stdout.writeln('ERRO: ${error.message}');
      io.stdout.writeln('  Linha ${line + 1}, coluna ${column + 1}');
      io.stdout.writeln(_lineWithPointer(content, line, column));
    }
  }

  if (failures > 0) {
    io.exitCode = 1;
  }
}

file.Directory _resolveViewsDir(String? overridePath) {
  const fs = LocalFileSystem();
  if (overridePath != null && overridePath.trim().isNotEmpty) {
    final custom = fs.directory(overridePath);
    if (custom.existsSync()) return custom.absolute;
    throw StateError('Pasta views nao encontrada: ${custom.path}');
  }
  final cwd = fs.currentDirectory;
  final direct = fs.directory(p.join(cwd.path, 'views'));
  if (direct.existsSync()) return direct.absolute;

  final fallback = fs.directory(p.join(cwd.path, 'backend', 'views'));
  if (fallback.existsSync()) return fallback.absolute;

  final testViews = fs.directory(p.join(cwd.path, 'test', 'assets', 'views'));
  if (testViews.existsSync()) return testViews.absolute;

  throw StateError('Nao encontrei a pasta views partindo de ${cwd.path}');
}

Future<List<file.File>> _collectTargets(
    List<String> args, file.Directory viewsDir) async {
  if (args.isEmpty) {
    final list = await viewsDir
        .list(recursive: true)
        .where((e) => e is file.File && _isTemplate(e.path))
        .cast<file.File>()
        .toList();
    list.sort((a, b) => a.path.compareTo(b.path));
    return list;
  }

  final files = <file.File>[];
  for (final arg in args) {
    final candidate = p.isAbsolute(arg)
        ? LocalFileSystem().file(arg)
        : LocalFileSystem().file(p.join(viewsDir.path, arg));
    if (candidate.existsSync()) {
      files.add(candidate);
    } else {
      io.stdout.writeln('Aviso: arquivo nao encontrado: $arg');
    }
  }
  return files;
}

bool _isTemplate(String path) {
  final lower = path.toLowerCase();
  return lower.endsWith('.html') || lower.endsWith('.jael');
}

String _lineWithPointer(String source, int line, int column) {
  final lines = source.replaceAll('\r', '').split('\n');
  if (line < 0 || line >= lines.length) return '';
  final text = lines[line];
  final safeColumn = column.clamp(0, text.length);
  final padding = List.filled(safeColumn, ' ').join();
  return '$text\n$padding^';
}

String? _readOption(List<String> args, String name) {
  for (var i = 0; i < args.length - 1; i++) {
    if (args[i] == name) return args[i + 1];
  }
  return null;
}

List<String> _stripArgs(List<String> args, Set<String> names) {
  final out = <String>[];
  for (var i = 0; i < args.length; i++) {
    final arg = args[i];
    if (names.contains(arg)) {
      if (arg == '--views-dir' && i + 1 < args.length) {
        i++;
      }
      continue;
    }
    out.add(arg);
  }
  return out;
}

Map<String, dynamic> _buildRenderLocals(String path) {
  final fileName = p.basename(path).toLowerCase();
  if (fileName == 'assinatura_validacao.html') {
    return _assinaturaValidacaoSample();
  }
  if (fileName == 'login.html') {
    return _loginSample();
  }
  if (fileName == 'scripts.html') {
    return _scriptsSample();
  }
  return <String, dynamic>{};
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

Map<String, dynamic> _loginSample() {
  return {
    'logoSvgString': '<svg viewBox="0 0 10 10"><circle cx="5" cy="5" r="4"/></svg>',
    'loginGovUrl': '/oauth/govbr',
    'urlGovBr': '/oauth/govbr',
    'urlLogin': '/login',
    'urlPasswordForgot': '/auth/forgot',
    'urlPasswordReset': '/auth/reset',
    'appName': 'SALI',
    'anoAtual': '2026',
    'erro': null,
  };
}

Map<String, dynamic> _scriptsSample() {
  return {
    'urlPasswordForgot': '/auth/forgot',
    'urlPasswordReset': '/auth/reset',
    'urlLoginGov': '/oauth/govbr',
    'urlGovBr': '/oauth/govbr',
    'urlLogin': '/login',
    'urlLoginGoogle': '/oauth/google',
    'urlLogout': '/logout',
  };
}
