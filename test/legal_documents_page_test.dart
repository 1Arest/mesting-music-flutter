import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mesting_music/features/legal/domain/legal_documents.dart';
import 'package:mesting_music/features/legal/presentation/legal_documents_page.dart';
import 'package:mesting_music/core/platform/distribution_channel.dart';

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
    expect(
      find.text(DistributionChannel.isBeta ? '三、登录、安全与账号归属' : '账号与使用规则'),
      findsOneWidget,
    );
    expect(
      find.text(DistributionChannel.isBeta ? '九、退出、数据管理与协议更新' : '注销与终止'),
      findsOneWidget,
    );
    expect(
      find.textContaining(DistributionChannel.isBeta ? '不提供会员破解' : '不提供破解会员'),
      findsOneWidget,
    );
  });

  testWidgets('隐私政策说明信息、存储和用户权利', (tester) async {
    await tester.pumpWidget(app(LegalDocumentType.privacyPolicy));
    await tester.pumpAndSettle();

    expect(find.text('隐私政策'), findsOneWidget);
    expect(
      find.text(DistributionChannel.isBeta ? '一、浏览、搜索与在线播放' : '我们处理的信息'),
      findsOneWidget,
    );
    expect(
      find.text(DistributionChannel.isBeta ? '八、服务提供方与历史账号' : '存储与服务提供方'),
      findsOneWidget,
    );
    expect(find.textContaining('腾讯云 CloudBase'), findsOneWidget);
    expect(
      find.text(DistributionChannel.isBeta ? '九、保留、退出与删除边界' : '你的权利'),
      findsOneWidget,
    );
  });
}
