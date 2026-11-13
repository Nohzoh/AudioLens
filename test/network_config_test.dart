import 'package:flutter_test/flutter_test.dart';
import 'package:audiolens/services/network_config.dart';

// #554
void main() {
  test('User-Agent names the app, its version and a contact', () {
    NetworkConfig.setAppVersion('');
    expect(NetworkConfig.userAgent, 'AudioLens (+https://github.com/Nohzoh/AudioLens)');
    NetworkConfig.setAppVersion('0.15.13');
    expect(NetworkConfig.userAgent, 'AudioLens/0.15.13 (+https://github.com/Nohzoh/AudioLens)');
    NetworkConfig.setAppVersion('');
  });
}
