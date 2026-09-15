/**
 * O'zbek (lotin) lug'ati — kalitlar to'plami uchun manba.
 *
 * Boshqa tillar `Dictionary` turida yoziladi: kalit yetishmasa yoki ortiqcha bo'lsa tsc xato beradi.
 * `{nom}` — o'rinbosar; `t()` ularni turdan tekshiradi.
 */
export const uz = {
  "app.title": "Agent Hub",
  "app.backend_version": "backend v{version}",

  "status.kanbot_online": "KanBot v{version}",
  "status.kanbot_offline": "KanBot o'chiq",
  "status.runners": "Runner: {count}",
  "status.agents_none": "agent yo'q",
  "status.checking": "Tekshirilmoqda…",
  "status.backend_offline": "Backend javob bermayapti",

  "panel.projects": "Loyihalar",
  "panel.board": "Doska",
  "panel.sessions": "Sessiyalar",

  "projects.empty": "Loyihalar yo'q",
  "projects.loading": "Loyihalar yuklanmoqda…",
  "projects.tasks": "{count} ta vazifa",
  "projects.backlog_error": "bekloq o'qilmadi",

  "board.select_project": "Chapdan loyiha tanlang",
  "board.placeholder": "Vazifalar doskasi shu yerda bo'ladi",

  "sessions.live": "Jonli agentlar",
  "sessions.past": "O'tgan sessiyalar",
  "sessions.none": "yo'q",
  "sessions.loading": "yuklanmoqda…",
  "sessions.unavailable": "KanBot ishlamayapti — sessiyalar ko'rinmaydi",

  "banner.backend_unreachable": "Agent Hub backend bilan aloqa yo'q. Ma'lumotlar yangilanmayapti.",
  "banner.kanbot_unavailable":
    "KanBot ishlamayapti — sessiyalar ko'rinmaydi va yangisini ochib bo'lmaydi. Ishga tushirish: make dev-kanbot",
  "banner.no_runner":
    "KanBot runner ulanmagan — agent ishga tushirib bo'lmaydi. Ishga tushirish: make dev-runner",
  "banner.backlog_cli_missing": "backlog CLI topilmadi — vazifalar o'qilmaydi",
  "banner.backlog_not_found": "«{project}» loyihasida bekloq topilmadi: {path}",
  "banner.backlog_error": "«{project}» loyihasining bekloqi o'qilmadi",

  "error.unknown": "Kutilmagan xato ({code})",
  "error.backend_unreachable": "Agent Hub backend bilan aloqa yo'q",
  "error.internal_error": "Serverda ichki xato",
  "error.not_found": "Topilmadi",
  "error.validation_error": "So'rov maydonlari noto'g'ri",

  "error.project_not_found": "«{id}» loyihasi topilmadi",
  "error.project_exists": "«{id}» loyihasi allaqachon bor",
  "error.project_id_invalid": "Loyiha ID noto'g'ri: «{id}»",
  "error.project_name_empty": "Loyiha nomi bo'sh",
  "error.path_invalid": "Papka topilmadi: {path}",
  "error.registry_invalid": "Loyihalar ro'yxati buzilgan: {path}",

  "error.backlog_error": "Bekloq xatosi",
  "error.backlog_not_found": "Bekloq topilmadi: {path}",
  "error.backlog_cli_missing": "backlog CLI topilmadi",
  "error.backlog_cli_error": "backlog buyrug'i xato bilan tugadi",
  "error.backlog_bad_output": "backlog kutilmagan javob qaytardi",
  "error.backlog_locked": "Vazifa hozir boshqa jarayonda tahrirlanmoqda, qayta urinib ko'ring",
  "error.backlog_timeout": "backlog javob bermadi",
  "error.task_not_found": "Vazifa topilmadi",
  "error.task_id_invalid": "Vazifa ID noto'g'ri: «{task_id}»",
  "error.status_invalid": "Status noto'g'ri: «{status}». Mumkin: {allowed}",
  "error.field_invalid": "Maydon noto'g'ri: {field}",

  "error.kanbot_error": "KanBot xatosi",
  "error.kanbot_unavailable": "KanBot ishlamayapti",
  "error.kanbot_no_runner": "KanBot'da ulangan runner yo'q",
  "error.kanbot_runner_error": "Runner so'rovni bajara olmadi",
  "error.pane_not_found": "Sessiya topilmadi yoki runner o'chiq",
  "error.pane_id_invalid": "Sessiya ID noto'g'ri",
  "error.agent_invalid": "Agent noto'g'ri: «{agent}». Mumkin: {allowed}",
  "error.agent_unavailable": "Runner'da «{agent}» agenti yo'q",
  "error.runner_offline": "Sessiya runner'i o'chiq",
  "error.runner_unsafe": "Runner xavfsiz rejimda emas — sessiya ochilmaydi",
  "error.cwd_outside_project": "Papka «{project}» loyihasiga tegishli emas: {cwd}",
  "error.session_not_found": "Sessiya topilmadi",
  "error.session_active": "Sessiya hozir ochiq",
  "error.session_id_invalid": "Sessiya ID noto'g'ri",

  "error.shell_enabled": "Xavfli «{agent}» agenti yoqilgan. O'chirish: kanbot config --disable shell glm kimi",
  "error.agent_enabled": "Xavfli «{agent}» agenti yoqilgan. O'chirish: kanbot config --disable shell glm kimi",
  "error.auto_approve_enabled":
    "Auto-approve yoqilgan — agentlar ruxsat so'ramasdan buyruq bajaradi. Runner --safe bilan ishlashi kerak",
  "error.multiple_runners": "Bir nechta runner ulangan: {runners}",
  "error.kanbot_version_unsupported": "KanBot {version} qo'llab-quvvatlanmaydi (kerak: {supported})",
  "error.kanbot_config_missing": "KanBot sozlamasi topilmadi: {path}",
  "error.kanbot_config_unreadable": "KanBot sozlamasi o'qilmadi: {path}",
} as const;
