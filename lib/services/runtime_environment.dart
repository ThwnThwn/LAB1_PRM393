import 'runtime_environment_stub.dart'
    if (dart.library.io) 'runtime_environment_io.dart'
    as platform;

String readRuntimeEnvironment(String name) =>
    platform.readRuntimeEnvironment(name).trim();
