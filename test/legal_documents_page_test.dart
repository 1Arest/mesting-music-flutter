import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mesting_music/features/legal/domain/legal_documents.dart';
import 'package:mesting_music/features/legal/presentation/legal_documents_page.dart';

void main() {
  Widget app(LegalDocumentType type) {
    return MaterialApp(
      home: Scaffold(body: LegalDocumentPage(documentType: type)),
    );
  }

  testWidgets('用户协议完整说明账号、内容和注销规则', (tester) async {
    await tester.pumpWidget(app(LegalDocumentType.userAgreement));
    await tester.pumpAndSettle();

    expect(find.text('用户协议'), findsOneWidget);
    expect(find.text('三、登录、安全与账号归属'), findsOneWidget);
    expect(find.text('九、退出、数据管理与协议更新'), findsOneWidget);
    expect(find.textContaining('不提供会员破解'), findsOneWidget);
  });

  testWidgets('隐私政策说明信息、存储和用户权利', (tester) async {
    await tester.pumpWidget(app(LegalDocumentType.privacyPolicy));
    await tester.pumpAndSettle();

    expect(find.text('隐私政策'), findsOneWidget);
    expect(find.text('一、浏览、搜索与在线播放'), findsOneWidget);
    expect(find.text('八、服务提供方与历史账号'), findsOneWidget);
    expect(find.textContaining('云同步客户端实现已移除'), findsOneWidget);
    expect(find.text('九、保留、退出与删除边界'), findsOneWidget);
  });
}
