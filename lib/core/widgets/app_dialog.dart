import 'package:flutter/material.dart';

import 'package:xtremflow/core/theme/app_colors.dart';
import 'package:xtremflow/core/theme/app_theme.dart';
import 'package:xtremflow/core/widgets/tv_focusable.dart';

/// Modals of the app — dialogs, bottom sheets and their buttons — drawn like
/// the rest of the interface: a graphite card with the blue hairline of the
/// glass cards, Figtree type, and on TV the focused button lit like a focused
/// card (#F4F4F2 with dark ink) so the remote always shows where it is.
///
/// Fire TV rule: no blurred shadow, no BackdropFilter — one small gradient.

const _panelRadius = 20.0;
const _buttonRadius = 12.0;

/// Darkens what is behind a modal.
const appBarrierColor = Color(0xB3000000);

BoxDecoration _panel({BorderRadius? radius}) => BoxDecoration(
  gradient: const LinearGradient(
    begin: Alignment.topCenter,
    end: Alignment.bottomCenter,
    colors: [AppColors.cardTop, AppColors.cardBottom],
  ),
  borderRadius: radius ?? BorderRadius.circular(_panelRadius),
  border: Border.all(color: AppColors.cardEdge),
);

/// A themed dialog: title, optional message or content, actions on the right.
class AppDialog extends StatelessWidget {
  const AppDialog({
    super.key,
    required this.title,
    this.message,
    this.content,
    this.actions = const [],
    this.width = 440,
  });

  final String title;
  final String? message;
  final Widget? content;
  final List<Widget> actions;
  final double width;

  @override
  Widget build(BuildContext context) {
    return Dialog(
      backgroundColor: Colors.transparent,
      surfaceTintColor: Colors.transparent,
      elevation: 0,
      insetPadding: const EdgeInsets.symmetric(horizontal: 24, vertical: 24),
      child: ConstrainedBox(
        constraints: BoxConstraints(maxWidth: width),
        child: Container(
          decoration: _panel(),
          padding: const EdgeInsets.fromLTRB(24, 22, 24, 20),
          child: FocusTraversalGroup(
            child: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    title,
                    style: AppTheme.display(
                      fontSize: 21,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  if (message != null) ...[
                    const SizedBox(height: 10),
                    Text(
                      message!,
                      style: AppTheme.body(
                        fontSize: 15,
                        height: 1.4,
                        color: AppColors.textSecondary,
                      ),
                    ),
                  ],
                  if (content != null) ...[
                    const SizedBox(height: 18),
                    content!,
                  ],
                  if (actions.isNotEmpty) ...[
                    const SizedBox(height: 24),
                    Align(
                      alignment: Alignment.centerRight,
                      child: Wrap(
                        alignment: WrapAlignment.end,
                        spacing: 10,
                        runSpacing: 10,
                        children: actions,
                      ),
                    ),
                  ],
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// Button of a modal. At rest: a quiet graphite pill (accent ink when
/// [primary], red ink when [destructive]); focused or hovered: lit.
class AppDialogButton extends StatelessWidget {
  const AppDialogButton({
    super.key,
    required this.label,
    required this.onPressed,
    this.primary = false,
    this.destructive = false,
    this.autofocus = false,
    this.focusNode,
  });

  final String label;
  final VoidCallback? onPressed;
  final bool primary;
  final bool destructive;
  final bool autofocus;
  final FocusNode? focusNode;

  @override
  Widget build(BuildContext context) {
    final enabled = onPressed != null;
    return Opacity(
      opacity: enabled ? 1 : 0.4,
      child: TVFocusable(
        paintsOwnFocus: true,
        autofocus: autofocus,
        focusNode: focusNode,
        scale: 1.04,
        borderRadius: BorderRadius.circular(_buttonRadius),
        onPressed: onPressed,
        child: Builder(
          builder: (context) {
            final lit = enabled && TVFocusable.isFocused(context);
            final Color ink;
            if (lit) {
              ink = destructive
                  ? AppColors.liveOnLight
                  : primary
                  ? AppColors.accentOnLight
                  : AppColors.onFocus;
            } else {
              ink = destructive
                  ? AppColors.live
                  : primary
                  ? AppColors.accent
                  : AppColors.textPrimary;
            }
            return AnimatedContainer(
              duration: AppTheme.durationFocus,
              curve: AppTheme.curveFocus,
              constraints: const BoxConstraints(minWidth: 96, minHeight: 44),
              padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
              decoration: BoxDecoration(
                color: lit
                    ? AppColors.focusTop
                    : primary
                    ? AppColors.accentFill
                    : AppColors.track,
                borderRadius: BorderRadius.circular(_buttonRadius),
              ),
              // Sized to its label, centred when stretched (form sheet).
              child: Center(
                widthFactor: 1,
                heightFactor: 1,
                child: Text(
                  label,
                  maxLines: 1,
                  style: AppTheme.body(
                    fontSize: 15,
                    fontWeight: FontWeight.w600,
                    color: ink,
                  ),
                ),
              ),
            );
          },
        ),
      ),
    );
  }
}

/// Full-width row of a modal (option of a sheet, field of a form): icon,
/// label, optional value under it, lit when focused.
class AppDialogTile extends StatelessWidget {
  const AppDialogTile({
    super.key,
    required this.icon,
    required this.label,
    required this.onPressed,
    this.value,
    this.valueIsPlaceholder = false,
    this.trailing,
    this.destructive = false,
    this.autofocus = false,
  });

  final IconData icon;
  final String label;
  final String? value;
  final bool valueIsPlaceholder;
  final IconData? trailing;
  final bool destructive;
  final bool autofocus;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    return TVFocusable(
      paintsOwnFocus: true,
      autofocus: autofocus,
      scale: 1.02,
      borderRadius: BorderRadius.circular(_buttonRadius),
      onPressed: onPressed,
      child: Builder(
        builder: (context) {
          final lit = TVFocusable.isFocused(context);
          final main = destructive
              ? (lit ? AppColors.liveOnLight : AppColors.live)
              : (lit ? AppColors.onFocus : AppColors.textPrimary);
          final muted = lit ? AppColors.onFocusMuted : AppColors.textMuted;
          return AnimatedContainer(
            duration: AppTheme.durationFocus,
            curve: AppTheme.curveFocus,
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 13),
            decoration: BoxDecoration(
              color: lit ? AppColors.focusTop : AppColors.glassBottom,
              borderRadius: BorderRadius.circular(_buttonRadius),
            ),
            child: Row(
              children: [
                Icon(
                  icon,
                  size: 22,
                  color: destructive
                      ? main
                      : (lit ? AppColors.accentOnLight : AppColors.accent),
                ),
                const SizedBox(width: 14),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(
                        label,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: value == null
                            ? AppTheme.body(
                                fontSize: 16,
                                fontWeight: FontWeight.w500,
                                color: main,
                              )
                            : AppTheme.body(fontSize: 12.5, color: muted),
                      ),
                      if (value != null) ...[
                        const SizedBox(height: 2),
                        Text(
                          value!,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: AppTheme.body(
                            fontSize: 15,
                            fontWeight: FontWeight.w500,
                            color: valueIsPlaceholder ? muted : main,
                          ),
                        ),
                      ],
                    ],
                  ),
                ),
                if (trailing != null) Icon(trailing, size: 18, color: muted),
              ],
            ),
          );
        },
      ),
    );
  }
}

/// Bottom sheet panel: rounded top, handle, safe bottom.
class AppSheet extends StatelessWidget {
  const AppSheet({super.key, required this.child, this.title});

  final String? title;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: _panel(
        radius: const BorderRadius.vertical(top: Radius.circular(_panelRadius)),
      ),
      padding: EdgeInsets.only(
        bottom: MediaQuery.of(context).viewInsets.bottom,
      ),
      child: SafeArea(
        top: false,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(20, 10, 20, 16),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Center(
                child: Container(
                  width: 40,
                  height: 4,
                  decoration: BoxDecoration(
                    color: AppColors.track,
                    borderRadius: BorderRadius.circular(2),
                  ),
                ),
              ),
              if (title != null) ...[
                const SizedBox(height: 18),
                Text(
                  title!,
                  style: AppTheme.display(
                    fontSize: 21,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ],
              const SizedBox(height: 16),
              Flexible(child: child),
            ],
          ),
        ),
      ),
    );
  }
}

/// Shows a themed dialog.
Future<T?> showAppDialog<T>(
  BuildContext context, {
  required WidgetBuilder builder,
  bool barrierDismissible = true,
}) => showDialog<T>(
  context: context,
  barrierColor: appBarrierColor,
  barrierDismissible: barrierDismissible,
  builder: builder,
);

/// Shows a themed bottom sheet ([AppSheet] around the content).
Future<T?> showAppSheet<T>(
  BuildContext context, {
  required WidgetBuilder builder,
  String? title,
  bool isScrollControlled = false,
}) => showModalBottomSheet<T>(
  context: context,
  isScrollControlled: isScrollControlled,
  backgroundColor: Colors.transparent,
  barrierColor: appBarrierColor,
  elevation: 0,
  builder: (context) => AppSheet(title: title, child: builder(context)),
);

/// Yes/no question. Cancel has the focus, so a stray OK does nothing.
Future<bool> showAppConfirm(
  BuildContext context, {
  required String title,
  String? message,
  required String confirmLabel,
  String cancelLabel = 'Annuler',
  bool destructive = false,
}) async {
  final ok = await showAppDialog<bool>(
    context,
    builder: (ctx) => AppDialog(
      title: title,
      message: message,
      actions: [
        AppDialogButton(
          label: cancelLabel,
          autofocus: true,
          onPressed: () => Navigator.of(ctx).pop(false),
        ),
        AppDialogButton(
          label: confirmLabel,
          primary: !destructive,
          destructive: destructive,
          onPressed: () => Navigator.of(ctx).pop(true),
        ),
      ],
    ),
  );
  return ok ?? false;
}

/// One line of text to type (TV keyboard friendly). Null when cancelled.
Future<String?> showAppTextInput(
  BuildContext context, {
  required String title,
  String initialValue = '',
  String? hint,
  bool obscure = false,
  TextInputType keyboardType = TextInputType.text,
  String confirmLabel = 'OK',
}) async {
  final controller = TextEditingController(text: initialValue);
  final result = await showAppDialog<String>(
    context,
    builder: (ctx) => AppDialog(
      title: title,
      content: TextField(
        controller: controller,
        autofocus: true,
        obscureText: obscure,
        keyboardType: keyboardType,
        textInputAction: TextInputAction.done,
        cursorColor: AppColors.accent,
        style: AppTheme.body(fontSize: 16),
        decoration: InputDecoration(
          hintText: hint,
          fillColor: AppColors.rail,
          focusedBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(_buttonRadius),
            borderSide: const BorderSide(color: AppColors.accent),
          ),
        ),
        onSubmitted: (v) => Navigator.of(ctx).pop(v),
      ),
      actions: [
        AppDialogButton(
          label: 'Annuler',
          onPressed: () => Navigator.of(ctx).pop(),
        ),
        AppDialogButton(
          label: confirmLabel,
          primary: true,
          onPressed: () => Navigator.of(ctx).pop(controller.text),
        ),
      ],
    ),
  );
  controller.dispose();
  return result;
}
