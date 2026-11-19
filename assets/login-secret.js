// Login secret sent as vocab_login p_password.
// Numeric national IDs stay digits-only (Thai numerals, spaces, hyphens, other separators).
// One English letter + 12 digits keeps the letter — digits() would drop it and leave 12 digits.
(function(root){
'use strict';
const THAI='๐๑๒๓๔๕๖๗๘๙';
const SEP=/[\s\u00A0\u200B-\u200D\uFEFF.\u00B7\u2022\/_‐‑‒–—―−-]+/g;
function thaiDigits(s){return String(s==null?'':s).replace(/[๐-๙]/g,d=>THAI.indexOf(d))}
function digits(s){return thaiDigits(s).replace(/[^0-9]/g,'')}
function loginSecret(raw){
  const compact=thaiDigits(raw).replace(SEP,'');
  const m=/^([A-Za-z])([0-9]{12})$/.exec(compact);
  if(m)return m[1].toUpperCase()+m[2];
  // A leading letter that is not exactly + 12 digits must not be stripped into a numeric ID.
  if(/^[A-Za-z]/.test(compact))return compact.toUpperCase();
  return digits(raw);
}
const OK=/^(?:[0-9]{13}|[A-Z][0-9]{12})$/;
const api={thaiDigits,digits,loginSecret,OK};
if(typeof module==='object'&&module.exports)module.exports=api;
root.LOGIN_SECRET=api;
})(typeof globalThis!=='undefined'?globalThis:this);
