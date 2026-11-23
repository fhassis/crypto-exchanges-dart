import 'dart:convert';
import 'dart:io';

/// Decoded JSON of `test/fixtures/<name>` (captured verbatim from the venues).
dynamic fixture(String name) =>
    jsonDecode(File('test/fixtures/$name').readAsStringSync());
