const retiredBundledTrackIds = <String>{
  'local_qi_feng_le',
  'local_qing_tian',
  'local_dao_xiang',
  'local_ye_qu',
  'local_qi_li_xiang',
  'local_gao_bai_qi_qiu',
  'local_qing_hua_ci',
  'local_hua_hai',
};

bool isRetiredBundledTrackId(String id) => retiredBundledTrackIds.contains(id);
