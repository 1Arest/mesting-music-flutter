/* Capture wire contracts from the original fixed Node modules, independently
 * of the Dart generator. No networking, logins or user credentials are used. */
const fs=require('fs'),path=require('path'),vm=require('vm'),crypto=require('crypto');
const source=path.resolve(process.argv[2]);
const catalog=JSON.parse(fs.readFileSync('assets/data/netease-full-catalog.json','utf8'));
const config=JSON.parse(fs.readFileSync(path.join(source,'util/config.json'),'utf8'));
const cases=[],skipped=[];
class FixedDate extends Date {constructor(...args){super(...(args.length?args:[1793232000000]));}static now(){return 1793232000000;}}
const defaults={id:'7',ids:'7,8',uid:'7',userId:'7',user_ids:'7',t:'1',type:'0',limit:'30',offset:'0',before:'123456',lasttime:'123456',year:'2026',month:'10',date:'2026-10-29',timestamp:'123456',initial:'a',level:'standard',order:'hot',sortType:'3',pageNo:'1',pageSize:'30',phone:'13800000000',captcha:'123456',countrycode:'86',ctcode:'86',privacy:'0',like:'1',subscribe:'1',randomList:'7,8',displayList:'7,8',op:'add',playlist:'7',keywords:'合约样本',password:'synthetic-not-a-password',md5_password:'',data:'{}',song:'7',realIP:'',cookie:{}};
(async()=>{
for(const endpoint of catalog.entries.filter(x=>x.builder==='generated')) {
  for(const variant of ['filled','defaults']) {
    const query={cookie:{}};
    if(variant==='filled')for(const p of endpoint.params)query[p.key]=defaults[p.key]??'7';
    const captures=[]; const stop={};
    const module={exports:{}};
    const stubRequire=(name)=>{
      if(name.includes('option'))return(q,mode='')=>({crypto:mode||'eapi'});
      if(name.includes('config.json'))return config;
      if(name.includes('logger'))return {info:()=>{},error:()=>{}};
      if(name.includes('index')||name==='../util')return {toBoolean:v=>v===true||v==='true'||v===1||v==='1'};
      if(name==='md5')return v=>crypto.createHash('md5').update(String(v)).digest('hex');
      if(name==='crypto-js')return {MD5:v=>crypto.createHash('md5').update(String(v)).digest('hex'),enc:{Hex:{}}};
      throw Error('Unexpected dependency '+name);
    };
    try{
      vm.runInNewContext(fs.readFileSync(path.join(source,'module',endpoint.source),'utf8'),{module,exports:module.exports,require:stubRequire,console:{log:()=>{},error:()=>{}},Date:FixedDate,Math,Buffer},{timeout:1000});
      try {await module.exports(query,(p,d,o)=>{captures.push({path:p,data:d,weapi:o.crypto==='weapi'});throw stop;});} catch(err){if(err!==stop)throw err;}
      if(captures.length!==1)throw Error('No unique first request');
      const clean=JSON.parse(JSON.stringify(captures[0]));
      // An absent required source argument is not an executable user request.
      // Keep the default case only when upstream can actually build it.
      cases.push({route:endpoint.route,variant,query:JSON.parse(JSON.stringify(variant==='filled'?Object.fromEntries(endpoint.params.map(p=>[p.key,defaults[p.key]??'7'])):{})),expected:clean});
    }catch(err){skipped.push({route:endpoint.route,variant,reason:String(err)});}
  }
}
fs.writeFileSync('test/fixtures/netease-full-upstream-contracts.json',JSON.stringify({source:'@neteaseapireborn/api@4.29.7',cases,skipped},null,2)+'\n');
console.log(JSON.stringify({captured:cases.length,routes:new Set(cases.map(x=>x.route)).size,skipped},null,2));
})();
