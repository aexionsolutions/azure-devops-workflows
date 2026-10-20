const {test}=require('node:test');
const assert=require('node:assert/strict');
const fs=require('node:fs'),os=require('node:os'),path=require('node:path'),{spawnSync}=require('node:child_process');
const script=fs.readFileSync(path.join(__dirname,'action.yml'),'utf8').split('      run: |')[1].split(/\r?\n/).map(x=>x.replace(/^        /,'')).join('\n');
const bash=process.platform==='win32'?'C:/Program Files/Git/bin/bash.exe':'bash';
const stub=`#!/usr/bin/env bash
echo "$*" >> "$CALLS"
case "$*" in
 'account show '*) echo test-subscription ;;
 'rest --method get '*)
   n=$(cat "$COUNTER"); echo $((n+1)) > "$COUNTER"
   case "$MODE" in
    read-denied|read-invalid|read-missing) echo 'metadata lookup failed' >&2; exit 1 ;;
    ready) echo Ready ;;
    stopped) if [ "$n" -lt 2 ]; then echo Stopped; else echo Ready; fi ;;
    starting) if [ "$n" -lt 2 ]; then echo Starting; else echo Ready; fi ;;
    timeout|start-denied) echo Stopped ;;
   esac ;;
 'rest --method post '*) [ "$MODE" != start-denied ] ;;
 *) exit 2 ;;
esac
`;
for(const mode of ['ready','stopped','starting','read-denied','read-invalid','read-missing','timeout','start-denied','non-blocking-timeout'])test(mode,()=>{
 const tmp=fs.mkdtempSync(path.join(os.tmpdir(),'pg-start-test-'));
 try{
  const unix=p=>p.replaceAll('\\','/').replace(/^([A-Za-z]):/,(_,drive)=>'/'+drive.toLowerCase());
  fs.mkdirSync(path.join(tmp,'bin'));fs.writeFileSync(path.join(tmp,'bin/az'),stub,{mode:0o755});
  fs.writeFileSync(path.join(tmp,'counter'),'0');fs.writeFileSync(path.join(tmp,'calls'),'');
  fs.writeFileSync(path.join(tmp,'run.sh'),`export PATH="${unix(tmp)}/bin:$PATH"\n${script}`);
  const result=spawnSync(bash,[unix(path.join(tmp,'run.sh'))],{encoding:'utf8',env:{...process.env,RG:'test-rg',PG_NAME:'test-pg',ATTEMPTS:'3',SLEEP_SECS:'0',NON_BLOCKING:String(mode==='non-blocking-timeout'),API_VER:'2024-08-01',MODE:mode==='non-blocking-timeout'?'timeout':mode,COUNTER:unix(path.join(tmp,'counter')),CALLS:unix(path.join(tmp,'calls'))},timeout:15000});
  assert.equal(result.status,['ready','stopped','starting','non-blocking-timeout'].includes(mode)?0:1,result.stderr);
  const calls=fs.readFileSync(path.join(tmp,'calls'),'utf8');
  assert.doesNotMatch(calls,/resource show/);
  assert.match(calls,/get .*api-version=2024-08-01/);
  if(mode==='ready'||mode.startsWith('read-'))assert.doesNotMatch(calls,/--method post/);
  if(mode==='stopped')assert.match(calls,/--method post/);
 }finally{
  assert.ok(path.resolve(tmp).startsWith(path.resolve(os.tmpdir())+path.sep) && path.basename(tmp).startsWith('pg-start-test-'));
  fs.rmSync(tmp,{recursive:true,force:true});
 }
});
