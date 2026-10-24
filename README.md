<div align="center">

# 🦜 Popug Cloud · selfsteal

**Сайт-маскировка для Reality-нод в режиме «self-steal»: ставится одной командой, настраивается в мастере прямо в терминале.**

[![release](https://img.shields.io/github/v/release/Popugtop/popug-cloud-selfsteal?style=flat-square&color=e58f33&label=release)](https://github.com/Popugtop/popug-cloud-selfsteal/releases/latest)
![Debian 12+ / Ubuntu 22.04+](https://img.shields.io/badge/Debian_12+_·_Ubuntu_22.04+-2a5745?style=flat-square)
![Caddy](https://img.shields.io/badge/Caddy-2.11-2a5745?style=flat-square)
![shellcheck](https://img.shields.io/badge/shellcheck-clean-2f9e5c?style=flat-square)

[Быстрый старт](#-быстрый-старт) · [Мастер установки](#-мастер-установки) · [Шаблоны](#-шаблоны) · [Команды](#%EF%B8%8F-команды) · [Переустановка](#-переустановка-и-удаление) · [DEPLOY.md](DEPLOY.md)

</div>

---

У каждой ноды свой домен (`se1.cdn.popug.cloud`, `pl1.api.popug.cloud`, …), настоящий сертификат Let's Encrypt
и правдоподобная страница за ним: CDN-узел, JSON API, S3-эндпоинт, container registry. Порт 443 держит Xray и
отдаёт этому сайту всё, что не является Reality-подключением. Сканер или браузер видит обычный сервис небольшого
облачного провайдера.

```
клиент ──443──▶ Xray (Reality) ──не-Reality трафик──▶ 127.0.0.1:8443  Caddy + шаблон
```

Саму ноду (Remnanode / Xray, управляется из панели Remnawave) скрипт **не ставит и не меняет** — он отвечает
только за сайт.

## 🚀 Быстрый старт

1. **DNS.** Создай `A`-запись для ноды, например `se1.cdn.popug.cloud` → IP ноды
   (и не оставляй `AAAA`-запись, которая указывает куда-то ещё).
2. **Запусти** на ноде от root:

   ```bash
   bash <(curl -Ls https://github.com/Popugtop/popug-cloud-selfsteal/releases/latest/download/selfsteal.sh)
   ```

3. Выбери **Install**, пройди мастер и перенеси значения, которые он напечатает, в Reality-профиль ноды в панели:

   ```
   serverNames : ["se1.cdn.popug.cloud"]
   target/dest : "127.0.0.1:8443"
   xver        : 0
   ```

Всё. Дальше на ноде достаточно набрать `selfsteal` — откроется то же меню.

## 🧭 Мастер установки

```
  ┌  selfsteal 0.2.1  ·  install  · step 3/6
  │
  ◇  Domain     se1.cdn.popug.cloud
  ◇  DNS        ✓ 203.0.113.10 — this server
  │
  ◆  Template
  │  What a visitor or a scanner sees at https://se1.cdn.popug.cloud/
  │
  │    ○ api       JSON API gateway
  │  ❯ ● cdn       Edge asset host  ★ suggested
  │    ○ console   Console sign-in (invite-only notice)
  │    ○ default   Neutral placeholder for any host
  │    ○ docs      Documentation site
  │    ○ registry  Container registry endpoint
  │    ○ storage   S3-style object storage endpoint
  │
  └  ↑↓ move · enter select · ← back · ctrl+c quit
```

| Шаг | Что происходит |
|---|---|
| **Domain** | домен проверяется сразу; в подсказке — публичный IP сервера, на который должна указывать A-запись |
| **DNS check** | «проверить сейчас» или «пропустить». Проверка идёт прямо в окне; если запись не та — видно почему, и можно **проверить ещё раз**, **сменить домен** или **продолжить всё равно** |
| **Template** | выбор стрелками; шаблон, подходящий по имени (`*.cdn.*` → `cdn`, `*.api.*` → `api`, `*.s3.*` → `storage`, …), выбран заранее |
| **Port** | loopback-порт для `target` в Xray, по умолчанию `8443`; если он занят — мастер сразу скажет кем |
| **E-mail** | необязательно, для писем Let's Encrypt об истечении сертификата |
| **Options** | правила ufw · включить ufw · staging-сертификат · предложить установщик ноды в конце |
| **Review** | все значения на одном экране, любое можно поменять — **до нажатия *Install* на сервере ничего не меняется** |

Клавиши: `↑↓` — перемещение · `enter` — выбор · `пробел` — галочка · `←` — назад · `ctrl+c` — выход.

Главное меню (`selfsteal` без аргументов) показывает текущее состояние и даёт **Status, Re-configure, Template,
Domain, Logs, Restart, Certificate, Update, Uninstall, Prepare**. Ошибка в одном действии возвращает в меню,
а не закрывает его.

### Без мастера

Для скриптов и массовой раскатки всё по-прежнему доступно флагами:

```bash
bash <(curl -Ls https://github.com/Popugtop/popug-cloud-selfsteal/releases/latest/download/selfsteal.sh) @ install \
  --domain se1.cdn.popug.cloud --template cdn --yes
```

С `--yes`, без терминала или с `SELFSTEAL_NO_TUI=1` ничего не спрашивается. В терминале флаги подставляются в
мастер как готовые значения; если переданы и `--domain`, и `--template`, `install` идёт без мастера.

## 🎭 Шаблоны

| Шаблон | Для | Типичные хосты | Что отвечает |
|---|---|---|---|
| `cdn` | ноды | `se1.cdn.popug.cloud` | фирменная 404 на `/`, статика в `/assets/` |
| `api` | ноды | `pl1.api.popug.cloud` | `{"service":"popug-api","status":"ok",…}`, JSON 401/404 |
| `storage` | ноды | `us1.s3.popug.cloud` | XML в стиле S3: `AccessDenied`, `NoSuchBucket`, `InvalidBucketName` |
| `registry` | ноды | `ru1.registry.popug.cloud` | короткая страница, `401` как у registry на `/v2/` |
| `default` | ноды | всё остальное | нейтральная страница «you have reached a Popug Cloud endpoint» |
| `root` | основной сервер | `popug.cloud`, `www.popug.cloud` | лендинг |
| `docs` | основной сервер | `docs.popug.cloud` | документация: обзор, quickstart, auth, storage, CDN, API, CLI |
| `status` | основной сервер | `status.popug.cloud` | статус-страница с историей за 90 дней |
| `console` | основной сервер | `console.popug.cloud`, `auth.popug.cloud` | страница входа и «private beta», форма никуда не отправляет |

Имена: `<страна><n>.<роль>.popug.cloud` — `cdn`: se1, se2, cz1, nl1, lv1, ee1, de1 · `api`: pl1, sg1 ·
`s3`: us1, tr1 · `registry`: ru1. Страницы основного сервера добавляются в уже работающий Caddy через `prepare`
(см. [DEPLOY.md §4](DEPLOY.md#4-the-main-domain-on-a-server-where-caddy-apt-already-runs)).

Всё статическое: без бэкенда, внешних шрифтов / CDN / аналитики, без JavaScript и без форм, которые что-то отправляют.

### Каждая нода немного отличается

Seed (домен + machine-id) делает каждую установку уникальной, но стабильной при переустановке:

- имена файлов ассетов заменяются хешами, ссылки переписываются;
- разные `Last-Modified` / `ETag`;
- меняются build id, версия API, `HostId` в XML-ошибках, даты и история аптайма;
- порядок некоторых списков перемешан;
- заголовка `Server` нет нигде (в том числе на 404), правильные заголовки кэша и безопасности.

## ⌨️ Команды

```
selfsteal                     интерактивное меню
selfsteal install             установить или применить заново (идемпотентно)
selfsteal update [--to TAG]   новый установщик и шаблоны; настройки и сертификаты сохраняются
selfsteal status              состояние, контейнер, порты, сертификат
selfsteal logs [-f] [--tail N]
selfsteal restart
selfsteal template [NAME]     сменить шаблон (без NAME — выбор из списка)
selfsteal domain [NAME]       сменить домен (без NAME — мастер с проверкой DNS)
selfsteal cert                выбросить сертификат и выпустить заново
selfsteal uninstall [--purge] удалить сайт (--purge — вместе с сертификатами)
selfsteal templates           список шаблонов
selfsteal prepare             только распаковать шаблон для УЖЕ установленного Caddy
```

<details>
<summary><b>Все флаги</b></summary>

| Флаг | Значение |
|---|---|
| `--domain NAME` | домен ноды (A/AAAA должны указывать на этот сервер) |
| `--template NAME` | какой шаблон отдавать |
| `--port N` | loopback-порт для `target` в Xray (по умолчанию `8443`) |
| `--email ADDR` | контактный e-mail для удостоверяющего центра |
| `--staging` | тестовый CA Let's Encrypt на этот запуск |
| `--skip-dns-check` | не проверять DNS-записи |
| `--no-ufw` / `--enable-ufw` | не трогать фаервол / установить и включить ufw |
| `--with-node` | в конце предложить запустить сторонний `remnanode.sh` (качается и запускается от root, **не проверяется**) |
| `--seed STRING` | seed для рандомизации |
| `--purge` | с `uninstall`: удалить ещё и сертификаты, и volumes |
| `--out DIR`, `--mode public\|node` | для `prepare` |
| `-y`, `--yes` | ничего не спрашивать; ошибка, если чего-то не хватает |

Любой флаг можно задать и переменной `SELFSTEAL_<NAME>` (например, `SELFSTEAL_DOMAIN`).

</details>

## 📦 Что устанавливается

| | |
|---|---|
| Веб-сервер | официальный образ `caddy`, закреплён по digest; Docker Compose, `network_mode: host` |
| Docker | из официального apt-репозитория, только если его нет |
| Файлы | `/opt/selfsteal/` — `docker-compose.yml`, `Caddyfile`, `snippet.caddy`, `site/`, `state.env` |
| Команда | `/usr/local/bin/selfsteal` |
| Слушает | `127.0.0.1:8443` (TLS, для Xray) и `:80` (проверка для сертификата + редирект) |
| Сертификат | Let's Encrypt, HTTP-01, ровно на домен ноды (TLS-ALPN выключен — 443 у Xray) |
| Фаервол | только ufw: ssh (определяется сам), 80, 443. Существующие правила не сбрасываются |

Требования: Debian 12+ или Ubuntu 22.04+, root, свободный порт 80, домен, указывающий на сервер.

## 🔄 Обновление

На ноде: `selfsteal update` (или **Update** в меню) — скачивает установщик последнего релиза и заново применяет
сайт; домен, шаблон, порт и сертификаты сохраняются. Конкретная версия: `--to 0.2.1`. На серверах с `prepare`
перезапусти `prepare` и сделай reload Caddy. Подробнее — [DEPLOY.md §5](DEPLOY.md#5-updating-templates-on-all-servers).

## ♻️ Переустановка и удаление

Если команды `selfsteal` на ноде нет (например, старая установка оборвалась до её появления), всё то же самое
делается напрямую через скрипт из релиза:

```bash
# поставить заново поверх старой версии — настройки из /opt/selfsteal подхватятся
bash <(curl -Ls https://github.com/Popugtop/popug-cloud-selfsteal/releases/latest/download/selfsteal.sh) @ install

# снести полностью (вместе с сертификатами), потом поставить с нуля
bash <(curl -Ls https://github.com/Popugtop/popug-cloud-selfsteal/releases/latest/download/selfsteal.sh) @ uninstall --purge
```

Если на ноде стоит selfsteal **другого** скрипта (обычно контейнер вроде `caddy-selfsteal` в `/opt/caddy`) —
останови его и поставь этот, см. [DEPLOY.md §2.6](DEPLOY.md#26-moving-from-another-self-steal-setup).

## 🔒 Целостность и безопасность

- Архивы шаблонов качаются из GitHub-релиза **той же версии**, что и установщик, и сверяются с SHA256,
  зашитыми в него; при несовпадении установка прерывается, сайт не трогается.
- Контрольная сумма самого установщика есть в `SHA256SUMS` каждого релиза.
- Образ Caddy закреплён по digest.
- Никаких секретов в URL, аргументах, логах и state-файлах; ключи Reality остаются в панели.

## 🛠 Разработка

```bash
npm install
node tools/build-release.mjs --repo Popugtop/popug-cloud-selfsteal   # → release/
test/gallery.sh                                   # скриншоты всех страниц → docs/gallery/
test/e2e/run.sh                                   # полный тест установщика: чистый Debian 12 + Pebble (нужен Docker)
test/e2e/existing-caddy.sh debian|cloudsmith      # `prepare` против Caddy из apt
```

E2E-тесты выпускают настоящие сертификаты через локальный ACME-сервер (Pebble) и никогда не обращаются к
Let's Encrypt. Shell-скрипты чисты под `shellcheck -S style`. Как выпустить релиз — [DEPLOY.md §1](DEPLOY.md#1-publishing-a-release).

<details>
<summary><b>Структура репозитория</b></summary>

```
packages/design/   дизайн-токены и общие компоненты (Astro)
sites/root/        лендинг popug.cloud
templates/<name>/  по каталогу на шаблон (+ caddy/Caddyfile.snippet, template.json)
installer/         selfsteal.sh (данные релиза вшиваются при сборке)
tools/             build-release.mjs (архивы, суммы, установщик), randomize.sh
test/              serve.sh, curl-all.sh, shoot.mjs, gallery.sh, e2e/
```

</details>
