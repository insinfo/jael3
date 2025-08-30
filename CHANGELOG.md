# Change Log

## 8.4.0

### Features
- Support for the **ternary operator `?:`** with correct precedence (higher than `??`).

### Removed
- Dependency on `dart:mirrors`.
- **`MemberExpression`** (property access via `.` / `?.`) and **`NewExpression`** (construction via `new`).

### Fixes
- Scanner now recognizes `?` and improves handling of HTML comments and content inside `<script>/<style>`.
- Parser skips comments/whitespace before/between DOCTYPE and the document root.
- Fix `Attribute.span` when using `!=`.
- Prevent false positives with `/>` inside expressions.

### Migration (BREAKING CHANGES)
- Replace property access `foo.bar` with **`foo['bar']`**.
- For object construction, inject factories/functions into the scope and call them (e.g., `makeUser(name: '...')`).


## 8.3.0

- Fix HTML comment handling in both the scanner and the parser:
  - Correctly tokenizes `<!-- ... -->`
  - Ensures comment contents are ignored (no longer leaked as text nodes)
  - Prevents delimiters from being emitted as literal text
  - Detects/guards against unterminated comments
- No public API changes; behavior is now spec-compliant and backwards compatible.
- incorporated jael3_preprocessor on package

## 8.2.0

* Require Dart >= 3.3
* Updated `lints` to 4.0.0

## 8.1.1

* Updated repository link

## 8.1.0

* Updated `lints` to 3.0.0
* Fixed linter warnings

## 8.0.0

* Require Dart >= 3.0

## 7.0.0

* Require Dart >= 2.17

## 6.0.1

* Fixed analyze errors

## 6.0.0

* Require Dart >= 2.16

## 5.0.0

* Skipped release

## 4.2.0

* Updated to use `package:belatuk_code_buffer`

## 4.1.0

* Updated to use `package:belatuk_symbol_table`
* Updated linter to `package:lints`

## 4.0.0

* Migrated to support Dart >= 2.12 NNBD

## 3.0.0

* Migrated to work with Dart >= 2.12 Non NNBD

## 2.0.2

* Fixed handling of `if` in non-strict mode.
* Roll `JaelFormatter` and `jaelfmt`.

## 2.0.1

* Fixed bug where the `textarea` name check would never return `true`.

## 2.0.0+1

* Meta-update for Pub score.

## 2.0.0

* Dart 2 updates.
* Remove usage of `package:dart2_constant`.

## 1.0.6+1

* Ensure `<element>` passes attributes.

## 1.0.6

* Add `index-as` to `for-each`.
* Support registering + rendering custom elements.
* Improve handling of booleans in non-strict mode.

## 1.0.5

* Add support for DSX, a port of JSX to Dart.

## 1.0.4

* Skip HTML comments in free text.

## 1.0.3

* Fix a scanner bug that prevented proper parsing of HTML nodes
followed by free text.
* Don't trim `<textarea>` content.

## 1.0.2

* Use `package:dart2_constant`.
* Upgrade `package:symbol_table`.
* Added `Renderer.errorDocument`.

## 1.0.1

* Reworked the scanner; thereby fixing an extremely pesky bug
that prevented successful parsing of Jael files containing
JavaScript.
