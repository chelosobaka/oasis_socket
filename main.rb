require_relative 'lib/socket'

host = ""
port = 
puts "Socket: #{host}:#{port}"
server = OasisTCPSocket.new(host, port)
server.start