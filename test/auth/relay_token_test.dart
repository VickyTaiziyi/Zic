import 'package:flutter_test/flutter_test.dart';
import 'package:zic/auth/relay_token.dart';

void main() {
  test('accepts a desktop-shaped token response', () {
    const body =
        '{"code":0,"msg":"ok","data":{"token":"aaaaaaaaaaaaaaaaaaaaaA","expires_in":600}}';
    expect(parseRelayTokenResponse(body), 'aaaaaaaaaaaaaaaaaaaaaA');
  });

  test('rejects junk, errors, and wrong alphabet', () {
    expect(parseRelayTokenResponse('not-json'), isNull);
    expect(
      parseRelayTokenResponse('{"code":401,"msg":"no","data":null}'),
      isNull,
    );
    expect(
      parseRelayTokenResponse(
        '{"code":0,"msg":"ok","data":{"token":"too-short"}}',
      ),
      isNull,
    );
    expect(
      parseRelayTokenResponse(
        '{"code":0,"msg":"ok","data":{"token":"aaaaaaaaaaaaaaaaaaaaaB"}}',
      ),
      isNull,
    );
  });
}
