// app/lib/features/profile/donate_sheet.dart
//
// 打赏弹层：金额 + 支付宝 / 微信两个入口。
//
// 两个平台的能力不一样，文案必须如实写：
//   · 支付宝的收款码内容是一串 `https://qr.alipay.com/...`，可以经
//     `alipays://` scheme 直接唤起收款页；
//   · 微信个人收款（`wxp://...`）没有公开的「唤起付款页」接口，只能展示二维码，
//     让用户截图后用「扫一扫 → 相册」识别，或让另一台设备扫。
//
// 因此这里没有「一键付款」的统一承诺：支付宝是一键，微信是扫码。收款码图片本身
// 不参与唤起，只做展示；`alipayQrContent` 是从图片里解出来的收款链接，**不要**
// 把账户、手机号之类的信息写进代码。
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../core/design_tokens.dart';
import '../../core/glass/glass.dart';
import '../../core/l10n.dart';
import '../../core/widgets/glass_action_button.dart';
import '../../core/widgets/glass_dialog.dart';
import '../../core/widgets/glass_field.dart';
import '../../core/widgets/glass_input.dart';
import '../../core/widgets/glass_segment.dart';
import '../../core/widgets/glass_sheet_header.dart';
import '../../core/widgets/glass_snackbar.dart';
import '../alarm/alarm_service.dart';

/// 支付宝收款码里的链接（从用户提供的 `assets/donate/alipay.png` 解出）。
/// 只用于 `alipays://` 唤起，不在界面上展示。
const String alipayQrContent = 'https://qr.alipay.com/fkx19195ffwze9uwenx5maa';

/// 默认金额。自定义档的值不进这个列表。
const List<int> donatePresetAmounts = [5, 10, 20];

/// 打开打赏弹层。入口在「我的 → 支持」。
void showDonateSheet(BuildContext context) {
  showGlassSheet<void>(
    context: context,
    builder: (_) => const GlassPanel(
      solid: true,
      margin: EdgeInsets.all(AppTokens.spaceMd),
      child: SafeArea(top: false, child: DonateSheet()),
    ),
  );
}

enum DonatePayKind {
  alipay('assets/donate/alipay.png'),
  wechat('assets/donate/wechat.png');

  const DonatePayKind(this.asset);

  final String asset;
}

class DonateSheet extends StatefulWidget {
  const DonateSheet({super.key});

  @override
  State<DonateSheet> createState() => _DonateSheetState();
}

class _DonateSheetState extends State<DonateSheet> {
  int _amount = donatePresetAmounts.first;
  bool _custom = false;

  /// 上一次唤起支付宝失败了。失败的二维码弹窗里不再放「打开支付宝」，
  /// 否则用户每点一次就又走一遍同样的失败路径、叠一层弹窗。
  bool _alipayFailed = false;

  int get _selectedIndex => _custom
      ? donatePresetAmounts.length
      : donatePresetAmounts.indexOf(_amount);

  void _onAmountSelected(int i) {
    if (i < donatePresetAmounts.length) {
      setState(() {
        _custom = false;
        _amount = donatePresetAmounts[i];
      });
      return;
    }
    _pickCustomAmount();
  }

  Future<void> _pickCustomAmount() async {
    final picked = await showGlassDialog<int>(
      context: context,
      builder: (_) => _CustomAmountDialog(initial: _amount),
    );
    if (picked == null || !mounted) return;
    setState(() {
      _custom = true;
      _amount = picked;
    });
  }

  String get _alipayDeepLink =>
      'alipays://platformapi/startapp?saId=10000007&qrcode=${Uri.encodeComponent(alipayQrContent)}';

  Future<void> _payAlipay() async {
    final ok = await AlarmService.openUrl(_alipayDeepLink);
    if (!mounted) return;
    _alipayFailed = !ok;
    if (!ok) {
      showGlassSnack(context, L10n.donateOpenFailed, icon: Icons.error_outline);
      _showQr(DonatePayKind.alipay);
    }
  }

  void _payWechat() => _showQr(DonatePayKind.wechat);

  void _showQr(DonatePayKind kind) {
    showGlassDialog<void>(
      context: context,
      builder: (dialogContext) => DonateQrDialog(
        kind: kind,
        amount: _amount,
        // 支付宝唤起失败时，这里**不再**放「打开支付宝」：那条路刚刚才失败，
        // 再点一次只会再失败、再叠一层弹窗。用户想重试，回上一页再点一次
        // 支付宝按钮即可（那次会重新试）。
        onOpenAlipay: kind == DonatePayKind.alipay && !_alipayFailed
            ? () {
                Navigator.pop(dialogContext);
                _payAlipay();
              }
            : null,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final muted = AppTokens.inkMuted(context);
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        GlassSheetHeader(title: L10n.donateTitle),
        Flexible(
          child: SingleChildScrollView(
            padding: const EdgeInsets.fromLTRB(AppTokens.spaceLg,
                AppTokens.spaceLg, AppTokens.spaceLg, AppTokens.spaceLg),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  L10n.donateIntro,
                  style: AppTokens.rowSecondary
                      .copyWith(height: 1.45, color: muted),
                ),
                const SizedBox(height: AppTokens.spaceLg),
                Text(L10n.donateAmount, style: AppTokens.labelStrong),
                const SizedBox(height: AppTokens.spaceSm),
                GlassSegment(
                  count: donatePresetAmounts.length + 1,
                  selectedIndex: _selectedIndex,
                  onSelected: _onAmountSelected,
                  itemBuilder: (i, selected) => FittedBox(
                    fit: BoxFit.scaleDown,
                    child: Text(
                      i < donatePresetAmounts.length
                          ? L10n.donateAmountLabel(donatePresetAmounts[i])
                          : L10n.donateCustom,
                      style: AppTokens.labelSecondary.copyWith(
                        fontWeight: selected ? FontWeight.w700 : FontWeight.w500,
                      ),
                    ),
                  ),
                ),
                const SizedBox(height: AppTokens.spaceLg),
                Row(
                  children: [
                    Expanded(
                      child: GlassActionButton(
                        variant: GlassActionVariant.primary,
                        onPressed: _payAlipay,
                        label: L10n.donateAlipay,
                      ),
                    ),
                    const SizedBox(width: AppTokens.spaceSm),
                    Expanded(
                      child: GlassActionButton(
                        onPressed: _payWechat,
                        label: L10n.donateWechat,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: AppTokens.spaceMd),
                Text(
                  L10n.donateAlipayHint,
                  style: AppTokens.microText.copyWith(color: muted),
                ),
                const SizedBox(height: AppTokens.spaceXs),
                Text(
                  L10n.donateWechatHint,
                  style: AppTokens.microText.copyWith(color: muted),
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }
}

/// 二维码弹窗：白底卡片 + 当前金额 + 下一步说明。抽成公开件是给视觉工装用的
/// （弹层里的弹窗没法直接从屏单渲染），同时让 DonateSheet 只负责金额与入口。
class DonateQrDialog extends StatelessWidget {
  const DonateQrDialog({
    super.key,
    required this.kind,
    required this.amount,
    this.onOpenAlipay,
  });

  final DonatePayKind kind;
  final int amount;

  /// 非空时显示「打开支付宝」动作（只有支付宝且这次没失败才传）。
  final VoidCallback? onOpenAlipay;

  @override
  Widget build(BuildContext context) {
    return GlassDialog(
      title: L10n.donateScanTitle,
      showClose: true,
      content: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            padding: const EdgeInsets.all(AppTokens.spaceMd),
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(AppTokens.radiusL),
            ),
            child: SizedBox(
              width: AppTokens.iconLg * 10,
              height: AppTokens.iconLg * 10,
              child: Image.asset(
                kind.asset,
                fit: BoxFit.contain,
                errorBuilder: (_, __, ___) => const _MissingQr(),
              ),
            ),
          ),
          const SizedBox(height: AppTokens.spaceMd),
          Text(L10n.donateAmountHint(amount), style: AppTokens.labelStrong),
          const SizedBox(height: AppTokens.spaceXs),
          Text(
            kind == DonatePayKind.alipay
                ? L10n.donateScanAlipay
                : L10n.donateScanWechat,
            textAlign: TextAlign.center,
            style: AppTokens.rowSecondary
                .copyWith(height: 1.45, color: AppTokens.inkMuted(context)),
          ),
        ],
      ),
      actions: [
        if (onOpenAlipay != null)
          GlassActionButton(
            variant: GlassActionVariant.primary,
            onPressed: onOpenAlipay,
            label: L10n.donateOpenAlipay,
          ),
      ],
    );
  }
}

class _MissingQr extends StatelessWidget {
  const _MissingQr();

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.all(AppTokens.spaceXl),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Icon(Icons.qr_code_2_outlined,
              size: AppTokens.iconLg * 2, color: Colors.black87),
          const SizedBox(height: AppTokens.spaceSm),
          Text(
            L10n.donateQrMissing,
            style: AppTokens.labelSecondary.copyWith(color: Colors.black87),
          ),
        ],
      ),
    );
  }
}

/// 自定义金额：数字键盘 + 1–2000 的整数校验。非法值留在弹窗里提示，不关窗。
class _CustomAmountDialog extends StatefulWidget {
  const _CustomAmountDialog({required this.initial});

  final int initial;

  @override
  State<_CustomAmountDialog> createState() => _CustomAmountDialogState();
}

class _CustomAmountDialogState extends State<_CustomAmountDialog> {
  late final TextEditingController _controller =
      TextEditingController(text: widget.initial.toString());
  String? _error;

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  void _submit() {
    final v = int.tryParse(_controller.text.trim());
    if (v == null || v < 1 || v > 2000) {
      setState(() => _error = L10n.donateCustomInvalid);
      return;
    }
    Navigator.pop(context, v);
  }

  @override
  Widget build(BuildContext context) {
    return GlassDialog(
      title: L10n.donateCustomTitle,
      content: SizedBox(
        width: double.maxFinite,
        child: GlassField(
          label: L10n.donateAmount,
          child: TextField(
            controller: _controller,
            autofocus: true,
            keyboardType: TextInputType.number,
            textInputAction: TextInputAction.done,
            inputFormatters: [
              FilteringTextInputFormatter.digitsOnly,
              LengthLimitingTextInputFormatter(4),
            ],
            onSubmitted: (_) => _submit(),
            decoration: glassInputDecoration(context).copyWith(
              hintText: L10n.donateCustomHint,
              errorText: _error,
            ),
          ),
        ),
      ),
      actions: [
        GlassActionButton(
          onPressed: () => Navigator.pop(context),
          label: L10n.cancel,
        ),
        const SizedBox(width: AppTokens.spaceSm),
        GlassActionButton(
          variant: GlassActionVariant.primary,
          onPressed: _submit,
          label: L10n.confirm,
        ),
      ],
    );
  }
}
