# Что изменилось: локальное развёртывание и CI

Ветка `local-dev-setup`. Стек для разработки теперь поднимается одной командой, prod-конфигурация не тронута.

## Было

- Бэкенд (эмуляция) не запускался под WSL.
- Ручная настройка: скопировать `vk_auth.json` из чата, создать `miminet_secret.conf`, поменять `MODE` в `.env`, запустить `start_all_containers.sh`.
- Войти локально можно было только через VK/Яндекс OAuth.
- Контейнеры общались по статическим IP, порядок старта никак не контролировался.

## Стало

```bash
./miminet.sh up        # Windows: .\miminet.ps1 up
```

Открыть http://localhost и войти под `admin@local` / `admin`.

| Что | Файлы |
|---|---|
| Единый compose-проект: postgres, rabbitmq, front, nginx, воркер эмуляции. DNS-имена вместо IP, старт по healthcheck, `up --wait`, именованные тома | `compose.yaml` |
| Обёртка с командами `up / down / logs / smoke / test / doctor / reset / shell`. При первом запуске генерирует `.env` из `.env.example` со случайными секретами | `miminet.sh`, `miminet.ps1`, `.env.example` |
| Проверка окружения: Docker, модули ядра (`openvswitch`, `netem` и др.), версия ядра WSL, CRLF, занятые порты, отключённый IPv6 на хосте. С `--fix` загружает модули сразу и при загрузке системы | `scripts/doctor.sh` |
| Воркер сам делает `modprobe` нужных модулей, если смонтирован `/lib/modules` (в prod ничего не меняется) | `back/ENTRYPOINT.sh` |
| Вход по логину и паролю для dev (`AUTH_PROVIDERS`), идемпотентное создание dev-админа. Приложение не стартует, если dev-вход включён без `MODE=dev` | `front/src/miminet_auth.py`, `app.py`, `templates/auth/login.html` |
| `SECRET_KEY` берётся из env, файл `miminet_secret.conf` больше не обязателен | `front/src/miminet_config.py` |
| Build-arg `WITH_YANDEX_CA`: dev-сборка не скачивает сертификат Yandex Cloud и работает офлайн или за прокси | `front/Dockerfile` |
| nginx определяет адрес приложения на каждый запрос, поэтому после пересоздания контейнера не остаётся устаревшего IP | `front/default.dev.conf.template` |
| Принудительные LF-окончания для скриптов, чтобы сборка не ломалась на Windows | `.gitattributes` |
| E2E smoke-тест: вход, админка, эмуляция, сверка пакетов с эталоном | `scripts/smoke-emulation.py` |
| `back-test.sh` пробрасывает аргументы в pytest | `scripts/back-test.sh` |

## CI

- Новые тесты dev-авторизации `front/tests/test_dev_auth.py` добавлены в browser-free coverage job (`.github/workflows/front_coverage.yml`).

## Документация

- `docs/LOCAL_SETUP.md`: требования, платформы (Linux, WSL, Docker Desktop, macOS), команды, конфигурация, решение проблем.
- В `README.md` раздел «Локальное развёртывание» заменён коротким quickstart.

## Что не менялось

`start_all_containers.sh`, `docker-compose-prod.yml`, `back/` и `front/docker-compose.yml`, `.env`-файлы для prod и Ansible.
