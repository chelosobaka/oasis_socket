require 'socket'
require 'json'
require_relative 'server_config_methods'

class OasisTCPSocket
  include ServerConfigMethods

  def initialize(host, port)
    @server = TCPServer.new(host, port)
    puts "Server running on #{host}:#{port}"
  end

  def start
    loop do
      Thread.start(@server.accept) do |client|
        handle_client(client)
      end
    end
  end

  def handle_client(client)
    raw = client.gets
    return if raw.nil?

    data = JSON.parse(raw)
    
    p data

    response =
      case data['action']
      when 'file_exist?'
        file_exist?

      when 'add_client'
        add_client(data['client'], data['type'])

      when 'remove_client'
        remove_client(data['email'], data['type'])

      when 'find_client'
        find_client(data['email'], data['type'])

      when 'server_values'
        server_values(data['type'])

      when 'reload_config'
        reload_config

      when 'file'
        server_config

      else
        false
      end

      p response.inspect 
    client.puts(response.to_json)
  rescue JSON::ParserError
    answer = { ok: false, error: 'Invalid_json' }
    client.puts(answer.to_json)
  rescue => e
    answer = { ok: false, error: e.message }
    client.puts(answer.to_json)
  ensure
    client.close
  end
end
