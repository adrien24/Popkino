import 'package:flutter/material.dart';
import 'package:material_symbols_icons/symbols.dart';
import 'package:qr_flutter/qr_flutter.dart';

import '../../i18n/strings.g.dart';
import '../../screens/settings/licenses_screen.dart';
import '../../theme/mono_tokens.dart';
import '../../utils/app_version.dart';
import '../../utils/dialogs.dart';
import '../../utils/external_url.dart';
import '../../utils/platform_detector.dart';
import '../../widgets/app_icon.dart';
import '../../widgets/dialog_action_button.dart';
import '../../widgets/focusable_list_tile.dart';
import '../../widgets/focused_scroll_scaffold.dart';
import '../../widgets/settings_section.dart';
import '../fork_identity.dart';

/// Settings > About for the fork: same layout as the upstream `AboutScreen`
/// (which stays untouched), plus the "based on" notice, the licence and the
/// source code address. TVs rarely have a browser, so there the address is
/// shown as a QR code.
class ForkAboutScreen extends StatefulWidget {
  const ForkAboutScreen({super.key});

  @override
  State<ForkAboutScreen> createState() => _ForkAboutScreenState();
}

class _ForkAboutScreenState extends State<ForkAboutScreen> {
  static final Future<AppVersion> _appVersionFuture = AppVersion.current();

  final _sourceCodeFocusNode = FocusNode(debugLabel: 'ForkAboutSourceCode');

  @override
  void dispose() {
    _sourceCodeFocusNode.dispose();
    super.dispose();
  }

  Future<void> _openSourceCode() async {
    final uri = Uri.parse(ForkIdentity.sourceCodeUrl);
    if (!PlatformDetector.isTV() && await openExternalUrl(uri)) return;
    if (!mounted) return;
    await showScopedDialog<void>(context: context, builder: (_) => const _SourceCodeQrDialog());
    // Back from the dialog lands on "Source code" again.
    if (mounted) _sourceCodeFocusNode.requestFocus();
  }

  @override
  Widget build(BuildContext context) {
    final appName = t.app.title;

    return FutureBuilder<AppVersion>(
      future: _appVersionFuture,
      builder: (context, snapshot) {
        final appVersion = snapshot.data?.version;
        return FocusedScrollScaffold(
          title: Text(t.about.title),
          slivers: [
            SliverPadding(
              padding: const EdgeInsets.all(16),
              sliver: SliverList(
                delegate: SliverChildListDelegate([
                  Center(
                    child: Column(
                      children: [
                        const SizedBox(height: 24),
                        Image.asset('assets/plezy.png', width: 80, height: 80),
                        const SizedBox(height: 16),
                        Text(appName, style: Theme.of(context).textTheme.headlineMedium?.copyWith(fontWeight: .bold)),
                        const SizedBox(height: 8),
                        Text(
                          // Blank while loading or when the platform can't report it; the line keeps its height.
                          appVersion == null ? '' : t.about.versionLabel(version: appVersion),
                          style: Theme.of(context).textTheme.bodyMedium?.copyWith(color: tokens(context).textMuted),
                        ),
                        const SizedBox(height: 24),
                        Text(
                          t.about.appDescription,
                          style: Theme.of(context).textTheme.bodyLarge,
                          textAlign: TextAlign.center,
                        ),
                        const SizedBox(height: 12),
                        Text(
                          t.fork.about.basedOn,
                          style: Theme.of(context).textTheme.bodyMedium?.copyWith(color: tokens(context).textMuted),
                          textAlign: TextAlign.center,
                        ),
                      ],
                    ),
                  ),

                  const SizedBox(height: 40),

                  SettingsGroup(
                    margin: EdgeInsets.zero,
                    children: [
                      FocusableListTile(
                        focusNode: _sourceCodeFocusNode,
                        leading: const AppIcon(Symbols.code_rounded, fill: 1),
                        title: Text(t.fork.about.sourceCode),
                        subtitle: Text(ForkIdentity.sourceCodeUrl),
                        trailing: const AppIcon(Symbols.open_in_new_rounded, fill: 1),
                        onTap: _openSourceCode,
                      ),
                      FocusableListTile(
                        leading: const AppIcon(Symbols.gavel_rounded, fill: 1),
                        title: Text(t.fork.about.license),
                        subtitle: Text(ForkIdentity.licenseName),
                        trailing: const AppIcon(Symbols.chevron_right_rounded, fill: 1),
                        onTap: () {
                          Navigator.push(context, MaterialPageRoute(builder: (context) => const LicensesScreen()));
                        },
                      ),
                      FocusableListTile(
                        leading: const AppIcon(Symbols.description_rounded, fill: 1),
                        title: Text(t.about.openSourceLicenses),
                        subtitle: Text(t.about.viewLicensesDescription),
                        trailing: const AppIcon(Symbols.chevron_right_rounded, fill: 1),
                        onTap: () {
                          Navigator.push(context, MaterialPageRoute(builder: (context) => const LicensesScreen()));
                        },
                      ),
                    ],
                  ),

                  const SizedBox(height: 24),
                ]),
              ),
            ),
          ],
        );
      },
    );
  }
}

/// The source code address as a QR code and as plain text.
class _SourceCodeQrDialog extends StatelessWidget {
  const _SourceCodeQrDialog();

  @override
  Widget build(BuildContext context) {
    final screen = MediaQuery.sizeOf(context);
    final qrSize = (screen.height * 0.45).clamp(140.0, 220.0);
    return AlertDialog(
      scrollable: true,
      title: Text(t.fork.about.sourceCode),
      content: Column(
        mainAxisSize: .min,
        children: [
          // Fixed size: the dialog measures its content's intrinsic size, which QrImageView cannot answer.
          SizedBox.square(
            dimension: qrSize,
            child: ClipRRect(
              borderRadius: const BorderRadius.all(Radius.circular(8)),
              child: QrImageView(
                data: ForkIdentity.sourceCodeUrl,
                size: qrSize,
                version: QrVersions.auto,
                backgroundColor: Colors.white,
              ),
            ),
          ),
          const SizedBox(height: 20),
          Text(
            ForkIdentity.sourceCodeUrl,
            style: Theme.of(context).textTheme.titleMedium?.copyWith(fontFamily: 'monospace'),
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: 12),
          Text(t.fork.about.sourceCodeQrHint, textAlign: TextAlign.center),
        ],
      ),
      actions: [
        DialogActionButton(
          autofocus: true,
          onPressed: () => Navigator.of(context).pop(),
          label: t.common.close,
          isPrimary: true,
        ),
      ],
    );
  }
}
