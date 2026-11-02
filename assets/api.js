(function(){
const ERR={BAD_CLASS_CODE:'รหัสห้องไม่ถูกต้อง ลองถามครูอีกครั้งนะ',BAD_USERNAME:'ชื่อผู้ใช้ต้องเป็น a-z, 0-9, _ หรือ . ยาว 3–20 ตัว',BAD_PASSWORD:'รหัสผ่านต้องยาว 4–64 ตัว',BAD_NAME:'กรอกชื่อเล่น 1–30 ตัวอักษร',BAD_NO:'เลขที่ต้องเป็น 1–99',USERNAME_TAKEN:'ชื่อผู้ใช้นี้มีคนใช้แล้ว ลองชื่ออื่นนะ',BAD_LOGIN:'ชื่อผู้ใช้หรือรหัสผ่านไม่ถูกต้อง',LOCKED:'ลองผิดหลายครั้งเกินไป รอ 10 นาทีแล้วลองใหม่',SESSION_EXPIRED:'หมดเวลาเข้าสู่ระบบ กรุณาเข้าสู่ระบบใหม่',TEACHER_SESSION_EXPIRED:'หมดเวลา กรุณาใส่รหัสครูใหม่',BAD_RESULTS:'ข้อมูลผลการเล่นไม่ถูกต้อง',BAD_MODE:'โหมดไม่ถูกต้อง',NETWORK:'เชื่อมต่ออินเทอร์เน็ตไม่ได้ ลองใหม่อีกครั้ง'};
async function rpc(fn,args){
  let res;
  try{res=await fetch(VCFG.url+'/rest/v1/rpc/'+fn,{method:'POST',headers:{'apikey':VCFG.key,'Content-Type':'application/json'},body:JSON.stringify(args||{})});}
  catch(e){const er=new Error(ERR.NETWORK);er.code='NETWORK';throw er;}
  let data=null;try{data=await res.json();}catch(e){}
  if(!res.ok){const m=(data&&data.message)||'ERROR';const code=Object.keys(ERR).find(k=>m.indexOf(k)>=0)||m;const er=new Error(ERR[code]||('เกิดข้อผิดพลาด: '+m));er.code=code;throw er;}
  if(data&&data.error){const er=new Error(ERR[data.error]||data.error);er.code=data.error;throw er;}
  return data;
}
window.API={rpc,ERR};
})();
