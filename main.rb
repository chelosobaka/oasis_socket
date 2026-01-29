$LOAD_PATH.unshift(File.expand_path("lib/protos", __dir__))
require_relative 'lib/socket'

host = "213.165.36.11"
port = 1703
puts "Socket: #{host}:#{port}"
server = OasisTCPSocket.new(host, port)
server.start
