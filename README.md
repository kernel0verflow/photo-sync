# 📸 FotoSync (ADB → USB Backup)

**FotoSync** ist ein bewusst **einseitiges, sicheres Foto-Backup-Tool** für Android-Geräte.  
Es kopiert Fotos (und andere Mediendaten) **per ADB** vom Smartphone auf einen **fest definierten USB-Stick** – **ohne Cloud**, **ohne Löschen**, **ohne Überschreiben**.

Das Ziel ist ein **idiotensicheres Langzeitarchiv**, ideal in Kombination mit **digiKam**.

---

## ✨ Features

- ✅ **One-Way-Backup** (Smartphone → USB)
- ✅ **Nie löschen, nie überschreiben**
- ✅ **ADB-basiert** (kein MTP, kein Mount)
- ✅ **Mehrere Sync-Jobs** (Camera, WhatsApp, Screenshots, Apps, …)
- ✅ **USB-Stick eindeutig per UUID abgesichert**
- ✅ **Smartphone eindeutig per ADB-ID abgesichert**
- ✅ **Optionaler Dry-Run**
- ✅ **Linux-first** (Arch / Debian / Ubuntu)

---

## ❌ Was dieses Tool bewusst NICHT macht

- ❌ Kein Mirror / kein `--delete`
- ❌ Kein Cloud-Sync
- ❌ Kein Zurückkopieren auf das Smartphone
- ❌ Keine automatische Ordner-Umstrukturierung
- ❌ Keine Datenbank-Magie (das macht digiKam)

---

## 🧠 Philosophie

> **Ein Backup darf niemals automatisch kleiner werden.**

Fotos, die einmal auf dem USB-Stick sind, **bleiben dort** –  
egal, ob sie auf dem Smartphone gelöscht, verschoben oder überschrieben werden.

---

## 🔧 Voraussetzungen

### Hardware
- Android-Smartphone mit USB-Debugging
- USB-Stick (empfohlen: `exFAT` oder `ext4`)
- Datenfähiges USB-Kabel (⚠️ kein reines Ladekabel)

### Software
- Linux
- `adb` / `android-tools`
- Paketmanager:
  - Arch: `pacman`
  - Debian/Ubuntu: `apt`

---

## 🚀 Installation

```bash
git clone <repo-url>
cd fotosync
chmod +x fotosync.sh
