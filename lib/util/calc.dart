/// Tiny calculator for amount fields: + − × ÷ with normal precedence,
/// parentheses and a leading minus. Accepts both ASCII (+-*/) and display
/// symbols (× ÷ −), and ignores thousands separators.
///
/// Returns null when the text is not a valid expression.
double? evaluateExpression(String input) {
  final src = input
      .replaceAll('×', '*')
      .replaceAll('x', '*')
      .replaceAll('X', '*')
      .replaceAll('÷', '/')
      .replaceAll('−', '-')
      .replaceAll(' ', '')
      .replaceAll(',', '');
  if (src.isEmpty) return null;
  final p = _Parser(src);
  try {
    final v = p.expr();
    if (!p.done) return null;
    if (v.isNaN || v.isInfinite) return null;
    return v;
  } on FormatException {
    return null;
  }
}

/// True when [text] contains an operation (not just a signed number).
bool hasOperator(String text) {
  final t = text.trim();
  if (t.isEmpty) return false;
  final body = (t.startsWith('-') || t.startsWith('−')) ? t.substring(1) : t;
  return RegExp(r'[+\-*/×÷−xX()]').hasMatch(body);
}

class _Parser {
  _Parser(this.s);

  final String s;
  int i = 0;

  bool get done => i >= s.length;

  String? get _peek => done ? null : s[i];

  double expr() {
    var v = term();
    while (_peek == '+' || _peek == '-') {
      final op = s[i++];
      final r = term();
      v = op == '+' ? v + r : v - r;
    }
    return v;
  }

  double term() {
    var v = factor();
    while (_peek == '*' || _peek == '/') {
      final op = s[i++];
      final r = factor();
      if (op == '/') {
        if (r == 0) throw const FormatException('divide by zero');
        v = v / r;
      } else {
        v = v * r;
      }
    }
    return v;
  }

  double factor() {
    if (_peek == '-') {
      i++;
      return -factor();
    }
    if (_peek == '+') {
      i++;
      return factor();
    }
    if (_peek == '(') {
      i++;
      final v = expr();
      if (_peek != ')') throw const FormatException('missing )');
      i++;
      return v;
    }
    final start = i;
    while (!done && RegExp(r'[0-9.]').hasMatch(s[i])) {
      i++;
    }
    if (start == i) throw const FormatException('number expected');
    final v = double.tryParse(s.substring(start, i));
    if (v == null) throw const FormatException('bad number');
    return v;
  }
}
