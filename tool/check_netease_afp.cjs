// Host-only smoke check for the shipped local fingerprint assets. The browser
// sandbox exposes no network API, filesystem API or account data to AFP.
const fs=require('fs'),vm=require('vm'),crypto=require('crypto');
const sandbox={WebAssembly,TextDecoder,TextEncoder,Uint8Array,Float32Array,ArrayBuffer,Int8Array,Int16Array,Int32Array,Uint16Array,Uint32Array,Float64Array,DataView,Promise,Math,Date,setTimeout,clearTimeout,setInterval,clearInterval,
  console:{log(){},info(){},warn(){},error(){}},atob:v=>Buffer.from(v,'base64').toString('binary'),btoa:v=>Buffer.from(v,'binary').toString('base64'),window:{location:{href:'about:blank'}},document:{currentScript:null}};
vm.createContext(sandbox);
vm.runInContext(fs.readFileSync('third_party/netease_protocol/afp/afp.wasm.js','utf8'),sandbox);
vm.runInContext(fs.readFileSync('third_party/netease_protocol/afp/afp.js','utf8'),sandbox);
const signal=new Float32Array(40000);
for(let i=0;i<signal.length;i++)signal[i]=.3*Math.sin(2*Math.PI*440*i/8000)+.15*Math.sin(2*Math.PI*730*i/8000);
sandbox.signal=signal;
const timeout=setTimeout(()=>{process.stdout.write(JSON.stringify({ok:false,error:'Fingerprint timeout'})+'\n');process.exit(1);},15000);
Promise.resolve(vm.runInContext('GenerateFP(signal)',sandbox)).then(fp=>{
  const bytes=Buffer.from(fp,'base64');
  process.stdout.write(JSON.stringify({ok:bytes.length>0,inputSamples:signal.length,fingerprintBytes:bytes.length,sha256:crypto.createHash('sha256').update(bytes).digest('hex'),network:false})+'\n');
  clearTimeout(timeout);process.exit(bytes.length?0:1);
},err=>{process.stdout.write(JSON.stringify({ok:false,error:String(err).slice(0,300)})+'\n');clearTimeout(timeout);process.exit(1);});
