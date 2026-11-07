/* เครื่องวิเคราะห์ 3 เสา — ตัวเลขน้ำหนักเป็นข้อเสนอตามเอกสารออกแบบ */
(function (global) {
  function clamp(n, a, b) { return Math.max(a, Math.min(b, n)); }
  function avg(arr) {
    if (!arr || !arr.length) return 0;
    return arr.reduce(function (s, x) { return s + x; }, 0) / arr.length;
  }
  function levelAbility(score) {
    if (score >= 3.2) return { key: "met", label: "ถึงระดับ" };
    if (score >= 2.2) return { key: "developing", label: "กำลังพัฒนา" };
    return { key: "support", label: "ต้องเสริม" };
  }
  function potentialBand(score) {
    if (score >= 4.0) return "ช่วงสูงที่ส่งเสริมต่อได้ดี หากมีแผนต่อเนื่อง";
    if (score >= 3.0) return "ช่วงกลาง–สูง ที่ส่งเสริมตรงจุดแล้วจะเห็นการเติบโตชัด";
    if (score >= 2.0) return "ช่วงที่ยังส่งเสริมได้หลายด้าน ควรเก็บข้อมูลเพิ่มและฝึกสม่ำเสมอ";
    return "ช่วงเริ่มต้นของการส่งเสริม เน้นสร้างนิสัยและแรงจูงใจ ไม่ติดป้ายจำกัดชะตา";
  }
  function confidence(stu, progress) {
    var needed = ["aptitude", "ability", "psych"];
    var done = 0;
    needed.forEach(function (k) {
      if (progress && progress[k] && progress[k].done) done++;
    });
    if (stu.status === "approved" || stu.status === "pending") done = Math.max(done, 2);
    if (stu.seed && stu.seed.observe) done = Math.max(done, 2);
    return done >= 2
      ? { key: "enough", label: "ข้อมูลเพียงพอ (ข้อเสนอ)" }
      : { key: "more", label: "ควรเก็บเพิ่ม (ข้อเสนอ)" };
  }
  function computeAptitude(stu, answers) {
    var w = global.APP_DATA.assessments.weights.aptitude;
    var domains = global.APP_DATA.assessments.aptitudes;
    var out = {};
    domains.forEach(function (d) {
      var seed = (stu.seed && stu.seed.apt && stu.seed.apt[d.id]) || 3;
      var actScores = [];
      if (answers && answers.aptitude && answers.aptitude[d.id]) {
        Object.keys(answers.aptitude[d.id]).forEach(function (qid) {
          actScores.push(Number(answers.aptitude[d.id][qid]));
        });
      }
      var activity = actScores.length ? avg(actScores) : seed;
      var observe = (stu.seed && stu.seed.observe) || 3;
      var portfolio = (stu.seed && stu.seed.portfolio) || 3;
      var score = activity * w.activity + observe * w.observeParent + portfolio * w.portfolio;
      // normalize observe/portfolio roughly 1-5
      out[d.id] = { name: d.name, score: clamp(score, 1, 5), activity: activity };
    });
    return out;
  }
  function computeAbility(stu, answers) {
    var w = global.APP_DATA.assessments.weights.ability;
    var bank = global.APP_DATA.assessments.abilityByBand[stu.band] || [];
    var bySubj = {};
    bank.forEach(function (q) {
      if (!bySubj[q.subject]) bySubj[q.subject] = [];
      var v = null;
      if (answers && answers.ability && answers.ability[q.id] != null) v = Number(answers.ability[q.id]);
      else if (stu.seed && stu.seed.ability && stu.seed.ability[q.subject] != null) v = Number(stu.seed.ability[q.subject]);
      if (v != null) bySubj[q.subject].push(v);
    });
    var out = {};
    Object.keys(bySubj).forEach(function (s) {
      var test = avg(bySubj[s]);
      var portfolio = (stu.seed && stu.seed.portfolio) || 3;
      // portfolio is 1-5, ability options 1-4 → scale portfolio to 1-4
      var port4 = portfolio * 0.8;
      var score = test * w.test + port4 * w.portfolio;
      out[s] = { score: clamp(score, 1, 4), level: levelAbility(score) };
    });
    return out;
  }
  function computePsych(stu, answers) {
    function meanPrefix(obj, fallback) {
      if (!obj) return fallback;
      var vals = Object.keys(obj).map(function (k) { return Number(obj[k]); });
      return vals.length ? avg(vals) : fallback;
    }
    var mot = meanPrefix(answers && answers.psych && answers.psych.motivation, stu.seed && stu.seed.motivation);
    var ls = meanPrefix(answers && answers.psych && answers.psych.learning_style, 3.5);
    var pe = meanPrefix(answers && answers.psych && answers.psych.personality, 3.5);
    return {
      motivation: clamp(mot || 3.5, 1, 5),
      learningStyle: clamp(ls || 3.5, 1, 5),
      personality: clamp(pe || 3.5, 1, 5),
      note: "เพื่อแนะแนว ไม่ใช่เพื่อวินิจฉัยโรค"
    };
  }
  function computeWork(stu, answers) {
    if (stu.band !== "upper_secondary") return null;
    var out = {};
    global.APP_DATA.assessments.workGroups.forEach(function (g) {
      var seed = (stu.seed && stu.seed.work && stu.seed.work[g.id]) || 3;
      var scores = [];
      if (answers && answers.work && answers.work[g.id]) {
        Object.keys(answers.work[g.id]).forEach(function (qid) {
          scores.push(Number(answers.work[g.id][qid]));
        });
      }
      out[g.id] = { name: g.name, score: clamp(scores.length ? avg(scores) : seed, 1, 5) };
    });
    return out;
  }
  function computePotential(stu, apt, abil, psych) {
    var w = global.APP_DATA.assessments.weights.potential;
    var aptAvg = avg(Object.keys(apt).map(function (k) { return apt[k].score; }));
    var abilAvg = avg(Object.keys(abil).map(function (k) { return abil[k].score; })) || 2.5;
    // scale ability 1-4 to 1-5
    var abil5 = abilAvg * 1.25;
    var growth = ((stu.seed && stu.seed.growth) || 0.5) * 5; // 0-1 → 0-5
    var gap = clamp(aptAvg - abil5 + 3, 1, 5); // positive gap = room to grow
    var mot = psych.motivation;
    var resp = (stu.seed && stu.seed.response) || 3.5;
    var score = growth * w.growth + gap * w.gap + mot * w.motivation + resp * w.response;
    return {
      score: clamp(score, 1, 5),
      band: potentialBand(score),
      aptAvg: aptAvg,
      abilAvg: abilAvg,
      growthLabel: "อัตราพัฒนา (ข้อมูลจำลอง)",
      weightsLabel: w.label
    };
  }
  function topN(map, n, key) {
    return Object.keys(map)
      .map(function (k) { return map[k]; })
      .sort(function (a, b) { return b.score - a.score; })
      .slice(0, n);
  }
  function pathways(stu, apt, abil, work) {
    var band = stu.band;
    var tops = topN(apt, 3);
    var paths = [];
    if (band === "early_primary") {
      paths = [
        { title: "แนวส่งเสริมพัฒนาการด้าน" + tops[0].name, reason: "เห็นจุดเด่นจากการเล่นมีโครงสร้างและการสังเกต — ไม่ล็อกอาชีพ", type: "พัฒนาการ" },
        { title: "แนวส่งเสริมการอยู่ร่วมกันและการสื่อสาร", reason: "สร้างพื้นฐานการเรียนและการเข้าสังคมช่วงต้น", type: "พัฒนาการ" },
        { title: "แนวสำรวจความสนใจผ่านกิจกรรมสั้น", reason: "ให้เด็กได้ลองหลายด้านอย่างปลอดภัย", type: "สำรวจ" }
      ];
    } else if (band === "late_primary") {
      paths = [
        { title: "สำรวจความสนใจด้าน" + tops[0].name + " และ " + (tops[1] && tops[1].name), reason: "จุดเด่นจากการทำกิจกรรม — ไม่ล็อกอาชีพ", type: "สำรวจ" },
        { title: "เสริมทักษะพื้นฐานวิชาการควบคู่ความสนใจ", reason: "เตรียมความพร้อมช่วงเปลี่ยนระดับโดยไม่บีบทางเดียว", type: "สำรวจ" },
        { title: "เส้นทางชมรม/ค่ายตามความสนใจ (ทางเลือก)", reason: "ให้ลองกิจกรรมนอกห้องเรียน", type: "ทางเลือก" }
      ];
    } else if (band === "lower_secondary") {
      var tracks = global.APP_DATA.assessments.tracks.lower_secondary;
      var sci = (apt.science && apt.science.score || 0) + (apt.logic && apt.logic.score || 0);
      var art = (apt.lang && apt.lang.score || 0) + (apt.art && apt.art.score || 0);
      var calc = (apt.logic && apt.logic.score || 0) + (apt.lang && apt.lang.score || 0);
      var ranked = [
        { title: tracks[0] + " (ข้อเสนอ รอยืนยันชื่อสายจริง)", score: sci, reason: "เด่นด้านวิทยาศาสตร์/ตรรกะจากแบบวัดและความสามารถ" },
        { title: tracks[1] + " (ข้อเสนอ รอยืนยันชื่อสายจริง)", score: calc, reason: "สมดุลตรรกะกับภาษา เหมาะสายคำนวณ" },
        { title: tracks[2] + " (ข้อเสนอ รอยืนยันชื่อสายจริง)", score: art, reason: "เด่นด้านภาษา/สร้างสรรค์" }
      ].sort(function (a, b) { return b.score - a.score; });
      paths = ranked.map(function (r) { return { title: "แนวเลือกสาย ม.ปลาย: " + r.title, reason: r.reason, type: "สาย ม.ปลาย" }; });
    } else {
      var wtop = work ? topN(work, 2) : [];
      paths = [
        { title: "แนวคณะ/ลักษณะงาน: " + (wtop[0] && wtop[0].name || "วิเคราะห์ข้อมูล") + " (ข้อเสนอ)", reason: "สอดคล้องกลุ่มลักษณะงานและจุดเด่นความถนัด", type: "คณะ/งาน" },
        { title: "แผน TCAS แบบข้อเสนอ (รอปฏิทินจริง)", reason: "เตรียมวิชาแกนตามเป้าหมาย + เส้นทบทวนรายภาค", type: "TCAS" },
        { title: "เส้นทางสำรอง: " + (wtop[1] && wtop[1].name || "ช่วยเหลือผู้อื่น"), reason: "เผื่อปรับเป้าหมายโดยไม่ทิ้งจุดแข็ง", type: "สำรอง" }
      ];
    }
    return paths.slice(0, 3);
  }
  function monthPlan(stu, tops) {
    var a = tops[0] && tops[0].name || "จุดแข็ง";
    var b = tops[1] && tops[1].name || "ด้านที่สนใจ";
    if (stu.band === "early_primary") {
      return {
        month: ["กิจกรรมเล่นมีโครงสร้างด้าน" + a + " สัปดาห์ละ 2 ครั้ง", "อ่าน/เล่าเรื่องสั้นกับผู้ปกครอง 10 นาที/วัน", "ครูสังเกตการอยู่ร่วมกันในกลุ่ม"],
        term: ["ทบทวนรูบริกอ่านเขียนและจำนวน", "ส่งต่อสิ่งที่บ้านช่วยได้ในรายงานสั้น", "ประสานฝ่ายประถมก่อนขยายผล (ข้อเสนอ)"]
      };
    }
    if (stu.band === "late_primary") {
      return {
        month: ["แบบฝึกสั้นด้าน" + a, "สำรวจชมรมที่เกี่ยวกับ" + b, "ทบทวนวิชาหลักที่ยังกำลังพัฒนา"],
        term: ["วัดซ้ำอัตราพัฒนา (ข้อมูลจำลองในต้นแบบ)", "รายงานสำรวจความสนใจโดยไม่ล็อกอาชีพ", "นัดคุยผู้ปกครอง 1 ครั้ง"]
      };
    }
    if (stu.band === "lower_secondary") {
      return {
        month: ["ทบทวนวิชาหลักสัปดาห์ละ 3 ชุดสั้น", "โมดูลบุคลิกภาพ/เป้าหมาย 1 ครั้ง", "พูดคุยแนวสาย ม.ปลายกับครูที่ปรึกษา"],
        term: ["สรุปเส้นทาง 2–3 ทางก่อนเลือกสาย (โดยเฉพาะ ม.3)", "นัดสามฝ่าย", "ยืนยันชื่อสายจริงของโรงเรียน"]
      };
    }
    return {
      month: ["แผนทบทวนรายวิชาเป้าหมายสัปดาห์ละ 4 ชุด", "ติดตามกลุ่มลักษณะงานที่สนใจ", "จำลองตารางเตรียมสอบ (ข้อเสนอรอปฏิทิน TCAS จริง)"],
      term: ["ทบทวนช่องว่างความรู้รายวิชา", "อัปเดตเส้นทางสำรอง", "นัดครูแนะแนวก่อนรอบสมัคร"]
    };
  }
  function buildReport(stu, answers, progress, editedSummary) {
    var apt = computeAptitude(stu, answers);
    var abil = computeAbility(stu, answers);
    var psych = computePsych(stu, answers);
    var work = computeWork(stu, answers);
    var pot = computePotential(stu, apt, abil, psych);
    var tops = topN(apt, 3);
    var low = Object.keys(apt).map(function (k) { return apt[k]; }).sort(function (a, b) { return a.score - b.score; }).slice(0, 2);
    var paths = pathways(stu, apt, abil, work);
    var plan = monthPlan(stu, tops);
    var conf = confidence(stu, progress);
    var strengths = tops.map(function (t) {
      return t.name + " — เห็นแนวโน้มจากกิจกรรมและการสังเกต (ข้อมูลจำลอง)";
    });
    var promote = low.map(function (t) {
      return t.name + " — ส่งเสริมเพิ่มด้วยกิจกรรมสั้นและแบบฝึก (ไม่ใช่ป้ายว่าไม่ถนัด)";
    });
    if (promote.length < 2) promote.push("เสริมแรงจูงใจใฝ่เรียนอย่างสม่ำเสมอ");
    var summary = editedSummary || (
      stu.display + " มีจุดเด่นด้าน" + tops.map(function (t) { return t.name; }).join(", ") +
      " ความสามารถปัจจุบันอยู่ในระดับที่ส่งเสริมต่อได้ และ" + pot.band
    );
    return {
      studentId: stu.id,
      generatedAt: new Date().toISOString(),
      summary: summary,
      strengths: strengths.slice(0, 3),
      promote: promote.slice(0, 3),
      potentialSentence: pot.band,
      aptitude: apt,
      ability: abil,
      psych: psych,
      work: work,
      potential: pot,
      pathways: paths,
      plan: plan,
      confidence: conf,
      schoolDoes: [
        "จัดกิจกรรมส่งเสริมตามจุดเด่นในชมรม/ชั่วโมงแนะแนว",
        "ครูที่ปรึกษาติดตามแผนรายเดือน",
        "วัดซ้ำเพื่อดูอัตราพัฒนา (ในต้นแบบใช้ข้อมูลจำลอง)"
      ],
      homeDoes: stu.band.indexOf("primary") >= 0 || stu.band === "early_primary" || stu.band === "late_primary"
        ? ["อ่าน/คุยกับลูกสั้น ๆ ทุกวัน", "ชมเมื่อพยายาม ไม่เทียบกับคนอื่น", "ตอบแบบสอบถามพฤติกรรมที่บ้าน"]
        : ["ช่วยจัดเวลาทบทวน", "พูดคุยเป้าหมายโดยไม่กดดัน", "สนับสนุนการพักผ่อนและสุขภาพ"]
    };
  }
  global.Analyzer = {
    buildReport: buildReport,
    computeAptitude: computeAptitude,
    computeAbility: computeAbility,
    levelAbility: levelAbility,
    topN: topN
  };
})(window);
