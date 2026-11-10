import 'package:flutter/material.dart';

import '../../l10n/l10n.dart';
import '../common.dart';
import '../theme.dart';
import '../app_icons.dart';
import '../skin_paint.dart';

const sponsorsPage = 'https://github.com/sponsors/0x696c757a696f';
const _repository = 'https://github.com/0x696c757a696f/lumtub';

/// A crypto address and the networks it takes.
typedef _Address = ({String label, String networks, String address});

const _evm = (label: 'ETH · USDC · USDT', networks: 'Ethereum, Arbitrum, Base, Optimism, Polygon, BNB Chain', address: '0x619FeeF5986b9ed8E75D7CFD67AdB575355b9F80');

const List<_Address> _bitcoin = [
  (label: 'Taproot', networks: 'bc1p…', address: 'bc1p7jf7pzep76cld4pd6xmtfjckpn6qamdqc2rhjus64re2cvuc72sqdwszqc'),
  (label: 'Native SegWit', networks: 'bc1q…', address: 'bc1q4rp3ag5lmnyy8eqwjm9s4xx62uulfr6n43ycvc'),
  (label: 'Nested SegWit', networks: '3…', address: '3Lu1yzQYfNZLpvh2dt6T6NuRbtwQkJHmT6'),
  (label: 'Legacy', networks: '1…', address: '123mpbi91xQitVkh9oosY4VczFqJB9kjDQ'),
];

const List<_Address> _stablecoins = [
  (label: 'USDT', networks: 'Tron (TRC-20)', address: 'TBHXcP2ReM5sqpRDTyrL1UWtcSmYeyrmnB'),
  (label: 'USDT', networks: 'Solana (SPL)', address: '4s6uaauKCgwSNVzb5Lq1kxUe9dpm8V64D6FPw7hTwrQ6'),
];

/// 关于 › 支持开发: GitHub Sponsors first, then crypto and other ways to help.
Future<void> openSupport(BuildContext context) => Navigator.of(context).push(MaterialPageRoute<void>(builder: (context) => const _SupportPage()));

class _SupportPage extends StatelessWidget {
  const _SupportPage();

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    return Scaffold(
      appBar: SkinAppBar(AppBar(title: Text(tr('Support development')))),
      body: Align(
        alignment: Alignment.topCenter,
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 720),
          child: ListView(padding: const EdgeInsets.fromLTRB(16, 8, 16, 40), children: [
            const _Hero(),
            const SizedBox(height: 24),
            _Heading(tr('Cryptocurrency'), AppIcons.currencyBtc),
            Container(
              margin: const EdgeInsets.only(bottom: 12),
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
              decoration: BoxDecoration(color: colors.errorContainer.withValues(alpha: 0.55), borderRadius: BorderRadius.circular(8)),
              child: Row(children: [
                Icon(AppIcons.warning, size: 20, color: colors.onErrorContainer),
                const SizedBox(width: 8),
                Expanded(child: Text(tr('Before sending, check that the coin and network match the address. Funds sent on the wrong chain cannot be recovered.'), style: TextStyle(color: colors.onErrorContainer, height: 1.4))),
              ]),
            ),
            _Group(tr('Ethereum and EVM chains'), const [_evm], note: tr('The same address receives on every EVM chain')),
            _Group(tr('Bitcoin'), _bitcoin, note: tr('Use any of the four, whichever your wallet supports')),
            _Group(tr('Stablecoins'), _stablecoins),
            const SizedBox(height: 16),
            _Heading(tr('Other ways to help'), AppIcons.handHeart),
            _Way(AppIcons.star, tr('Star it on GitHub'), tr('Helps more people find Lumtub'), _repository),
            _Way(AppIcons.bug, tr('Report a bug or suggest an idea'), tr('Diagnostics and the error log help most'), '$_repository/issues'),
            _Way(AppIcons.translate, tr('Help translate'), tr('Translate Lumtub into your language on Weblate'), 'https://hosted.weblate.org/engage/lumtub/'),
          ]),
        ),
      ),
    );
  }
}

class _Hero extends StatelessWidget {
  const _Hero();

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final text = Theme.of(context).textTheme;
    return Container(
      padding: const EdgeInsets.fromLTRB(24, 24, 24, 24),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(8),
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [colors.primaryContainer, colors.tertiaryContainer],
        ),
      ),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(children: [
          Container(
            width: 48,
            height: 48,
            decoration: BoxDecoration(color: const Color(0xFFEA4AAA), borderRadius: BorderRadius.circular(8)),
            child: const Icon(AppIcons.heartFill, color: Colors.white, size: 26),
          ),
          const SizedBox(width: 12),
          Expanded(child: Text(tr('Support Lumtub'), style: text.headlineSmall?.copyWith(fontWeight: FontWeight.w600, color: colors.onPrimaryContainer))),
        ]),
        const SizedBox(height: 16),
        Text(
          tr('Lumtub is free and open source, with no ads and no data collection. Sponsoring keeps it updated: more development time, test devices and a code-signing certificate.'),
          style: text.bodyLarge?.copyWith(color: colors.onPrimaryContainer, height: 1.5),
        ),
        const SizedBox(height: 16),
        Wrap(spacing: 12, runSpacing: 10, crossAxisAlignment: WrapCrossAlignment.center, children: [
          FilledButton.icon(
            style: FilledButton.styleFrom(backgroundColor: const Color(0xFFEA4AAA), foregroundColor: Colors.white, padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12)),
            onPressed: () => openExternal(sponsorsPage),
            icon: Icon(AppIcons.heart, size: 20),
            label: Text(tr('Sponsor on GitHub')),
          ),
          Text(tr('Monthly or one-time, any amount'), style: text.bodyMedium?.copyWith(color: colors.onPrimaryContainer.withValues(alpha: 0.75))),
        ]),
      ]),
    );
  }
}

class _Heading extends StatelessWidget {
  const _Heading(this.text, this.icon);
  final String text;
  final IconData icon;

  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.fromLTRB(4, 0, 4, 12),
        child: Row(children: [
          Icon(icon, size: 20, color: context.colors.primary),
          const SizedBox(width: 8),
          Text(text, style: Theme.of(context).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w600)),
        ]),
      );
}

class _Group extends StatelessWidget {
  const _Group(this.title, this.addresses, {this.note});
  final String title;
  final List<_Address> addresses;
  final String? note;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    return Card(
      margin: const EdgeInsets.only(bottom: 12),
      elevation: 0,
      color: colors.surfaceContainerLow,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8), side: BorderSide(color: colors.outlineVariant)),
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 8),
        child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 4, 16, 2),
            child: Text(title, style: Theme.of(context).textTheme.titleSmall?.copyWith(fontWeight: FontWeight.w600)),
          ),
          if (note != null) Padding(padding: const EdgeInsets.fromLTRB(16, 0, 16, 4), child: Text(note!, style: TextStyle(fontSize: 12, color: colors.outline))),
          for (final address in addresses) _AddressRow(address),
        ]),
      ),
    );
  }
}

class _AddressRow extends StatelessWidget {
  const _AddressRow(this.address);
  final _Address address;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    return InkWell(
      onTap: () => copyText(context, address.address, tr('Address copied')),
      child: Padding(
        padding: const EdgeInsetsDirectional.fromSTEB(16, 8, 8, 8),
        child: Row(children: [
          Expanded(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Wrap(spacing: 8, crossAxisAlignment: WrapCrossAlignment.center, children: [
                Text(address.label, style: const TextStyle(fontWeight: FontWeight.w600)),
                Text(address.networks, style: TextStyle(fontSize: 12, color: colors.outline)),
              ]),
              const SizedBox(height: 4),
              SelectableText(address.address, style: TextStyle(fontFamily: 'Consolas', fontFamilyFallback: const ['monospace'], fontSize: 12, color: colors.onSurfaceVariant)),
            ]),
          ),
          IconButton(tooltip: tr('Copy address'), icon: Icon(AppIcons.copySimple, size: 20), onPressed: () => copyText(context, address.address, tr('Address copied'))),
        ]),
      ),
    );
  }
}

class _Way extends StatelessWidget {
  const _Way(this.icon, this.title, this.subtitle, this.url);
  final IconData icon;
  final String title, subtitle, url;

  @override
  Widget build(BuildContext context) => ListTile(
        contentPadding: const EdgeInsets.symmetric(horizontal: 8),
        leading: Icon(icon, color: context.colors.primary),
        title: Text(title),
        subtitle: Text(subtitle),
        trailing: Icon(AppIcons.arrowSquareOut, size: 18),
        onTap: () => openExternal(url),
      );
}
