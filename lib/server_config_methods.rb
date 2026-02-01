require 'json'
require 'open3'
require_relative 'xray_api'

module ServerConfigMethods
  PATH = '/usr/local/etc/xray/config.json'

  # Определяем теги inbound'ов для разных протоколов
  PROTOCOL_TAGS = {
    'Reality' => 'inbound-443',
    'Grpc'    => 'INBOUND', 
    'Xhttp'   => 'INBOUND2'
  }.freeze

  # Протоколы, которые поддерживают динамическое добавление пользователей
  DYNAMIC_PROTOCOLS = ['Reality', 'Grpc'].freeze

  def xray_api
    @xray_api ||= Xray::XRayAPI.new
  end

  def config_mutex
    @config_mutex ||= Mutex.new
  end

  def file_exist?
    { ok: true, data: File.exist?(PATH) }
  rescue => e
    { ok: false, error: e.message }
  end

  def server_config
    raw_data = File.read(PATH)
    data = JSON.parse(raw_data)
    { ok: true, data: data }
  rescue => e
    { ok: false, error: "Ошибка при чтении файла: #{e}" }
  end

  def find_inbound_by_tag(config, tag)
    config['inbounds'].find_index { |inbound| inbound['tag'] == tag }
  end

  def add_client(new_client, type)
    inbound_tag = PROTOCOL_TAGS[type]
    raise "Неизвестный тип протокола: #{type}" unless inbound_tag
    
    flow = new_client['flow'] || ""
    
    config_response = server_config
    raise config_response[:error] unless config_response[:ok]
    config = config_response[:data]

    inbound_index = find_inbound_by_tag(config, inbound_tag)
    raise "Inbound с тегом #{inbound_tag} не найден" unless inbound_index
    
    inbound = config['inbounds'][inbound_index]
    inbound_clients = inbound.dig('settings', 'clients')
    raise "Клиенты не найдены в конфигурации" unless inbound_clients

    # Проверяем, существует ли уже пользователь
    if inbound_clients.any? { |client| client['email'] == new_client['email'] }
      raise "Пользователь с email #{new_client['email']} уже существует"
    end

    # Для протоколов с динамическим управлением пользователями
    #if DYNAMIC_PROTOCOLS.include?(type)
      # Добавляем через gRPC API
      unless xray_api.add_user(
        email: new_client['email'], 
        uuid: new_client['id'], 
        tag: inbound_tag, 
        flow: flow
      )
        raise "Не удалось добавить пользователя через gRPC API"
      end
    #else
      # Для Xhttp: пересоздаем inbound целиком
      # Сначала обновляем конфигурацию
    #  inbound_clients << new_client
      
      # Затем пересоздаем inbound через gRPC
    #  unless xray_api.recreate_inbound(inbound)
    #    raise "Не удалось пересоздать inbound через gRPC"
    #  end
    #end

    # Обновляем конфигурационный файл
    new_json_data = JSON.pretty_generate(config)
    config_mutex.synchronize { File.write(PATH, new_json_data) }

    { ok: true, data: true }
  rescue => e
    { ok: false, error: e.message }
  end

  def remove_client(email, type)
    inbound_tag = PROTOCOL_TAGS[type]
    raise "Неизвестный тип протокола: #{type}" unless inbound_tag
    
    config_response = server_config
    raise config_response[:error] unless config_response[:ok]
    config = config_response[:data]

    inbound_index = find_inbound_by_tag(config, inbound_tag)
    raise "Inbound с тегом #{inbound_tag} не найден" unless inbound_index
    
    inbound = config['inbounds'][inbound_index]
    inbound_clients = inbound.dig('settings', 'clients')
    raise "Клиенты не найдены в конфигурации" unless inbound_clients

    # Проверяем, существует ли пользователь
    unless inbound_clients.any? { |client| client['email'] == email }
      raise "Пользователь с email #{email} не найден"
    end

    # Для протоколов с динамическим управлением пользователями
    #if DYNAMIC_PROTOCOLS.include?(type)
      # Удаляем через gRPC API
      unless xray_api.remove_user(email: email, tag: inbound_tag)
        raise "Не удалось удалить пользователя через gRPC API"
      end
    #else
      # Для Xhttp: пересоздаем inbound целиком
      # Сначала обновляем конфигурацию
      #inbound_clients.reject! { |client| client['email'] == email }
      
      # Затем пересоздаем inbound через gRPC
     # unless xray_api.recreate_inbound(inbound)
      #  raise "Не удалось пересоздать inbound через gRPC"
      #end
   # end

    # Обновляем конфигурационный файл
    new_json_data = JSON.pretty_generate(config)
    config_mutex.synchronize { File.write(PATH, new_json_data) }

    { ok: true, data: true }
  rescue => e
    { ok: false, error: e.message }
  end

  def find_client(email, type)
    inbound_tag = PROTOCOL_TAGS[type]
    raise "Неизвестный тип протокола: #{type}" unless inbound_tag
    
    config_response = server_config
    raise config_response[:error] unless config_response[:ok]
    config = config_response[:data]

    inbound_index = find_inbound_by_tag(config, inbound_tag)
    raise "Inbound с тегом #{inbound_tag} не найден" unless inbound_index
    
    inbound = config['inbounds'][inbound_index]
    inbound_clients = inbound.dig('settings', 'clients')
    
    client_exists = inbound_clients&.any? { |client| client['email'] == email } || false
    { ok: true, data: client_exists }
  rescue => e
    { ok: false, error: e.message }
  end

  def server_values(type)
    inbound_tag = PROTOCOL_TAGS[type]
    raise "Неизвестный тип протокола: #{type}" unless inbound_tag
    
    config_response = server_config
    raise config_response[:error] unless config_response[:ok]
    config = config_response[:data]

    inbound_index = find_inbound_by_tag(config, inbound_tag)
    raise "Inbound с тегом #{inbound_tag} не найден" unless inbound_index
    
    inbound = config['inbounds'][inbound_index]
    
    result = {
      port: inbound['port'],
      network_type: inbound.dig('streamSettings', 'network') || 'tcp'
    }

    # Для Reality протокола
    if type == 'Reality'
      result.merge!({
        security: inbound.dig('streamSettings', 'security'),
        sni: inbound.dig('streamSettings', 'realitySettings', 'serverNames')&.first,
        fp: inbound.dig('streamSettings', 'realitySettings', 'settings', 'fingerprint'),
        pbk: inbound.dig('streamSettings', 'realitySettings', 'settings', 'publicKey'),
        sid: inbound.dig('streamSettings', 'realitySettings', 'shortIds', 0),
        flow: 'xtls-rprx-vision'
      })
    end

    { ok: true, data: result }
  rescue => e
    { ok: false, error: e.message }
  end

  def reload_config
    # Этот метод теперь не должен использоваться
    { ok: false, error: "Перезапуск Xray не поддерживается" }
  end
end