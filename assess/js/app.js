/* วิเคราะห์ผู้เรียนรายบุคคล — โรงเรียนปิยมิตรวิทยา
   UI ตามต้นแบบ เก็บข้อมูลผ่าน assess_* RPC (ไม่ใช้ localStorage) */
(function () {
  var SCHOOL = "โรงเรียนปิยมิตรวิทยา";
  var state = { user: null, view: "login", selectedStudentId: null, quiz: null };
  var STORE = emptyStore();
  var TOK = sessionGet();
  var BUSY = false;
  window.APP_DATA = window.APP_DATA || { students: [], assessments: {} };

  function emptyStore() {
    return { answers: {}, progress: {}, reports: {}, teacherNotes: {}, parentHome: {}, personality: {} };
  }
  function sessionGet() {
    try { return sessionStorage.getItem("assess_tok"); } catch (e) { return null; }
  }
  function sessionSet(v) {
    try {
      if (v) sessionStorage.setItem("assess_tok", v);
      else sessionStorage.removeItem("assess_tok");
    } catch (e) {}
  }
  function $(id) { return document.getElementById(id); }
  function esc(s) {
    return String(s == null ? "" : s)
      .replace(/&/g, "&amp;").replace(/</g, "&lt;").replace(/>/g, "&gt;").replace(/"/g, "&quot;");
  }
  function toast(msg) {
    var el = $("toast");
    if (!el) return;
    el.textContent = msg;
    el.style.display = "block";
    setTimeout(function () { el.style.display = "none"; }, 2400);
  }
  function guard(fn) {
    return function () {
      if (BUSY) return;
      BUSY = true;
      var args = arguments;
      Promise.resolve(fn.apply(null, args)).catch(function (e) {
        toast((e && e.message) || "บันทึกไม่สำเร็จ");
      }).then(function () { BUSY = false; });
    };
  }
  function studentById(id) {
    return (window.APP_DATA.students || []).find(function (s) { return s.id === id; });
  }
  function visibleStudents() { return (window.APP_DATA.students || []).slice(); }
  function bandLabel(b) {
    var labels = window.APP_DATA.assessments && window.APP_DATA.assessments.bandLabels;
    return (labels && labels[b]) || b;
  }
  function sampleTag(s) {
    return s && s.fictional !== false ? '<span class="tag">ข้อมูลจำลอง</span>' : "";
  }
  function headerSample() {
    var list = visibleStudents();
    if (!list.length) return "";
    if (list.every(function (s) { return s.fictional !== false; })) return '<span class="sample-pill">ข้อมูลจำลอง</span>';
    return "";
  }
  function statusTag(st) {
    if (st === "approved") return '<span class="tag ok">รายงานอนุมัติแล้ว</span>';
    if (st === "pending") return '<span class="tag warn">รอครูอนุมัติ</span>';
    if (st === "incomplete") return '<span class="tag warn">ทำค้างบางโมดูล</span>';
    return '<span class="tag">เพิ่งเริ่ม</span>';
  }
  function roleName(r) {
    return ({ admin: "ผู้บริหาร", teacher: "ครูที่ปรึกษา", counselor: "ครูแนะแนว", parent: "ผู้ปกครอง", student: "นักเรียน" })[r] || r;
  }
  function defaultProgress() {
    return {
      aptitude: { done: false, pct: 0 },
      ability: { done: false, pct: 0 },
      psych: { done: false, pct: 0 },
      work: { done: false, pct: 0 },
      exercises: { done: false, pct: 0 },
      personality: { done: false, pct: 0 },
      potential_survey: { done: false, pct: 0 },
      cognition: { done: false, pct: 0 },
      study_habits: { done: false, pct: 0 }
    };
  }
  function progressOf(id) {
    var base = defaultProgress();
    var got = (STORE.progress && STORE.progress[id]) || {};
    Object.keys(base).forEach(function (k) {
      if (got[k]) base[k] = { done: !!got[k].done, pct: Number(got[k].pct) || 0 };
    });
    STORE.progress[id] = base;
    return base;
  }
  function answersOf(id) {
    STORE.answers[id] = STORE.answers[id] || {};
    return STORE.answers[id];
  }
  function reportStatus(id) {
    var r = STORE.reports[id];
    if (r && r.status) return r.status;
    var stu = studentById(id);
    return stu ? stu.status : "started";
  }
  function showLoading() {
    $("app").innerHTML = '<div class="login-wrap"><div class="card"><h2>กำลังโหลด</h2><p class="muted">' + SCHOOL + " · ข้อมูลจำลอง</p></div></div>";
  }
  function ensureBanks() {
    window.APP_DATA.assessments = window.APP_DATA.assessments || {};
    var list = (window.ASSESS_002 && window.ASSESS_002.newInstruments) || [];
    list.forEach(function (inst) {
      if (inst.key === "potential_survey") window.APP_DATA.assessments.potentialSurvey = inst;
      if (inst.key === "cognition") window.APP_DATA.assessments.cognition = inst;
      if (inst.key === "study_habits") window.APP_DATA.assessments.studyHabits = inst;
    });
  }
  function trialFooter() {
    return '<p class="trial-foot">ใช้ภายใน' + SCHOOL + " · เป็นการทดลองภายใน รอผู้อำนวยการอนุมัติก่อนเผยแพร่นอกโรงเรียน · ข้อมูลผู้เรียนตัวอย่างเป็นข้อมูลจำลอง</p>";
  }
  async function loadData() {
    var data = await AssessApi.bootstrap(TOK);
    state.user = data.user;
    window.APP_DATA.students = data.students || [];
    window.APP_DATA.assessments = data.catalog || {};
    ensureBanks();
    STORE = data.store || emptyStore();
    ["answers", "progress", "reports", "teacherNotes", "parentHome", "personality"].forEach(function (k) {
      if (!STORE[k] || typeof STORE[k] !== "object") STORE[k] = {};
    });
  }
  async function reloadKeep() {
    var view = state.view, sel = state.selectedStudentId, quiz = state.quiz;
    await loadData();
    state.view = view;
    state.selectedStudentId = sel;
    state.quiz = quiz;
    if (sel && !studentById(sel)) state.selectedStudentId = visibleStudents()[0] && visibleStudents()[0].id;
  }

  function render() {
    var root = $("app");
    if (!state.user) {
      root.innerHTML = renderLogin() + trialFooter();
      bindLogin();
      return;
    }
    root.innerHTML =
      '<div class="app-header">' +
        "<div><h1>วิเคราะห์ผู้เรียนรายบุคคล" + headerSample() + "</h1>" +
        '<div class="sub">' + SCHOOL + " · " + esc(state.user.name) + " (" + roleName(state.user.role) + ")</div></div>" +
        '<div class="btn-row" style="margin:0"><button class="btn-secondary" id="btnLogout" style="width:auto">ออกจากระบบ</button></div>' +
      "</div>" +
      '<div class="layout"><nav class="sidebar" id="nav"></nav><main class="main" id="main"></main></div>' + trialFooter();
    $("btnLogout").onclick = logout;
    renderNav();
    renderMain();
  }
  function logout() {
    var t = TOK;
    TOK = null;
    sessionSet(null);
    state.user = null;
    state.view = "login";
    state.quiz = null;
    STORE = emptyStore();
    render();
    if (t) AssessApi.logout(t).catch(function () {});
  }
  function renderNav() {
    var items = [];
    var role = state.user.role;
    items.push(["home", "หน้าหลัก"]);
    if (role === "student") {
      items.push(["modules", "แบบวัดของฉัน"], ["exercises", "แบบฝึก"], ["personality", "พัฒนาบุคลิกภาพ"], ["myreport", "รายงานของฉัน"]);
    } else if (role === "parent") {
      items.push(["parenthome", "แบบสอบถามที่บ้าน"], ["myreport", "รายงานบุตรหลาน"]);
    } else if (role === "teacher" || role === "counselor") {
      items.push(["students", "รายชื่อผู้เรียน"], ["approve", "คิวอนุมัติรายงาน"], ["observe", "บันทึกสังเกต/รูบริก"], ["modules", "ดู/ทำแบบวัดแทนทดสอบ"], ["results", "ผลรวมทุกแบบวัด"]);
      if (role === "counselor") items.push(["psychview", "ผลแนะแนว"]);
    } else if (role === "admin") {
      items.push(["admin", "แดชบอร์ดผู้บริหาร"], ["students", "รายชื่อ (ภาพรวม)"], ["results", "ผลรวมทุกแบบวัด"]);
    }
    $("nav").innerHTML = items.map(function (it) {
      return '<button data-view="' + it[0] + '" class="' + (state.view === it[0] ? "active" : "") + '">' + it[1] + "</button>";
    }).join("");
    Array.prototype.forEach.call(document.querySelectorAll("#nav button"), function (btn) {
      btn.onclick = function () {
        state.view = btn.getAttribute("data-view");
        state.quiz = null;
        render();
      };
    });
  }
  function renderMain() {
    var map = {
      home: renderHome,
      modules: renderModules,
      quiz: renderQuiz,
      exercises: renderExercises,
      personality: renderPersonality,
      myreport: renderMyReport,
      parenthome: renderParentHome,
      students: renderStudents,
      approve: renderApprove,
      observe: renderObserve,
      psychview: renderPsychView,
      admin: renderAdmin,
      results: renderResults
    };
    var fn = map[state.view] || renderHome;
    $("main").innerHTML = fn();
    bindMain();
  }

  function renderLogin() {
    return '<div class="login-wrap"><div class="card">' +
      "<h2>เข้าสู่ระบบ</h2>" +
      '<p class="muted">' + SCHOOL + " · วิเคราะห์ผู้เรียนรายบุคคล · ข้อมูลจำลองทั้งหมด</p>" +
      "<h3>เลือกบทบาททดลองทันที</h3>" +
      '<div class="role-grid">' +
        roleQuick("admin", "ผู้บริหาร") +
        roleQuick("teacher", "ครูที่ปรึกษา") +
        roleQuick("counselor", "ครูแนะแนว") +
        roleQuick("parent-a", "ผู้ปกครอง เด็กชาย ก.") +
        roleQuick("student-a", "นักเรียน ด.ช.ตัวอย่าง ก.") +
        roleQuick("student-g", "นักเรียน ม.5 ตัวอย่าง") +
        roleQuick("parent-c", "ผู้ปกครอง ประถมต้น") +
        roleQuick("student-f", "นักเรียน ป.6 ตัวอย่าง") +
      "</div>" +
      "<h3>หรือใส่รหัสโรงเรียนจำลอง</h3>" +
      '<form id="loginForm">' +
      '<label for="loginUser">ชื่อผู้ใช้</label><input id="loginUser" type="text" placeholder="เช่น student-a" value="student-a" autocomplete="username">' +
      '<label for="loginPass">รหัสผ่าน</label><input id="loginPass" type="password" placeholder="demo" value="demo" autocomplete="current-password">' +
      '<div class="err" id="e"></div>' +
      '<div class="btn-row"><button class="btn-primary" id="btnLogin" type="submit" style="width:auto">เข้าสู่ระบบ</button></div>' +
      "</form>" +
      '<p class="muted" style="margin-top:12px">บัญชีทดลองทั้งหมดใช้รหัสผ่าน <strong>demo</strong> · ไม่ใช่บัญชีแอปคำศัพท์ · ไม่มีเลขบัตรประชาชน</p>' +
      "</div></div>";
  }
  function roleQuick(user, label) {
    return '<button type="button" class="role-btn" data-user="' + user + '" data-pass="demo">' + label + "</button>";
  }
  function bindLogin() {
    Array.prototype.forEach.call(document.querySelectorAll(".role-btn"), function (b) {
      b.onclick = function () { loginAs(b.getAttribute("data-user"), b.getAttribute("data-pass")); };
    });
    var form = $("loginForm");
    if (form) form.onsubmit = function (ev) {
      ev.preventDefault();
      loginAs($("loginUser").value.trim(), $("loginPass").value);
    };
  }
  async function loginAs(username, password) {
    var err = $("e");
    if (err) err.textContent = "";
    try {
      var d = await AssessApi.login(username, password);
      TOK = d.token;
      sessionSet(TOK);
      showLoading();
      await loadData();
      state.view = "home";
      state.quiz = null;
      state.selectedStudentId = visibleStudents()[0] && visibleStudents()[0].id;
      render();
      toast("เข้าสู่ระบบแล้ว: " + (state.user && state.user.name ? state.user.name : username));
    } catch (e) {
      TOK = null;
      sessionSet(null);
      state.user = null;
      render();
      var el = $("e");
      if (el) el.textContent = e.message || "เข้าสู่ระบบไม่สำเร็จ";
      else toast(e.message || "เข้าสู่ระบบไม่สำเร็จ");
    }
  }

  function renderHome() {
    var weights = window.APP_DATA.assessments.weights;
    var label = weights && weights.aptitude ? weights.aptitude.label : "";
    var cards = visibleStudents().map(function (s) {
      return '<div class="card" style="margin:0"><strong>' + esc(s.display) + "</strong> " + sampleTag(s) + "<br>" +
        '<span class="muted">' + esc(s.grade) + " · " + esc(s.code) + "</span><br>" +
        statusTag(reportStatus(s.id)) +
        '<div class="btn-row"><button class="btn-secondary" style="width:auto" data-pick="' + esc(s.id) + '">เลือก</button></div></div>';
    }).join("");
    return '<div class="card"><h2>หน้าหลัก</h2>' +
      "<p>สวัสดี " + esc(state.user.name) + " — เลือกผู้เรียนหรือไปที่เมนูด้านซ้าย</p>" +
      '<p class="muted">น้ำหนักการวิเคราะห์เป็น <strong>ข้อเสนอ</strong> ตามเอกสารออกแบบ · ' + esc(label) + "</p>" +
      '<div class="pillars">' +
        '<div class="pillar"><strong>ความถนัด</strong>แนวโน้ม/จุดเด่น</div>' +
        '<div class="pillar"><strong>ความสามารถ</strong>สิ่งที่ทำได้ตอนนี้</div>' +
        '<div class="pillar"><strong>ศักยภาพ</strong>ช่วงที่ส่งเสริมได้ (ไม่ติดป้ายชะตา)</div>' +
      "</div></div>" +
      '<div class="grid">' + cards + "</div>";
  }
  function renderStudents() {
    var rows = visibleStudents().map(function (s) {
      var p = progressOf(s.id);
      return "<tr><td>" + esc(s.display) + " " + sampleTag(s) + "</td><td>" + esc(s.grade) + "</td><td>" + esc(bandLabel(s.band)) +
        "</td><td>" + statusTag(reportStatus(s.id)) + "</td><td>" +
        (p.aptitude.pct || 0) + "% / " + (p.ability.pct || 0) + "%</td>" +
        '<td><button class="btn-secondary" style="width:auto;margin:0" data-pick="' + esc(s.id) + '">เปิด</button></td></tr>';
    }).join("");
    return '<div class="card"><h2>รายชื่อผู้เรียนจำลอง</h2>' +
      (state.user.role === "admin" ? '<p class="muted">ผู้บริหารเห็นรายชื่อเพื่อวางแผนภาพรวม — ผลจิตวิทยารายบุคคลไม่แสดงในแดชบอร์ดผู้บริหาร</p>' : "") +
      '<table class="table"><thead><tr><th>ชื่อ</th><th>ชั้น</th><th>ช่วงชั้น</th><th>สถานะ</th><th>ความคืบหน้า ถนัด/สามารถ</th><th></th></tr></thead><tbody>' +
      rows + "</tbody></table></div>";
  }
  function ensureStudent() {
    if (!state.selectedStudentId || !studentById(state.selectedStudentId)) {
      state.selectedStudentId = visibleStudents()[0] && visibleStudents()[0].id;
    }
    return studentById(state.selectedStudentId);
  }
  function studentPicker() {
    if (state.user.role === "student" || state.user.role === "parent") return "";
    var opts = visibleStudents().map(function (s) {
      return '<option value="' + esc(s.id) + '"' + (s.id === state.selectedStudentId ? " selected" : "") + ">" +
        esc(s.display) + " (" + esc(s.grade) + ")</option>";
    }).join("");
    return '<label for="stuPick">เลือกผู้เรียน</label><select id="stuPick">' + opts + "</select>";
  }
  function renderModules() {
    var stu = ensureStudent();
    if (!stu) return '<div class="card">ไม่พบผู้เรียน</div>';
    var p = progressOf(stu.id);
    var mods = [
      { key: "aptitude", title: "ความถนัด 10 ด้าน", desc: "กิจกรรมต้นฉบับด้านละหลายข้อ" },
      { key: "ability", title: "แบบทดสอบความสามารถ", desc: "ตามช่วงชั้น" },
      { key: "potential_survey", title: "แบบสำรวจศักยภาพที่ส่งเสริมได้", desc: "ช่วงที่ส่งเสริมได้ ไม่ใช่คะแนนคงที่" },
      { key: "cognition", title: "แบบสำรวจการคิดและเหตุผล", desc: "เครื่องมือต้นฉบับของโรงเรียน ไม่รายงานเป็นคะแนนคงที่" },
      { key: "study_habits", title: "แบบสำรวจนิสัยการเรียน", desc: "นิสัยการเรียนและความพร้อม" },
      { key: "psych", title: "แบบทดสอบทางจิตวิทยาเพื่อแนะแนว", desc: "แรงจูงใจ · รูปแบบการเรียน · จุดแข็งบุคลิกภาพ — ไม่ใช่เพื่อวินิจฉัยโรค" },
      { key: "exercises", title: "แบบฝึกสั้น", desc: "เห็นผลทันที" },
      { key: "personality", title: "โมดูลพัฒนาบุคลิกภาพ", desc: "กิจกรรมสั้น บันทึกความคืบหน้า" }
    ];
    if (stu.band === "upper_secondary") {
      mods.splice(1, 0, { key: "work", title: "กลุ่มลักษณะงาน 6 กลุ่ม", desc: "สถานการณ์สั้น (ไม่ใช่ข้อสอบลิขสิทธิ์)" });
    }
    return '<div class="card"><h2>ชุดแบบวัด — ' + esc(stu.display) + "</h2>" + sampleTag(stu) +
      '<p class="muted">' + esc(stu.grade) + " · " + esc(bandLabel(stu.band)) + " · รหัส " + esc(stu.code) + "</p>" +
      studentPicker() +
      mods.map(function (m) {
        var pr = p[m.key] || { pct: 0, done: false };
        return '<div class="q-card"><strong>' + m.title + "</strong>" +
          (pr.done ? ' <span class="tag ok">เสร็จ</span>' : ' <span class="tag warn">ค้างได้</span>') +
          '<div class="muted">' + m.desc + "</div>" +
          '<div class="progress"><span style="width:' + (pr.pct || 0) + '%"></span></div>' +
          '<button class="btn-primary" style="width:auto" data-start="' + m.key + '">' +
          (m.key === "exercises" || m.key === "personality" ? "เปิด" : "ทำต่อ / เริ่ม") + "</button></div>";
      }).join("") +
      '<div class="btn-row"><button class="btn-secondary" style="width:auto" id="btnGenDraft">สร้างร่างรายงานจากข้อมูลปัจจุบัน</button></div></div>';
  }
  function questionsFor(kind, stu) {
    var A = window.APP_DATA.assessments;
    var questions = [];
    if (kind === "aptitude") {
      A.aptitudes.forEach(function (d) {
        (A.aptitudeBank[d.id] || []).forEach(function (q) {
          questions.push(Object.assign({ domain: d.id, domainName: d.name }, q));
        });
      });
    } else if (kind === "work") {
      A.workGroups.forEach(function (d) {
        (A.workBank[d.id] || []).forEach(function (q) {
          questions.push(Object.assign({ domain: d.id, domainName: d.name }, q));
        });
      });
    } else if (kind === "ability") {
      questions = (A.abilityByBand[stu.band] || []).map(function (q) {
        return Object.assign({ domain: q.subject, domainName: q.subject }, q);
      });
    } else if (kind === "psych") {
      var labels = { motivation: "แรงจูงใจใฝ่เรียน", learning_style: "รูปแบบการเรียน", personality: "จุดแข็งบุคลิกภาพ" };
      ["motivation", "learning_style", "personality"].forEach(function (sec) {
        (A.psych[sec] || []).forEach(function (q) {
          questions.push(Object.assign({ domain: sec, domainName: labels[sec] }, q));
        });
      });
    } else if (kind === "potential_survey" || kind === "study_habits" || kind === "cognition") {
      var bank = kind === "potential_survey" ? A.potentialSurvey : kind === "study_habits" ? A.studyHabits : A.cognition;
      if (!bank) return questions;
      var names = {};
      (bank.facets || bank.domains || []).forEach(function (d) { names[d.id] = d.name; });
      (bank.items || []).forEach(function (q) {
        var dom = q.facet || q.domain;
        var item = Object.assign({ domain: dom, domainName: names[dom] || dom }, q);
        if (!item.options) item.options = bank.options;
        questions.push(item);
      });
    }
    return questions;
  }
  function startQuiz(kind) {
    if (kind === "exercises") { state.view = "exercises"; render(); return; }
    if (kind === "personality") { state.view = "personality"; render(); return; }
    var stu = ensureStudent();
    ensureBanks();
    var titles = {
      aptitude: "ความถนัด 10 ด้าน",
      work: "กลุ่มลักษณะงาน",
      ability: "ความสามารถตามช่วงชั้น",
      psych: "จิตวิทยาเพื่อแนะแนว",
      potential_survey: "แบบสำรวจศักยภาพที่ส่งเสริมได้",
      cognition: "แบบสำรวจการคิดและเหตุผล",
      study_habits: "แบบสำรวจนิสัยการเรียน"
    };
    state.quiz = { kind: kind, title: titles[kind] || kind, questions: questionsFor(kind, stu), index: 0 };
    state.view = "quiz";
    render();
  }
  function getAnswer(ans, kind, q) {
    if (!ans) return null;
    if (kind === "aptitude" || kind === "work" || kind === "psych" || kind === "potential_survey" || kind === "study_habits" || kind === "cognition") {
      return ans[kind] && ans[kind][q.domain] && ans[kind][q.domain][q.id];
    }
    if (kind === "ability") return ans.ability && ans.ability[q.id];
    return null;
  }
  function setAnswer(ans, kind, q, val) {
    if (kind === "aptitude" || kind === "work" || kind === "psych" || kind === "potential_survey" || kind === "study_habits" || kind === "cognition") {
      ans[kind] = ans[kind] || {};
      ans[kind][q.domain] = ans[kind][q.domain] || {};
      ans[kind][q.domain][q.id] = val;
    } else if (kind === "ability") {
      ans.ability = ans.ability || {};
      ans.ability[q.id] = val;
    }
  }
  function renderQuiz() {
    var qz = state.quiz;
    var stu = ensureStudent();
    if (!qz || !qz.questions.length) return renderModules();
    var i = qz.index;
    var q = qz.questions[i];
    var current = getAnswer(answersOf(stu.id), qz.kind, q);
    var pct = Math.round((i / qz.questions.length) * 100);
    var opts = (q.options || []).map(function (o) {
      var checked = String(current) === String(o.v) ? " checked" : "";
      return '<label class="opt"><input type="radio" name="opt" value="' + esc(o.v) + '"' + checked + "> " + esc(o.l) + "</label>";
    }).join("");
    return '<div class="card"><h2>' + esc(qz.title) + "</h2>" +
      '<p class="muted">' + esc(stu.display) + " " + sampleTag(stu) + " · ข้อ " + (i + 1) + "/" + qz.questions.length +
      (q.domainName ? " · " + esc(q.domainName) : "") + "</p>" +
      '<div class="progress"><span style="width:' + pct + '%"></span></div>' +
      '<div class="q-card"><strong>' + esc(q.text) + '</strong><div class="opts">' + opts + "</div></div>" +
      '<div class="btn-row">' +
      '<button class="btn-secondary" style="width:auto" id="btnQuizSave">บันทึกค้างไว้</button>' +
      '<button class="btn-secondary" style="width:auto" id="btnQuizPrev"' + (i === 0 ? " disabled" : "") + ">ก่อนหน้า</button>" +
      '<button class="btn-primary" style="width:auto" id="btnQuizNext">' + (i >= qz.questions.length - 1 ? "เสร็จสิ้น" : "ถัดไป") + "</button>" +
      '<button class="btn-secondary" style="width:auto" id="btnQuizBack">กลับรายการโมดูล</button>' +
      "</div>" +
      (qz.kind === "psych" ? '<p class="muted">แบบวัดนี้เพื่อแนะแนว ไม่ใช่เพื่อวินิจฉัยโรค</p>' : "") +
      (qz.kind === "cognition" ? '<p class="muted">' + esc((window.APP_DATA.assessments.cognition || {}).disclaimer || "") + "</p>" : "") +
      (qz.kind === "potential_survey" ? '<p class="muted">ผลเป็นช่วงศักยภาพที่ส่งเสริมได้ ไม่ใช่คะแนนคงที่</p>' : "") +
      "</div>";
  }
  async function persistQuiz(done) {
    var stu = ensureStudent();
    var qz = state.quiz;
    var ans = answersOf(stu.id);
    var sel = document.querySelector('input[name="opt"]:checked');
    if (sel) setAnswer(ans, qz.kind, qz.questions[qz.index], qz.kind === "cognition" ? sel.value : Number(sel.value));
    var answered = 0;
    qz.questions.forEach(function (q) {
      if (getAnswer(ans, qz.kind, q) != null) answered++;
    });
    var pct = Math.round((answered / qz.questions.length) * 100);
    var finished = !!done || pct >= 100;
    await AssessApi.saveModule(TOK, stu.id, qz.kind, ans[qz.kind] || {}, finished, pct);
    progressOf(stu.id)[qz.kind] = { done: finished, pct: pct };
  }

  function renderExercises() {
    var stu = ensureStudent();
    var list = (window.APP_DATA.assessments.exercises || {})[stu.band] || [];
    var saved = (answersOf(stu.id).exercises) || {};
    var html = list.map(function (ex) {
      return '<div class="q-card"><strong>' + esc(ex.title) + '</strong> <span class="tag">' + esc(ex.domain) + "</span>" +
        "<p>" + esc(ex.prompt) + "</p>" +
        '<input type="text" id="ex_' + esc(ex.id) + '" placeholder="คำตอบของคุณ" value="' + esc(saved[ex.id] || "") + '">' +
        '<div class="btn-row"><button class="btn-primary" style="width:auto" data-ex="' + esc(ex.id) + '">ตรวจทันที</button></div>' +
        '<div class="muted" id="exr_' + esc(ex.id) + '"></div></div>';
    }).join("");
    return '<div class="card"><h2>แบบฝึกสั้น — ' + esc(stu.display) + "</h2>" + sampleTag(stu) + studentPicker() + html + "</div>";
  }
  function renderPersonality() {
    var stu = ensureStudent();
    var saved = STORE.personality[stu.id] || {};
    var html = (window.APP_DATA.assessments.personalityActs || []).map(function (a) {
      var val = saved[a.id] == null ? "" : saved[a.id];
      if (a.type === "choice") {
        var opts = a.options.map(function (o) {
          return '<label class="opt"><input type="radio" name="' + esc(a.id) + '" value="' + esc(o.v) + '"' +
            (String(val) === String(o.v) ? " checked" : "") + "> " + esc(o.l) + "</label>";
        }).join("");
        return '<div class="q-card"><strong>' + esc(a.title) + "</strong><p>" + esc(a.prompt) + '</p><div class="opts">' + opts + "</div></div>";
      }
      return '<div class="q-card"><strong>' + esc(a.title) + "</strong><p>" + esc(a.prompt) + "</p>" +
        '<textarea rows="3" id="' + esc(a.id) + '">' + esc(val) + "</textarea></div>";
    }).join("");
    return '<div class="card"><h2>โมดูลพัฒนาบุคลิกภาพ</h2>' + sampleTag(stu) + studentPicker() + html +
      '<div class="btn-row"><button class="btn-primary" style="width:auto" id="btnSavePers">บันทึกความคืบหน้า</button></div></div>';
  }
  function renderParentHome() {
    var stu = ensureStudent();
    var saved = STORE.parentHome[stu.id] || {};
    var html = (window.APP_DATA.assessments.parentHome || []).map(function (q) {
      var opts = q.options.map(function (o) {
        return '<label class="opt"><input type="radio" name="' + esc(q.id) + '" value="' + esc(o.v) + '"' +
          (String(saved[q.id]) === String(o.v) ? " checked" : "") + "> " + esc(o.l) + "</label>";
      }).join("");
      return '<div class="q-card"><strong>' + esc(q.text) + '</strong><div class="opts">' + opts + "</div></div>";
    }).join("");
    return '<div class="card"><h2>แบบสอบถามพฤติกรรมที่บ้าน</h2>' +
      "<p class=\"muted\">สำหรับผู้ปกครองของ " + esc(stu.display) + " " + sampleTag(stu) + " — สำคัญมากโดยเฉพาะประถมต้น</p>" +
      html +
      '<div class="btn-row"><button class="btn-primary" style="width:auto" id="btnSaveParent">บันทึก</button></div></div>';
  }
  function renderObserve() {
    var stu = ensureStudent();
    var saved = STORE.teacherNotes[stu.id] || {};
    var html = (window.APP_DATA.assessments.teacherRubric || []).map(function (q) {
      if (q.type === "text") {
        return '<div class="q-card"><strong>' + esc(q.text) + '</strong><textarea rows="3" id="' + esc(q.id) + '">' + esc(saved[q.id] || "") + "</textarea></div>";
      }
      var opts = q.options.map(function (o) {
        return '<label class="opt"><input type="radio" name="' + esc(q.id) + '" value="' + esc(o.v) + '"' +
          (String(saved[q.id]) === String(o.v) ? " checked" : "") + "> " + esc(o.l) + "</label>";
      }).join("");
      return '<div class="q-card"><strong>' + esc(q.text) + '</strong><div class="opts">' + opts + "</div></div>";
    }).join("");
    return '<div class="card"><h2>บันทึกสังเกต / รูบริก</h2>' + sampleTag(stu) + studentPicker() + html +
      '<div class="btn-row"><button class="btn-primary" style="width:auto" id="btnSaveObs">บันทึก</button></div></div>';
  }
  function renderApprove() {
    var pending = visibleStudents().filter(function (s) {
      var r = STORE.reports[s.id];
      return r && r.status === "pending" && r.summary;
    });
    var html = pending.map(function (s) {
      var r = STORE.reports[s.id];
      return '<div class="card"><h3>' + esc(s.display) + " · " + esc(s.grade) + "</h3>" + sampleTag(s) +
        "<p>" + esc(r.summary) + "</p>" +
        '<label for="edit_' + esc(s.id) + '">แก้ข้อความสรุปก่อนอนุมัติ</label>' +
        '<textarea rows="3" id="edit_' + esc(s.id) + '">' + esc(r.summary) + "</textarea>" +
        '<div class="btn-row">' +
        '<button class="btn-primary" style="width:auto" data-approve="' + esc(s.id) + '">อนุมัติให้ผู้ปกครองเห็น</button>' +
        '<button class="btn-secondary" style="width:auto" data-pick="' + esc(s.id) + '">ดูรายละเอียด</button>' +
        "</div></div>";
    }).join("");
    if (!pending.length) html = '<p class="muted">ไม่มีคิวรออนุมัติตอนนี้ — สามารถสร้างร่างจากหน้ารายชื่อ/โมดูลได้</p>';
    return '<div class="card"><h2>คิวอนุมัติรายงาน</h2><p>ครูที่ปรึกษาหรือครูแนะแนวต้องแก้และอนุมัติก่อนผู้ปกครองเห็น</p></div>' + html;
  }
  function renderMyReport() {
    var stu = ensureStudent();
    if (!stu) return '<div class="card">ไม่พบผู้เรียน</div>';
    var r = STORE.reports[stu.id];
    var role = state.user.role;
    if (!r) {
      return '<div class="card"><h2>รายงาน</h2><p>ยังไม่มีรายงาน — ให้ทำแบบวัดหรือให้ครูสร้างร่าง</p>' +
        (role === "teacher" || role === "counselor" || role === "student"
          ? '<button class="btn-primary" style="width:auto" id="btnGenDraft">สร้างร่างรายงาน</button>' : "") +
        "</div>";
    }
    if ((role === "parent" || role === "student") && r.status !== "approved") {
      return '<div class="card"><h2>รายงาน</h2><p>รายงานยังรอครูอนุมัติ — ผู้ปกครองและนักเรียนยังไม่เห็นรายละเอียด</p>' +
        statusTag(r.status) + "</div>";
    }
    if (!r.summary || !r.aptitude) {
      return '<div class="card"><h2>รายงาน</h2><p>รายงานยังรอครูอนุมัติ — ผู้ปกครองและนักเรียนยังไม่เห็นรายละเอียด</p>' +
        statusTag(r.status || "pending") + "</div>";
    }
    return renderReportHTML(stu, r, role);
  }
  function renderReportHTML(stu, r, role) {
    var bars = (window.APP_DATA.assessments.aptitudes || []).map(function (d) {
      var sc = r.aptitude && r.aptitude[d.id] ? Number(r.aptitude[d.id].score) || 0 : 0;
      var pct = Math.round((sc / 5) * 100);
      return '<div class="bar-row"><div>' + esc(d.name) + '</div><div class="bar-track"><div class="bar-fill" style="width:' + pct + '%"></div></div><div>' + sc.toFixed(1) + "</div></div>";
    }).join("");
    var abilRows = Object.keys(r.ability || {}).map(function (s) {
      var a = r.ability[s];
      var score = Number(a.score) || 0;
      var level = (a.level && a.level.label) || "";
      return "<tr><td>" + esc(s) + "</td><td>" + score.toFixed(1) + '</td><td><span class="tag">' + esc(level) + "</span></td></tr>";
    }).join("");
    var paths = (r.pathways || []).map(function (p, i) {
      return "<li><strong>ทางที่ " + (i + 1) + ": " + esc(p.title) + "</strong><br><span class=\"muted\">" + esc(p.reason) + "</span></li>";
    }).join("");
    var psychBlock = "";
    if (role === "counselor" && r.psych && r.psych.learningStyle != null) {
      psychBlock = '<div class="card"><h3>ข้อมูลแนะแนว (เห็นเฉพาะครูแนะแนว)</h3>' +
        "<p>แรงจูงใจ: " + Number(r.psych.motivation).toFixed(1) + " · รูปแบบการเรียน: " + Number(r.psych.learningStyle).toFixed(1) +
        " · จุดแข็งบุคลิกภาพ: " + Number(r.psych.personality).toFixed(1) + "</p>" +
        '<p class="muted">' + esc(r.psych.note || "เพื่อแนะแนว ไม่ใช่เพื่อวินิจฉัยโรค") + " · ห้ามใส่ผลการวินิจฉัย</p></div>";
    } else if (role === "teacher" && r.psych) {
      var mot = Number(r.psych.motivation);
      psychBlock = '<div class="card"><h3>สัญญาณแนะแนว</h3><p class="muted">ครูที่ปรึกษาเห็นเฉพาะสัญญาณสรุป — รายละเอียดอยู่ที่ครูแนะแนว</p>' +
        "<p>แรงจูงใจโดยรวม: " + (mot >= 3 ? "อยู่ในเกณฑ์ที่ส่งเสริมต่อได้" : "ควรพบครูแนะแนวเพื่อพูดคุยเพิ่ม") + "</p></div>";
    }
    var plan = r.plan || { month: [], term: [] };
    var weightsLabel = r.potential && r.potential.weightsLabel;
    var growthLabel = r.potential && r.potential.growthLabel;
    var wAbility = window.APP_DATA.assessments.weights && window.APP_DATA.assessments.weights.ability;
    return '<div class="card report"><h2>รายงานผู้ปกครอง — ' + esc(stu.display) + "</h2>" +
      sampleTag(stu) + " " + statusTag(r.status) +
      ' <span class="tag">ความมั่นใจ: ' + esc(r.confidence && r.confidence.label) + "</span>" +
      (r.approvedBy ? ' <span class="tag ok">อนุมัติโดย ' + esc(r.approvedBy) + "</span>" : "") +
      "<h3>สรุป 1 หน้า</h3><p>" + esc(r.summary) + "</p>" +
      '<div class="strength"><strong>จุดแข็ง</strong><ol>' + (r.strengths || []).map(function (x) { return "<li>" + esc(x) + "</li>"; }).join("") + "</ol></div>" +
      '<div class="promote"><strong>สิ่งที่ควรส่งเสริม</strong><ol>' + (r.promote || []).map(function (x) { return "<li>" + esc(x) + "</li>"; }).join("") + "</ol></div>" +
      "<p><strong>ศักยภาพ:</strong> " + esc(r.potentialSentence) + "</p>" +
      (r.potentialSurvey && r.potentialSurvey.sentence ? "<p><strong>แบบสำรวจศักยภาพที่ส่งเสริมได้:</strong> " + esc(r.potentialSurvey.sentence) + "</p>" : "") +
      (r.cognition && r.cognition.sentence ? "<p><strong>แบบสำรวจการคิดและเหตุผล:</strong> " + esc(r.cognition.sentence) + "</p>" : "") +
      (r.studyHabits && r.studyHabits.sentence ? "<p><strong>แบบสำรวจนิสัยการเรียน:</strong> " + esc(r.studyHabits.sentence) + "</p>" : "") +
      "<p><strong>สิ่งที่โรงเรียนทำ:</strong> " + (r.schoolDoes || []).map(esc).join(" · ") + "</p>" +
      "<p><strong>สิ่งที่บ้านช่วยได้:</strong> " + (r.homeDoes || []).map(esc).join(" · ") + "</p>" +
      (stu.band === "early_primary" ? '<p class="muted">รายงานประถมต้นย่อตามช่วงวัย</p>' : "") +
      "</div>" +
      '<div class="card"><h3>แผนภาพความถนัด 10 ด้าน</h3><div class="bar-chart">' + bars + "</div>" +
      '<p class="muted">' + esc(window.APP_DATA.assessments.weights.aptitude.label) + "</p></div>" +
      '<div class="card"><h3>ความสามารถเทียบเกณฑ์ชั้น</h3><table class="table"><thead><tr><th>วิชา/ด้าน</th><th>คะแนน (ข้อเสนอ)</th><th>ระดับ</th></tr></thead><tbody>' +
      abilRows + "</tbody></table>" +
      '<p class="muted">' + esc(wAbility ? wAbility.label : "") + "</p></div>" +
      '<div class="card"><h3>เส้นทางรายบุคคล 2–3 ทาง</h3><ol>' + paths + "</ol>" +
      (stu.band === "lower_secondary" ? '<p class="muted">' + esc(window.APP_DATA.assessments.tracks.note) + "</p>" : "") +
      (stu.band === "upper_secondary" ? '<p class="muted">แผน TCAS เป็นข้อเสนอ รอปฏิทินจริง</p>' : "") +
      "</div>" +
      '<div class="card"><h3>แผนส่งเสริม</h3><p><strong>รายเดือน:</strong></p><ul>' +
      (plan.month || []).map(function (x) { return "<li>" + esc(x) + "</li>"; }).join("") +
      "</ul><p><strong>รายเทอม:</strong></p><ul>" +
      (plan.term || []).map(function (x) { return "<li>" + esc(x) + "</li>"; }).join("") +
      '</ul><p class="muted">' + esc(weightsLabel || "") + " · " + esc(growthLabel || "") + "</p></div>" +
      psychBlock;
  }
  function renderPsychView() {
    var stu = ensureStudent();
    var r = STORE.reports[stu.id];
    if (!r || !r.psych || r.psych.learningStyle == null) {
      if (stu && stu.seed && state.user.role === "counselor") {
        r = Analyzer.buildReport(stu, answersOf(stu.id), progressOf(stu.id), null);
      }
    }
    if (!r || !r.psych) return '<div class="card"><h2>ผลแนะแนวรายบุคคล</h2><p>ยังไม่มีผลให้แสดง</p></div>';
    return '<div class="card"><h2>ผลแนะแนวรายบุคคล</h2>' + studentPicker() + sampleTag(stu) +
      "<p>เห็นเฉพาะครูแนะแนว · เพื่อแนะแนว ไม่ใช่เพื่อวินิจฉัยโรค</p>" +
      "<p>แรงจูงใจ: <strong>" + Number(r.psych.motivation).toFixed(2) + "</strong></p>" +
      "<p>รูปแบบการเรียน: <strong>" + Number(r.psych.learningStyle || 0).toFixed(2) + "</strong></p>" +
      "<p>จุดแข็งบุคลิกภาพ: <strong>" + Number(r.psych.personality || 0).toFixed(2) + "</strong></p>" +
      '<p class="muted">หากพบสัญญาณที่ควรส่งต่อผู้เชี่ยวชาญ ให้บันทึกและส่งต่อ — ห้ามใส่ผลการวินิจฉัยในรายงานผู้ปกครอง</p></div>';
  }
  function renderAdmin() {
    var simulated = { early_primary: 42, late_primary: 48, lower_secondary: 55, upper_secondary: 51 };
    var rows = Object.keys(simulated).map(function (b) {
      var n = simulated[b];
      var show = n >= 10 ? n + " คน (ตัวเลขภาพรวมจำลอง)" : "ไม่แสดงกลุ่มที่น้อยกว่า 10 คน";
      return "<tr><td>" + esc(bandLabel(b)) + "</td><td>" + show + "</td><td>วางครู / ชมรม / ค่าย / สอนเสริม</td></tr>";
    }).join("");
    var smallDemo = visibleStudents().length;
    return '<div class="card"><h2>แดชบอร์ดผู้บริหาร</h2>' +
      "<p>ภาพรวมระดับชั้นเพื่อวางครู ชมรม ค่าย สอนเสริม</p>" +
      '<p class="tag">ห้ามแสดงผลจิตวิทยารายบุคคล</p> ' +
      '<p class="tag warn">ข้อเสนอ: ไม่แสดงกลุ่มที่น้อยกว่า 10 คน</p>' +
      '<table class="table"><thead><tr><th>ช่วงชั้น</th><th>จำนวนในภาพรวม</th><th>การใช้ประโยชน์</th></tr></thead><tbody>' +
      rows + "</tbody></table>" +
      '<div class="q-card"><strong>ตัวอย่างกฎกลุ่มเล็ก</strong><p>รายชื่อจำลองมี ' + smallDemo +
      " คน — หากนับเป็นกลุ่มเดียวที่น้อยกว่า 10 คน ระบบจะแสดงข้อความว่า «ไม่แสดงกลุ่มที่น้อยกว่า 10 คน» แทนการเปิดเผยรายละเอียดที่ระบุตัวตนได้ง่าย</p>" +
      (smallDemo < 10 ? '<p class="tag warn">ไม่แสดงกลุ่มที่น้อยกว่า 10 คน</p>' : "") +
      "</div>" +
      "<h3>สถานะรายงาน (ภาพรวม ไม่มีผลจิตวิทยา)</h3>" +
      adminStatusTable() +
      "</div>";
  }
  function adminStatusTable() {
    var counts = { approved: 0, pending: 0, incomplete: 0, started: 0 };
    visibleStudents().forEach(function (s) {
      var st = reportStatus(s.id);
      counts[st] = (counts[st] || 0) + 1;
    });
    return '<table class="table"><thead><tr><th>สถานะ</th><th>จำนวน (จำลอง)</th></tr></thead><tbody>' +
      ["approved", "pending", "incomplete", "started"].map(function (k) {
        return "<tr><td>" + statusTag(k) + "</td><td>" + (counts[k] || 0) + "</td></tr>";
      }).join("") + "</tbody></table>";
  }

  var INSTRUMENT_ORDER = [
    ["aptitude", "ความถนัด"],
    ["ability", "ความสามารถ"],
    ["work", "กลุ่มลักษณะงาน"],
    ["potential_survey", "แบบสำรวจศักยภาพที่ส่งเสริมได้"],
    ["cognition", "แบบสำรวจการคิดและเหตุผล"],
    ["study_habits", "แบบสำรวจนิสัยการเรียน"],
    ["psych", "จิตวิทยาเพื่อแนะแนว"],
    ["exercises", "แบบฝึกสั้น"],
    ["personality", "พัฒนาบุคลิกภาพ"],
    ["parentHome", "แบบสอบถามที่บ้าน"],
    ["teacherRubric", "บันทึกสังเกต/รูบริก"]
  ];
  function fmtScore(n) { return n == null || n === "" || isNaN(Number(n)) ? "—" : Number(n).toFixed(1); }
  function renderResults() {
    var role = state.user.role;
    return '<div class="card"><h2>ผลรวมทุกแบบวัด</h2>' +
      (role === "admin"
        ? '<p class="muted">ผลรายคนของข้อมูลจำลอง ไม่แสดงผลจิตวิทยารายบุคคล แดชบอร์ดภาพรวมยังไม่แสดงกลุ่มที่น้อยกว่า 10 คน</p>'
        : '<p class="muted">รวมทุกแบบวัดที่เก็บไว้ของนักเรียนที่เลือก</p>') +
      studentPicker() +
      '<div id="resultsBody"><p class="muted">กำลังโหลด</p></div></div>';
  }
  function instrumentBlock(key, fallback, data) {
    data = data || {};
    var title = data.title || fallback;
    var prog = data.progress;
    var progTxt = "";
    if (prog) progTxt = (prog.done ? "ทำแล้ว" : "ค้าง") + " " + (prog.pct || 0) + "%";
    else if (data.available === false) progTxt = "ยังไม่เปิดในรายงานนี้";
    var lines = "";
    if (Array.isArray(data.domains)) {
      lines += "<ul>" + data.domains.map(function (d) {
        if (d.percent != null) return "<li>" + esc(d.name) + " " + d.percent + "% · " + esc(d.label) + "</li>";
        if (d.score != null) return "<li>" + esc(d.name) + " " + fmtScore(d.score) + (d.level ? " · " + esc(d.level) : "") + "</li>";
        return "<li>" + esc(d.name || d.id) + " ยังไม่ทำ</li>";
      }).join("") + "</ul>";
    }
    if (data.overall && data.overall.label) {
      lines += "<p>ภาพรวม: " + esc(data.overall.label) + (data.overall.percent != null ? " (" + data.overall.percent + "%)" : "") + "</p>";
    }
    if (data.range) lines += "<p>" + esc(data.range) + "</p>";
    if (data.sentence) lines += "<p>" + esc(data.sentence) + "</p>";
    if (data.mean != null && key === "study_habits") lines += "<p>ค่าเฉลี่ย " + fmtScore(data.mean) + "</p>";
    if (data.hidden) lines += '<p class="muted">' + esc(data.note || "ไม่แสดง") + "</p>";
    if (data.visibility === "signal") lines += "<p>" + esc(data.motivationSignal || "") + "</p><p class=\"muted\">" + esc(data.note || "") + "</p>";
    if (data.visibility === "full") {
      lines += "<p>แรงจูงใจ " + fmtScore(data.motivation) + " · รูปแบบการเรียน " + fmtScore(data.learningStyle) + " · จุดแข็งบุคลิกภาพ " + fmtScore(data.personality) + "</p>";
      lines += '<p class="muted">' + esc(data.note || "") + "</p>";
    }
    if (data.answered != null && (key === "parentHome" || key === "teacherRubric")) lines += "<p>บันทึกแล้ว " + data.answered + " ข้อ</p>";
    return '<div class="q-card"><strong>' + esc(title) + "</strong> " + (progTxt ? '<span class="tag">' + esc(progTxt) + "</span>" : "") + lines + "</div>";
  }
  function renderExport(payload) {
    var inst = (payload && payload.instruments) || {};
    var blocks = INSTRUMENT_ORDER.map(function (pair) { return instrumentBlock(pair[0], pair[1], inst[pair[0]]); }).join("");
    var disc = (window.APP_DATA.assessments.cognition || {}).disclaimer || "";
    return blocks +
      '<div class="disclaimer"><strong>แบบสำรวจการคิดและเหตุผล</strong><p>' + esc(disc) + "</p></div>" +
      '<div class="btn-row"><button type="button" class="btn-primary" style="width:auto" id="btnDl">ดาวน์โหลด JSON</button>' +
      '<button type="button" class="btn-secondary" style="width:auto" id="btnCopy">คัดลอกข้อความสรุปภาษาไทย</button></div>';
  }
  function thaiSummary(payload) {
    var lines = [
      "ผลรวมทุกแบบวัด — " + (payload.display || payload.name || ""),
      (payload.code ? "รหัส " + payload.code + " · " : "") + (payload.grade || ""),
      SCHOOL,
      ""
    ];
    var inst = payload.instruments || {};
    INSTRUMENT_ORDER.forEach(function (pair) {
      var d = inst[pair[0]] || {};
      var bit = pair[1];
      if (d.progress) bit += " · " + (d.progress.done ? "ทำแล้ว" : "ค้าง") + " " + (d.progress.pct || 0) + "%";
      if (d.range) bit += " — " + d.range;
      if (d.sentence) bit += " — " + d.sentence;
      if (d.overall && d.overall.label) bit += " — ภาพรวม " + d.overall.label;
      if (Array.isArray(d.domains) && d.domains.length) {
        bit += " — " + d.domains.map(function (x) {
          if (x.label) return (x.name || x.id) + " " + x.label;
          if (x.score != null) return (x.name || x.id) + " " + fmtScore(x.score);
          return (x.name || x.id) + " ยังไม่ทำ";
        }).join(", ");
      }
      if (d.hidden) bit += " — " + (d.note || "ไม่แสดง");
      if (d.visibility === "signal") bit += " — " + (d.motivationSignal || "");
      lines.push(bit);
    });
    lines.push("");
    lines.push((window.APP_DATA.assessments.cognition || {}).disclaimer || "");
    return lines.join("\n");
  }
  function fallbackCopy(text) {
    var ta = document.createElement("textarea");
    ta.value = text;
    document.body.appendChild(ta);
    ta.select();
    try { document.execCommand("copy"); toast("คัดลอกข้อความสรุปแล้ว"); }
    catch (e) { toast("คัดลอกไม่สำเร็จ"); }
    ta.remove();
  }
  function loadResults() {
    var box = $("resultsBody");
    if (!box) return;
    var stu = ensureStudent();
    if (!stu) { box.textContent = "ไม่พบผู้เรียน"; return; }
    AssessApi.exportResults(TOK, stu.id).then(function (payload) {
      var host = $("resultsBody");
      if (!host) return;
      host.innerHTML = renderExport(payload);
      var dl = $("btnDl");
      if (dl) dl.onclick = function () {
        var blob = new Blob([JSON.stringify(payload, null, 2)], { type: "application/json" });
        var a = document.createElement("a");
        a.href = URL.createObjectURL(blob);
        a.download = "assess-results-" + stu.id + ".json";
        a.click();
        setTimeout(function () { URL.revokeObjectURL(a.href); }, 1000);
      };
      var cp = $("btnCopy");
      if (cp) cp.onclick = function () {
        var text = thaiSummary(payload);
        if (navigator.clipboard && navigator.clipboard.writeText) {
          navigator.clipboard.writeText(text).then(function () { toast("คัดลอกข้อความสรุปแล้ว"); }, function () { fallbackCopy(text); });
        } else fallbackCopy(text);
      };
    }).catch(function (e) {
      var host = $("resultsBody");
      if (host) host.innerHTML = '<p class="err">' + esc(e.message || "โหลดไม่สำเร็จ") + "</p>";
    });
  }
  function collectForm(items, textIds) {
    var values = {};
    items.forEach(function (q) {
      if (q.type === "text" || (textIds && textIds[q.id])) {
        var el = $(q.id);
        if (el) values[q.id] = el.value;
      } else {
        var sel = document.querySelector('input[name="' + q.id + '"]:checked');
        if (sel) values[q.id] = Number(sel.value);
      }
    });
    return values;
  }
  async function genDraft(stuId) {
    var stu = studentById(stuId || state.selectedStudentId);
    if (!stu) throw new Error("ไม่พบผู้เรียน");
    var rep = Analyzer.buildReport(stu, answersOf(stu.id), progressOf(stu.id), null);
    await AssessApi.saveReport(TOK, stu.id, rep);
    await reloadKeep();
    toast("สร้างร่างรายงานแล้ว — รอครูอนุมัติ");
    render();
  }
  function bindMain() {
    var pick = $("stuPick");
    if (pick) pick.onchange = function () { state.selectedStudentId = pick.value; render(); };
    Array.prototype.forEach.call(document.querySelectorAll("[data-pick]"), function (b) {
      b.onclick = function () {
        state.selectedStudentId = b.getAttribute("data-pick");
        var role = state.user.role;
        state.view = role === "admin" ? "students" : "modules";
        if (role === "parent") state.view = "myreport";
        render();
      };
    });
    Array.prototype.forEach.call(document.querySelectorAll("[data-start]"), function (b) {
      b.onclick = function () { startQuiz(b.getAttribute("data-start")); };
    });
    var back = $("btnQuizBack");
    if (back) back.onclick = guard(async function () {
      await persistQuiz(false);
      state.view = "modules";
      state.quiz = null;
      render();
    });
    var save = $("btnQuizSave");
    if (save) save.onclick = guard(async function () {
      await persistQuiz(false);
      toast("บันทึกค้างไว้แล้ว");
    });
    var prev = $("btnQuizPrev");
    if (prev) prev.onclick = guard(async function () {
      await persistQuiz(false);
      state.quiz.index = Math.max(0, state.quiz.index - 1);
      render();
    });
    var next = $("btnQuizNext");
    if (next) next.onclick = guard(async function () {
      var finishing = state.quiz.index >= state.quiz.questions.length - 1;
      await persistQuiz(finishing);
      if (finishing) {
        toast("ทำชุดนี้เสร็จแล้ว");
        state.view = "modules";
        state.quiz = null;
        render();
        return;
      }
      state.quiz.index++;
      render();
    });
    Array.prototype.forEach.call(document.querySelectorAll("[data-ex]"), function (b) {
      b.onclick = guard(async function () {
        var id = b.getAttribute("data-ex");
        var stu = ensureStudent();
        var ex = ((window.APP_DATA.assessments.exercises || {})[stu.band] || []).find(function (x) { return x.id === id; });
        var val = ($("ex_" + id).value || "").trim();
        var ok = val && ex && ex.answer && (val.indexOf(ex.answer.split(" ")[0]) >= 0 || ex.answer.indexOf(val) >= 0 || val === ex.answer);
        $("exr_" + id).innerHTML = ok
          ? '<span class="tag ok">ถูกต้อง / ใกล้เคียง — เก่งมาก</span>'
          : '<span class="tag warn">ลองใหม่ — คำใบ้: ' + esc(ex.hint) + " · แนวคำตอบ: " + esc(ex.answer) + "</span>";
        var ans = answersOf(stu.id);
        ans.exercises = ans.exercises || {};
        if (val) ans.exercises[id] = val;
        await AssessApi.saveModule(TOK, stu.id, "exercises", ans.exercises, true, 100);
        progressOf(stu.id).exercises = { done: true, pct: 100 };
      });
    });
    var bp = $("btnSavePers");
    if (bp) bp.onclick = guard(async function () {
      var stu = ensureStudent();
      var values = collectForm(window.APP_DATA.assessments.personalityActs || []);
      await AssessApi.saveForm(TOK, stu.id, "personality", values);
      await reloadKeep();
      toast("บันทึกโมดูลบุคลิกภาพแล้ว");
      render();
    });
    var bpar = $("btnSaveParent");
    if (bpar) bpar.onclick = guard(async function () {
      var stu = ensureStudent();
      var values = collectForm(window.APP_DATA.assessments.parentHome || []);
      await AssessApi.saveForm(TOK, stu.id, "parent", values);
      await reloadKeep();
      toast("บันทึกแบบสอบถามผู้ปกครองแล้ว");
      render();
    });
    var bobs = $("btnSaveObs");
    if (bobs) bobs.onclick = guard(async function () {
      var stu = ensureStudent();
      var values = collectForm(window.APP_DATA.assessments.teacherRubric || []);
      await AssessApi.saveForm(TOK, stu.id, "rubric", values);
      await reloadKeep();
      toast("บันทึกสังเกตแล้ว");
      render();
    });
    var bg = $("btnGenDraft");
    if (bg) bg.onclick = guard(function () { return genDraft(state.selectedStudentId); });
    Array.prototype.forEach.call(document.querySelectorAll("[data-approve]"), function (b) {
      b.onclick = guard(async function () {
        var id = b.getAttribute("data-approve");
        var edit = $("edit_" + id);
        var summary = edit ? edit.value.trim() : "";
        if (!summary) { toast("กรุณาเขียนสรุปก่อนอนุมัติ"); return; }
        await AssessApi.approve(TOK, id, summary);
        await reloadKeep();
        toast("อนุมัติรายงานแล้ว — ผู้ปกครองมองเห็นได้");
        render();
      });
    });
    loadResults();
  }

  document.addEventListener("DOMContentLoaded", function () {
    if (!TOK) { render(); return; }
    showLoading();
    loadData().then(function () {
      state.view = "home";
      state.selectedStudentId = visibleStudents()[0] && visibleStudents()[0].id;
      render();
    }).catch(function (e) {
      TOK = null;
      sessionSet(null);
      state.user = null;
      render();
      if (!e || (String(e.code || "").indexOf("NO_SESSION") < 0 && String(e.message || "").indexOf("หมดเวลา") < 0)) {
        var el = $("e");
        if (el) el.textContent = e.message;
      }
    });
  });
})();
