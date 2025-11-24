import 'package:medsoft_patient/api/base_dao.dart';
import 'package:medsoft_patient/constants.dart';

//Нүүр хуудас DAO
class HomeDAO extends BaseDAO {
  //Нүүр хуудасны товчлуурууд дуудах
  Future<ApiResponse<List<dynamic>>> getHomeButtons() {
    return get<List<dynamic>>(
      '${Constants.appUrl}/home/available',
      config: const RequestConfig(headerType: HeaderType.bearerToken),
    );
  }
}
