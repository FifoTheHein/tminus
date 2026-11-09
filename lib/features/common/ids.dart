import 'dart:math';

/// `p-0a1b2c3d4e5f`: a prefix and 6 random bytes as hex. [random] is for
/// tests; without it the id comes from a secure source.
String newId(String prefix, [Random? random]) {
  final r = random ?? Random.secure();
  final hex = [
    for (var i = 0; i < 6; i++)
      r.nextInt(256).toRadixString(16).padLeft(2, '0'),
  ].join();
  return '$prefix-$hex';
}
