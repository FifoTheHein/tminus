/// One phone maker's advice for keeping T-Minus's alarms on time (spec §9).
/// Several makers stop background apps harder than stock Android does.
class MakerTip {
  const MakerTip({required this.maker, required this.tip});

  /// The maker as the tip names it: `Samsung`, `Other phones`.
  final String maker;
  final String tip;
}

const _samsung = MakerTip(
  maker: 'Samsung',
  tip:
      'Settings → Battery → Background usage limits → Never sleeping apps → '
      'add T-Minus.',
);

const _xiaomi = MakerTip(
  maker: 'Xiaomi',
  tip:
      'Settings → Apps → T-Minus: turn Autostart on, and set Battery saver to '
      'No restrictions.',
);

const _oneplus = MakerTip(
  maker: 'OnePlus / OPPO / realme',
  tip: "Settings → Battery → T-Minus: Don't optimise, and allow Auto-launch.",
);

const _huawei = MakerTip(
  maker: 'Huawei / Honor',
  tip:
      'Settings → Battery → App launch → T-Minus → Manage manually, with '
      'every switch on.',
);

const _other = MakerTip(
  maker: 'Other phones',
  tip: 'Settings → Apps → T-Minus → Battery → Unrestricted.',
);

/// Every tip, in the order the rest follow the device's own.
const _all = [_samsung, _xiaomi, _oneplus, _huawei, _other];

/// What `Build.MANUFACTURER` reads on each maker's phones, lower case.
const _byManufacturer = {
  'samsung': _samsung,
  'xiaomi': _xiaomi,
  'redmi': _xiaomi,
  'poco': _xiaomi,
  'oneplus': _oneplus,
  'oppo': _oneplus,
  'realme': _oneplus,
  'huawei': _huawei,
  'honor': _huawei,
};

MakerTip? _tipFor(String? manufacturer) =>
    manufacturer == null ? null : _byManufacturer[_key(manufacturer)];

String _key(String manufacturer) => manufacturer.trim().toLowerCase();

/// Every tip, with the one for [manufacturer] first and the rest after it.
/// A maker this list does not know gets the general tip first.
List<MakerTip> makerTips(String manufacturer) {
  final own = _tipFor(manufacturer) ?? _other;
  return [
    own,
    for (final tip in _all)
      if (!identical(tip, own)) tip,
  ];
}

/// The tile's title: `Samsung tips`, or `Phone-maker tips` while the maker is
/// not known (the phone could not be read, or is not on the list).
String makerTipsTitle(String? manufacturer) {
  final own = _tipFor(manufacturer);
  return own == null ? 'Phone-maker tips' : '${own.maker} tips';
}
