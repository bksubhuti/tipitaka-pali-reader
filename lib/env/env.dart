import 'package:envied/envied.dart';

part 'env.g.dart';

@Envied(path: '.env')
abstract class Env {
  @EnviedField(varName: 'FIREBASE_API_KEY', obfuscate: true)
  static final String firebaseApiKey = _Env.firebaseApiKey;

  @EnviedField(varName: 'OPEN_ROUTER_API_KEY', obfuscate: true)
  static final String openRouterApiKey = _Env.openRouterApiKey;

  @EnviedField(varName: 'DEEPSEEK_API_KEY', obfuscate: true)
  static final String deepSeekApiKey = _Env.deepSeekApiKey;
}
