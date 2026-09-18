# L2HC-native-linux

> **Полностью нативная чистая реализация аудиокодека Huawei L2HC для Linux (PipeWire / BlueZ)**

[![License: MIT](https://img.shields.io/badge/License-MIT-blue.svg)](LICENSE)
[![Release](https://img.shields.io/github/v/release/darakcheeff/L2HC-native-linux)](https://github.com/darakcheeff/L2HC-native-linux/releases)
[![Platform](https://img.shields.io/badge/platform-Linux%20x86__64-lightgrey)](https://github.com/darakcheeff/L2HC-native-linux)

[English version](README.md)

---

## 🎧 Описание

**L2HC-native-linux** — это самостоятельная, нативная реализация кодека **Huawei L2HC** (Low-Latency High-Definition Codec) на языке Си. Обеспечивает беспроводную передачу звука высокого разрешения (**до 960 кбит/с, 24 бит / 48–96 кГц**) в Linux через **PipeWire** и **BlueZ**.

В отличие от решений на базе эмуляции (QEMU + Android Bionic), кодек **L2HC-native-linux** работает **напрямую на процессоре x86_64**. Никаких внешних эмуляторов, сервисов и закрытых бинарников не требуется.

---

## ✨ Ключевые возможности

- **100% Native C99:** Чистая реализация математического аппарата кодека без проприетарных зависимостей.
- **Высочайшая производительность (>40x Realtime):** Кодирование 10-мс фрейма занимает всего ~0.23 мс (<2.5% нагрузки одного ядра современного CPU).
- **Звук без артефактов (`EncodeMDCTCountBits`):** Точный цикл обратной связи по битрейту полностью исключает переполнение буфера и обрезку частотного диапазона.
- **Адаптивное квантование:** Автоматический подбор оптимальных таблиц Хаффмана для 1-, 2- и 4-кортежей.
- **Поддержка тонких резидуалов (`PackMDCTResBranch`):** Весь свободный битрейт фрейма направляется на повышение детализации спектра.
- **Простая интеграция:** Поддерживается PipeWire 0.3 / 1.x, WirePlumber, Blueman, `pavucontrol`, GNOME и MATE.
- **Поддерживаемые битрейты:**
  - `320 кбит/с` (Высокое качество, максимальная стабильность соединения)
  - `640 кбит/с` (Очень высокое качество)
  - `960 кбит/с` (Студийное качество / Audiophile)
  - `Auto` (Адаптивный битрейт в зависимости от радиоканала)

---

## 📦 Быстрая установка (.deb)

1. Скачайте пакет со страницы [Releases](https://github.com/darakcheeff/L2HC-native-linux/releases):
   ```bash
   wget https://github.com/darakcheeff/L2HC-native-linux/releases/download/v1.0.0/l2hc-native-linux_1.0.0_amd64.deb
   ```
2. Установите пакет:
   ```bash
   sudo dpkg -i l2hc-native-linux_1.0.0_amd64.deb
   sudo apt-get install -f
   ```
3. Подключите наушники Huawei (FreeBuds Studio, FreeBuds Pro и др.) и выберите профиль **L2HC** в настройках звука или в Blueman.

---

## 🛠️ Сборка из исходников

```bash
git clone https://github.com/darakcheeff/L2HC-native-linux.git
cd L2HC-native-linux
make check
```

Сборка установочного Debian-пакета:
```bash
./scripts/build_deb.sh
```
Готовый `.deb` пакет появится в каталоге `dist/`.

---


---

## 📚 Техническая документация и спецификации

Подробное математическое описание, спецификации формата потока и заметки по реверс-инжинирингу доступны в каталоге [`docs/`](docs/):

- **[Полная спецификация кодека L2HC](docs/L2HC_SPECIFICATION.md):** Полное техническое описание согласования AVDTP CIE, банка фильтров MDCT, 32 критических полос Барка, дифференциальных масштабных коэффициентов и психоакустического квантования.
- **[Архитектура DSP и заметки по реверсу](docs/DSP_ALGORITHM.md):** Сопоставление функций декомпиляции Ghidra (`EncodeMDCTMainLoop`, `EncodeMDCTCountBits`, `CountBitsRough`, `QuantMDCT` и др.) с нативной C-реализацией.
- **[Спецификация битового потока (Wire Format)](docs/BITSTREAM_FORMAT.md):** Побитовая и побайтная схема упаковки заголовков, Хаффмана, знаковых битов и резидуалов.

## 🎧 Поддерживаемые устройства

- **Huawei FreeBuds Studio**
- **Huawei FreeBuds Pro / Pro 2 / Pro 3**
- **Huawei FreeClip**
- Любые другие наушники с поддержкой кодека L2HC (`Vendor ID: 0x027d`, `Codec ID: 0x3500`).

---

## 📄 Лицензия

Проект распространяется под свободной лицензией [MIT](LICENSE).
