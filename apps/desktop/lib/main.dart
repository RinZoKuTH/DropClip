import 'dart:io';
import 'package:dropclip_protocol/dropclip_protocol.dart';
import 'package:dropclip_ui/dropclip_ui.dart';

void main(List<String> args) {
  final isHiddenLaunch = args.contains('--hidden');
  stdout.writeln('Starting ${DropClipThemeTokens.appName} Desktop Client...');
  stdout.writeln('Protocol Version: ${ProtocolConstants.protocolVersion}');
  stdout.writeln('Launch mode: ${isHiddenLaunch ? "Background / Tray Only" : "Interactive Window"}');
}
