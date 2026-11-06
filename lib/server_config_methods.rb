require 'json'
require 'open3'
require_relative 'agent_error'
require_relative 'xray_api'

# Команды агента: config.json Xray и работающий Xray (через Xray::XrayAPI).
#
# Inbound'ы в config.json (решение владельца 06.11.2026): inbounds[0] — системный (API Xray),
# агент его не трогает; ключи — в inbounds[1], это inbound VLESS. На сервере один тип ключей,
# поэтому inbound для ключей один. Его тег агент берёт из файла: по тегу он обращается к API Xray.
#
# Команда, которая не выполнилась, бросает AgentError с причиной. OasisTCPSocket отвечает
# на неё «false» (или «{}») и второй строкой — этой причиной.
module ServerConfigMethods
  VISION = 'xtls-rprx-vision'.freeze
  KEYS_INBOUND = 1
  # Чтение и запись config.json идут под одной блокировкой: соединения обслуживаются
  # параллельно, и без неё одновременные add_client/remove_client затирали изменения друг
  # друга (клиент оставался в Xray, но пропадал из файла).
  CONFIG_LOCK = Mutex.new

  def path
    ENV.fetch('XRAY_CONFIG_PATH', '/usr/local/etc/xray/config.json')
  end

  def file_exist?
    raise AgentError, "нет файла #{path}" unless File.exist?(path)

    true
  end

  # Добавляет клиента в работающий Xray и в config.json. flow присылает Rails; на inbound'е
  # без vision (gRPC, XHTTP) агент ставит пустой flow, что бы ни пришло.
  def add_client(client)
    id = client['id'].to_s
    email = client['email'].to_s
    raise AgentError, 'в add_client нет id или email клиента' if id.empty? || email.empty?

    CONFIG_LOCK.synchronize do
      config = read_config
      inbound = client_inbound(config)
      flow = vision?(inbound) ? client['flow'].to_s : ''
      xray_api.add_user(inbound['tag'], email, id, flow)
      save_client(config, inbound, client.merge('flow' => flow))
    end
    true
  end

  def remove_client(email)
    raise AgentError, 'в remove_client не указан email' if email.to_s.empty?

    CONFIG_LOCK.synchronize do
      config = read_config
      inbound = client_inbound(config)
      xray_api.remove_user(inbound['tag'], email)
      clients_of(inbound).reject! { |client| client['email'] == email }
      write_config(config)
    end
    true
  end

  # Есть ли клиент в config.json (в работающем Xray не проверяет).
  def find_client(email)
    clients_of(client_inbound(locked_read)).any? { |client| client['email'] == email }
  end

  # Параметры для ссылки vless://. Первые восемь полей — как раньше; config_type (тип
  # ключей в терминах Rails, под который настроен inbound, или null), tag, service_name,
  # path и mode — для проверки сервера.
  def server_values
    inbound = client_inbound(locked_read)
    stream = inbound['streamSettings'] || {}
    security = stream['security']
    reality = stream['realitySettings'] || {}
    tls = stream['tlsSettings'] || {}
    {
      port: inbound['port'], security: security,
      sni: security == 'tls' ? tls['serverName'] : reality['serverNames']&.first,
      fp: (security == 'tls' ? tls : reality).dig('settings', 'fingerprint'),
      pbk: reality.dig('settings', 'publicKey'), sid: reality['shortIds']&.first,
      network_type: stream['network'], flow: vision?(inbound) ? VISION : '',
      config_type: config_type(inbound), tag: inbound['tag'],
      service_name: stream.dig('grpcSettings', 'serviceName'),
      path: stream.dig('xhttpSettings', 'path'), mode: stream.dig('xhttpSettings', 'mode')
    }
  end

  def reload_config
    _, stderr, status = Open3.capture3('systemctl', 'restart', 'xray')
    return true if status.success?

    raise AgentError, "systemctl restart xray: #{stderr.strip.empty? ? status : stderr.strip}"
  end

  def file
    locked_read
  end

  private

  def xray_api
    @xray_api ||= Xray::XrayAPI.new
  end

  def read_config
    JSON.parse(File.read(path))
  rescue Errno::ENOENT
    raise AgentError, "нет файла #{path}"
  rescue JSON::ParserError, SystemCallError => e
    raise AgentError, "не удалось прочитать #{path}: #{e.message}"
  end

  def locked_read
    CONFIG_LOCK.synchronize { read_config }
  end

  # Пишем во временный файл рядом и подменяем им config.json: если запись упадёт (например,
  # кончилось место), старый файл останется целым и Xray запустится после перезагрузки.
  # Права и владельца переносим со старого файла.
  def write_config(config)
    temp = "#{path}.tmp"
    File.write(temp, JSON.pretty_generate(config))
    stat = File.stat(path)
    File.chmod(stat.mode, temp)
    File.chown(stat.uid, stat.gid, temp)
    File.rename(temp, path)
  ensure
    File.delete(temp) if temp && File.exist?(temp)
  end

  # Inbound для ключей — inbounds[1]. Каким бы ни был inbounds[0], агент его не берёт: он системный.
  def client_inbound(config)
    name = "inbounds[#{KEYS_INBOUND}]"
    inbound = Array(config['inbounds'])[KEYS_INBOUND]
    raise AgentError, "в #{path} нет #{name} для ключей (inbounds[0] — системный)" unless inbound.is_a?(Hash)

    protocol = inbound['protocol']
    raise AgentError, "#{name} в #{path} — не VLESS (protocol: #{protocol || 'не указан'})" unless protocol == 'vless'
    raise AgentError, "у #{name} в #{path} нет тега (tag): без него Xray API его не найдёт" if inbound['tag'].to_s.empty?

    inbound
  end

  def clients_of(inbound)
    settings = (inbound['settings'] ||= {})
    settings['clients'] ||= []
  end

  # Клиент уже в работающем Xray. Запись с тем же email в файле (осталась от сбоя) заменяем,
  # чтобы в файле не было двух одинаковых email: с ними Xray не запустится. Файл не записался —
  # убираем клиента из Xray обратно, чтобы Xray и файл не разошлись.
  def save_client(config, inbound, client)
    clients = clients_of(inbound)
    clients.reject! { |existing| existing['email'] == client['email'] }
    clients << client
    write_config(config)
  rescue StandardError => e
    begin
      xray_api.remove_user(inbound['tag'], client['email'])
    rescue AgentError => rollback_error
      warn "add_client: не удалось убрать #{client['email']} из Xray после сбоя записи: #{rollback_error.message}"
    end
    raise AgentError, "не удалось записать #{path}: #{e.message}"
  end

  # Vision работает только поверх TCP (raw) с REALITY или TLS. С gRPC и XHTTP Xray не пускает
  # клиента, у которого в аккаунте flow xtls-rprx-vision.
  def vision?(inbound)
    stream = inbound['streamSettings'] || {}
    %w[raw tcp].include?(stream['network'] || 'raw') && %w[reality tls].include?(stream['security'])
  end

  # Тип ключей Rails (Server#config_type), под который подходит inbound: reality — TCP + REALITY,
  # grpc — gRPC + REALITY, xhttp — XHTTP + TLS. Другое сочетание — nil.
  def config_type(inbound)
    stream = inbound['streamSettings'] || {}
    network = stream['network'] || 'raw'
    security = stream['security']
    return 'reality' if %w[raw tcp].include?(network) && security == 'reality'
    return 'grpc' if network == 'grpc' && security == 'reality'

    'xhttp' if network == 'xhttp' && security == 'tls'
  end
end
