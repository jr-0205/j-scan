/// Librería compartida de J-SCAN: protocolo, servidor, cliente y mDNS.
library;

export 'src/client/jscan_client.dart';
export 'src/discovery/discovered_peer.dart';
export 'src/discovery/dns.dart';
export 'src/discovery/mdns_advertiser.dart';
export 'src/discovery/mdns_browser.dart';
export 'src/network/network_info.dart';
export 'src/protocol/constants.dart';
export 'src/protocol/device_info.dart';
export 'src/protocol/messages.dart';
export 'src/protocol/protocol_exception.dart';
export 'src/server/client_session.dart';
export 'src/server/local_server.dart';
export 'src/server/server_events.dart';
export 'src/util/ids.dart';
