-- assess_002_additional_instruments.sql
-- Adds three original school instruments to the existing assess_* module.
-- Touches assess_* objects only. Does not read or write vocab_*, vocab__bak*, or exam-gym tables.
-- Idempotent: safe to run again. Item rows are upserted, the catalog is merged, functions are replaced.
-- Does not import real students or national IDs. New modules start incomplete.
-- Demo passwords are not stored here.

do $assess_002_need$
begin
  if to_regclass('public.assess_catalog') is null or to_regclass('public.assess_items') is null then
    raise exception 'assess_002 requires assess_001 (assess_catalog / assess_items)';
  end if;
end
$assess_002_need$;

-- Widen kind/module checks. Drop only the checks that mention those columns, then recreate them.
do $assess_002_constraints$
declare
  r record;
begin
  for r in
    select c.relname as table_name, con.conname
    from pg_constraint con
    join pg_class c on c.oid = con.conrelid
    join pg_namespace n on n.oid = c.relnamespace
    where n.nspname = 'public'
      and c.relname in ('assess_items', 'assess_progress')
      and con.contype = 'c'
      and pg_get_constraintdef(con.oid) ~ '(kind|module)'
  loop
    execute format('alter table public.%I drop constraint %I', r.table_name, r.conname);
  end loop;
end
$assess_002_constraints$;

alter table public.assess_items
  add constraint assess_items_kind_check
  check (kind in (
    'aptitude', 'work', 'ability', 'psych', 'exercises', 'personality', 'parent', 'rubric',
    'potential_survey', 'cognition', 'study_habits'
  ));

alter table public.assess_progress
  add constraint assess_progress_module_check
  check (module in (
    'aptitude', 'ability', 'psych', 'work', 'exercises', 'personality',
    'potential_survey', 'cognition', 'study_habits'
  ));

-- Merge new banks into the existing catalog document. Other keys stay.
update public.assess_catalog
set doc = doc || $assess002cat${"potentialSurvey":{"key":"potential_survey","title":"แบบสำรวจศักยภาพที่ส่งเสริมได้","shortTitle":"ศักยภาพ","kind":"likert5","forBands":["early_primary","late_primary","lower_secondary","upper_secondary"],"purpose":"เก็บหลักฐานด้านความอยากรู้ การพัฒนาหลังได้ฝึก การตอบสนองต่อความช่วยเหลือ และการยืนหยัด เพื่อประกอบการคำนวณช่วงศักยภาพที่ส่งเสริมได้ ไม่ใช่คะแนนคงที่","scoreLabel":"ช่วงศักยภาพที่ส่งเสริมได้","forbiddenOutput":["IQ","ศักยภาพต่ำ","คะแนนศักยภาพคงที่"],"facets":[{"id":"curiosity","name":"ความอยากรู้"},{"id":"growth","name":"การพัฒนาหลังได้ฝึก"},{"id":"response","name":"การตอบสนองต่อความช่วยเหลือ"},{"id":"persistence","name":"การยืนหยัดเมื่องานยาก"}],"options":[{"v":1,"l":"ยังไม่ค่อยเป็นเช่นนั้น"},{"v":2,"l":"เป็นบ้างเมื่อมีคนชวน"},{"v":3,"l":"เป็นเป็นครั้งคราว"},{"v":4,"l":"เป็นบ่อยเมื่อได้ลอง"},{"v":5,"l":"เป็นเช่นนั้นเกือบทุกครั้ง"}],"items":[{"id":"pot_c1","facet":"curiosity","text":"เมื่อเจอเรื่องใหม่ที่ยังไม่เคยเรียน ฉันอยากถามต่อว่าทำไมจึงเป็นเช่นนั้น"},{"id":"pot_c2","facet":"curiosity","text":"ฉันค้นหาข้อมูลเพิ่มเองเมื่อบทเรียนจุดประกายความสงสัย"},{"id":"pot_c3","facet":"curiosity","text":"ฉันสนใจสังเกตสิ่งรอบตัวแล้วเชื่อมกับสิ่งที่เรียนในห้อง"},{"id":"pot_g1","facet":"growth","text":"หลังจากได้ฝึกเรื่องที่ยากซ้ำหลายครั้ง ฉันทำได้ดีขึ้นกว่าตอนเริ่ม"},{"id":"pot_g2","facet":"growth","text":"เมื่อครูชี้จุดที่ควรปรับ ฉันนำไปฝึกต่อจนเห็นการเปลี่ยนแปลง"},{"id":"pot_g3","facet":"growth","text":"ฉันเปรียบเทียบงานชิ้นใหม่กับงานเก่าของตนเองเพื่อดูว่าพัฒนาขึ้นตรงไหน"},{"id":"pot_r1","facet":"response","text":"เมื่อได้รับคำแนะนำ ฉันลองทำให้ดูแล้วบอกครูว่าตรงไหนยังติด"},{"id":"pot_r2","facet":"response","text":"ฉันขอตัวอย่างหรือคำใบ้เมื่อไม่เข้าใจ แทนการปล่อยผ่าน"},{"id":"pot_r3","facet":"response","text":"หลังได้ความช่วยเหลือ ฉันลองทำข้อถัดไปด้วยตนเอง โดยไม่ให้ครูทำให้ทั้งหมด"},{"id":"pot_p1","facet":"persistence","text":"เมื่องานยากกว่าที่คิด ฉันแบ่งเป็นขั้นเล็กแล้วทำให้ครบทีละขั้น"},{"id":"pot_p2","facet":"persistence","text":"ฉันไม่เลิกทันทีเมื่อทำผิด แต่หาสาเหตุแล้วลองใหม่"},{"id":"pot_p3","facet":"persistence","text":"ฉันตั้งเป้าหมายสั้นที่วัดได้ แล้วตรวจเองว่าคืบหน้าแค่ไหน"}]},"cognition":{"key":"cognition","title":"แบบสำรวจการคิดและเหตุผล","shortTitle":"การคิดและเหตุผล","kind":"mcq","forBands":["early_primary","late_primary","lower_secondary","upper_secondary"],"purpose":"สำรวจการคิดเชิงภาษา จำนวน ภาพและมิติ และการให้เหตุผล ด้วยข้อต้นฉบับของโรงเรียน เพื่อประกอบการแนะแนว ไม่ใช่แบบวัดเชาว์ปัญญามาตรฐาน และไม่แปลงเป็นคะแนนไอคิว","disclaimer":"ต้นฉบับของโรงเรียนปิยมิตรวิทยา ไม่ใช่แบบวัดเชาว์ปัญญาลิขสิทธิ์ และไม่รายงานเป็นคะแนนไอคิว ใช้เพื่อแนะแนวไม่ใช่เพื่อวินิจฉัย","scoreLabel":"แนวโน้มการคิดแต่ละด้าน (จุดเด่น / ถึงระดับ / กำลังพัฒนา)","forbiddenOutput":["IQ","ไอคิว","เชาว์ปัญญาต่ำ","WISC","Raven","Stanford-Binet"],"domains":[{"id":"verbal","name":"การคิดเชิงภาษา"},{"id":"quantitative","name":"การคิดเชิงจำนวน"},{"id":"spatial","name":"การคิดเชิงภาพและมิติ"},{"id":"reasoning","name":"การให้เหตุผล"}],"scoring":{"method":"percent_correct_by_domain_and_overall","bands":[{"min":0,"max":49,"label":"กำลังพัฒนา"},{"min":50,"max":79,"label":"ถึงระดับ"},{"min":80,"max":100,"label":"จุดเด่น"}],"neverConvertToIQ":true},"items":[{"id":"cog_v1","domain":"verbal","text":"ป้ายที่โรงอาหารเขียนว่า «วันนี้ปิดจำหน่ายน้ำหวาน เปิดจำหน่ายน้ำเปล่าและน้ำสมุนไพร» ข้อใดถูก","options":[{"v":"a","l":"วันนี้ไม่มีเครื่องดื่มขาย"},{"v":"b","l":"วันนี้มีน้ำเปล่าและน้ำสมุนไพร แต่ไม่มีน้ำหวาน"},{"v":"c","l":"วันนี้ขายแต่น้ำหวาน"},{"v":"d","l":"วันนี้ปิดโรงอาหารทั้งหลัง"}],"correct":"b"},{"id":"cog_v2","domain":"verbal","text":"«เมฆบังอาทิตย์ ทำให้ลานโรงเรียนมืดลงชั่วคราว» ประโยคนี้บอกเหตุและผลอย่างไร","options":[{"v":"a","l":"ลานมืดเป็นเหตุให้อาทิตย์ถูกบัง"},{"v":"b","l":"เมฆบังอาทิตย์เป็นเหตุ ทำให้ลานมืดลงเป็นผล"},{"v":"c","l":"ลานมืดและเมฆไม่เกี่ยวข้องกัน"},{"v":"d","l":"อาทิตย์ทำให้เกิดเมฆ แล้วลานจึงมืด"}],"correct":"b"},{"id":"cog_v3","domain":"verbal","text":"คำว่า «ประหยัด» ในประโยค «นักเรียนประหยัดน้ำเมื่อล้างจาน» ใกล้เคียงความหมายใดมากที่สุด","options":[{"v":"a","l":"ใช้น้ำเท่าที่จำเป็น ไม่ฟุ่มเฟือย"},{"v":"b","l":"ไม่ล้างจานเลย"},{"v":"c","l":"ใช้น้ำให้มากที่สุด"},{"v":"d","l":"เก็บน้ำไว้ดูอย่างเดียว"}],"correct":"a"},{"id":"cog_v4","domain":"verbal","text":"ข้อความ: «หลังฝนตก สนามหญ้าเปียกและมีแอ่งน้ำ» ข้อสรุปใดสมเหตุสมผลที่สุด","options":[{"v":"a","l":"คงไม่มีฝนตกแน่นอน"},{"v":"b","l":"สนามแห้งทันทีหลังฝน"},{"v":"c","l":"ฝนที่ตกมีส่วนทำให้สนามเปียกและมีแอ่งน้ำ"},{"v":"d","l":"แอ่งน้ำเกิดก่อนฝนเสมอ"}],"correct":"c"},{"id":"cog_q1","domain":"quantitative","text":"ตะกร้ามีมะม่วง 12 ผล แบ่งให้นักเรียน 3 คน คนละเท่า ๆ กัน แต่ละคนได้กี่ผล","options":[{"v":"a","l":"3 ผล"},{"v":"b","l":"4 ผล"},{"v":"c","l":"6 ผล"},{"v":"d","l":"9 ผล"}],"correct":"b"},{"id":"cog_q2","domain":"quantitative","text":"ลำดับจำนวน 2, 5, 8, 11, … จำนวนถัดไปคือข้อใด","options":[{"v":"a","l":"12"},{"v":"b","l":"13"},{"v":"c","l":"14"},{"v":"d","l":"15"}],"correct":"c"},{"id":"cog_q3","domain":"quantitative","text":"สมุดราคาเล่มละ 40 บาท ซื้อ 2 เล่ม ลดทันที 10 บาท ต้องจ่ายจริงกี่บาท","options":[{"v":"a","l":"70 บาท"},{"v":"b","l":"80 บาท"},{"v":"c","l":"50 บาท"},{"v":"d","l":"30 บาท"}],"correct":"a"},{"id":"cog_q4","domain":"quantitative","text":"เชือกยาว 18 เมตร ตัดเป็นท่อนละ 3 เมตร ได้กี่ท่อน","options":[{"v":"a","l":"3 ท่อน"},{"v":"b","l":"5 ท่อน"},{"v":"c","l":"6 ท่อน"},{"v":"d","l":"9 ท่อน"}],"correct":"c"},{"id":"cog_s1","domain":"spatial","text":"กล่องสี่เหลี่ยมลูกบาศก์มีกี่หน้า หากทาสีทุกหน้า จะต้องทากี่หน้า","options":[{"v":"a","l":"4 หน้า"},{"v":"b","l":"5 หน้า"},{"v":"c","l":"6 หน้า"},{"v":"d","l":"8 หน้า"}],"correct":"c"},{"id":"cog_s2","domain":"spatial","text":"นักเรียนนั่งหันหน้าไปทางกระดานซึ่งอยู่ทิศเหนือ หน้าต่างอยู่ด้านซ้ายของนักเรียน หน้าต่างอยู่ทิศใด","options":[{"v":"a","l":"เหนือ"},{"v":"b","l":"ใต้"},{"v":"c","l":"ตะวันออก"},{"v":"d","l":"ตะวันตก"}],"correct":"d"},{"id":"cog_s3","domain":"spatial","text":"กระดาษสี่เหลี่ยมผืนผ้ายาว 20 ซม. กว้าง 10 ซม. พับครึ่งโดยให้ด้านยาวมาชนกัน จะได้รูปสี่เหลี่ยมขนาดใด","options":[{"v":"a","l":"ยาว 10 ซม. กว้าง 10 ซม."},{"v":"b","l":"ยาว 20 ซม. กว้าง 5 ซม."},{"v":"c","l":"ยาว 20 ซม. กว้าง 10 ซม."},{"v":"d","l":"ยาว 5 ซม. กว้าง 5 ซม."}],"correct":"a"},{"id":"cog_s4","domain":"spatial","text":"มองกล่องจากด้านบน เห็นฝาเป็นสี่เหลี่ยมจัตุรัส และมีมือจับอยู่กึ่งกลางฝา ข้อใดอธิบายมุมมองนี้ได้ถูกต้อง","options":[{"v":"a","l":"มองจากด้านข้าง จึงเห็นความสูงชัดที่สุด"},{"v":"b","l":"มองจากด้านบน จึงเห็นรูปทรงของฝาและตำแหน่งมือจับบนฝา"},{"v":"c","l":"มองจากด้านล่าง จึงเห็นฝา"},{"v":"d","l":"มองจากด้านในกล่อง"}],"correct":"b"},{"id":"cog_r1","domain":"reasoning","text":"มีผู้กล่าวว่า «นกทุกชนิดบินได้» แต่เพนกวินเป็นนกที่บินไม่ได้ ข้อนี้สอนให้ตรวจอะไรก่อนสรุปคำว่า «ทุก»","options":[{"v":"a","l":"ตรวจว่ามีข้อยกเว้นหรือไม่ ก่อนสรุปว่าทุกตัวเป็นเช่นนั้น"},{"v":"b","l":"ไม่ต้องสนใจตัวอย่างที่ต่างออกไป"},{"v":"c","l":"สรุปจากคำเดียวเสมอโดยไม่ต้องมีหลักฐาน"},{"v":"d","l":"นกทุกชนิดบินได้แน่นอน"}],"correct":"a"},{"id":"cog_r2","domain":"reasoning","text":"ถ้าฝนตก งานกีฬากลางแจ้งจะเลื่อน วันนี้ท้องฟ้าโปร่งและไม่มีฝน ข้อใดสมเหตุสมผลที่สุด","options":[{"v":"a","l":"งานกีฬากลางแจ้งไม่ถูกเลื่อนเพราะฝน"},{"v":"b","l":"งานต้องเลื่อนแน่นอน"},{"v":"c","l":"ฝนจะตกในอีกไม่กี่นาทีอย่างหลีกเลี่ยงไม่ได้"},{"v":"d","l":"โรงเรียนไม่มีงานกีฬา"}],"correct":"a"},{"id":"cog_r3","domain":"reasoning","text":"จำนวนนักเรียนในห้องเป็นจำนวนคู่ จึงนับทีละ 2 ได้ลงตัวไม่เหลือเศษ ข้อใดเข้ากันได้","options":[{"v":"a","l":"มีนักเรียน 25 คน"},{"v":"b","l":"มีนักเรียน 31 คน"},{"v":"c","l":"มีนักเรียน 28 คน"},{"v":"d","l":"มีนักเรียน 17 คน"}],"correct":"c"},{"id":"cog_r4","domain":"reasoning","text":"กฎของห้องเรียนคือ «ใครมาสายต้องถูกบันทึกชื่อ» เพื่อนคนหนึ่งไม่ถูกบันทึกชื่อ ข้อใดสมเหตุสมผลตามกฎนี้","options":[{"v":"a","l":"ตามกฎที่กล่าว เพื่อนคนนี้ไม่ได้มาสาย"},{"v":"b","l":"การไม่ถูกบันทึกชื่อไม่เกี่ยวกับการมาสาย"},{"v":"c","l":"ทุกคนถูกบันทึกชื่อเสมอ แม้ไม่มาสาย"},{"v":"d","l":"กฎนี้ใช้กับครูเท่านั้น"}],"correct":"a"}]},"studyHabits":{"key":"study_habits","title":"แบบสำรวจนิสัยการเรียน","shortTitle":"นิสัยการเรียน","kind":"likert5","forBands":["early_primary","late_primary","lower_secondary","upper_secondary"],"purpose":"สำรวจนิสัยการเรียนและความพร้อมที่เกี่ยวข้องกับการวิเคราะห์ผู้เรียนรายบุคคล","facets":[{"id":"habits","name":"นิสัยการเรียน"}],"options":[{"v":1,"l":"ยังไม่ค่อยเป็นเช่นนั้น"},{"v":2,"l":"เป็นบ้างเมื่อมีคนชวน"},{"v":3,"l":"เป็นเป็นครั้งคราว"},{"v":4,"l":"เป็นบ่อยเมื่อได้ลอง"},{"v":5,"l":"เป็นเช่นนั้นเกือบทุกครั้ง"}],"items":[{"id":"sh1","facet":"habits","text":"ฉันวางแผนก่อนลงมือทำการบ้านหรืออ่านหนังสือ"},{"id":"sh2","facet":"habits","text":"ฉันทบทวนบทเรียนภายในวันที่เรียน"},{"id":"sh3","facet":"habits","text":"ฉันถามเมื่อไม่เข้าใจ แทนการข้ามไป"},{"id":"sh4","facet":"habits","text":"ฉันจัดที่นั่งให้เรียบร้อยและลดสิ่งรบกวนก่อนเริ่มงาน"},{"id":"sh5","facet":"habits","text":"ฉันแบ่งงานยาวเป็นช่วงสั้น ๆ แล้วพักตามที่กำหนด"},{"id":"sh6","facet":"habits","text":"ฉันตรวจงานอีกครั้งก่อนส่ง"},{"id":"sh7","facet":"habits","text":"ฉันเชื่อมสิ่งที่เรียนกับตัวอย่างในชีวิตจริงเพื่อให้จำได้"},{"id":"sh8","facet":"habits","text":"ฉันนอนให้เพียงพอก่อนวันที่มีการสอบหรือนำเสนอ"}]}}$assess002cat$::jsonb,
    updated_at = now()
where id = 1;

insert into public.assess_items (item_id, kind, domain, band, sort_no, body)
select x->>'item_id', x->>'kind', x->>'domain', null, (x->>'sort_no')::integer, x->'body'
from jsonb_array_elements($assess002items$[{"item_id":"pot_c1","kind":"potential_survey","domain":"curiosity","sort_no":1,"body":{"id":"pot_c1","text":"เมื่อเจอเรื่องใหม่ที่ยังไม่เคยเรียน ฉันอยากถามต่อว่าทำไมจึงเป็นเช่นนั้น","type":"likert","options":[{"v":1,"l":"ยังไม่ค่อยเป็นเช่นนั้น"},{"v":2,"l":"เป็นบ้างเมื่อมีคนชวน"},{"v":3,"l":"เป็นเป็นครั้งคราว"},{"v":4,"l":"เป็นบ่อยเมื่อได้ลอง"},{"v":5,"l":"เป็นเช่นนั้นเกือบทุกครั้ง"}],"facet":"curiosity"}},{"item_id":"pot_c2","kind":"potential_survey","domain":"curiosity","sort_no":2,"body":{"id":"pot_c2","text":"ฉันค้นหาข้อมูลเพิ่มเองเมื่อบทเรียนจุดประกายความสงสัย","type":"likert","options":[{"v":1,"l":"ยังไม่ค่อยเป็นเช่นนั้น"},{"v":2,"l":"เป็นบ้างเมื่อมีคนชวน"},{"v":3,"l":"เป็นเป็นครั้งคราว"},{"v":4,"l":"เป็นบ่อยเมื่อได้ลอง"},{"v":5,"l":"เป็นเช่นนั้นเกือบทุกครั้ง"}],"facet":"curiosity"}},{"item_id":"pot_c3","kind":"potential_survey","domain":"curiosity","sort_no":3,"body":{"id":"pot_c3","text":"ฉันสนใจสังเกตสิ่งรอบตัวแล้วเชื่อมกับสิ่งที่เรียนในห้อง","type":"likert","options":[{"v":1,"l":"ยังไม่ค่อยเป็นเช่นนั้น"},{"v":2,"l":"เป็นบ้างเมื่อมีคนชวน"},{"v":3,"l":"เป็นเป็นครั้งคราว"},{"v":4,"l":"เป็นบ่อยเมื่อได้ลอง"},{"v":5,"l":"เป็นเช่นนั้นเกือบทุกครั้ง"}],"facet":"curiosity"}},{"item_id":"pot_g1","kind":"potential_survey","domain":"growth","sort_no":4,"body":{"id":"pot_g1","text":"หลังจากได้ฝึกเรื่องที่ยากซ้ำหลายครั้ง ฉันทำได้ดีขึ้นกว่าตอนเริ่ม","type":"likert","options":[{"v":1,"l":"ยังไม่ค่อยเป็นเช่นนั้น"},{"v":2,"l":"เป็นบ้างเมื่อมีคนชวน"},{"v":3,"l":"เป็นเป็นครั้งคราว"},{"v":4,"l":"เป็นบ่อยเมื่อได้ลอง"},{"v":5,"l":"เป็นเช่นนั้นเกือบทุกครั้ง"}],"facet":"growth"}},{"item_id":"pot_g2","kind":"potential_survey","domain":"growth","sort_no":5,"body":{"id":"pot_g2","text":"เมื่อครูชี้จุดที่ควรปรับ ฉันนำไปฝึกต่อจนเห็นการเปลี่ยนแปลง","type":"likert","options":[{"v":1,"l":"ยังไม่ค่อยเป็นเช่นนั้น"},{"v":2,"l":"เป็นบ้างเมื่อมีคนชวน"},{"v":3,"l":"เป็นเป็นครั้งคราว"},{"v":4,"l":"เป็นบ่อยเมื่อได้ลอง"},{"v":5,"l":"เป็นเช่นนั้นเกือบทุกครั้ง"}],"facet":"growth"}},{"item_id":"pot_g3","kind":"potential_survey","domain":"growth","sort_no":6,"body":{"id":"pot_g3","text":"ฉันเปรียบเทียบงานชิ้นใหม่กับงานเก่าของตนเองเพื่อดูว่าพัฒนาขึ้นตรงไหน","type":"likert","options":[{"v":1,"l":"ยังไม่ค่อยเป็นเช่นนั้น"},{"v":2,"l":"เป็นบ้างเมื่อมีคนชวน"},{"v":3,"l":"เป็นเป็นครั้งคราว"},{"v":4,"l":"เป็นบ่อยเมื่อได้ลอง"},{"v":5,"l":"เป็นเช่นนั้นเกือบทุกครั้ง"}],"facet":"growth"}},{"item_id":"pot_r1","kind":"potential_survey","domain":"response","sort_no":7,"body":{"id":"pot_r1","text":"เมื่อได้รับคำแนะนำ ฉันลองทำให้ดูแล้วบอกครูว่าตรงไหนยังติด","type":"likert","options":[{"v":1,"l":"ยังไม่ค่อยเป็นเช่นนั้น"},{"v":2,"l":"เป็นบ้างเมื่อมีคนชวน"},{"v":3,"l":"เป็นเป็นครั้งคราว"},{"v":4,"l":"เป็นบ่อยเมื่อได้ลอง"},{"v":5,"l":"เป็นเช่นนั้นเกือบทุกครั้ง"}],"facet":"response"}},{"item_id":"pot_r2","kind":"potential_survey","domain":"response","sort_no":8,"body":{"id":"pot_r2","text":"ฉันขอตัวอย่างหรือคำใบ้เมื่อไม่เข้าใจ แทนการปล่อยผ่าน","type":"likert","options":[{"v":1,"l":"ยังไม่ค่อยเป็นเช่นนั้น"},{"v":2,"l":"เป็นบ้างเมื่อมีคนชวน"},{"v":3,"l":"เป็นเป็นครั้งคราว"},{"v":4,"l":"เป็นบ่อยเมื่อได้ลอง"},{"v":5,"l":"เป็นเช่นนั้นเกือบทุกครั้ง"}],"facet":"response"}},{"item_id":"pot_r3","kind":"potential_survey","domain":"response","sort_no":9,"body":{"id":"pot_r3","text":"หลังได้ความช่วยเหลือ ฉันลองทำข้อถัดไปด้วยตนเอง โดยไม่ให้ครูทำให้ทั้งหมด","type":"likert","options":[{"v":1,"l":"ยังไม่ค่อยเป็นเช่นนั้น"},{"v":2,"l":"เป็นบ้างเมื่อมีคนชวน"},{"v":3,"l":"เป็นเป็นครั้งคราว"},{"v":4,"l":"เป็นบ่อยเมื่อได้ลอง"},{"v":5,"l":"เป็นเช่นนั้นเกือบทุกครั้ง"}],"facet":"response"}},{"item_id":"pot_p1","kind":"potential_survey","domain":"persistence","sort_no":10,"body":{"id":"pot_p1","text":"เมื่องานยากกว่าที่คิด ฉันแบ่งเป็นขั้นเล็กแล้วทำให้ครบทีละขั้น","type":"likert","options":[{"v":1,"l":"ยังไม่ค่อยเป็นเช่นนั้น"},{"v":2,"l":"เป็นบ้างเมื่อมีคนชวน"},{"v":3,"l":"เป็นเป็นครั้งคราว"},{"v":4,"l":"เป็นบ่อยเมื่อได้ลอง"},{"v":5,"l":"เป็นเช่นนั้นเกือบทุกครั้ง"}],"facet":"persistence"}},{"item_id":"pot_p2","kind":"potential_survey","domain":"persistence","sort_no":11,"body":{"id":"pot_p2","text":"ฉันไม่เลิกทันทีเมื่อทำผิด แต่หาสาเหตุแล้วลองใหม่","type":"likert","options":[{"v":1,"l":"ยังไม่ค่อยเป็นเช่นนั้น"},{"v":2,"l":"เป็นบ้างเมื่อมีคนชวน"},{"v":3,"l":"เป็นเป็นครั้งคราว"},{"v":4,"l":"เป็นบ่อยเมื่อได้ลอง"},{"v":5,"l":"เป็นเช่นนั้นเกือบทุกครั้ง"}],"facet":"persistence"}},{"item_id":"pot_p3","kind":"potential_survey","domain":"persistence","sort_no":12,"body":{"id":"pot_p3","text":"ฉันตั้งเป้าหมายสั้นที่วัดได้ แล้วตรวจเองว่าคืบหน้าแค่ไหน","type":"likert","options":[{"v":1,"l":"ยังไม่ค่อยเป็นเช่นนั้น"},{"v":2,"l":"เป็นบ้างเมื่อมีคนชวน"},{"v":3,"l":"เป็นเป็นครั้งคราว"},{"v":4,"l":"เป็นบ่อยเมื่อได้ลอง"},{"v":5,"l":"เป็นเช่นนั้นเกือบทุกครั้ง"}],"facet":"persistence"}},{"item_id":"cog_v1","kind":"cognition","domain":"verbal","sort_no":1,"body":{"id":"cog_v1","text":"ป้ายที่โรงอาหารเขียนว่า «วันนี้ปิดจำหน่ายน้ำหวาน เปิดจำหน่ายน้ำเปล่าและน้ำสมุนไพร» ข้อใดถูก","type":"choice","options":[{"v":"a","l":"วันนี้ไม่มีเครื่องดื่มขาย"},{"v":"b","l":"วันนี้มีน้ำเปล่าและน้ำสมุนไพร แต่ไม่มีน้ำหวาน"},{"v":"c","l":"วันนี้ขายแต่น้ำหวาน"},{"v":"d","l":"วันนี้ปิดโรงอาหารทั้งหลัง"}],"domain":"verbal","correct":"b"}},{"item_id":"cog_v2","kind":"cognition","domain":"verbal","sort_no":2,"body":{"id":"cog_v2","text":"«เมฆบังอาทิตย์ ทำให้ลานโรงเรียนมืดลงชั่วคราว» ประโยคนี้บอกเหตุและผลอย่างไร","type":"choice","options":[{"v":"a","l":"ลานมืดเป็นเหตุให้อาทิตย์ถูกบัง"},{"v":"b","l":"เมฆบังอาทิตย์เป็นเหตุ ทำให้ลานมืดลงเป็นผล"},{"v":"c","l":"ลานมืดและเมฆไม่เกี่ยวข้องกัน"},{"v":"d","l":"อาทิตย์ทำให้เกิดเมฆ แล้วลานจึงมืด"}],"domain":"verbal","correct":"b"}},{"item_id":"cog_v3","kind":"cognition","domain":"verbal","sort_no":3,"body":{"id":"cog_v3","text":"คำว่า «ประหยัด» ในประโยค «นักเรียนประหยัดน้ำเมื่อล้างจาน» ใกล้เคียงความหมายใดมากที่สุด","type":"choice","options":[{"v":"a","l":"ใช้น้ำเท่าที่จำเป็น ไม่ฟุ่มเฟือย"},{"v":"b","l":"ไม่ล้างจานเลย"},{"v":"c","l":"ใช้น้ำให้มากที่สุด"},{"v":"d","l":"เก็บน้ำไว้ดูอย่างเดียว"}],"domain":"verbal","correct":"a"}},{"item_id":"cog_v4","kind":"cognition","domain":"verbal","sort_no":4,"body":{"id":"cog_v4","text":"ข้อความ: «หลังฝนตก สนามหญ้าเปียกและมีแอ่งน้ำ» ข้อสรุปใดสมเหตุสมผลที่สุด","type":"choice","options":[{"v":"a","l":"คงไม่มีฝนตกแน่นอน"},{"v":"b","l":"สนามแห้งทันทีหลังฝน"},{"v":"c","l":"ฝนที่ตกมีส่วนทำให้สนามเปียกและมีแอ่งน้ำ"},{"v":"d","l":"แอ่งน้ำเกิดก่อนฝนเสมอ"}],"domain":"verbal","correct":"c"}},{"item_id":"cog_q1","kind":"cognition","domain":"quantitative","sort_no":5,"body":{"id":"cog_q1","text":"ตะกร้ามีมะม่วง 12 ผล แบ่งให้นักเรียน 3 คน คนละเท่า ๆ กัน แต่ละคนได้กี่ผล","type":"choice","options":[{"v":"a","l":"3 ผล"},{"v":"b","l":"4 ผล"},{"v":"c","l":"6 ผล"},{"v":"d","l":"9 ผล"}],"domain":"quantitative","correct":"b"}},{"item_id":"cog_q2","kind":"cognition","domain":"quantitative","sort_no":6,"body":{"id":"cog_q2","text":"ลำดับจำนวน 2, 5, 8, 11, … จำนวนถัดไปคือข้อใด","type":"choice","options":[{"v":"a","l":"12"},{"v":"b","l":"13"},{"v":"c","l":"14"},{"v":"d","l":"15"}],"domain":"quantitative","correct":"c"}},{"item_id":"cog_q3","kind":"cognition","domain":"quantitative","sort_no":7,"body":{"id":"cog_q3","text":"สมุดราคาเล่มละ 40 บาท ซื้อ 2 เล่ม ลดทันที 10 บาท ต้องจ่ายจริงกี่บาท","type":"choice","options":[{"v":"a","l":"70 บาท"},{"v":"b","l":"80 บาท"},{"v":"c","l":"50 บาท"},{"v":"d","l":"30 บาท"}],"domain":"quantitative","correct":"a"}},{"item_id":"cog_q4","kind":"cognition","domain":"quantitative","sort_no":8,"body":{"id":"cog_q4","text":"เชือกยาว 18 เมตร ตัดเป็นท่อนละ 3 เมตร ได้กี่ท่อน","type":"choice","options":[{"v":"a","l":"3 ท่อน"},{"v":"b","l":"5 ท่อน"},{"v":"c","l":"6 ท่อน"},{"v":"d","l":"9 ท่อน"}],"domain":"quantitative","correct":"c"}},{"item_id":"cog_s1","kind":"cognition","domain":"spatial","sort_no":9,"body":{"id":"cog_s1","text":"กล่องสี่เหลี่ยมลูกบาศก์มีกี่หน้า หากทาสีทุกหน้า จะต้องทากี่หน้า","type":"choice","options":[{"v":"a","l":"4 หน้า"},{"v":"b","l":"5 หน้า"},{"v":"c","l":"6 หน้า"},{"v":"d","l":"8 หน้า"}],"domain":"spatial","correct":"c"}},{"item_id":"cog_s2","kind":"cognition","domain":"spatial","sort_no":10,"body":{"id":"cog_s2","text":"นักเรียนนั่งหันหน้าไปทางกระดานซึ่งอยู่ทิศเหนือ หน้าต่างอยู่ด้านซ้ายของนักเรียน หน้าต่างอยู่ทิศใด","type":"choice","options":[{"v":"a","l":"เหนือ"},{"v":"b","l":"ใต้"},{"v":"c","l":"ตะวันออก"},{"v":"d","l":"ตะวันตก"}],"domain":"spatial","correct":"d"}},{"item_id":"cog_s3","kind":"cognition","domain":"spatial","sort_no":11,"body":{"id":"cog_s3","text":"กระดาษสี่เหลี่ยมผืนผ้ายาว 20 ซม. กว้าง 10 ซม. พับครึ่งโดยให้ด้านยาวมาชนกัน จะได้รูปสี่เหลี่ยมขนาดใด","type":"choice","options":[{"v":"a","l":"ยาว 10 ซม. กว้าง 10 ซม."},{"v":"b","l":"ยาว 20 ซม. กว้าง 5 ซม."},{"v":"c","l":"ยาว 20 ซม. กว้าง 10 ซม."},{"v":"d","l":"ยาว 5 ซม. กว้าง 5 ซม."}],"domain":"spatial","correct":"a"}},{"item_id":"cog_s4","kind":"cognition","domain":"spatial","sort_no":12,"body":{"id":"cog_s4","text":"มองกล่องจากด้านบน เห็นฝาเป็นสี่เหลี่ยมจัตุรัส และมีมือจับอยู่กึ่งกลางฝา ข้อใดอธิบายมุมมองนี้ได้ถูกต้อง","type":"choice","options":[{"v":"a","l":"มองจากด้านข้าง จึงเห็นความสูงชัดที่สุด"},{"v":"b","l":"มองจากด้านบน จึงเห็นรูปทรงของฝาและตำแหน่งมือจับบนฝา"},{"v":"c","l":"มองจากด้านล่าง จึงเห็นฝา"},{"v":"d","l":"มองจากด้านในกล่อง"}],"domain":"spatial","correct":"b"}},{"item_id":"cog_r1","kind":"cognition","domain":"reasoning","sort_no":13,"body":{"id":"cog_r1","text":"มีผู้กล่าวว่า «นกทุกชนิดบินได้» แต่เพนกวินเป็นนกที่บินไม่ได้ ข้อนี้สอนให้ตรวจอะไรก่อนสรุปคำว่า «ทุก»","type":"choice","options":[{"v":"a","l":"ตรวจว่ามีข้อยกเว้นหรือไม่ ก่อนสรุปว่าทุกตัวเป็นเช่นนั้น"},{"v":"b","l":"ไม่ต้องสนใจตัวอย่างที่ต่างออกไป"},{"v":"c","l":"สรุปจากคำเดียวเสมอโดยไม่ต้องมีหลักฐาน"},{"v":"d","l":"นกทุกชนิดบินได้แน่นอน"}],"domain":"reasoning","correct":"a"}},{"item_id":"cog_r2","kind":"cognition","domain":"reasoning","sort_no":14,"body":{"id":"cog_r2","text":"ถ้าฝนตก งานกีฬากลางแจ้งจะเลื่อน วันนี้ท้องฟ้าโปร่งและไม่มีฝน ข้อใดสมเหตุสมผลที่สุด","type":"choice","options":[{"v":"a","l":"งานกีฬากลางแจ้งไม่ถูกเลื่อนเพราะฝน"},{"v":"b","l":"งานต้องเลื่อนแน่นอน"},{"v":"c","l":"ฝนจะตกในอีกไม่กี่นาทีอย่างหลีกเลี่ยงไม่ได้"},{"v":"d","l":"โรงเรียนไม่มีงานกีฬา"}],"domain":"reasoning","correct":"a"}},{"item_id":"cog_r3","kind":"cognition","domain":"reasoning","sort_no":15,"body":{"id":"cog_r3","text":"จำนวนนักเรียนในห้องเป็นจำนวนคู่ จึงนับทีละ 2 ได้ลงตัวไม่เหลือเศษ ข้อใดเข้ากันได้","type":"choice","options":[{"v":"a","l":"มีนักเรียน 25 คน"},{"v":"b","l":"มีนักเรียน 31 คน"},{"v":"c","l":"มีนักเรียน 28 คน"},{"v":"d","l":"มีนักเรียน 17 คน"}],"domain":"reasoning","correct":"c"}},{"item_id":"cog_r4","kind":"cognition","domain":"reasoning","sort_no":16,"body":{"id":"cog_r4","text":"กฎของห้องเรียนคือ «ใครมาสายต้องถูกบันทึกชื่อ» เพื่อนคนหนึ่งไม่ถูกบันทึกชื่อ ข้อใดสมเหตุสมผลตามกฎนี้","type":"choice","options":[{"v":"a","l":"ตามกฎที่กล่าว เพื่อนคนนี้ไม่ได้มาสาย"},{"v":"b","l":"การไม่ถูกบันทึกชื่อไม่เกี่ยวกับการมาสาย"},{"v":"c","l":"ทุกคนถูกบันทึกชื่อเสมอ แม้ไม่มาสาย"},{"v":"d","l":"กฎนี้ใช้กับครูเท่านั้น"}],"domain":"reasoning","correct":"a"}},{"item_id":"sh1","kind":"study_habits","domain":"habits","sort_no":1,"body":{"id":"sh1","text":"ฉันวางแผนก่อนลงมือทำการบ้านหรืออ่านหนังสือ","type":"likert","options":[{"v":1,"l":"ยังไม่ค่อยเป็นเช่นนั้น"},{"v":2,"l":"เป็นบ้างเมื่อมีคนชวน"},{"v":3,"l":"เป็นเป็นครั้งคราว"},{"v":4,"l":"เป็นบ่อยเมื่อได้ลอง"},{"v":5,"l":"เป็นเช่นนั้นเกือบทุกครั้ง"}],"facet":"habits"}},{"item_id":"sh2","kind":"study_habits","domain":"habits","sort_no":2,"body":{"id":"sh2","text":"ฉันทบทวนบทเรียนภายในวันที่เรียน","type":"likert","options":[{"v":1,"l":"ยังไม่ค่อยเป็นเช่นนั้น"},{"v":2,"l":"เป็นบ้างเมื่อมีคนชวน"},{"v":3,"l":"เป็นเป็นครั้งคราว"},{"v":4,"l":"เป็นบ่อยเมื่อได้ลอง"},{"v":5,"l":"เป็นเช่นนั้นเกือบทุกครั้ง"}],"facet":"habits"}},{"item_id":"sh3","kind":"study_habits","domain":"habits","sort_no":3,"body":{"id":"sh3","text":"ฉันถามเมื่อไม่เข้าใจ แทนการข้ามไป","type":"likert","options":[{"v":1,"l":"ยังไม่ค่อยเป็นเช่นนั้น"},{"v":2,"l":"เป็นบ้างเมื่อมีคนชวน"},{"v":3,"l":"เป็นเป็นครั้งคราว"},{"v":4,"l":"เป็นบ่อยเมื่อได้ลอง"},{"v":5,"l":"เป็นเช่นนั้นเกือบทุกครั้ง"}],"facet":"habits"}},{"item_id":"sh4","kind":"study_habits","domain":"habits","sort_no":4,"body":{"id":"sh4","text":"ฉันจัดที่นั่งให้เรียบร้อยและลดสิ่งรบกวนก่อนเริ่มงาน","type":"likert","options":[{"v":1,"l":"ยังไม่ค่อยเป็นเช่นนั้น"},{"v":2,"l":"เป็นบ้างเมื่อมีคนชวน"},{"v":3,"l":"เป็นเป็นครั้งคราว"},{"v":4,"l":"เป็นบ่อยเมื่อได้ลอง"},{"v":5,"l":"เป็นเช่นนั้นเกือบทุกครั้ง"}],"facet":"habits"}},{"item_id":"sh5","kind":"study_habits","domain":"habits","sort_no":5,"body":{"id":"sh5","text":"ฉันแบ่งงานยาวเป็นช่วงสั้น ๆ แล้วพักตามที่กำหนด","type":"likert","options":[{"v":1,"l":"ยังไม่ค่อยเป็นเช่นนั้น"},{"v":2,"l":"เป็นบ้างเมื่อมีคนชวน"},{"v":3,"l":"เป็นเป็นครั้งคราว"},{"v":4,"l":"เป็นบ่อยเมื่อได้ลอง"},{"v":5,"l":"เป็นเช่นนั้นเกือบทุกครั้ง"}],"facet":"habits"}},{"item_id":"sh6","kind":"study_habits","domain":"habits","sort_no":6,"body":{"id":"sh6","text":"ฉันตรวจงานอีกครั้งก่อนส่ง","type":"likert","options":[{"v":1,"l":"ยังไม่ค่อยเป็นเช่นนั้น"},{"v":2,"l":"เป็นบ้างเมื่อมีคนชวน"},{"v":3,"l":"เป็นเป็นครั้งคราว"},{"v":4,"l":"เป็นบ่อยเมื่อได้ลอง"},{"v":5,"l":"เป็นเช่นนั้นเกือบทุกครั้ง"}],"facet":"habits"}},{"item_id":"sh7","kind":"study_habits","domain":"habits","sort_no":7,"body":{"id":"sh7","text":"ฉันเชื่อมสิ่งที่เรียนกับตัวอย่างในชีวิตจริงเพื่อให้จำได้","type":"likert","options":[{"v":1,"l":"ยังไม่ค่อยเป็นเช่นนั้น"},{"v":2,"l":"เป็นบ้างเมื่อมีคนชวน"},{"v":3,"l":"เป็นเป็นครั้งคราว"},{"v":4,"l":"เป็นบ่อยเมื่อได้ลอง"},{"v":5,"l":"เป็นเช่นนั้นเกือบทุกครั้ง"}],"facet":"habits"}},{"item_id":"sh8","kind":"study_habits","domain":"habits","sort_no":8,"body":{"id":"sh8","text":"ฉันนอนให้เพียงพอก่อนวันที่มีการสอบหรือนำเสนอ","type":"likert","options":[{"v":1,"l":"ยังไม่ค่อยเป็นเช่นนั้น"},{"v":2,"l":"เป็นบ้างเมื่อมีคนชวน"},{"v":3,"l":"เป็นเป็นครั้งคราว"},{"v":4,"l":"เป็นบ่อยเมื่อได้ลอง"},{"v":5,"l":"เป็นเช่นนั้นเกือบทุกครั้ง"}],"facet":"habits"}}]$assess002items$::jsonb) x
on conflict (item_id) do update
set kind = excluded.kind,
    domain = excluded.domain,
    band = excluded.band,
    sort_no = excluded.sort_no,
    body = excluded.body;

create or replace function public.assess__cog_label(p_answered integer, p_percent numeric)
returns text
language sql
immutable
set search_path = public
as $fn$
  select case
    when coalesce(p_answered, 0) = 0 then 'ยังไม่ทำ'
    when p_percent >= 80 then 'จุดเด่น'
    when p_percent >= 50 then 'ถึงระดับ'
    else 'กำลังพัฒนา'
  end;
$fn$;
comment on function public.assess__cog_label(integer, numeric) is 'assess_* only. Thinking-survey band. Not an IQ score. Not an API.';

create or replace function public.assess__answers(p_student text, p_include_psych boolean)
returns jsonb
language sql
stable
set search_path = public
as $fn$
  select jsonb_strip_nulls(jsonb_build_object(
    'aptitude', (
      select jsonb_object_agg(s.domain, s.items)
      from (
        select i.domain, jsonb_object_agg(i.item_id, r.value_num) as items
        from public.assess_responses r
        join public.assess_items i on i.item_id = r.item_id
        where r.student_id = p_student and i.kind = 'aptitude' and r.value_num is not null
        group by i.domain
      ) s
    ),
    'work', (
      select jsonb_object_agg(s.domain, s.items)
      from (
        select i.domain, jsonb_object_agg(i.item_id, r.value_num) as items
        from public.assess_responses r
        join public.assess_items i on i.item_id = r.item_id
        where r.student_id = p_student and i.kind = 'work' and r.value_num is not null
        group by i.domain
      ) s
    ),
    'ability', (
      select jsonb_object_agg(i.item_id, r.value_num)
      from public.assess_responses r
      join public.assess_items i on i.item_id = r.item_id
      where r.student_id = p_student and i.kind = 'ability' and r.value_num is not null
    ),
    'exercises', (
      select jsonb_object_agg(i.item_id, r.value_text)
      from public.assess_responses r
      join public.assess_items i on i.item_id = r.item_id
      where r.student_id = p_student and i.kind = 'exercises' and r.value_text is not null
    ),
    'potential_survey', (
      select jsonb_object_agg(s.domain, s.items)
      from (
        select i.domain, jsonb_object_agg(i.item_id, r.value_num) as items
        from public.assess_responses r
        join public.assess_items i on i.item_id = r.item_id
        where r.student_id = p_student and i.kind = 'potential_survey' and r.value_num is not null
        group by i.domain
      ) s
    ),
    'study_habits', (
      select jsonb_object_agg(s.domain, s.items)
      from (
        select i.domain, jsonb_object_agg(i.item_id, r.value_num) as items
        from public.assess_responses r
        join public.assess_items i on i.item_id = r.item_id
        where r.student_id = p_student and i.kind = 'study_habits' and r.value_num is not null
        group by i.domain
      ) s
    ),
    'cognition', (
      select jsonb_object_agg(s.domain, s.items)
      from (
        select i.domain, jsonb_object_agg(i.item_id, r.value_text) as items
        from public.assess_responses r
        join public.assess_items i on i.item_id = r.item_id
        where r.student_id = p_student and i.kind = 'cognition' and r.value_text is not null
        group by i.domain
      ) s
    ),
    'psych', case when p_include_psych then (
      select jsonb_object_agg(s.domain, s.items)
      from (
        select i.domain, jsonb_object_agg(i.item_id, r.value_num) as items
        from public.assess_responses r
        join public.assess_items i on i.item_id = r.item_id
        where r.student_id = p_student and i.kind = 'psych' and r.value_num is not null
        group by i.domain
      ) s
    ) else null end
  ));
$fn$;

create or replace function public.assess_save_module(
  p_token text,
  p_student text,
  p_module text,
  p_answers jsonb,
  p_done boolean,
  p_pct integer
)
returns jsonb
language plpgsql
volatile
security definer
set search_path = public, extensions
as $fn$
declare
  u public.assess_users;
  v_student text := btrim(coalesce(p_student, ''));
  v_done boolean;
  v_band text;
begin
  u := public.assess__user(p_token);
  if u.role not in ('student', 'teacher', 'counselor') then
    raise exception 'FORBIDDEN';
  end if;
  if p_module not in (
    'aptitude', 'work', 'ability', 'psych', 'exercises',
    'potential_survey', 'cognition', 'study_habits'
  ) then
    raise exception 'BAD_MODULE';
  end if;
  if p_pct is null or p_pct < 0 or p_pct > 100 then
    raise exception 'BAD_PCT';
  end if;
  if p_answers is null or jsonb_typeof(p_answers) <> 'object' then
    raise exception 'BAD_ANSWERS';
  end if;
  perform public.assess__require_student(u.id, u.role, v_student);
  select band into v_band from public.assess_students where id = v_student;
  if p_module = 'work' and v_band <> 'upper_secondary' then
    raise exception 'BAD_MODULE';
  end if;
  v_done := coalesce(p_done, false) or p_pct = 100;

  delete from public.assess_responses r
  using public.assess_items i
  where r.item_id = i.item_id
    and r.student_id = v_student
    and i.kind = p_module;

  if p_module in ('aptitude', 'work', 'psych', 'potential_survey', 'study_habits') then
    insert into public.assess_responses (student_id, item_id, value_num, updated_by, updated_at)
    select v_student, i.item_id, v.val::numeric, u.id, now()
    from jsonb_each(p_answers) as dom(key, value)
    cross join lateral jsonb_each_text(dom.value) as v(key, val)
    join public.assess_items i
      on i.item_id = v.key
     and i.kind = p_module
     and i.domain = dom.key
    where jsonb_typeof(dom.value) = 'object'
      and v.val ~ '^[1-5]$';
  elsif p_module = 'cognition' then
    insert into public.assess_responses (student_id, item_id, value_text, updated_by, updated_at)
    select v_student, i.item_id, lower(v.val), u.id, now()
    from jsonb_each(p_answers) as dom(key, value)
    cross join lateral jsonb_each_text(dom.value) as v(key, val)
    join public.assess_items i
      on i.item_id = v.key
     and i.kind = 'cognition'
     and i.domain = dom.key
    where jsonb_typeof(dom.value) = 'object'
      and lower(v.val) ~ '^[a-d]$';
  elsif p_module = 'ability' then
    insert into public.assess_responses (student_id, item_id, value_num, updated_by, updated_at)
    select v_student, i.item_id, v.val::numeric, u.id, now()
    from jsonb_each_text(p_answers) as v(key, val)
    join public.assess_items i
      on i.item_id = v.key
     and i.kind = 'ability'
     and i.band = v_band
    where v.val ~ '^[1-4]$';
  elsif p_module = 'exercises' then
    insert into public.assess_responses (student_id, item_id, value_text, updated_by, updated_at)
    select v_student, i.item_id, left(btrim(v.val), 500), u.id, now()
    from jsonb_each_text(p_answers) as v(key, val)
    join public.assess_items i
      on i.item_id = v.key
     and i.kind = 'exercises'
     and i.band = v_band
    where char_length(btrim(v.val)) > 0;
  end if;

  insert into public.assess_progress (student_id, module, done, pct)
  values (v_student, p_module, v_done, p_pct)
  on conflict (student_id, module) do update
  set done = excluded.done, pct = excluded.pct, updated_at = now();

  return jsonb_build_object('ok', true, 'module', p_module, 'done', v_done, 'pct', p_pct);
end
$fn$;
comment on function public.assess_save_module(text, text, text, jsonb, boolean, integer) is 'assess_* only. Save an instrument, including potential_survey, cognition, and study_habits.';

create or replace function public.assess__export_one(p_role text, p_student text)
returns jsonb
language plpgsql
stable
security definer
set search_path = public
as $fn$
declare
  s public.assess_students;
  v_seed jsonb;
  prog jsonb;
  apt jsonb;
  abil jsonb;
  workj jsonb;
  facets jsonb := '[]'::jsonb;
  cog_domains jsonb := '[]'::jsonb;
  rec record;
  n integer;
  m numeric;
  pot_n integer := 0;
  pot_sum numeric := 0;
  pot_mean numeric;
  cog_correct integer := 0;
  cog_total integer := 0;
  cog_answered integer := 0;
  d_correct integer;
  d_total integer;
  d_answered integer;
  d_percent integer;
  sh_n integer;
  sh_mean numeric;
  v_mot numeric;
  v_ls numeric;
  v_pe numeric;
  psych jsonb;
  disc text;
  parent_n integer;
  rubric_n integer;
begin
  select * into s from public.assess_students where id = p_student;
  if not found then
    raise exception 'NO_STUDENT';
  end if;
  v_seed := s.seed;
  prog := public.assess__progress(p_student);
  disc := coalesce((select c.doc->'cognition'->>'disclaimer' from public.assess_catalog c where c.id = 1), '');

  select coalesce(jsonb_agg(jsonb_build_object(
    'id', a.id,
    'name', a.name,
    'score', round(sc, 2)
  ) order by a.ord), '[]'::jsonb)
  into apt
  from (
    select t.ord::integer as ord, t.item->>'id' as id, t.item->>'name' as name,
      coalesce(
        (select avg(r.value_num)
         from public.assess_responses r
         join public.assess_items i on i.item_id = r.item_id
         where r.student_id = p_student and i.kind = 'aptitude' and i.domain = t.item->>'id'),
        nullif(v_seed->'apt'->> (t.item->>'id'), '')::numeric
      ) as sc
    from public.assess_catalog c
    cross join lateral jsonb_array_elements(c.doc->'aptitudes') with ordinality as t(item, ord)
    where c.id = 1
  ) a;

  select coalesce(jsonb_agg(jsonb_build_object(
    'id', g.subject,
    'name', g.subject,
    'score', round(g.sc, 2),
    'level', case
      when g.sc is null then 'ยังไม่ทำ'
      when g.sc >= 3.2 then 'ถึงระดับ'
      when g.sc >= 2.2 then 'กำลังพัฒนา'
      else 'ต้องเสริม'
    end
  ) order by g.subject), '[]'::jsonb)
  into abil
  from (
    select i.domain as subject,
      coalesce(
        avg(r.value_num),
        nullif(v_seed->'ability'->> i.domain, '')::numeric
      ) as sc
    from public.assess_items i
    left join public.assess_responses r
      on r.item_id = i.item_id and r.student_id = p_student and r.value_num is not null
    where i.kind = 'ability' and i.band = s.band
    group by i.domain
  ) g;

  if s.band <> 'upper_secondary' then
    workj := jsonb_build_object(
      'title', 'กลุ่มลักษณะงาน 6 กลุ่ม',
      'available', false,
      'reason', 'เฉพาะมัธยมปลาย',
      'domains', '[]'::jsonb,
      'progress', coalesce(prog->'work', '{"done":false,"pct":0}'::jsonb)
    );
  else
    select coalesce(jsonb_agg(jsonb_build_object(
      'id', a.id, 'name', a.name, 'score', round(a.sc, 2)
    ) order by a.ord), '[]'::jsonb)
    into workj
    from (
      select t.ord::integer as ord, t.item->>'id' as id, t.item->>'name' as name,
        coalesce(
          (select avg(r.value_num)
           from public.assess_responses r
           join public.assess_items i on i.item_id = r.item_id
           where r.student_id = p_student and i.kind = 'work' and i.domain = t.item->>'id'),
          nullif(v_seed->'work'->> (t.item->>'id'), '')::numeric
        ) as sc
      from public.assess_catalog c
      cross join lateral jsonb_array_elements(c.doc->'workGroups') with ordinality as t(item, ord)
      where c.id = 1
    ) a;
    workj := jsonb_build_object(
      'title', 'กลุ่มลักษณะงาน 6 กลุ่ม',
      'available', true,
      'domains', workj,
      'progress', coalesce(prog->'work', '{"done":false,"pct":0}'::jsonb)
    );
  end if;

  for rec in
    select t.ord::integer as ord, t.item->>'id' as id, t.item->>'name' as name
    from public.assess_catalog c
    cross join lateral jsonb_array_elements(c.doc->'potentialSurvey'->'facets') with ordinality as t(item, ord)
    where c.id = 1
    order by t.ord
  loop
    select count(r.value_num), avg(r.value_num) into n, m
    from public.assess_responses r
    join public.assess_items i on i.item_id = r.item_id
    where r.student_id = p_student and i.kind = 'potential_survey' and i.domain = rec.id;
    facets := facets || jsonb_build_array(jsonb_build_object(
      'id', rec.id, 'name', rec.name,
      'score', case when coalesce(n, 0) = 0 then null else round(m, 2) end,
      'n', coalesce(n, 0)
    ));
    pot_n := pot_n + coalesce(n, 0);
    if coalesce(n, 0) > 0 then
      pot_sum := pot_sum + m * n;
    end if;
  end loop;
  pot_mean := case when pot_n = 0 then null else pot_sum / pot_n end;

  for rec in
    select t.ord::integer as ord, t.item->>'id' as id, t.item->>'name' as name
    from public.assess_catalog c
    cross join lateral jsonb_array_elements(c.doc->'cognition'->'domains') with ordinality as t(item, ord)
    where c.id = 1
    order by t.ord
  loop
    select count(*),
           count(r.value_text),
           count(*) filter (where r.value_text = i.body->>'correct')
      into d_total, d_answered, d_correct
    from public.assess_items i
    left join public.assess_responses r
      on r.item_id = i.item_id and r.student_id = p_student
    where i.kind = 'cognition' and i.domain = rec.id;
    d_percent := case when coalesce(d_total, 0) = 0 then 0 else round(100.0 * d_correct / d_total)::integer end;
    cog_domains := cog_domains || jsonb_build_array(jsonb_build_object(
      'id', rec.id,
      'name', rec.name,
      'correct', coalesce(d_correct, 0),
      'total', coalesce(d_total, 0),
      'answered', coalesce(d_answered, 0),
      'percent', case when coalesce(d_answered, 0) = 0 then null else d_percent end,
      'label', public.assess__cog_label(d_answered, d_percent)
    ));
    cog_correct := cog_correct + coalesce(d_correct, 0);
    cog_total := cog_total + coalesce(d_total, 0);
    cog_answered := cog_answered + coalesce(d_answered, 0);
  end loop;

  select count(r.value_num), avg(r.value_num) into sh_n, sh_mean
  from public.assess_responses r
  join public.assess_items i on i.item_id = r.item_id
  where r.student_id = p_student and i.kind = 'study_habits';

  select avg(r.value_num) into v_mot
  from public.assess_responses r
  join public.assess_items i on i.item_id = r.item_id
  where r.student_id = p_student and i.kind = 'psych' and i.domain = 'motivation';
  select avg(r.value_num) into v_ls
  from public.assess_responses r
  join public.assess_items i on i.item_id = r.item_id
  where r.student_id = p_student and i.kind = 'psych' and i.domain = 'learning_style';
  select avg(r.value_num) into v_pe
  from public.assess_responses r
  join public.assess_items i on i.item_id = r.item_id
  where r.student_id = p_student and i.kind = 'psych' and i.domain = 'personality';
  if v_mot is null then
    v_mot := nullif(v_seed->>'motivation', '')::numeric;
  end if;

  if p_role = 'counselor' then
    psych := jsonb_build_object(
      'visibility', 'full',
      'motivation', v_mot,
      'learningStyle', v_ls,
      'personality', v_pe,
      'note', 'เพื่อแนะแนว ไม่ใช่เพื่อวินิจฉัยโรค',
      'progress', coalesce(prog->'psych', '{"done":false,"pct":0}'::jsonb)
    );
  elsif p_role = 'teacher' then
    psych := jsonb_build_object(
      'visibility', 'signal',
      'motivationSignal', case
        when v_mot is null then 'ยังไม่มีข้อมูลแรงจูงใจ'
        when v_mot >= 3 then 'อยู่ในเกณฑ์ที่ส่งเสริมต่อได้'
        else 'ควรพบครูแนะแนวเพื่อพูดคุยเพิ่ม'
      end,
      'note', 'ครูที่ปรึกษาเห็นเฉพาะสัญญาณสรุป',
      'progress', coalesce(prog->'psych', '{"done":false,"pct":0}'::jsonb)
    );
  else
    psych := jsonb_build_object(
      'hidden', true,
      'note', 'ไม่แสดงผลจิตวิทยารายบุคคล',
      'progress', coalesce(prog->'psych', '{"done":false,"pct":0}'::jsonb)
    );
  end if;

  select count(*) into parent_n
  from public.assess_responses r
  join public.assess_items i on i.item_id = r.item_id
  where r.student_id = p_student and i.kind = 'parent';
  select count(*) into rubric_n
  from public.assess_responses r
  join public.assess_items i on i.item_id = r.item_id
  where r.student_id = p_student and i.kind = 'rubric';

  return jsonb_build_object(
    'studentId', s.id,
    'code', s.code,
    'name', s.name,
    'display', s.display_name,
    'grade', s.grade,
    'band', s.band,
    'fictional', s.fictional,
    'instruments', jsonb_build_object(
      'aptitude', jsonb_build_object('title', 'ความถนัด 10 ด้าน', 'domains', apt, 'progress', coalesce(prog->'aptitude', '{"done":false,"pct":0}'::jsonb)),
      'ability', jsonb_build_object('title', 'แบบทดสอบความสามารถ', 'domains', abil, 'progress', coalesce(prog->'ability', '{"done":false,"pct":0}'::jsonb)),
      'work', workj,
      'potential_survey', jsonb_build_object(
        'title', 'แบบสำรวจศักยภาพที่ส่งเสริมได้',
        'domains', facets,
        'mean', case when pot_n = 0 then null else round(pot_mean, 2) end,
        'range', case
          when pot_n = 0 then 'ยังไม่ได้ทำแบบสำรวจศักยภาพที่ส่งเสริมได้'
          when pot_mean >= 4 then 'ช่วงสูงที่ส่งเสริมต่อได้ดี หากมีแผนต่อเนื่อง'
          when pot_mean >= 3 then 'ช่วงกลาง–สูง ที่ส่งเสริมตรงจุดแล้วจะเห็นการเติบโตชัด'
          when pot_mean >= 2 then 'ช่วงที่ยังส่งเสริมได้หลายด้าน ควรเก็บข้อมูลเพิ่มและฝึกสม่ำเสมอ'
          else 'ช่วงเริ่มต้นของการส่งเสริม เน้นสร้างนิสัยและแรงจูงใจ ไม่ติดป้ายจำกัดชะตา'
        end,
        'progress', coalesce(prog->'potential_survey', '{"done":false,"pct":0}'::jsonb)
      ),
      'cognition', jsonb_build_object(
        'title', 'แบบสำรวจการคิดและเหตุผล',
        'disclaimer', disc,
        'domains', cog_domains,
        'overall', jsonb_build_object(
          'correct', cog_correct,
          'total', cog_total,
          'answered', cog_answered,
          'percent', case when cog_answered = 0 then null else round(100.0 * cog_correct / nullif(cog_total, 0))::integer end,
          'label', public.assess__cog_label(cog_answered, case when cog_total = 0 then 0 else round(100.0 * cog_correct / cog_total) end)
        ),
        'progress', coalesce(prog->'cognition', '{"done":false,"pct":0}'::jsonb)
      ),
      'study_habits', jsonb_build_object(
        'title', 'แบบสำรวจนิสัยการเรียน',
        'mean', case when coalesce(sh_n, 0) = 0 then null else round(sh_mean, 2) end,
        'sentence', case
          when coalesce(sh_n, 0) = 0 then 'ยังไม่ได้ทำแบบสำรวจนิสัยการเรียน'
          when sh_mean >= 4 then 'นิสัยการเรียนอยู่ในช่วงที่ทำได้สม่ำเสมอ และยังส่งเสริมต่อได้'
          when sh_mean >= 3 then 'นิสัยการเรียนอยู่ในช่วงที่ทำได้เป็นครั้งคราว ฝึกต่อแล้วจะชัดขึ้น'
          else 'นิสัยการเรียนยังเริ่มต้น ฝึกทีละเรื่องสั้น ๆ จะช่วยให้คงที่ขึ้น'
        end,
        'progress', coalesce(prog->'study_habits', '{"done":false,"pct":0}'::jsonb)
      ),
      'psych', psych,
      'exercises', jsonb_build_object('title', 'แบบฝึกสั้น', 'progress', coalesce(prog->'exercises', '{"done":false,"pct":0}'::jsonb)),
      'personality', jsonb_build_object('title', 'พัฒนาบุคลิกภาพ', 'progress', coalesce(prog->'personality', '{"done":false,"pct":0}'::jsonb)),
      'parentHome', jsonb_build_object('title', 'แบบสอบถามที่บ้าน', 'answered', parent_n),
      'teacherRubric', jsonb_build_object('title', 'บันทึกสังเกต/รูบริก', 'answered', rubric_n)
    )
  );
end
$fn$;
comment on function public.assess__export_one(text, text) is 'assess_* only. One student combined result. Not granted to anon.';

create or replace function public.assess_export_results(p_token text, p_student_id text default null)
returns jsonb
language plpgsql
volatile
security definer
set search_path = public, extensions
as $fn$
declare
  u public.assess_users;
  v_student text := nullif(btrim(coalesce(p_student_id, '')), '');
  s public.assess_students;
  v_status text;
  v_report jsonb;
  v_by text;
  keys jsonb := '["aptitude","ability","work","psych","exercises","personality","parentHome","teacherRubric","potential_survey","cognition","study_habits"]'::jsonb;
  hidden jsonb;
begin
  u := public.assess__user(p_token);

  if v_student is null and u.role = 'admin' then
    return jsonb_build_object(
      'mode', 'aggregate',
      'role', 'admin',
      'instruments', keys,
      'psychology', 'hidden',
      'note', 'ไม่แสดงผลจิตวิทยารายบุคคล และไม่แสดงกลุ่มที่น้อยกว่า 10 คน',
      'bands', (
        select coalesce(jsonb_agg(jsonb_build_object(
          'band', b.band,
          'count', b.n,
          'shown', b.n >= 10,
          'message', case when b.n >= 10 then b.n::text || ' คน' else 'ไม่แสดงกลุ่มที่น้อยกว่า 10 คน' end
        ) order by b.band), '[]'::jsonb)
        from (
          select band, count(*)::integer as n
          from public.assess_students
          group by band
        ) b
      ),
      'statusCounts', (
        select jsonb_object_agg(status, n)
        from (select status, count(*)::integer as n from public.assess_students group by status) c
      )
    );
  end if;

  if v_student is null and u.role in ('teacher', 'counselor') then
    return jsonb_build_object(
      'mode', 'list',
      'role', u.role,
      'instruments', keys,
      'students', (
        select coalesce(jsonb_agg(public.assess__export_one(u.role, st.id) order by st.sort_no), '[]'::jsonb)
        from public.assess_students st
        where public.assess__can_see(u.id, u.role, st.id)
      )
    );
  end if;

  if v_student is null and u.role in ('parent', 'student') then
    select st.id into v_student
    from public.assess_user_students us
    join public.assess_students st on st.id = us.student_id
    where us.user_id = u.id
    order by st.sort_no
    limit 1;
    if v_student is null then
      raise exception 'NO_STUDENT';
    end if;
  end if;

  perform public.assess__require_student(u.id, u.role, v_student);

  if u.role in ('parent', 'student') then
    select r.status, r.report, au.display_name
      into v_status, v_report, v_by
    from public.assess_reports r
    left join public.assess_users au on au.id = r.approved_by
    where r.student_id = v_student;
    select * into s from public.assess_students where id = v_student;
    hidden := (
      select jsonb_object_agg(k, jsonb_build_object('available', false, 'status', coalesce(v_status, s.status, 'started')))
      from jsonb_array_elements_text(keys) k
    ) || jsonb_build_object('psych', jsonb_build_object('hidden', true, 'note', 'ไม่แสดงผลจิตวิทยาดิบ'));
    if v_report is null or v_status is distinct from 'approved' then
      return jsonb_build_object(
        'mode', 'student',
        'role', u.role,
        'studentId', s.id,
        'code', s.code,
        'name', s.name,
        'display', s.display_name,
        'grade', s.grade,
        'band', s.band,
        'fictional', s.fictional,
        'approved', false,
        'report', jsonb_build_object('status', coalesce(v_status, s.status)),
        'instruments', hidden
      );
    end if;
    return jsonb_build_object(
      'mode', 'student',
      'role', u.role,
      'studentId', s.id,
      'code', s.code,
      'name', s.name,
      'display', s.display_name,
      'grade', s.grade,
      'band', s.band,
      'fictional', s.fictional,
      'approved', true,
      'report', (v_report - 'psych') || jsonb_build_object('status', 'approved', 'approvedBy', v_by),
      'instruments', jsonb_build_object(
        'aptitude', coalesce(v_report->'aptitude', '{"available":false}'::jsonb),
        'ability', coalesce(v_report->'ability', '{"available":false}'::jsonb),
        'work', coalesce(v_report->'work', '{"available":false}'::jsonb),
        'psych', '{"hidden":true,"note":"ไม่แสดงผลจิตวิทยาดิบ"}'::jsonb,
        'exercises', coalesce(v_report->'exercises', '{"available":false}'::jsonb),
        'personality', coalesce(v_report->'personality', '{"available":false}'::jsonb),
        'parentHome', coalesce(v_report->'parentHome', '{"available":false}'::jsonb),
        'teacherRubric', coalesce(v_report->'teacherRubric', '{"available":false}'::jsonb),
        'potential_survey', coalesce(v_report->'potentialSurvey', v_report->'potential_survey', '{"available":false}'::jsonb),
        'cognition', coalesce(v_report->'cognition', '{"available":false}'::jsonb),
        'study_habits', coalesce(v_report->'studyHabits', v_report->'study_habits', '{"available":false}'::jsonb)
      )
    );
  end if;

  return public.assess__export_one(u.role, v_student) || jsonb_build_object('mode', 'student', 'role', u.role);
end
$fn$;
comment on function public.assess_export_results(text, text) is 'assess_* only. Combined results for every instrument. Hides raw psychology from admin, parents, and students; teachers get a signal only.';

revoke all on function public.assess__cog_label(integer, numeric) from public, anon, authenticated;
revoke all on function public.assess__export_one(text, text) from public, anon, authenticated;
revoke all on function public.assess_export_results(text, text) from public;
grant execute on function public.assess_export_results(text, text) to anon, authenticated, service_role;

do $assess_002_check$
declare
  n integer;
begin
  select count(*) into n from public.assess_items where kind in ('potential_survey', 'cognition', 'study_habits');
  if n <> 36 then
    raise exception 'assess_002 item count %', n;
  end if;
  if (select count(*) from public.assess_items where kind = 'potential_survey') <> 12 then
    raise exception 'assess_002 potential_survey';
  end if;
  if (select count(*) from public.assess_items where kind = 'cognition') <> 16 then
    raise exception 'assess_002 cognition';
  end if;
  if (select count(*) from public.assess_items where kind = 'study_habits') <> 8 then
    raise exception 'assess_002 study_habits';
  end if;
  if (select count(*) from public.assess_items where kind = 'aptitude') <> 50 then
    raise exception 'assess_002 aptitude preserved';
  end if;
  if not exists (
    select 1 from public.assess_catalog
    where id = 1
      and doc ? 'aptitudeBank'
      and doc ? 'potentialSurvey'
      and doc ? 'cognition'
      and doc ? 'studyHabits'
  ) then
    raise exception 'assess_002 catalog merge';
  end if;
  if exists (
    select 1 from public.assess_items
    where kind = 'cognition' and (body->>'correct') is null
  ) then
    raise exception 'assess_002 missing correct';
  end if;
end
$assess_002_check$;

notify pgrst, 'reload schema';
