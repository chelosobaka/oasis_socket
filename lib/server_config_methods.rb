require 'json'
require 'open3'
require_relative 'xray_api'

module ServerConfigMethods
  def path
    '/usr/local/etc/xray/config.json'
  end

  def file_exist?
    File.exist?(path)
  rescue
    false
  end

  def server_config
    raw_data = File.read(path)
    JSON.parse(raw_data)
  rescue => e
    raise "Ошибка при обработке файла: #{e}"
  end

  def file
    raw_data = File.read(path)
    JSON.parse(raw_data)
  rescue
    {}
  end

  def add_client(new_client)
    return false unless Xray::XrayAPI.new.add_user(new_client['email'], new_client['id'])

    config = server_config
    config.dig('inbounds', 1, 'settings', 'clients') << new_client

    new_json_data = JSON.pretty_generate(config)
    File.write(path, new_json_data)
    true
  rescue
    false
  end

  def remove_client(email)
    return false unless Xray::XrayAPI.new.remove_user(email)

    config = server_config
    config.dig('inbounds', 1, 'settings', 'clients')&.reject! { |client| client['email'] == email }
    new_json_data = JSON.pretty_generate(config)
    File.write(path, new_json_data)
    true
  rescue
    false
  end

  def find_client(uuid)
    config = server_config
    if config.dig('inbounds', 1, 'settings', 'clients')&.any? { |client| client['id'] == uuid }
      true
    else
      false
    end
  rescue
    false
  end

  def server_values
    config = server_config

    port = config.dig('inbounds', 1, 'port')
    security = config.dig('inbounds', 1, 'streamSettings', 'security')
    sni = config.dig('inbounds', 1, 'streamSettings', 'realitySettings', 'dest')&.split(':')&.first
    fp = config.dig('inbounds', 1, 'streamSettings', 'realitySettings', 'settings', 'fingerprint')
    pbk = config.dig('inbounds', 1, 'streamSettings', 'realitySettings', 'settings', 'publicKey')
    sid = config.dig('inbounds', 1, 'streamSettings', 'realitySettings', 'shortIds', 0)
    network_type = config.dig('inbounds', 1, 'streamSettings', 'network')
    flow = 'xtls-rprx-vision'

    { port: port, security: security, sni: sni, fp: fp, pbk: pbk, sid: sid, network_type: network_type, flow: flow }
  rescue
    {}
  end

  def reload_config
    _, _, status = Open3.capture3('systemctl restart xray')
    status.success? ? true : false
  rescue
    false
  end
end
