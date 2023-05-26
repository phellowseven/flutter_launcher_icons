// ignore_for_file: public_member_api_docs

import 'dart:io';

import 'package:args/args.dart';
import 'package:flutter_launcher_icons/android.dart' as android_launcher_icons;
import 'package:flutter_launcher_icons/config/config.dart';
import 'package:flutter_launcher_icons/constants.dart';
import 'package:flutter_launcher_icons/custom_exceptions.dart';
import 'package:flutter_launcher_icons/ios.dart' as ios_launcher_icons;
import 'package:flutter_launcher_icons/logger.dart';
import 'package:path/path.dart' as path;

const String fileOption = 'file';
const String helpFlag = 'help';
const String defaultConfigFilePath = 'scripts/flavored_pubspec/flavor/';
const String flavorOption = 'flavor';
const String generateAllFlag = 'all';
const String defaultConfigFile =
    defaultConfigFilePath + 'flutter_launcher_icons.yaml';
const String flavorConfigFilePattern = r'^(.*).yaml$';
String flavorConfigFile(String flavor) => '$flavor.yaml';

const String verboseFlag = 'verbose';
const String prefixOption = 'prefix';

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
  parser
    ..addFlag(
      helpFlag,
      abbr: 'h',
      help: 'Usage help',
      negatable: false,
    )
    // Make default null to differentiate when it is explicitly set
    ..addOption(
      flavorOption,
      abbr: 'f',
      help: 'Configure flavor name (<flavor name>)',
    )
    ..addFlag(
      generateAllFlag,
      abbr: 'a',
      help: 'Generate all flavors in folder (default: $defaultConfigFilePath)',
      negatable: false,
    )
    ..addFlag(
      verboseFlag,
      abbr: 'v',
      help: 'Verbose output',
      defaultsTo: false,
    )
    ..addOption(
      prefixOption,
      abbr: 'p',
      help: 'Generates config in the given path. Only Supports web platform',
      defaultsTo: '.',
    );

  final ArgResults argResults = parser.parse(arguments);
  // creating logger based on -v flag
  final logger = FLILogger(argResults[verboseFlag]);

  logger.verbose('Received args ${argResults.arguments}');

  if (argResults[helpFlag]) {
    stdout.writeln(parser.usage);
    exit(0);
  }

  // Flavors management
  final flavors = getFlavors();
  final hasFlavors = flavors.isNotEmpty;

  if (argResults[generateAllFlag]) {
    // Create icons
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
              '\n✓ Successfully generated launcher icons for flavor: $specificFlavor',
            );
          } else {
            stderr.writeln(
              '\n✕ Could not find flavor ${flavorConfigFile(specificFlavor)} in $defaultConfigFilePath',
            );
            exit(2);
          }
        } catch (e) {
          stderr.writeln(
            '\n✕ Could not generate launcher icons for flavor $specificFlavor',
          );
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

Future<void> generateFlavor(
  String flavor,
) async {
  final flutterConfigs = Config.loadConfigFromPath(
    flavorConfigFile(flavor),
    defaultConfigFilePath,
  );
  if (flutterConfigs == null) {
    throw const NoConfigFoundException(
      'No configuration found',
    );
  }

  await createIconsFromConfig(
    flutterConfigs,
    flavor,
  );
}

Future<void> createIconsFromConfig(
  Config flutterConfigs, [
  String? flavor,
]) async {
  if (!flutterConfigs.hasPlatformConfig) {
    throw const InvalidConfigException(errorMissingPlatform);
  }

  if (flutterConfigs.isNeedingNewAndroidIcon) {
    android_launcher_icons.createDefaultIcons(flutterConfigs, flavor);
  }
  if (flutterConfigs.hasAndroidAdaptiveConfig) {
    android_launcher_icons.createAdaptiveIcons(flutterConfigs, flavor);
  }
  if (flutterConfigs.isNeedingNewIOSIcon) {
    ios_launcher_icons.createIcons(flutterConfigs, flavor);
  }
}

Config? loadConfigFileFromArgResults(
  ArgResults argResults,
) {
  final String prefixPath = argResults[prefixOption];
  final flutterLauncherIconsConfigs = Config.loadConfigFromPath(
        argResults[fileOption],
        prefixPath,
      ) ??
      Config.loadConfigFromPubSpec(prefixPath);
  return flutterLauncherIconsConfigs;
}
