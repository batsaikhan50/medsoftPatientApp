import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:medsoft_patient/api/base_dao.dart';
import 'package:medsoft_patient/constants.dart';

//Түүхийн DAO
class HistoryDAO extends BaseDAO {
  //Дуудах боломжтой тайлангууд аваа
  Future<ApiResponse<List<dynamic>>> getHistoryTenants() {
    return get<List<dynamic>>(
      '${Constants.appUrl}/history/tenants',
      config: const RequestConfig(headerType: HeaderType.bearerToken),
    );
  }

  //Эмнэлгүүд авах
  Future<ApiResponse<List<dynamic>>> getHistoryAvailable() {
    return get<List<dynamic>>(
      '${Constants.appUrl}/history/available',
      config: const RequestConfig(headerType: HeaderType.bearerToken),
    );
  }

  //Тайлан дуудах
  Future<ApiResponse<List<dynamic>>> getHistory(String year, String key, String tenant) {
    debugPrint('Getting history for year: $year, key: $key, tenant: $tenant');
    return get<List<dynamic>>(
      '${Constants.appUrl}/history/get?year=$year&key=$key&tenant=$tenant',
      config: const RequestConfig(headerType: HeaderType.bearerToken),
    );
  }

  //Тайлан хэвлэх
  Future<Uint8List> printHistoryRaw(String id, String historyKey, String actionKey, String tenant) {
    debugPrint(
      'Printing history: $id, historyKey: $historyKey, actionKey: $actionKey, tenantName: $tenant',
    );

    return getRaw(
      '${Constants.appUrl}/history/print?id=$id&historyKey=$historyKey&actionKey=$actionKey&tenant=$tenant',
      config: const RequestConfig(headerType: HeaderType.bearerToken),
    );
  }
}
