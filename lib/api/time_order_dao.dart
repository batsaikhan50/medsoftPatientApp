import 'package:medsoft_patient/api/base_dao.dart';
import 'package:medsoft_patient/constants.dart';

//Цаг авах үйлдлийн DAO
class TimeOrderDAO extends BaseDAO {
  //Бүх эмнэлгүүдийг дуудах
  Future<ApiResponse<List<dynamic>>> getAllHospitals() {
    return get<List<dynamic>>(
      '${Constants.appUrl}/order/hospitals',
      config: const RequestConfig(headerType: HeaderType.bearerToken),
    );
  }

  //Сонгосон эмнэлгийн салбаруудыг дуудах
  Future<ApiResponse<List<dynamic>>> getBranches(String tenant) {
    return get<List<dynamic>>(
      '${Constants.appUrl}/order/branch?tenant=$tenant',
      config: const RequestConfig(headerType: HeaderType.bearerToken),
    );
  }

  //Сонгосон салбарын тасгуудыг дуудах
  Future<ApiResponse<List<dynamic>>> getTasags(String tenant, String branchId) {
    return get<List<dynamic>>(
      '${Constants.appUrl}/order/tasag?tenant=$tenant&branchId=$branchId',
      config: const RequestConfig(headerType: HeaderType.bearerToken),
    );
  }

  //Сонгосон тасгийн эмч нарын жагсаалтыг дуудах
  Future<ApiResponse<List<dynamic>>> getDoctors(String tenant, String branchId, String tasagId) {
    return get<List<dynamic>>(
      '${Constants.appUrl}/order/employee?tenant=$tenant&branchId=$branchId&tasagId=$tasagId',
      config: const RequestConfig(headerType: HeaderType.bearerToken),
    );
  }

  //Сонгосон эмчийн цагийн үзэх боломжтой цагыг дуудах
  Future<ApiResponse<List<dynamic>>> getTimes(Map<String, dynamic> body) {
    return post<List<dynamic>>(
      '${Constants.appUrl}/order/times',
      body: body,
      config: const RequestConfig(headerType: HeaderType.bearerAndJson),
    );
  }

  //Сонгосон цагыг баталгаажуулах
  Future<ApiResponse<List<dynamic>>> confirmOrder(Map<String, dynamic> body) {
    return post<List<dynamic>>(
      '${Constants.appUrl}/order/confirm',
      body: body,
      config: const RequestConfig(headerType: HeaderType.bearerAndJson),
    );
  }
}
