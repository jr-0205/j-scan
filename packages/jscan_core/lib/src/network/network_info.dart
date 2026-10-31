import 'dart:io';

/// Devuelve las IPv4 locales útiles para anunciar (sin loopback ni link-local).
///
/// Los adaptadores virtuales (WSL, Hyper-V, Docker, VPN…) se ordenan al final
/// para que la UI muestre primero la IP real de la LAN.
Future<List<String>> localIPv4Addresses({bool includeLoopback = false}) async {
  final interfaces = await NetworkInterface.list(
    type: InternetAddressType.IPv4,
    includeLoopback: includeLoopback,
    includeLinkLocal: false,
  );

  final entries = <_AddressEntry>[];
  for (final interface in interfaces) {
    for (final address in interface.addresses) {
      if (address.type != InternetAddressType.IPv4) continue;
      if (!includeLoopback && address.isLoopback) continue;
      if (address.address.startsWith('169.254.')) continue;
      entries.add(
        _AddressEntry(
          address: address.address,
          interfaceName: interface.name.toLowerCase(),
        ),
      );
    }
  }

  entries.sort((a, b) {
    final interfaceRank = a.interfaceRank.compareTo(b.interfaceRank);
    if (interfaceRank != 0) return interfaceRank;
    final addressRank = _rank(a.address).compareTo(_rank(b.address));
    if (addressRank != 0) return addressRank;
    return a.address.compareTo(b.address);
  });

  final result = <String>[];
  for (final entry in entries) {
    if (!result.contains(entry.address)) {
      result.add(entry.address);
    }
  }
  return result;
}

/// Mejor IPv4 local (la primera de la lista ordenada), o `null` si no hay red.
Future<String?> primaryLocalAddress({bool includeLoopback = false}) async {
  final addresses = await localIPv4Addresses(includeLoopback: includeLoopback);
  return addresses.isEmpty ? null : addresses.first;
}

final class _AddressEntry {
  const _AddressEntry({
    required this.address,
    required this.interfaceName,
  });

  final String address;
  final String interfaceName;

  int get interfaceRank => _virtualTokens.any(interfaceName.contains) ? 1 : 0;
}

const List<String> _virtualTokens = <String>[
  'vethernet',
  'hyper-v',
  'wsl',
  'virtual',
  'vmware',
  'virtualbox',
  'docker',
  'tailscale',
  'zerotier',
  'wireguard',
  'openvpn',
  'tap-',
  'tun',
  'loopback',
  'bluetooth',
];

int _rank(String address) {
  if (address.startsWith('192.168.')) return 0;
  if (address.startsWith('10.')) return 1;
  if (_is172Private(address)) return 2;
  if (address.startsWith('172.')) return 3;
  if (address.startsWith('127.')) return 9;
  return 4;
}

bool _is172Private(String address) {
  final parts = address.split('.');
  if (parts.length < 2 || parts[0] != '172') return false;
  final second = int.tryParse(parts[1]);
  return second != null && second >= 16 && second <= 31;
}
