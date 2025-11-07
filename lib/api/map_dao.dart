import 'package:medsoft_patient/api/base_dao.dart';
import 'package:medsoft_patient/constants.dart';

//Байршил солилцох үйлдлийн DAO
class MapDAO extends BaseDAO {
  //Үйлдийг дуусгах хүсэлтийг шалгах
  Future<ApiResponse<Map<String, dynamic>>> checkDoneRequest() {
    return get<Map<String, dynamic>>(
      '${Constants.appUrl}/room/done_request',
      config: const RequestConfig(headerType: HeaderType.bearerToken),
    );
  }

  //Үйлдлийг дуусгах
  Future<ApiResponse<Map<String, dynamic>>> acceptDoneRequest(Map<String, dynamic> body) {
    return post<Map<String, dynamic>>(
      '${Constants.appUrl}/room/done',
      body: body,
      config: const RequestConfig(headerType: HeaderType.bearerAndJsonAndXtokenAndTenant),
    );
  }

  //Өрөөний мэдээлэл авах
  Future<ApiResponse<Map<String, dynamic>>> getRoomInfo() {
    return get<Map<String, dynamic>>(
      '${Constants.appUrl}/room/get/patient',
      config: const RequestConfig(headerType: HeaderType.bearerToken),
    );
  }
}
