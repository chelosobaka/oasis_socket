# oasis_socket — агент Xray для OasisNet

Демон на Ruby, который работает на каждом VPN-сервере OasisNet рядом с Xray.
Приложение [rails_oasis](https://github.com/chelosobaka/rails_oasis) шлёт ему по TCP
текстовые команды (одна строка — один ответ), а агент добавляет и удаляет клиентов в
работающем Xray через gRPC API (`127.0.0.1:10085`) и в
`/usr/local/etc/xray/config.json`.

Команды: `file_exist?`, `add_client <json>`, `remove_client <email>`,
`find_client <email>`, `server_values`, `reload_config`, `file`.

- На сервере один тип ключей (Reality, gRPC или XHTTP) и **один inbound VLESS**: агент
  находит его в `config.json` сам, номер и тег не зашиты.
- `flow` клиента приходит от Rails; у gRPC и XHTTP агент всегда ставит пустой `flow`
  (vision работает только по TCP).
- Если команда не выполнилась, после ответа (`false` или `{}`) агент шлёт **второй строкой
  причину** — её показывает админка. Старый Rails читает только первую строку, так что
  совместимость не ломается.

**Полная документация** — протокол, требования к конфигу Xray, установка нового
сервера, безопасность и подводные камни:
[rails_oasis/docs/XRAY_AGENT.md](https://github.com/chelosobaka/rails_oasis/blob/main/docs/XRAY_AGENT.md).
Общая схема системы — [ARCHITECTURE.md](https://github.com/chelosobaka/rails_oasis/blob/main/docs/ARCHITECTURE.md).

Быстрый старт:

1. `gem install grpc google-protobuf`
2. Вписать `host` и `port` в `main.rb` (в репозитории они пустые).
3. `sudo ruby main.rb` (нужен root: агент пишет конфиг Xray и делает `systemctl restart xray`).
4. **Закрыть порт агента файрволом для всех, кроме сервера приложения**: у агента нет
   аутентификации.
5. Проверить: `echo server_values | nc <ip> <порт>` — в ответе `config_type` должен
   совпадать с типом сервера в админке.

Тесты (без Xray, на временном `config.json`): `ruby test/agent_test.rb`.
