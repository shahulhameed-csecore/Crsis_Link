import 'package:serverpod/serverpod.dart';
import 'package:serverpod_auth_server/serverpod_auth_server.dart';

class DemoAuthEndpoint extends Endpoint {
  Future<AuthenticationResponse> demoLogin(Session session) async {
    const demoEmail = 'judge@demo.com';
    const demoUserName = 'Judge Demo';
    
    // Check if user exists
    var userInfo = await Users.findUserByEmail(session, demoEmail);
    
    if (userInfo == null) {
      // Create user if they don't exist
      userInfo = await Users.createUser(
        session,
        UserInfo(
          userIdentifier: demoEmail,
          email: demoEmail,
          userName: demoUserName,
          created: DateTime.now().toUtc(),
          scopeNames: [],
          blocked: false,
        ),
        'demo_auth',
      );
    }
    
    if (userInfo == null) {
      return AuthenticationResponse(
        success: false,
        failReason: AuthenticationFailReason.internalError,
      );
    }
    
    // Generate auth key
    final authKey = await UserAuthentication.signInUser(
      session,
      userInfo.id!,
      'demo_auth',
      scopes: userInfo.scopes,
    );
    
    return AuthenticationResponse(
      success: true,
      keyId: authKey.id,
      key: authKey.key,
      userInfo: userInfo,
    );
  }
}
