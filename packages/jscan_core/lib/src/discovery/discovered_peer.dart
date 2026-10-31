import '../protocol/constants.dart';

/// PC descubierta en la red local.
final class DiscoveredPeer {
  const DiscoveredPeer({
    required this.instanceName,
    required this.id,
    required this.name,
    required this.host,
    required this.address,
    required this.port,
    required this.protocolVersion,
    this.txt = const <String, String>{},
  });

  /// Nombre completo de la instancia DNS-SD.
  final String instanceName;
  final String id;
  final String name;
  final String host;
  final String address;
  final int port;
  final int protocolVersion;
  final Map<String, String> txt;

  String get connectHost => address.isNotEmpty ? address : host;

  bool get isCompatible => protocolVersion == JScanDefaults.protocolVersion;

  String get signature =>
      '$instanceName|$id|$name|$address|$port|$protocolVersion';

  Map<String, Object?> toJson() => <String, Object?>{
        'instance': instanceName,
        'id': id,
        'name': name,
        'host': host,
        'address': address,
        'port': port,
        'protocolVersion': protocolVersion,
        'txt': txt,
      };

  @override
  String toString() => 'DiscoveredPeer($name, $address:$port)';
}
