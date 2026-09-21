import 'dart:io';

Future<String?> findLanIpv4Address() async {
  final interfaces = await NetworkInterface.list(
    type: InternetAddressType.IPv4,
    includeLoopback: false,
  );

  final candidates =
      interfaces
          .expand(
            (interface) => interface.addresses.map(
              (address) => _AddressCandidate(interface.name, address.address),
            ),
          )
          .where(
            (candidate) =>
                candidate.address.isNotEmpty &&
                !candidate.address.startsWith('169.254.'),
          )
          .toList()
        ..sort((left, right) => right.score.compareTo(left.score));

  return candidates.firstOrNull?.address;
}

bool _isPrivateAddress(String address) {
  if (address.startsWith('10.') || address.startsWith('192.168.')) {
    return true;
  }

  final parts = address.split('.');
  if (parts.length != 4 || parts.first != '172') {
    return false;
  }

  final secondOctet = int.tryParse(parts[1]);
  return secondOctet != null && secondOctet >= 16 && secondOctet <= 31;
}

class _AddressCandidate {
  const _AddressCandidate(this.interfaceName, this.address);

  final String interfaceName;
  final String address;

  int get score {
    final normalizedName = interfaceName.toLowerCase();
    if (normalizedName.contains('wsl') ||
        normalizedName.contains('vethernet') ||
        normalizedName.contains('docker') ||
        normalizedName.contains('virtualbox') ||
        normalizedName.contains('vmware')) {
      return -100;
    }

    // Windows Mobile Hotspot uses 192.168.137.1 by default. Prefer it while
    // active because campus/guest Wi-Fi commonly isolates wireless clients.
    if (address == '192.168.137.1') return 100;
    if (address.startsWith('192.168.')) return 80;
    if (address.startsWith('10.')) return 70;
    if (_isPrivateAddress(address)) return 60;
    return 10;
  }
}
