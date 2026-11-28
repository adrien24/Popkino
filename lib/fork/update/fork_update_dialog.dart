// FORK: bouton-mise-a-jour — the update window (notes, download, permission, install).
import 'package:flutter/material.dart';

import '../../i18n/strings.g.dart';
import '../../services/update_service.dart';
import '../../utils/app_version.dart';
import '../../utils/dialogs.dart';
import '../../widgets/dialog_action_button.dart';
import 'apk_downloader.dart';
import 'fork_release.dart';
import 'fork_update_controller.dart';
import 'fork_update_session.dart';
import 'sideload_flags.dart';
import 'sideload_installer.dart';
import 'update_files.dart';

bool _dialogOpen = false;

/// Test-only session factory (fake installer and downloader).
@visibleForTesting
ForkUpdateSession Function({ForkRelease? release, ForkPendingInstall? pending})? debugSessionFactory;

/// Test-only: forgets a window left open by a finished test.
@visibleForTesting
void debugResetForkUpdateDialogGuard() => _dialogOpen = false;

/// Opens the update window for a [release] (notes first) or for a [pending] install
/// left by a previous run. Does nothing if a window is already open.
Future<void> showForkUpdateDialog(
  BuildContext context, {
  ForkRelease? release,
  ForkPendingInstall? pending,
  bool showSkipVersion = false,
}) async {
  if (!ForkSideload.isSupported) return;
  if (_dialogOpen) return;
  _dialogOpen = true;
  ForkUpdateSession? session;
  try {
    final factory = debugSessionFactory;
    session = factory != null
        ? factory(release: release, pending: pending)
        : ForkUpdateSession(
            release: release,
            pending: pending,
            controller: ForkUpdateController.instance,
            installer: MethodChannelSideloadInstaller(),
            files: ForkUpdateFiles(),
            downloader: ForkApkDownloader(),
          );
    final owned = session;
    await showScopedDialog<void>(
      context: context,
      builder: (_) => _ForkUpdateDialog(session: owned, showSkipVersion: showSkipVersion),
    );
  } finally {
    session?.dispose();
    _dialogOpen = false;
  }
}

class _ForkUpdateDialog extends StatefulWidget {
  const _ForkUpdateDialog({required this.session, required this.showSkipVersion});

  final ForkUpdateSession session;
  final bool showSkipVersion;

  @override
  State<_ForkUpdateDialog> createState() => _ForkUpdateDialogState();
}

class _ForkUpdateDialogState extends State<_ForkUpdateDialog> {
  final ScrollController _notesScroll = ScrollController();
  late final Future<AppVersion> _installed = AppVersion.current();
  bool _closing = false;

  ForkUpdateSession get _session => widget.session;

  @override
  void initState() {
    super.initState();
    _session.addListener(_onSession);
  }

  @override
  void dispose() {
    _session.removeListener(_onSession);
    _notesScroll.dispose();
    super.dispose();
  }

  void _onSession() {
    if (_session.phase is ForkUpdateDone) _close();
  }

  void _close() {
    if (_closing || !mounted) return;
    _closing = true;
    Navigator.of(context).pop();
  }

  void _scrollNotes(double direction) {
    if (!_notesScroll.hasClients) return;
    final position = _notesScroll.position;
    final target = (position.pixels + direction * position.viewportDimension * 0.8).clamp(
      position.minScrollExtent,
      position.maxScrollExtent,
    );
    _notesScroll.animateTo(target, duration: const Duration(milliseconds: 150), curve: Curves.easeOut);
  }

  String? _settingsPath(InstallSettingsTarget? target) {
    switch (target) {
      case null:
      case InstallSettingsTarget.appPermission:
        return null;
      case InstallSettingsTarget.unknownAppsList:
        return t.fork.update.permissionPathUnknownApps;
      case InstallSettingsTarget.developerOptions:
        return t.fork.update.permissionPathDeveloper;
      case InstallSettingsTarget.security:
      case InstallSettingsTarget.settings:
      case InstallSettingsTarget.none:
        return t.fork.update.permissionPathGeneric;
    }
  }

  @override
  Widget build(BuildContext context) {
    return PopScope(
      canPop: true,
      onPopInvokedWithResult: (didPop, _) {
        if (didPop) _session.cancel();
      },
      child: ListenableBuilder(listenable: _session, builder: (context, _) => _buildDialog(context)),
    );
  }

  Widget _buildDialog(BuildContext context) {
    final phase = _session.phase;
    final theme = Theme.of(context);

    DialogActionButton cancel(String key, {String? label, bool primary = true}) => DialogActionButton(
      key: ValueKey('$key-cancel'),
      onPressed: () => Navigator.of(context).pop(),
      label: label ?? t.common.cancel,
      autofocus: primary,
      isPrimary: primary,
    );

    final List<Widget> content;
    final List<Widget> actions;
    switch (phase) {
      case ForkUpdateDetails():
        final release = _session.release;
        final height = MediaQuery.sizeOf(context).height;
        void up() => _scrollNotes(-1);
        void down() => _scrollNotes(1);
        content = [
          Text(t.update.versionAvailable(version: release.version), style: theme.textTheme.titleMedium),
          FutureBuilder<AppVersion>(
            future: _installed,
            builder: (context, snapshot) {
              final version = snapshot.data?.version;
              if (version == null) return const SizedBox.shrink();
              return Padding(
                padding: const EdgeInsets.only(top: 4),
                child: Text(t.fork.update.installedVersion(version: version), style: theme.textTheme.bodySmall),
              );
            },
          ),
          if (release.notes.isNotEmpty) ...[
            const SizedBox(height: 12),
            ConstrainedBox(
              constraints: BoxConstraints(maxHeight: height * 0.5),
              child: Scrollbar(
                controller: _notesScroll,
                child: SingleChildScrollView(
                  controller: _notesScroll,
                  child: Text(release.notes, style: theme.textTheme.bodyLarge),
                ),
              ),
            ),
          ],
        ];
        actions = [
          DialogActionButton(
            key: const ValueKey('details-later'),
            onPressed: () => Navigator.of(context).pop(),
            label: t.common.later,
            onNavigateUp: up,
            onNavigateDown: down,
          ),
          if (widget.showSkipVersion)
            DialogActionButton(
              key: const ValueKey('details-skip'),
              onPressed: () async {
                await UpdateService.skipVersion(release.version);
                _close();
              },
              label: t.update.skipVersion,
              onNavigateUp: up,
              onNavigateDown: down,
            ),
          DialogActionButton(
            key: const ValueKey('details-download'),
            onPressed: _session.startDownload,
            label: t.fork.update.downloadAndInstall,
            autofocus: true,
            isPrimary: true,
            onNavigateUp: up,
            onNavigateDown: down,
          ),
        ];
      case ForkUpdateDownloading(:final fraction):
        content = [
          LinearProgressIndicator(value: fraction),
          const SizedBox(height: 12),
          Text(t.fork.update.progress(percent: (fraction * 100).round()), style: theme.textTheme.bodyLarge),
        ];
        actions = [cancel('downloading')];
      case ForkUpdateVerifying():
        content = [
          const LinearProgressIndicator(),
          const SizedBox(height: 12),
          Text(t.fork.update.verifying, style: theme.textTheme.bodyLarge),
        ];
        actions = [cancel('verifying')];
      case ForkUpdateNeedsPermission(:final lastTarget):
        content = _messageWithPath(theme, t.fork.update.permissionExplanation, _settingsPath(lastTarget));
        actions = [
          cancel('permission', primary: false),
          DialogActionButton(
            key: const ValueKey('permission-settings'),
            onPressed: _session.openSettings,
            label: t.fork.update.openSettings,
            autofocus: true,
            isPrimary: true,
          ),
        ];
      case ForkUpdatePermissionDenied(:final lastTarget):
        content = _messageWithPath(theme, t.fork.update.permissionDenied, _settingsPath(lastTarget));
        actions = [_close_('denied'), _retry('denied')];
      case ForkUpdateReadyToInstall():
        content = [
          Text(t.fork.update.readyToInstall(version: _session.release.version), style: theme.textTheme.bodyLarge),
        ];
        actions = [
          cancel('ready', label: t.common.later, primary: false),
          DialogActionButton(
            key: const ValueKey('ready-install'),
            onPressed: _session.install,
            label: t.fork.update.install,
            autofocus: true,
            isPrimary: true,
          ),
        ];
      case ForkUpdateInstalling():
        content = [Text(t.fork.update.installing, style: theme.textTheme.bodyLarge)];
        actions = [cancel('installing')];
      case ForkUpdateFailed(:final kind):
        switch (kind) {
          case ForkUpdateFailure.network:
            content = [Text(t.fork.update.downloadFailed, style: theme.textTheme.bodyLarge)];
            actions = [_close_('failed'), _retry('failed')];
          case ForkUpdateFailure.storage:
            content = [Text(t.fork.update.notEnoughSpace, style: theme.textTheme.bodyLarge)];
            actions = [_close_('failed'), _retry('failed')];
          case ForkUpdateFailure.signature:
            content = [Text(t.fork.update.signatureConflict, style: theme.textTheme.bodyLarge)];
            actions = [_close_('failed', primary: true)];
          case ForkUpdateFailure.other:
            content = [Text(t.fork.update.installFailed, style: theme.textTheme.bodyLarge)];
            actions = [_close_('failed', primary: true)];
        }
      case ForkUpdateDone():
        // Closes itself (see _onSession); render nothing meaningful meanwhile.
        content = const [];
        actions = const [];
    }

    return AlertDialog(
      title: Text(t.update.available),
      content: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: content),
      actions: actions,
    );
  }

  List<Widget> _messageWithPath(ThemeData theme, String message, String? path) => [
    Text(message, style: theme.textTheme.bodyLarge),
    if (path != null) ...[
      const SizedBox(height: 12),
      Text(path, style: theme.textTheme.bodyMedium?.copyWith(fontWeight: FontWeight.w600)),
    ],
  ];

  Widget _close_(String key, {bool primary = false}) => DialogActionButton(
    key: ValueKey('$key-close'),
    onPressed: () => Navigator.of(context).pop(),
    label: t.common.close,
    autofocus: primary,
    isPrimary: primary,
  );

  Widget _retry(String key) => DialogActionButton(
    key: ValueKey('$key-retry'),
    onPressed: _session.retry,
    label: t.common.retry,
    autofocus: true,
    isPrimary: true,
  );
}
