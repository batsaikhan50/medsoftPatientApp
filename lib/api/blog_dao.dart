import 'package:medsoft_patient/api/base_dao.dart';
import 'package:medsoft_patient/constants.dart';

//Нийтлэл дуудах DAO
class BlogDAO extends BaseDAO {
  //Түргэн тусмалжийн жагсаалт дуудах
  Future<ApiResponse<List<dynamic>>> getAllNews() {
    return get<List<dynamic>>(
      '${Constants.runnerUrl}/blog/all/unauthorized/list',
      config: const RequestConfig(excludeToken: false),
    );
  }

  //Түргэн тусмалжийн жагсаалт дуудах
  Future<ApiResponse<dynamic>> getNewsDetail(String id) {
    return get<dynamic>(
      '${Constants.runnerUrl}/blog/all/unauthorized?blogId=$id',
      config: const RequestConfig(excludeToken: false),
    );
  }
}
