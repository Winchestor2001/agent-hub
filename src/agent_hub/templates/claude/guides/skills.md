# Skill'lar

Skill — Claude kerak bo'lganda o'zi yuklaydigan yo'riqnoma to'plami. Har skill alohida papka: `<nom>/SKILL.md` (yonida skriptlar va misollar ham turishi mumkin).

## SKILL.md tuzilishi

```markdown
---
name: deploy
description: Foydalanuvchi deploy so'raganda ishlatiladi. Build, test va chiqarish qadamlari.
---

# Deploy
1. ...
```

- `description` majburiy: Claude skill'ni aynan shu matn bo'yicha tanlaydi — **nima** va **qachon** ekanini yozing.
- Nom: kichik harf, raqam va tire (`deploy`, `db-migrate`), 64 belgigacha. Papka nomi bilan bir xil bo'lsin.

## 1. Global skill (barcha loyihalar)

Qamrov: **Global** → `~/.claude/skills/<nom>/SKILL.md`. Har bir loyihada ishlaydi.

## 2. Bitta loyiha uchun skill

Qamrov: **loyiha** → `<loyiha>/.claude/skills/<nom>/SKILL.md`. Faqat shu loyihada ishlaydi; git'ga qo'shsangiz jamoa ham oladi.

## 3. Bir nechta loyiha uchun skill

Skill'ni yozing va **"Qo'llash"** orqali kerakli loyihalarni belgilang: har loyihaga alohida nusxa yoziladi. Natija har loyiha uchun alohida ko'rsatiladi (yaratildi / yangilandi / o'zgarmadi / xato). Barcha loyihalarga kerak bo'lsa — globalga yozish soddaroq.

## Ustuvorlik va yopilish

Bir xil nomli skill global va loyihada bo'lsa, **Personal (global) ustun**: global skill loyiha skill'ini **yopadi** va loyihadagi nusxa ishlamaydi. Agent Hub bunday holatda ogohlantiradi. Loyiha nusxasi ishlashi kerak bo'lsa, unga boshqa nom bering.
