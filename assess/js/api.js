/* Supabase RPC client for assess_* only. Uses the publishable key in ../assets/config.js. */
(function (global) {
  function mapErr(m) {
    var s = String(m || "");
    if (s.indexOf("NO_SESSION") >= 0) return "หมดเวลา กรุณาเข้าสู่ระบบใหม่";
    if (s.indexOf("LOCKED") >= 0) return "ใส่ผิดหลายครั้ง รอ 10 นาที";
    if (s.indexOf("BAD_LOGIN") >= 0) return "ชื่อผู้ใช้หรือรหัสผ่านไม่ถูกต้อง";
    if (s.indexOf("FORBIDDEN") >= 0) return "ไม่มีสิทธิ์ทำรายการนี้";
    if (s.indexOf("BAD_CONTENT") >= 0) return "ข้อความนี้ใช้ไม่ได้";
    if (s.indexOf("NO_REPORT") >= 0) return "ยังไม่มีร่างรายงาน";
    if (s.indexOf("PGRST202") >= 0 || s.indexOf("Could not find the function") >= 0) return "ระบบยังไม่พร้อมใช้งาน";
    if (s === "NETWORK") return "เชื่อมต่อไม่ได้";
    return "ทำรายการไม่สำเร็จ";
  }
  async function rpc(fn, args) {
    if (!global.VCFG || !global.VCFG.url || !global.VCFG.key) {
      var missing = new Error("ไม่พบการตั้งค่า");
      missing.code = "CONFIG";
      throw missing;
    }
    var r;
    try {
      r = await fetch(global.VCFG.url + "/rest/v1/rpc/" + fn, {
        method: "POST",
        headers: { apikey: global.VCFG.key, "Content-Type": "application/json" },
        body: JSON.stringify(args || {})
      });
    } catch (e) {
      var net = new Error(mapErr("NETWORK"));
      net.code = "NETWORK";
      throw net;
    }
    var d = null;
    try { d = await r.json(); } catch (e) { d = null; }
    if (!r.ok) {
      var raw = (d && (d.message || d.error || d.code)) || "ERROR";
      var err = new Error(mapErr(raw));
      err.code = String(raw);
      throw err;
    }
    if (d && d.error) {
      var soft = new Error(mapErr(d.error));
      soft.code = String(d.error);
      throw soft;
    }
    return d;
  }
  global.AssessApi = {
    rpc: rpc,
    login: function (username, password) {
      return rpc("assess_login", { p_username: username, p_password: password });
    },
    logout: function (token) { return rpc("assess_logout", { p_token: token }); },
    bootstrap: function (token) { return rpc("assess_bootstrap", { p_token: token }); },
    saveModule: function (token, student, module, answers, done, pct) {
      return rpc("assess_save_module", {
        p_token: token,
        p_student: student,
        p_module: module,
        p_answers: answers || {},
        p_done: !!done,
        p_pct: pct
      });
    },
    saveForm: function (token, student, form, values) {
      return rpc("assess_save_form", {
        p_token: token,
        p_student: student,
        p_form: form,
        p_values: values || {}
      });
    },
    saveReport: function (token, student, report) {
      return rpc("assess_save_report", { p_token: token, p_student: student, p_report: report });
    },
    approve: function (token, student, summary) {
      return rpc("assess_approve_report", { p_token: token, p_student: student, p_summary: summary });
    }
  };
})(window);
