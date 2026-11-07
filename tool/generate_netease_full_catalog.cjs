/*
 * Build-time port of the pinned MIT request modules. This script is never
 * bundled or evaluated by the app. Generated Dart contains an explicit
 * allowlist and native payload builders, not an embedded JavaScript engine.
 *
 * Usage: node tool/generate_netease_full_catalog.cjs <package> <docs.md>
 *        <acorn-module> [--inspect]
 */
const fs = require('fs');
const path = require('path');
const crypto = require('crypto');
const [sourceRoot, docPath, parserPath] = process.argv.slice(2);
const acorn = require(path.resolve(parserPath));
const root = path.resolve(__dirname, '..');
const out = path.join(root, 'lib/features/music_platform/netease/full');
fs.mkdirSync(out, {recursive:true});
const text = fs.readFileSync(docPath, 'utf8');
const sections = text.split(/(?=^#{3,6} \[)/m).filter(s=>/^#{3,6} /.test(s));
const entries = new Map();
for (const section of sections) {
  const heading = section.match(/^#+ \[([^\]]+)\]\(([^\n]+)\)/);
  if (!heading) continue;
  let routes = [...section.matchAll(/^.*接口地址[^\n]*$/gm)].flatMap(line=>[...line[0].matchAll(/`(\/[^`\s?]+)/g)].map(x=>x[1]));
  if (!routes.length) routes = [...section.matchAll(/调用例子[^\n]*?`(\/[^`\s?]+)/g)].map(x=>x[1]);
  for (const route of routes) if (!entries.has(route)) entries.set(route, {
    route, title:heading[1].replace(/\\/g,'').replace(/^\d+\.\s*/,''),
    url:heading[2].replace(/\\#/g,'#'), section,
  });
}
// The document delegates Together to its linked example, rather than listing
// every command in the main page. Keep these commands in the same inventory.
for (const [route,title] of Object.entries({
  '/listentogether/room/create':'创建一起听房间', '/listentogether/room/check':'检查一起听房间',
  '/listentogether/accept':'接受一起听邀请', '/listentogether/end':'结束一起听',
  '/listentogether/status':'一起听状态', '/listentogether/heatbeat':'一起听心跳',
  '/listentogether/play/command':'一起听播放控制', '/listentogether/sync/list/command':'一起听队列同步',
  '/listentogether/sync/playlist/get':'一起听共享队列',
})) entries.set(route,{route,title,url:'https://github.com/Binaryify/NeteaseCloudMusicApi/issues/1676',section:''});
const str = s=>JSON.stringify(String(s)).replace(/\$/g,'\\$');
const rt = n=>{throw Error(n.type+': '+JSON.stringify(n).slice(0,140));};
let routeWeapi = false;
function e(n) {
  if (!n) return 'null';
  switch(n.type) {
    case 'Literal': return n.regex ? `RegExp(${str(n.regex.pattern)})` : n.value===null?'null':typeof n.value==='string'?str(n.value):String(n.value);
    case 'Identifier': return ({undefined:'jsUndefined', NaN:'double.nan', resourceTypeMap:'jsResourceTypes',APP_CONF:'appConf'})[n.name] || n.name;
    case 'ObjectExpression': return `<String, dynamic>{${n.properties.map(p=>p.type==='SpreadElement'?`...jsMap(${e(p.argument)})`:`${p.computed?`jsString(${e(p.key)})`:str(p.key.name??p.key.value)}: ${e(p.value)}`).join(', ')}}`;
    case 'ArrayExpression': return `<dynamic>[${n.elements.map(v=>v?.type==='SpreadElement'?`...jsList(${e(v.argument)})`:e(v)).join(', ')}]`;
    case 'MemberExpression': return `jsGet(${e(n.object)}, ${n.computed?e(n.property):str(n.property.name)})`;
    case 'TemplateLiteral': {
      const parts=[];n.quasis.forEach((q,i)=>{if(q.value.cooked)parts.push(str(q.value.cooked));if(n.expressions[i])parts.push(`jsString(${e(n.expressions[i])})`);});
      return parts.length?`[${parts.join(', ')}].join()`:`''`;
    }
    case 'LogicalExpression': return n.operator==='??'?`(${e(n.left)} ?? ${e(n.right)})`:`js${n.operator==='||'?'Or':'And'}(${e(n.left)}, () => ${e(n.right)})`;
    case 'BinaryExpression': {
      const a=e(n.left),b=e(n.right);
      if(n.operator==='+')return `jsAdd(${a}, ${b})`;
      if(['==','===','!=','!=='].includes(n.operator)) return `${n.operator.includes('!')?'!':''}${n.operator.length===3?'jsStrictEqual':'jsEqual'}(${a}, ${b})`;
      if(['<','>','<=','>=','-','*','/','%','|','&','^','<<','>>'].includes(n.operator)) return `(jsNumber(${a}) ${n.operator} jsNumber(${b}))`;
      return rt(n);
    }
    case 'ConditionalExpression': return `(jsTruthy(${e(n.test)}) ? ${e(n.consequent)} : ${e(n.alternate)})`;
    case 'UnaryExpression': return n.operator==='!'?`!jsTruthy(${e(n.argument)})`:n.operator==='+'?`jsNumber(${e(n.argument)})`:n.operator==='-'?`(-jsNumber(${e(n.argument)}))`:n.operator==='typeof'?`jsType(${e(n.argument)})`:rt(n);
    case 'CallExpression': {
      if(n.callee.type==='Identifier') {
        const name=n.callee.name;
        if(name==='isNaN')return `jsNumber(${e(n.arguments[0])}).isNaN`;
        if(['Number','parseInt','parseFloat'].includes(name))return `jsNumber(${e(n.arguments[0])})`;
        if(name==='String')return `jsString(${e(n.arguments[0])})`;
        if(name==='toBoolean')return `jsBoolean(${e(n.arguments[0])})`;
        if(name==='encodeURIComponent')return `Uri.encodeComponent(jsString(${e(n.arguments[0])}))`;
        if(name==='decodeURIComponent')return `Uri.decodeComponent(jsString(${e(n.arguments[0])}))`;
        if(name==='md5')return `jsMd5(${e(n.arguments[0])})`;
        return rt(n);
      }
      if(n.callee.type==='MemberExpression') {
        const obj=n.callee.object, method=n.callee.property.name;
        if(obj.type==='Identifier'&&obj.name==='CryptoJS'&&method==='MD5')return `jsMd5(${e(n.arguments[0])})`;
        if(obj.type==='Identifier'&&obj.name==='Date'&&method==='parse')return `DateTime.parse(jsString(${e(n.arguments[0])})).millisecondsSinceEpoch`;
        if(obj.type==='Identifier'&&obj.name==='JSON'&&method==='stringify')return `jsJson(${e(n.arguments[0])})`;
        if(obj.type==='Identifier'&&obj.name==='JSON'&&method==='parse')return `jsonDecode(jsString(${e(n.arguments[0])}))`;
        if(obj.type==='Identifier'&&obj.name==='Date'&&method==='now')return `now.millisecondsSinceEpoch`;
        if(obj.type==='Identifier'&&obj.name==='Math')return `jsMath(${str(method)}, [${n.arguments.map(e).join(', ')}])`;
        if(obj.type==='Identifier'&&obj.name==='Array'&&method==='isArray')return `(${e(n.arguments[0])} is List)`;
        if(method==='toString')return `jsString(${e(obj)})`;
        return `jsMethod(${e(obj)}, ${str(method)}, [${n.arguments.map(e).join(', ')}])`;
      }
      return rt(n);
    }
    case 'ArrowFunctionExpression': {
      if(n.body.type==='BlockStatement'&&(n.body.body.length!==1||n.body.body[0].type!=='ReturnStatement'))return rt(n.body);
      return `(${n.params.map(p=>'dynamic '+p.name).join(', ')}) => ${e(n.body.type==='BlockStatement'?n.body.body[0].argument:n.body)}`;
    }
    case 'NewExpression': if(n.callee.name==='Date') return n.arguments.length?`DateTime.fromMillisecondsSinceEpoch(jsNumber(${e(n.arguments[0])}).toInt())`:'now'; return rt(n);
    default:return rt(n);
  }
}
function lhs(n) {if(n.type==='Identifier')return n.name;if(n.type==='MemberExpression')return `${e(n.object)}[${n.computed?e(n.property):str(n.property.name)}]`;return rt(n);}
function requestReturn(n) {
  if(n.type==='AwaitExpression')n=n.argument;
  if(n.type!=='CallExpression'||n.callee.name!=='request')return rt(n);
  if(n.arguments.length<2)return rt(n);
  let option=n.arguments[2];
  if(option?.type==='CallExpression'&&option.callee.name==='createOption') {
    const mode=option.arguments[1]?.value||'eapi';
    if(!['eapi','weapi',''].includes(mode))throw Error('crypto '+mode);
    routeWeapi=mode==='weapi';
  } else if(option) throw Error('option '+option.type);
  return `return (path: jsString(${e(n.arguments[0])}), data: Map<String, Object?>.from(jsClean(jsMap(${e(n.arguments[1])})) as Map), weapi: ${routeWeapi});`;
}
function stmt(n) {
  switch(n.type) {
    case 'VariableDeclaration': return n.declarations.map(d=>{if(d.id.type!=='Identifier')return rt(d);return `dynamic ${d.id.name} = ${e(d.init)};`;}).join('\n');
    case 'ExpressionStatement': {
      const v=n.expression;
      if(JSON.stringify(v).includes('"name":"cookie"')) return '';
      if(v.type==='CallExpression'&&['logger','console'].includes(v.callee.object?.name))return '';
      if(v.type==='AssignmentExpression')return `${lhs(v.left)} ${v.operator} ${e(v.right)};`;
      if(v.type==='UnaryExpression'&&v.operator==='delete')return `${e(v.argument.object)}.remove(${v.argument.computed?e(v.argument.property):str(v.argument.property.name)});`;
      // Cookie transport options never override the current account jar.
      if(v.type==='CallExpression')return `${e(v)};`;
      return rt(v);
    }
    case 'ReturnStatement':return requestReturn(n.argument);
    case 'BlockStatement':return n.body.map(stmt).join('\n');
    case 'IfStatement':return `if (jsTruthy(${e(n.test)})) {\n${stmt(n.consequent)}\n}${n.alternate?` else {\n${stmt(n.alternate)}\n}`:''}`;
    case 'EmptyStatement':return '';
    default:return rt(n);
  }
}
function group(route) {
  if(route==='/related/playlist'||route==='/song/order/update')return ['音乐库','歌单与收藏'];
  if(route==='/hug/comment')return ['功能','评论与云村'];
  if(route==='/scrobble')return ['我的','播放与同步'];
  if(route==='/inner/version')return ['我的','兼容信息'];
  if(route==='/batch')return ['音乐库','资料与收藏概览'];
  if(route.startsWith('/listentogether/'))return ['功能','一起听'];
  if(route.startsWith('/sheet/'))return ['功能','乐谱'];
  if(route.startsWith('/comment/')||route==='/comment')return ['功能','评论与云村'];
  if(route.startsWith('/record/')||route==='/user/record'||route.startsWith('/history/'))return ['音乐库','历史与听歌报告'];
  if(route.startsWith('/user/cloud')||route==='/cloud'||route==='/cloud/match')return ['音乐库','音乐云盘'];
  if(route==='/song/purchased'||route==='/digitalAlbum/purchased')return ['音乐库','已购音乐'];
  if(route.startsWith('/album')||route.startsWith('/top/album'))return ['发现','新歌与专辑'];
  if(route.startsWith('/song')||route.startsWith('/lyric')||route==='/check/music')return ['功能','歌曲与歌词'];
  if(route==='/toplist'||route.startsWith('/top/')&&route!='/top/playlist')return ['发现','榜单与热门'];
  if(route.startsWith('/search')||route==='/cloudsearch')return ['发现','音乐搜索'];
  if(route==='/calendar')return ['发现','音乐日历'];
  if(/^\/(msg|send|pl\/count)/.test(route))return ['我的','消息中心'];
  if(/^\/(musician|artist\/new\/|ugc|voice\/upload|voice\/delete|voicelist\/trans)/.test(route))return ['我的','音乐人中心'];
  if(/^\/(vip|yunbei|digitalAlbum|sign\/|song\/purchased)/.test(route))return ['我的','会员与云贝'];
  if(/^\/(login|logout|register|captcha|cellphone|activate|nickname|rebind|user\/(account|detail|subcount|level|binding|replacephone|update)|avatar|countries|setting|verify)/.test(route))return ['我的','账号与安全'];
  if(/^\/(event|user\/event|share|comment\/event|comment\/hotwall|hot\/topic|topic|follow|resource\/like|user\/(follows|followeds|comment))/.test(route))return ['功能','云村与话题'];
  if(/^\/(dj|voice|voicelist|personalized\/djprogram|program)/.test(route))return ['功能','播客与声音'];
  if(/^\/(mv|video|mlog|related)/.test(route))return ['功能','视频与MV'];
  if(/^\/(playlist|song\/order|likelist|like|user\/(playlist|cloud|dj)|cloud|record|user\/record|album\/sublist|artist\/sublist)/.test(route))return ['音乐库','歌单与收藏'];
  if(/^\/(listen|audio|sheet|inner|batch)/.test(route))return ['功能','听歌工具'];
  if(/^\/(artist|simi\/artist)/.test(route))return ['发现','歌手与专辑'];
  if(/^\/(style|music\/|song\/wiki|album\/wiki|artist\/wiki)/.test(route))return ['发现','曲风与音乐百科'];
  return ['发现','音乐探索'];
}
const schema=[];const generated=[];const errors=[];
// Reviewed against the pinned modules. Chinese titles such as "新建歌单" do
// not reliably describe side effects; likewise "点赞统计" is only a read.
// Keep confirmation policy tied to these stable route identities.
const mutationRoutes = new Set([
  '/login/cellphone', '/login', '/register/anonimous', '/login/refresh',
  '/captcha/sent', '/register/cellphone', '/activate/init/profile', '/rebind',
  '/logout', '/user/replacephone', '/user/update', '/avatar/upload',
  '/playlist/create', '/playlist/update', '/playlist/desc/update',
  '/playlist/name/update', '/playlist/tags/update', '/playlist/cover/update',
  '/playlist/order/update', '/song/order/update', '/event/forward',
  '/event/del', '/share/resource', '/follow', '/artist/sub', '/video/sub',
  '/mv/sub', '/playlist/update/playcount', '/playlist/delete',
  '/playlist/subscribe', '/playlist/tracks', '/playlist/track/add',
  '/playlist/track/delete', '/comment/like', '/comment', '/resource/like',
  '/album/sub', '/recommend/songs/dislike', '/daily_signin', '/like',
  '/fm_trash', '/scrobble', '/user/cloud/del', '/cloud', '/cloud/match',
  '/dj/sub', '/send/text', '/send/song', '/send/album', '/send/playlist',
  '/digitalAlbum/ordering', '/yunbei/sign', '/yunbei/task/finish',
  '/yunbei/rcmd/song', '/vip/growthpoint/get', '/musician/cloudbean/obtain',
  '/musician/sign', '/playlist/privacy', '/voicelist/trans', '/voice/upload',
  '/listentogether/room/create', '/listentogether/accept',
  '/listentogether/end', '/listentogether/heatbeat',
  '/listentogether/play/command', '/listentogether/sync/list/command',
]);
for(const entry of entries.values()) {
  let filename=entry.route.slice(1).replaceAll('/','_')+'.js';
  if(entry.route==='/yunbei/tasks/receipt')filename='yunbei_receipt.js';
  if(entry.route==='/yunbei/tasks/expense')filename='yunbei_expense.js';
  if(entry.route==='/search')filename='search.js';
  const sourceFile=path.join(sourceRoot,'module',filename);
  let code='',body='',fields=[],reason='';
  if(fs.existsSync(sourceFile)) {
    code=fs.readFileSync(sourceFile,'utf8');
    const ast=acorn.parse(code,{ecmaVersion:'latest'});
    const exportNode=ast.body.find(n=>n.type==='ExpressionStatement'&&n.expression.type==='AssignmentExpression'&&n.expression.left.object?.name==='module');
    fields=[...new Set([...code.matchAll(/query\.([a-zA-Z0-9_]+)/g)].map(m=>m[1]))].filter(k=>!['cookie','crypto','ua','proxy','realIP','e_r','domain','checkToken'].includes(k));
    try {routeWeapi=false;body=stmt(exportNode.expression.right.body);
      const constants=ast.body.filter(n=>n.type==='VariableDeclaration').flatMap(n=>n.declarations).filter(d=>d.id.type==='Identifier'&&d.init?.type==='ObjectExpression');
      const prefix=constants.map(d=>`dynamic ${d.id.name} = ${e(d.init)};`).join('\n');
      generated.push(`case ${str(entry.route)}: {\n${prefix}\n${body}\n}`);
    }catch(err){reason=err.message;errors.push({route:entry.route,error:reason});}
  }else{reason='missing source module';errors.push({route:entry.route,error:reason});}
  let [tab,category]=group(entry.route);
  const section=entry.section;
  let requiredPart=section.split(/必选参数|必选参数：/)[1]?.split(/可选参数|接口地址|调用例子/)[0]||'';
  let required=[...requiredPart.matchAll(/(?:`([a-zA-Z][a-zA-Z0-9_]*)`|\b([a-zA-Z][a-zA-Z0-9_]*))\s*[:：]/g)].map(m=>m[1]||m[2]);
  const params=fields.map(key=>{
    const marker='`'+key+'`';const at=section.indexOf(marker);
    const help=at<0?(section.match(new RegExp('(?:^|\\n)'+key+'[ :：]+([^\\n]+)'))?.[1]||''):section.slice(at+marker.length).split('\n')[0].replace(/^\s*[:：]\s*/,'').replace(/`/g,'').slice(0,180);
    return {key,required:required.includes(key),help};
  });
  const write=mutationRoutes.has(entry.route);
  const desc=(section.match(/说明\s*[:：]\s*([^\n]+)/)?.[1]||'').replace(/`/g,'').replace(/\[([^\]]+)\]\([^)]*\)/g,'$1');
  schema.push({...entry,section:undefined,tab,category,params,write,description:desc,
    source:filename,sha256:code?crypto.createHash('sha256').update(code).digest('hex'):null,
    builder:reason?'manual':'generated', unavailable:entry.route==='/comment/hotwall/list'?'文档已标注网易云官方下架此功能':null});
}
if(!process.argv.includes('--inspect')) {
fs.writeFileSync(path.join(out,'netease_native_routes.g.dart'),`// GENERATED by tool/generate_netease_full_catalog.cjs.\n// Source: @neteaseapireborn/api 4.29.7 (MIT). See third_party/netease_protocol.\n// Payload builders are native Dart. Never edit this allowlist by inferring a URL.\nimport '../netease_extended_routes.dart';\nimport 'netease_js_values.dart';\nNeteaseRoute? neteaseNativeRoute(String route, Map<String, Object?> input, {DateTime Function()? clock}) {\nfinal now = clock?.call() ?? DateTime.now();\nfinal dynamic query = Map<String, dynamic>.of(input);\nswitch (route) {\n${generated.join('\n')}\ndefault: return null;\n}\n}\n`);
fs.writeFileSync(path.join(root,'assets/data/netease-full-catalog.json'),JSON.stringify({source:'@neteaseapireborn/api@4.29.7',documentation:'https://binaryify.github.io/NeteaseCloudMusicApi/',entries:schema},null,2)+'\n');
}
fs.writeFileSync(path.join(root,'.codex-artifacts/2026-10-29-netease-full-scope/generator-errors.json'),JSON.stringify(errors,null,2));
console.log(JSON.stringify({entries:entries.size,generated:generated.length,manual:errors.length,errors},null,2));
