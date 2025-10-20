import 'package:medsoft_patient/api/base_dao.dart';
import 'package:medsoft_patient/constants.dart';

class AuthDAO extends BaseDAO {
  Future<ApiResponse<Map<String, dynamic>>> register(
      Map<String, dynamic> body) {
    return post<Map<String, dynamic>>(
      '${Constants.appUrl}/auth/signup',
      body: body,
      config: const RequestConfig(headerType: HeaderType.jsonOnly, excludeToken: true),
    );
  }

  Future<ApiResponse<Map<String, dynamic>>> login(
      Map<String, dynamic> body) {
    return post<Map<String, dynamic>>(
      '${Constants.appUrl}/auth/login',
      body: body,
      config: const RequestConfig(headerType: HeaderType.jsonOnly, excludeToken: true),
    );
  }

  Future<ApiResponse<Map<String, dynamic>>> waitQR(String token) {
    return get<Map<String, dynamic>>(
      '${Constants.appUrl}/qr/wait?id=$token',
      config: const RequestConfig(headerType: HeaderType.bearerToken),
    );
  }
}