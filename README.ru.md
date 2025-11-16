# ⚠️ УСТАРЕЛО - ТРЕБУЕТСЯ МИГРАЦИЯ ⚠️

**Эта роль устарела в пользу официальной коллекции [grafana-ansible-collection](https://github.com/grafana/grafana-ansible-collection).**

## 🚨 Почему вам следует мигрировать

Официальная коллекция Grafana Ansible предоставляет:
- ✅ **Активная поддержка** от Grafana Labs
- ✅ **Поддержка современных версий Grafana** (v9+, v10+, v11+)
- ✅ Интеграция с **Grafana Cloud API**
- ✅ **Дополнительные модули** для Alloy, Loki, Mimir, Tempo
- ✅ Интеграция с **OpenTelemetry Collector**
- ✅ **Улучшенная безопасность** и регулярные обновления

## 📖 Руководство по миграции

Смотрите **[MIGRATION.md](MIGRATION.md)** для подробных пошаговых инструкций по миграции.

### Быстрый старт миграции

```bash
# Установите официальную коллекцию
ansible-galaxy collection install grafana.grafana

# Обновите ваши playbook'и
- hosts: grafana
  collections:
    - grafana.grafana
  roles:
    - grafana.grafana.grafana
  vars:
    grafana_security:
      admin_user: admin
      admin_password: "{{ vault_grafana_password }}"
```

## 📚 Дополнительные ресурсы

- **[Контейнерные развертывания](examples/)** - Примеры для Docker, Podman и Kubernetes
- **[Скрипты резервного копирования](scripts/)** - Автоматизированные скрипты резервного копирования и проверки работоспособности
- **[Настройка обратного прокси](examples/nginx/)** - Конфигурации для Nginx и Traefik

---

## 👤 Автор

Этот репозиторий поддерживается Ранасом Мукминовым.

**Контакты и дополнительная информация:** [run-as-daemon.ru](https://run-as-daemon.ru)

На сайте вы найдете мои контакты и информацию о том, чем я занимаюсь.

---

<p><img src="https://grafana.com/blog/assets/img/blog/timeshift/grafana_release_icon.png" alt="grafana logo" title="grafana" align="right" height="60" /></p>

# Ansible роль: grafana

[![Build Status](https://travis-ci.org/cloudalchemy/ansible-grafana.svg?branch=master)](https://travis-ci.org/cloudalchemy/ansible-grafana)
[![License](https://img.shields.io/badge/license-MIT%20License-brightgreen.svg)](https://opensource.org/licenses/MIT)
[![Ansible Role](https://img.shields.io/badge/ansible%20role-cloudalchemy.grafana-blue.svg)](https://galaxy.ansible.com/cloudalchemy/grafana/)
[![GitHub tag](https://img.shields.io/github/tag/cloudalchemy/ansible-grafana.svg)](https://github.com/cloudalchemy/ansible-grafana/tags)

Установка и управление [grafana](https://github.com/grafana/grafana) - платформой для аналитики и мониторинга

## Требования

- Ansible >= 2.7 (Может работать на предыдущих версиях, но мы не можем этого гарантировать)
- libselinux-python на хосте развертывания (только когда на машине развертывания есть SELinux)
- grafana >= 5.1 (для более старых версий grafana используйте эту роль в версии 0.10.1 или ранее)
- jmespath на машине развертывания. Если вы используете Ansible из виртуального окружения Python, установите *jmespath* в то же виртуальное окружение через pip.

## Переменные роли

Все переменные, которые можно переопределить, хранятся в файле [defaults/main.yml](defaults/main.yml), а также в таблице ниже.

| Название           | Значение по умолчанию | Описание                        |
| -------------- | ------------- | -----------------------------------|
| `grafana_use_provisioning` | true | Использовать возможности провизионирования Grafana, когда это возможно (**grafana_version=latest предполагает >= 5.0**). |
| `grafana_provisioning_synced` | false | Убедиться, что ранее провизированные дашборды не сохраняются, если на них больше нет ссылок. |
| `grafana_version` | latest | Версия пакета Grafana |
| `grafana_yum_repo_template` | etc/yum.repos.d/grafana.repo.j2 | Шаблон Yum для использования |
| `grafana_manage_repo` | true | Управлять репозиторием пакетов (или нет) |
| `grafana_instance` | {{ ansible_fqdn \| default(ansible_host) \| default(inventory_hostname) }} | Имя экземпляра Grafana |
| `grafana_logs_dir` | /var/log/grafana | Путь к директории логов |
| `grafana_data_dir` | /var/lib/grafana | Путь к директории базы данных |
| `grafana_address` | 0.0.0.0 | Адрес, на котором слушает grafana |
| `grafana_port` | 3000 | Порт, на котором слушает grafana |
| `grafana_cap_net_bind_service` | false | Разрешает использование портов ниже 1024 без привилегий root, используя 'capabilities' ядра Linux. Читайте: http://man7.org/linux/man-pages/man7/capabilities.7.html |
| `grafana_url` | "http://{{ grafana_address }}:{{ grafana_port }}" | Полный URL для доступа к Grafana из веб-браузера |
| `grafana_api_url` | "{{ grafana_url }}" | URL, используемый для API-вызовов при провизионировании, если отличается от публичного URL. См. [этот issue](https://github.com/cloudalchemy/ansible-grafana/issues/70). |
| `grafana_domain` | "{{ ansible_fqdn \| default(ansible_host) \| default('localhost') }}" | Настройка используется только как часть опции `root_url`. Полезна при использовании GitHub или Google OAuth |
| `grafana_server` | { protocol: http, enforce_domain: false, socket: "", cert_key: "", cert_file: "", enable_gzip: false, static_root_path: public, router_logging: false } | Секция конфигурации [server](http://docs.grafana.org/installation/configuration/#server) |
| `grafana_security` | { admin_user: admin, admin_password: "" } | Секция конфигурации [security](http://docs.grafana.org/installation/configuration/#security) |
| `grafana_database` | { type: sqlite3 } | Секция конфигурации [database](http://docs.grafana.org/installation/configuration/#database) |
| `grafana_welcome_email_on_sign_up` | false | Отправлять приветственное письмо после регистрации |
| `grafana_users` | { allow_sign_up: false, auto_assign_org_role: Viewer, default_theme: dark } | Секция конфигурации [users](http://docs.grafana.org/installation/configuration/#users) |
| `grafana_auth` | {} | Секция конфигурации [authorization](http://docs.grafana.org/installation/configuration/#auth) |
| `grafana_ldap` | {} | Секция конфигурации [ldap](http://docs.grafana.org/installation/ldap/). group_mappings раскрываются, см. defaults для примера |
| `grafana_session` | {} | Секция конфигурации управления [session](http://docs.grafana.org/installation/configuration/#session) |
| `grafana_analytics` | {} | Секция конфигурации Google [analytics](http://docs.grafana.org/installation/configuration/#analytics) |
| `grafana_smtp` | {} | Секция конфигурации [smtp](http://docs.grafana.org/installation/configuration/#smtp) |
| `grafana_alerting` | {} | Секция конфигурации [alerting](http://docs.grafana.org/installation/configuration/#alerting) |
| `grafana_log` | {} | Секция конфигурации [log](http://docs.grafana.org/installation/configuration/#log) |
| `grafana_metrics` | {} | Секция конфигурации [metrics](http://docs.grafana.org/installation/configuration/#metrics) |
| `grafana_tracing` | {} | Секция конфигурации [tracing](http://docs.grafana.org/installation/configuration/#tracing) |
| `grafana_snapshots` | {} | Секция конфигурации [snapshots](http://docs.grafana.org/installation/configuration/#snapshots) |
| `grafana_image_storage` | {} | Секция конфигурации [image storage](http://docs.grafana.org/installation/configuration/#external-image-storage) |
| `grafana_dashboards` | [] | Список дашбордов, которые должны быть импортированы |
| `grafana_dashboards_dir` | "dashboards" | Путь к локальной директории, содержащей файлы дашбордов в формате `json` |
| `grafana_datasources` | [] | Список источников данных, которые должны быть настроены |
| `grafana_environment` | {} | Опциональный параметр Environment для установки Grafana, полезен для установки http_proxy |
| `grafana_plugins` | [] | Список плагинов Grafana, которые должны быть установлены |
| `grafana_alert_notifications` | [] | Список каналов уведомления об алертах для создания, обновления или удаления |

Пример источника данных:

```yaml
grafana_datasources:
  - name: prometheus
    type: prometheus
    access: proxy
    url: 'http://{{ prometheus_web_listen_address }}'
    basicAuth: false
```

Пример дашборда:

```yaml
grafana_dashboards:
  - dashboard_id: 111
    revision_id: 1
    datasource: prometheus
```

Пример канала уведомления об алерте:

**ПРИМЕЧАНИЕ**: установка переменной `grafana_alert_notifications` вступит в силу только когда `grafana_use_provisioning` установлен в `true`. Это означает, что должна использоваться новая система провизионирования через конфигурационные файлы, которая доступна начиная с Grafana v5.0.

```yaml
grafana_alert_notifications:
  notifiers:
    - name: Channel 1
      type: email
      uid: channel1
      is_default: false
      send_reminder: false
      settings:
        addresses: "example@example.com"
        autoResolve: true
  delete_notifiers:
    - name: Channel 2
      uid: channel2
```

Пример использования пользовательского шаблона Yum репозитория Grafana:

- Разместите ваш шаблон рядом с вашим playbook в папке `templates`

- Используйте путь, отличный от стандартного, потому что ansible при использовании относительного пути ищет первый найденный шаблон сначала в директории роли, затем в директории playbook.

- Расширенный шаблон будет размещен в `/etc/yum.repos.d/` и будет иметь имя, равное `basename` пути шаблона без .j2

  Пример:

  ```yaml
  grafana_yum_repo_template: my_yum_repos/grafana.repo.j2

  # [playbook_dir]/templates/my_yum_repos/grafana.repo.j2
  # будет помещен в
  # /etc/yum.repos.d/grafana.repo
  # на удаленном хосте
  ```

## Поддерживаемые архитектуры CPU

Исторически пакеты брались из разных каналов в зависимости от архитектуры CPU. В частности, пакеты для armv6/armv7 и aarch64/arm64 распространялись через [неофициальные пакеты от fg2it](https://github.com/fg2it/grafana-on-raspberry). Теперь, когда Grafana публикует официальные сборки для ARM, все пакеты берутся из официальных пакетов [Debian/Ubuntu](http://docs.grafana.org/installation/debian/#installing-on-debian-ubuntu) или [RPM](http://docs.grafana.org/installation/rpm/).

## Пример

### Playbook

Заполните поле пароля администратора на ваш выбор, веб-страница Grafana не будет просить изменить его при первом входе.

```yaml
- hosts: all
  roles:
    - role: cloudalchemy.grafana
      vars:
        grafana_security:
          admin_user: admin
          admin_password: enter_your_secure_password
```

### Демо-сайт

Мы предоставляем демо-сайт для полного решения мониторинга на базе prometheus и grafana. Репозиторий с кодом и ссылками на работающие экземпляры [доступен на github](https://github.com/cloudalchemy/demo-site), а сайт размещен на [DigitalOcean](https://digitalocean.com).

## Локальное тестирование

Предпочтительный способ локального тестирования роли - использование Docker и [molecule](https://github.com/metacloud/molecule) (v2.x). Вам нужно будет установить Docker на вашу систему. См. "Get started" для пакета Docker, подходящего для вашей системы.
Мы используем tox для упрощения процесса тестирования на нескольких версиях ansible. Чтобы установить tox, выполните:
```sh
pip3 install tox
```
Для запуска тестов на всех версиях ansible (ВНИМАНИЕ: это может занять некоторое время)
```sh
tox
```
Для запуска пользовательской команды molecule в пользовательском окружении только с тестовым сценарием по умолчанию:
```sh
tox -e py35-ansible28 -- molecule test -s default
```
Для получения дополнительной информации о molecule обращайтесь к их [документации](http://molecule.readthedocs.io/en/latest/).

Если вы хотите запустить тесты на удаленном docker-хосте, просто укажите переменную `DOCKER_HOST` перед запуском тестов tox.

## Travis CI

Комбинация molecule и Travis CI позволяет нам тестировать, как новые PR будут вести себя при использовании с несколькими версиями ansible и несколькими операционными системами. Это также позволяет создавать тестовые сценарии для различных конфигураций роли. В результате у нас довольно большая тестовая матрица, которая займет больше времени, чем локальное тестирование, так что, пожалуйста, будьте терпеливы.

## Участие в разработке

См. [руководство для участников](CONTRIBUTING.md).

## Устранение неполадок

См. [устранение неполадок](TROUBLESHOOTING.md).

## Лицензия

Этот проект лицензирован под лицензией MIT. Подробности см. в [LICENSE](/LICENSE).

---

**Другие языки:** [English](README.md) | **Русский**
