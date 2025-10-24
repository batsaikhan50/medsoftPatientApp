import 'package:medsoft_patient/api/base_dao.dart';
import 'package:medsoft_patient/constants.dart';

//Цаг авах үйлдлийн DAO
class TimeOrderDAO extends BaseDAO {
  //Бүх эмнэлгүүдийг дуудах
  Future<ApiResponse<List<dynamic>>> getAllHospitals() {
    return get<List<dynamic>>(
      '${Constants.appUrl}/order/hospitals',
      config: const RequestConfig(headerType: HeaderType.bearerToken),
      // transform:
      //     (json) => (json['data'] as List).map((item) => item as Map<String, dynamic>).toList(),
    );
  }

  //Сонгосон эмнэлгийн салбаруудыг дуудах
  Future<ApiResponse<List<dynamic>>> getBranches(String tenant) {
    return get<List<dynamic>>(
      '${Constants.appUrl}/order/branch?tenant=$tenant',
      config: const RequestConfig(headerType: HeaderType.bearerToken),
      // transform:
      //     (json) => (json['data'] as List).map((item) => item as Map<String, dynamic>).toList(),
    );
  }

  //Сонгосон салбарын тасгуудыг дуудах
  Future<ApiResponse<List<dynamic>>> getTasags(String tenant, String branchId) {
    return get<List<dynamic>>(
      '${Constants.appUrl}/order/tasag?tenant=$tenant&branchId=$branchId',
      config: const RequestConfig(headerType: HeaderType.bearerToken),
      // transform:
      //     (json) => (json['data'] as List).map((item) => item as Map<String, dynamic>).toList(),
    );
  }

  //Сонгосон тасгийн эмч нарын жагсаалтыг дуудах
  Future<ApiResponse<List<dynamic>>> getDoctors(
    String tenant,
    String branchId,
    String tasagId,
  ) {
    return get<List<dynamic>>(
      '${Constants.appUrl}/order/employee?tenant=$tenant&branchId=$branchId&tasagId=$tasagId',
      config: const RequestConfig(headerType: HeaderType.bearerToken),
      // transform:
      //     (json) => (json['data'] as List).map((item) => item as Map<String, dynamic>).toList(),
    );
  }

  //Сонгосон эмчийн цагийн үзэх боломжтой цагыг дуудах
  Future<ApiResponse<List<dynamic>>> getTimes(Map<String, dynamic> body) {
    return post<List<dynamic>>(
      '${Constants.appUrl}/order/times',
      body: body,
      config: const RequestConfig(headerType: HeaderType.bearerAndJson),
      // transform:
      //     (json) => (json['data'] as List).map((item) => item as Map<String, dynamic>).toList(),
    );
  }
}
