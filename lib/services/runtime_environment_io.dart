import 'dart:io';

String readRuntimeEnvironment(String name) => Platform.environment[name] ?? '';
