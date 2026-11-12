import 'dart:convert';

import '../domain/platform_session.dart';

/// 官版网页只从这些一方 HTTPS 站点打开；每次主文档导航都重新校验。
/// 业务 API 使用另一份封闭路由表，网页不能借桥接要求任意地址携带凭据。
abstract final class KugouOfficialWebContract {
  static final growth = Uri.parse(
    'https://m.kugou.com/ssr/listen-level/home?ssr_header_param=266431&isHideTitleBar=1&outerFramework=1',
  );
  static final rules = Uri.parse(
    'https://activity.kugou.com/voo/v-bf6de1d1/index.html',
  );
  static const _hosts = {
    'm3ws.kugou.com',
    'm.kugou.com',
    'h5.kugou.com',
    'activity.kugou.com',
  };
  static final _trade = RegExp(
    r'(?:^|[/_.?&=\-])(pay|payment|recharge|cashier|vip|svip|subscribe|mall|blind_?box|lottery|buy)(?:$|[/_.?&=\-])',
    caseSensitive: false,
  );

  static bool accepts(Uri uri) {
    if (uri.scheme != 'https' ||
        !_hosts.contains(uri.host) ||
        uri.userInfo.isNotEmpty ||
        uri.hasPort && uri.port != 443 ||
        uri.toString().length > 4096) {
      return false;
    }
    String decoded;
    try {
      decoded = Uri.decodeFull(uri.toString());
    } on FormatException {
      return false;
    }
    if (decoded.contains('\\') || _trade.hasMatch(decoded)) return false;
    if (uri.queryParameters.keys.any(
      (key) => const {
        'token',
        'clienttoken',
        'vip_token',
        'authorization',
      }.contains(key.toLowerCase()),
    )) {
      return false;
    }
    // 不把开放重定向参数交给已授权的页面执行。
    for (final entry in uri.queryParameters.entries) {
      if (![
        'url',
        'redirect',
        'redirect_url',
        'target',
        'returnurl',
      ].contains(entry.key.toLowerCase())) {
        continue;
      }
      final value = entry.value;
      if (value.contains('://') || value.startsWith('//')) {
        return false;
      }
    }
    return true;
  }

  static String _json(Object value) => jsonEncode(value)
      .replaceAll('<', r'\u003c')
      .replaceAll('\u2028', r'\u2028')
      .replaceAll('\u2029', r'\u2029');

  /// 同步读取由主文档闭包提供，跨源 iframe 不能通过 JavaScriptChannel 取凭据。
  /// 只使用当前账号实际签发的Lite或补充标准版凭据。
  /// 不支持的原生命令明确失败；签名764失败时官方H5采用自己的H5签名。
  static String bootstrap({
    required PlatformSession session,
    required Map<String, String> device,
    required Map<String, dynamic> grade,
  }) {
    final user = {
      'status': 1,
      'kugouID': session.userId,
      'userid': session.userId,
      'token': session.kugouOfficialToken,
      'nickName': session.nickname,
      'photo': session.avatarUrl,
      'appid': session.kugouAppId,
      'gradeData': grade,
    };
    return '''
<script>(function(){'use strict';
if(window!==window.top)return;
const user=${_json(user)},device=${_json({'status': 1, ...device})};
let live=true;
const failed={status:0,error:'该操作暂不支持'};
function send(cmd,data){if(live&&window.MestingKugou){
window.MestingKugou.postMessage(JSON.stringify({cmd:cmd,data:data||{}}));}}
function invoke(cmd,raw){
if(!live)return JSON.stringify({status:0});
let data={};try{data=typeof raw==='string'?JSON.parse(raw):raw||{};}catch(_){}
const code=Number(cmd);
if(code===101)return JSON.stringify(user);
if(code===122)return JSON.stringify({status:1,version:${session.kugouClientVersion},platform:'android',function_module:{}});
if(code===124)return JSON.stringify(device);
if(code===123||code===158||code===102||code===115){send(code,data);return JSON.stringify(failed);}
return JSON.stringify(failed);
}
const external=window.external||{};external.superCall=invoke;
Object.defineProperty(window,'external',{value:external,configurable:true});
window.__mestingKugouRevoke=function(){live=false;Object.keys(user).forEach(k=>delete user[k]);
Object.keys(device).forEach(k=>delete device[k]);external.superCall=()=>JSON.stringify({status:0});};
// 交易入口不进入Mesting的功能范围；保留原页面中的真实等级和徽章内容。
const excluded=/加速|开通会员|立即开通|续费|盲盒|抽奖|抽取|购买|充值|支付/;
function hideTrade(){document.querySelectorAll('a,button,[role="button"],[onclick],[class*="button"],[class*="Button"],[class*="btn"],[class*="Btn"],[class*="vip"],[class*="Vip"],[class*="lottery"],[class*="Lottery"]').forEach(el=>{
if(excluded.test((el.innerText||'').trim())&&el.innerText.length<80){el.hidden=true;el.setAttribute('aria-hidden','true');}
});}
document.addEventListener('DOMContentLoaded',function(){hideTrade();
new MutationObserver(hideTrade).observe(document.body,{childList:true,subtree:true});});
if(document.currentScript)document.currentScript.remove();
})();</script>''';
  }

  static String inject(String html, String bootstrap) {
    final head = RegExp(
      r'<head\b[^>]*>',
      caseSensitive: false,
    ).firstMatch(html);
    if (head != null) {
      return html.replaceRange(head.end, head.end, bootstrap);
    }
    return '$bootstrap$html';
  }
}
