import 'dart:convert';
import 'dart:io';

const String _defaultSourceUrl = 'https://unpkg.com/@types/web/index.d.ts';
const String _defaultOutputPath =
    'assets/autocomplete/javascript_objects.generated.json';

class _MemberInfo {
  const _MemberInfo({
    required this.name,
    required this.kind,
  });

  final String name;
  final String kind;
}

Future<void> main(List<String> args) async {
  final String source = _readOption(args, '--source') ?? _defaultSourceUrl;
  final String outputPath = _readOption(args, '--output') ?? _defaultOutputPath;
  final int minMembers =
      int.tryParse(_readOption(args, '--min-members') ?? '') ?? 2;

  final String dtsContent = await _loadSource(source);
  final Map<String, List<_MemberInfo>> interfaces =
      _parseInterfaces(dtsContent);
  final Map<String, String> globals = _parseGlobalObjectTypes(dtsContent);

  final Map<String, dynamic> javascriptObjects = <String, dynamic>{};
  final List<String> sortedObjectNames = globals.keys.toList()..sort();

  for (final String objectName in sortedObjectNames) {
    final String typeName = globals[objectName]!;
    final List<_MemberInfo>? members = interfaces[typeName];
    if (members == null || members.length < minMembers) {
      continue;
    }

    final List<Map<String, String>> serializedMembers = members
        .map((member) => <String, String>{
              'name': member.name,
              'kind': member.kind,
            })
        .toList(growable: false);

    javascriptObjects[objectName] = <String, dynamic>{
      'type': typeName,
      'members': serializedMembers,
    };
  }

  final Map<String, dynamic> output = <String, dynamic>{
    'version': 1,
    'source': source,
    'generatedAt': DateTime.now().toUtc().toIso8601String(),
    'objects': <String, dynamic>{
      'javascript': javascriptObjects,
    },
  };

  final File file = File(outputPath);
  await file.parent.create(recursive: true);
  await file.writeAsString(
    const JsonEncoder.withIndent('  ').convert(output),
  );

  stdout.writeln(
    'Generated ${javascriptObjects.length} objects into $outputPath '
    '(min members: $minMembers).',
  );
}

String? _readOption(List<String> args, String option) {
  for (final String arg in args) {
    if (arg.startsWith('$option=')) {
      return arg.substring(option.length + 1);
    }
  }
  return null;
}

Future<String> _loadSource(String source) async {
  if (source.startsWith('http://') || source.startsWith('https://')) {
    final HttpClient client = HttpClient();
    try {
      final HttpClientRequest request = await client.getUrl(Uri.parse(source));
      final HttpClientResponse response = await request.close();
      if (response.statusCode < 200 || response.statusCode >= 300) {
        throw Exception('Request failed with status ${response.statusCode}');
      }
      return await utf8.decoder.bind(response).join();
    } finally {
      client.close(force: true);
    }
  }

  return File(source).readAsString();
}

Map<String, String> _parseGlobalObjectTypes(String content) {
  final RegExp globalPattern = RegExp(
    r'^declare\s+(?:var|const)\s+([A-Za-z_$][\w$]*)\s*:\s*([^;]+);',
    multiLine: true,
  );
  final Map<String, String> objectTypes = <String, String>{};
  for (final RegExpMatch match in globalPattern.allMatches(content)) {
    final String? objectName = match.group(1);
    final String? typeExpression = match.group(2);
    final String? typeName = _extractPrimaryTypeName(typeExpression);
    if (objectName == null || typeName == null) {
      continue;
    }
    objectTypes[objectName] = typeName;
  }
  return objectTypes;
}

String? _extractPrimaryTypeName(String? typeExpression) {
  if (typeExpression == null) {
    return null;
  }

  final Iterable<RegExpMatch> tokens =
      RegExp(r'[A-Za-z_$][\w$]*').allMatches(typeExpression);
  if (tokens.isEmpty) {
    return null;
  }

  String token = tokens.first.group(0)!;
  if (token == 'typeof' && tokens.length > 1) {
    token = tokens.elementAt(1).group(0)!;
  }

  return token;
}

Map<String, List<_MemberInfo>> _parseInterfaces(String content) {
  final RegExp headerPattern = RegExp(
    r'^interface\s+([A-Za-z_$][\w$]*)[^{]*\{',
    multiLine: true,
  );
  final Map<String, List<_MemberInfo>> interfaces =
      <String, List<_MemberInfo>>{};

  for (final RegExpMatch match in headerPattern.allMatches(content)) {
    final String? interfaceName = match.group(1);
    if (interfaceName == null) {
      continue;
    }

    final int openBraceIndex = content.indexOf('{', match.start);
    if (openBraceIndex < 0) {
      continue;
    }

    final int closeBraceIndex = _findMatchingBrace(content, openBraceIndex);
    if (closeBraceIndex <= openBraceIndex) {
      continue;
    }

    final String body = content.substring(openBraceIndex + 1, closeBraceIndex);
    final List<_MemberInfo> members = _parseMembers(body);
    if (members.isNotEmpty) {
      interfaces[interfaceName] = members;
    }
  }

  return interfaces;
}

int _findMatchingBrace(String source, int openBraceIndex) {
  int depth = 0;
  bool inLineComment = false;
  bool inBlockComment = false;
  bool inSingleQuote = false;
  bool inDoubleQuote = false;
  bool inBacktick = false;

  for (int i = openBraceIndex; i < source.length; i++) {
    final String next = i + 1 < source.length ? source[i + 1] : '';
    final String char = source[i];

    if (inLineComment) {
      if (char == '\n') {
        inLineComment = false;
      }
      continue;
    }

    if (inBlockComment) {
      if (char == '*' && next == '/') {
        inBlockComment = false;
        i += 1;
      }
      continue;
    }

    if (inSingleQuote) {
      if (char == '\\' && next.isNotEmpty) {
        i += 1;
        continue;
      }
      if (char == "'") {
        inSingleQuote = false;
      }
      continue;
    }

    if (inDoubleQuote) {
      if (char == '\\' && next.isNotEmpty) {
        i += 1;
        continue;
      }
      if (char == '"') {
        inDoubleQuote = false;
      }
      continue;
    }

    if (inBacktick) {
      if (char == '\\' && next.isNotEmpty) {
        i += 1;
        continue;
      }
      if (char == '`') {
        inBacktick = false;
      }
      continue;
    }

    if (char == '/' && next == '/') {
      inLineComment = true;
      i += 1;
      continue;
    }

    if (char == '/' && next == '*') {
      inBlockComment = true;
      i += 1;
      continue;
    }

    if (char == "'") {
      inSingleQuote = true;
      continue;
    }

    if (char == '"') {
      inDoubleQuote = true;
      continue;
    }

    if (char == '`') {
      inBacktick = true;
      continue;
    }

    if (char == '{') {
      depth += 1;
    } else if (char == '}') {
      depth -= 1;
      if (depth == 0) {
        return i;
      }
    }
  }
  return -1;
}

List<_MemberInfo> _parseMembers(String body) {
  final RegExp methodPattern =
      RegExp(r'^(?:readonly\s+)?([A-Za-z_$][\w$]*)\s*\(');
  final RegExp propertyPattern =
      RegExp(r'^(?:readonly\s+)?([A-Za-z_$][\w$]*)\s*:');
  final Map<String, String> kindsByName = <String, String>{};

  bool inBlockComment = false;
  for (final String rawLine in body.split('\n')) {
    String line = rawLine.trim();
    if (line.isEmpty) {
      continue;
    }

    if (inBlockComment) {
      if (line.contains('*/')) {
        inBlockComment = false;
      }
      continue;
    }

    if (line.startsWith('/*')) {
      if (!line.contains('*/')) {
        inBlockComment = true;
      }
      continue;
    }

    if (line.startsWith('//') ||
        line.startsWith('*') ||
        line.startsWith('[') ||
        line.startsWith('new(')) {
      continue;
    }

    final RegExpMatch? methodMatch = methodPattern.firstMatch(line);
    if (methodMatch != null) {
      final String? name = methodMatch.group(1);
      if (_isValidMemberName(name)) {
        kindsByName[name!] = 'method';
      }
      continue;
    }

    final RegExpMatch? propertyMatch = propertyPattern.firstMatch(line);
    if (propertyMatch != null) {
      final String? name = propertyMatch.group(1);
      if (_isValidMemberName(name) && !kindsByName.containsKey(name)) {
        kindsByName[name!] = 'property';
      }
    }
  }

  final List<String> sortedNames = kindsByName.keys.toList()..sort();
  return sortedNames
      .map(
        (name) => _MemberInfo(
          name: name,
          kind: kindsByName[name]!,
        ),
      )
      .toList(growable: false);
}

bool _isValidMemberName(String? name) {
  if (name == null || name.isEmpty) {
    return false;
  }
  if (name == 'constructor' || name == 'prototype') {
    return false;
  }
  return true;
}
