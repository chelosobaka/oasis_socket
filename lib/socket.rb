require 'socket'
require_relative 'server_config_methods'

class OasisTCPSocket
  include ServerConfigMethods

  def initialize(host, port)
    @server = TCPServer.new(host, port)
    puts "Server running on #{host}:#{port}"
  end

  def start
    loop do
      client = @server.accept
      request = client.gets.chomp

      case request
      when 'file_exist?'
        response = file_exist?.to_s
      when /^add_client (.+)/
        _, new_client = request.split(' ', 2)
        response = add_client(JSON.parse(new_client)) ? 'true' : 'false'
      when /^remove_client (.+)/
        _, email = request.split(' ', 2)
        response = remove_client(email) ? 'true' : 'false'
      when /^find_client (.+)/
        _, uuid = request.split(' ', 2)
        response = find_client(uuid) ? 'true' : 'false'
      when 'server_values'
        response = server_values.to_json
      when 'reload_config'
        response = reload_config ? 'true' : 'false'
      when 'file'
        response = file.to_json
      else
        response = 'Invalid request'
      end

      client.puts(response)
      client.close
    end
  end
end
