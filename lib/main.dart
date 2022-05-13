import 'dart:io';

import 'package:args/args.dart';
import 'package:path/path.dart' as path;
import 'package:yaml/yaml.dart';

import 'android.dart' as android_launcher_icons;
import 'constants.dart';
import 'custom_exceptions.dart';
import 'ios.dart' as ios_launcher_icons;

const String helpFlag = 'help';
const String defaultConfigFilePath = 'assets/flutter_launcher_icons/';
const String flavorOption = 'flavor';
const String generateAllFlag = 'all';
const String defaultConfigFile =
    defaultConfigFilePath + 'flutter_launcher_icons.yaml';
const String flavorConfigFilePattern = r'^flutter_launcher_icons-(.*).yaml$';
String flavorConfigFile(String flavor) => 'flutter_launcher_icons-$flavor.yaml';

List<String> getFlavors() {
  final List<String> flavors = [];
  for (var item in Directory(defaultConfigFilePath).listSync()) {
    if (item is File) {
      final name = path.basename(item.path);
      final match = RegExp(flavorConfigFilePattern).firstMatch(name);
      if (match != null) {
        flavors.add(match.group(1)!);
      }
    }
  }
  return flavors;
}

Future<void> createIconsFromArguments(List<String> arguments) async {
  final ArgParser parser = ArgParser(allowTrailingOptions: true);
  parser.addFlag(helpFlag, abbr: 'h', help: 'Usage help', negatable: false);
  // Make default null to differentiate when it is explicitly set
  parser.addOption(
    flavorOption,
    abbr: 'f',
    help: 'Configure flavor name (flutter_launcher_icons-<flavor name>)',
  );
  parser.addFlag(generateAllFlag,
      abbr: 'a',
      help: 'Generate all flavors in folder (default: $defaultConfigFilePath)',
      negatable: false);
  final ArgResults argResults = parser.parse(arguments);

  if (argResults[helpFlag]) {
    stdout.writeln(parser.usage);
    exit(0);
  }

  // Flavors manangement
  final flavors = getFlavors();
  final hasFlavors = flavors.isNotEmpty;

  if (argResults[generateAllFlag]) {
    // Create icons
    print('\n✓ generateAllFlag');
    if (!hasFlavors) {
      stderr.writeln('\n✕ No flavors found (default: $defaultConfigFilePath)');
      exit(2);
    } else {
      try {
        for (String flavor in flavors) {
          print('\nFlavor: $flavor');
          generateFlavor(flavor);
        }
        print('\n✓ Successfully generated launcher icons for flavors');
      } catch (e) {
        stderr.writeln('\n✕ Could not generate launcher icons for flavors');
        stderr.writeln(e);
        exit(2);
      }
    }
  } else {
    final String? specificFlavor = argResults[flavorOption];

    if (specificFlavor != null) {
      if (specificFlavor == flavorOption) {
        stderr.writeln('\n✕ Specify a flavor to be generated');
        exit(2);
      } else {
        try {
          bool flavorExists = false;
          for (String flavor in flavors) {
            if (flavor == specificFlavor) {
              flavorExists = true;
            }
          }
          if (flavorExists) {
            generateFlavor(specificFlavor);
            print(
                '\n✓ Successfully generated launcher icons for flavor: $specificFlavor');
          } else {
            stderr.writeln(
                '\n✕ Could not find flavor ${flavorConfigFile(specificFlavor)} in $defaultConfigFilePath');
            exit(2);
          }
        } catch (e) {
          stderr.writeln(
              '\n✕ Could not generate launcher icons for flavor $specificFlavor');
          stderr.writeln(e);
          exit(2);
        }
      }
    } else {
      stdout.writeln(parser.usage);
      exit(0);
    }
  }
}

Future<void> generateFlavor(String flavor) async {
  final Map<String, dynamic> yamlConfig = loadConfigFile(
      defaultConfigFilePath + flavorConfigFile(flavor),
      flavorConfigFile(flavor));
  await createIconsFromConfig(yamlConfig, flavor);
}

Future<void> createIconsFromConfig(Map<String, dynamic> config,
    [String? flavor]) async {
  if (!isImagePathInConfig(config)) {
    throw const InvalidConfigException(errorMissingImagePath);
  }
  if (!hasPlatformConfig(config)) {
    throw const InvalidConfigException(errorMissingPlatform);
  }

  if (isNeedingNewAndroidIcon(config) || hasAndroidAdaptiveConfig(config)) {
    final int minSdk = android_launcher_icons.minSdk();
    if (minSdk < 26 &&
        hasAndroidAdaptiveConfig(config) &&
        !hasAndroidConfig(config)) {
      throw const InvalidConfigException(errorMissingRegularAndroid);
    }
  }

  if (isNeedingNewAndroidIcon(config)) {
    android_launcher_icons.createDefaultIcons(config, flavor);
  }
  if (hasAndroidAdaptiveConfig(config)) {
    android_launcher_icons.createAdaptiveIcons(config, flavor);
  }
  if (isNeedingNewIOSIcon(config)) {
    ios_launcher_icons.createIcons(config, flavor);
  }
}

Map<String, dynamic>? loadConfigFileFromArgResults(ArgResults argResults,
    {bool verbose = false}) {
  final String? configFile = argResults[flavorOption];

  // if icon is given, try to load icon
  if (configFile != null && configFile != defaultConfigFile) {
    try {
      return loadConfigFile(configFile, configFile);
    } catch (e) {
      if (verbose) {
        stderr.writeln(e);
      }

      return null;
    }
  }

  // If none set try flutter_launcher_icons.yaml first then pubspec.yaml
  // for compatibility
  try {
    return loadConfigFile(defaultConfigFile, configFile);
  } catch (e) {
    // Try pubspec.yaml for compatibility
    if (configFile == null) {
      try {
        return loadConfigFile('pubspec.yaml', configFile);
      } catch (_) {}
    }

    // if nothing got returned, print error
    if (verbose) {
      stderr.writeln(e);
    }
  }

  return null;
}

Map<String, dynamic> loadConfigFile(String path, String? fileOptionResult) {
  final File file = File(path);
  final String yamlString = file.readAsStringSync();
  // ignore: always_specify_types
  final Map yamlMap = loadYaml(yamlString);

  if (!(yamlMap['flutter_icons'] is Map)) {
    stderr.writeln(NoConfigFoundException('Check that your config file '
        '`${fileOptionResult ?? defaultConfigFile}`'
        ' has a `flutter_icons` section'));
    exit(1);
  }

  // yamlMap has the type YamlMap, which has several unwanted sideeffects
  final Map<String, dynamic> config = <String, dynamic>{};
  for (MapEntry<dynamic, dynamic> entry in yamlMap['flutter_icons'].entries) {
    config[entry.key] = entry.value;
  }

  return config;
}

bool isImagePathInConfig(Map<String, dynamic> flutterIconsConfig) {
  return flutterIconsConfig.containsKey('image_path') ||
      (flutterIconsConfig.containsKey('image_path_android') &&
          flutterIconsConfig.containsKey('image_path_ios'));
}

bool hasPlatformConfig(Map<String, dynamic> flutterIconsConfig) {
  return hasAndroidConfig(flutterIconsConfig) ||
      hasIOSConfig(flutterIconsConfig);
}

bool hasAndroidConfig(Map<String, dynamic> flutterLauncherIcons) {
  return flutterLauncherIcons.containsKey('android');
}

bool isNeedingNewAndroidIcon(Map<String, dynamic> flutterLauncherIconsConfig) {
  return hasAndroidConfig(flutterLauncherIconsConfig) &&
      flutterLauncherIconsConfig['android'] != false;
}

bool hasAndroidAdaptiveConfig(Map<String, dynamic> flutterLauncherIconsConfig) {
  return isNeedingNewAndroidIcon(flutterLauncherIconsConfig) &&
      flutterLauncherIconsConfig.containsKey('adaptive_icon_background') &&
      flutterLauncherIconsConfig.containsKey('adaptive_icon_foreground');
}

bool hasIOSConfig(Map<String, dynamic> flutterLauncherIconsConfig) {
  return flutterLauncherIconsConfig.containsKey('ios');
}

bool isNeedingNewIOSIcon(Map<String, dynamic> flutterLauncherIconsConfig) {
  return hasIOSConfig(flutterLauncherIconsConfig) &&
      flutterLauncherIconsConfig['ios'] != false;
}
