require 'json'
require 'open3'
require_relative 'xray_api'

module ServerConfigMethods
  PATH = '/usr/local/etc/xray/config.json'

  def clients(config, inbound_number)
    config.dig('inbounds', inbound_number, 'settings', 'clients')
  end

  def xray_api
    @xray_api ||= Xray::XrayAPI.new
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

  def available_types
    {
      'Reality' => { inbound_number: 1, inbound_tag: 'inbound-443' },
      'Grpc'    => { inbound_number: 2, inbound_tag: 'inbound-1111' },
      'Xhttp'   => { inbound_number: 3, inbound_tag: 'inbound-2222' }
    }
  end

  def get_inbound_number(type)
    available_types[type][:inbound_number]
  end

  def get_inbound_tag(type)
    available_types[type][:inbound_tag]
  end

  def add_client(new_client, type)
    inbound_number = get_inbound_number(type)
    inbound_tag = get_inbound_tag(type)
    raise "Inbound number not found" unless inbound_number
    raise "Failed to add user to Xray" unless xray_api.add_user(new_client['email'], new_client['id'], inbound_tag)

    config_response = server_config
    raise config_response[:error] unless config_response[:ok]
    config = config_response[:data]

    inbound_clients = clients(config, inbound_number)
    raise "Failed connect to inbound" unless inbound_clients

    inbound_clients << new_client

    new_json_data = JSON.pretty_generate(config)
    config_mutex.synchronize { File.write(PATH, new_json_data) }

    # Для Xhttp пересоздаем inbound через gRPC
    if type == 'Xhttp'
      result = reload_xhttp_inbound_grpc(type)
      raise result[:error] unless result[:ok]
    end

    { ok: true, data: true }
  rescue => e
    { ok: false, error: e.message }
  end

  def remove_client(email, type)
    inbound_number = get_inbound_number(type)
    inbound_tag = get_inbound_tag(type)
    raise "Inbound number not found" unless inbound_number
    raise "Failed to remove user from Xray" unless xray_api.remove_user(email, inbound_tag)

    config_response = server_config
    raise config_response[:error] unless config_response[:ok]
    config = config_response[:data]

    inbound_clients = clients(config, inbound_number)
    raise "Failed connect to inbound" unless inbound_clients

    inbound_clients.reject! { |client| client['email'] == email }

    new_json_data = JSON.pretty_generate(config)
    config_mutex.synchronize { File.write(PATH, new_json_data) }

    # Для Xhttp пересоздаем inbound через gRPC
    if type == 'Xhttp'
      result = reload_xhttp_inbound_grpc(type)
      raise result[:error] unless result[:ok]
    end

    { ok: true, data: true }
  rescue => e
    { ok: false, error: e.message }
  end

  def find_client(email, type)
    inbound_number = get_inbound_number(type)
    raise "Inbound number not found" unless inbound_number

    config_response = server_config
    raise config_response[:error] unless config_response[:ok]
    config = config_response[:data]

    inbound_clients = clients(config, inbound_number)
    raise "Failed connect to inbound" unless inbound_clients

    any_client = inbound_clients.any? { |client| client['email'] == email }
    { ok: true, data: any_client }
  rescue => e
    { ok: false, error: e.message}
  end

  def reload_xhttp_inbound_grpc(type)
    inbound_number = get_inbound_number(type)
    raise "Inbound number not found" unless inbound_number
    raise "Only Xhttp inbound supported" unless type == "Xhttp"

    config_response = server_config
    raise config_response[:error] unless config_response[:ok]
    config = config_response[:data]

    inbound_json = config['inbounds'][inbound_number]

    success = xray_api.reload_inbound_xhttp_grpc(inbound_json)
    raise "Failed to reload inbound via gRPC" unless success

    { ok: true, data: true }
  rescue => e
    { ok: false, error: e.message }
  end

  # -----------------------------
  # Остальные методы остаются без изменений
  # -----------------------------
  def server_values(type)
    inbound_number = get_inbound_number(type)
    raise "Inbound number not found" unless inbound_number

    config_response = server_config
    raise config_response[:error] unless config_response[:ok]
    config = config_response[:data]

    port = config.dig('inbounds', inbound_number, 'port')
    security = config.dig('inbounds', inbound_number, 'streamSettings', 'security')
    sni = config.dig('inbounds', inbound_number, 'streamSettings', 'realitySettings', 'serverNames')&.first
    fp = config.dig('inbounds', inbound_number, 'streamSettings', 'realitySettings', 'settings', 'fingerprint')
    pbk = config.dig('inbounds', inbound_number, 'streamSettings', 'realitySettings', 'settings', 'publicKey')
    sid = config.dig('inbounds', inbound_number, 'streamSettings', 'realitySettings', 'shortIds', 0)
    network_type = config.dig('inbounds', inbound_number, 'streamSettings', 'network')
    flow = 'xtls-rprx-vision'

    { ok: true,
      data: {
        port: port, 
        security: security, 
        sni: sni, 
        fp: fp,
        pbk: pbk, 
        sid: sid, 
        network_type: network_type, 
        flow: flow 
      }
    }
  rescue => e
    { ok: false, error: e.message }
  end

  def reload_config
    _, _, status = Open3.capture3('systemctl restart xray')
    { ok: true, data: status.success? }
  rescue
    { ok: false, data: false }
  end
end
