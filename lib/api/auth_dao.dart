import 'package:medsoft_patient/api/base_dao.dart';
import 'package:medsoft_patient/constants.dart';

//Нэвтрэх, бүртгүүлэх DAO
class AuthDAO extends BaseDAO {
  //Бүртгүүлэх
  Future<ApiResponse<Map<String, dynamic>>> register(Map<String, dynamic> body) {
    return post<Map<String, dynamic>>(
      '${Constants.appUrl}/auth/signup',
      body: body,
      config: const RequestConfig(headerType: HeaderType.jsonOnly, excludeToken: true),
    );
  }

  //Нэвтрэх
  Future<ApiResponse<Map<String, dynamic>>> login(Map<String, dynamic> body) {
    return post<Map<String, dynamic>>(
      '${Constants.appUrl}/auth/login',
      body: body,
      config: const RequestConfig(headerType: HeaderType.jsonOnly, excludeToken: true),
    );
  }

  // QR хүлээх
  Future<ApiResponse<Map<String, dynamic>>> waitQR(String token) {
    return get<Map<String, dynamic>>(
      '${Constants.appUrl}/qr/wait?id=$token',
      config: const RequestConfig(headerType: HeaderType.bearerToken),
    );
  }

  // QR баталгаажуулах
  Future<ApiResponse<Map<String, dynamic>>> claimQR(String token) {
    return get<Map<String, dynamic>>(
      '${Constants.appUrl}/qr/claim?id=$token',
      config: const RequestConfig(headerType: HeaderType.bearerToken),
    );
  }

  //Нууц үг сэргээх OTP илгээх
  Future<ApiResponse<Map<String, dynamic>>> sendResetPassOTP(Map<String, dynamic> body) {
    return post<Map<String, dynamic>>(
      '${Constants.appUrl}/auth/otp',
      body: body,
      config: const RequestConfig(headerType: HeaderType.jsonOnly, excludeToken: true),
    );
  }

  //Нууц үг сэргээх
  Future<ApiResponse<Map<String, dynamic>>> resetPassword(Map<String, dynamic> body) {
    return post<Map<String, dynamic>>(
      '${Constants.appUrl}/auth/reset/password',
      body: body,
      config: const RequestConfig(headerType: HeaderType.jsonOnly, excludeToken: true),
    );
  }
}
