# ศัพท์สนุก Word Quest · โรงเรียนปิยมิตรวิทยา ฝ่ายมัธยม

เกมฝึกคำศัพท์ภาษาอังกฤษ (PWA) สำหรับนักเรียน ม.ต้น–ม.ปลาย ไต่ระดับ CEFR A1 → C2 · ภารกิจเช้า 10–20 คำ/วัน

- แอปนักเรียน: `index.html` · Dashboard ครู: `teacher.html` · ความเป็นส่วนตัว: `privacy.html` · แหล่งข้อมูล: `about.html`
- โหมด: ทายภาพ→คำ (หลัก), จับคู่ภาพกับคำ, ฟังแล้วเลือก, ฝึกออกเสียง (TTS + Speech Recognition ถ้ารองรับ), ไทม์รัช 60 วิ, บอส, ทบทวนคำยาก
- Static site (GitHub Pages) + Supabase RPC (เฉพาะ publishable/anon key ในหน้าเว็บ; ตารางทั้งหมดปิดด้วย RLS เข้าถึงผ่านฟังก์ชันที่ตรวจ token เท่านั้น)

## Credits / Licences
- **CEFR-J Wordlist Version 1.5** — Yukio Tono, Tokyo University of Foreign Studies (Tono Laboratory). Free for research and commercial use with citation. http://www.cefr-j.org/download.html · via https://github.com/openlanguageprofiles/olp-en-cefrj
- **Octanove Vocabulary Profile C1/C2 v1.0** — Octanove Labs, CC BY-SA 4.0. The C1/C2 portion of `data/words.json` is an adaptation and is shared under CC BY-SA 4.0.
- Fonts: Kanit, Fredoka — SIL Open Font License 1.1.
- Illustrations: original AI-generated artwork made for this school. Thai meanings & example sentences: school team (under review).
