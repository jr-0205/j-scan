/// Librería compartida de J-SCAN: protocolo, cifrado, servidor, cliente y mDNS.
library;

export 'src/client/jscan_client.dart';
export 'src/crypto/bytes.dart';
export 'src/crypto/identity.dart';
export 'src/crypto/pairing_code.dart';
export 'src/crypto/secure_channel.dart';
export 'src/discovery/discovered_peer.dart';
export 'src/discovery/dns.dart';
export 'src/discovery/mdns_advertiser.dart';
export 'src/discovery/mdns_browser.dart';
export 'src/files/file_receiver.dart';
export 'src/files/file_transfer.dart';
export 'src/history/history_entry.dart';
export 'src/history/history_repository.dart';
export 'src/network/network_info.dart';
export 'src/pairing/paired_device.dart';
export 'src/pairing/pairing_manager.dart';
export 'src/pairing/repositories.dart';
export 'src/protocol/constants.dart';
export 'src/protocol/device_info.dart';
export 'src/protocol/messages.dart';
export 'src/protocol/protocol_exception.dart';
export 'src/server/client_session.dart';
export 'src/server/local_server.dart';
export 'src/server/server_events.dart';
export 'src/text/text_payload.dart';
export 'src/util/ids.dart';
