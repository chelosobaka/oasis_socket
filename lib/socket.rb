require 'socket'
require 'json'
require_relative 'server_config_methods'

# TCP-сервер агента: Rails шлёт одну строку-команду, агент отвечает и закрывает соединение.
# Каждое соединение — в своём потоке.
#
# Ответ. Первая строка — как всегда: «true»/«false» или JSON (server_values, file). Если
# команда не выполнилась, вторая строка — причина отказа (AgentError или исключение), её
# показывает Rails. Старый Rails читает только первую строку, так что с новым агентом он
# работает как раньше. Отказ ещё и пишется в журнал агента (stderr, journalctl).
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
    # Сокет отдаёт байты (ASCII-8BIT): читаем как UTF-8, битые байты заменяем.
    request = client.gets&.chomp&.force_encoding(Encoding::UTF_8)&.scrub
    return if request.nil?

    answer, reason = respond_to_request(request)
    log_refusal(request, reason) if reason
    client.puts(answer)
    client.puts(one_line(reason)) if reason
  rescue StandardError => e
    log_refusal(request, "#{e.class}: #{e.message}")
  ensure
    client.close
  end

  # [первая строка ответа, причина отказа или nil]
  def respond_to_request(request)
    command, argument = request.split(' ', 2)
    case command
    when 'file_exist?' then boolean { file_exist? }
    when 'add_client' then boolean { add_client(parse_client(argument)) }
    when 'remove_client' then boolean { remove_client(argument) }
    when 'find_client' then boolean { find_client(argument) }
    when 'server_values' then json { server_values }
    when 'reload_config' then boolean { reload_config }
    when 'file' then json { file }
    else ['Invalid request', "неизвестная команда «#{command}»"]
    end
  end

  private

  def boolean
    [yield ? 'true' : 'false', nil]
  rescue StandardError => e
    ['false', reason_of(e)]
  end

  def json
    [yield.to_json, nil]
  rescue StandardError => e
    ['{}', reason_of(e)]
  end

  # Причина — одной строкой в UTF-8: вторая строка ответа должна быть последней.
  def one_line(text)
    text.dup.force_encoding(Encoding::UTF_8).scrub.gsub(/\s+/, ' ').strip
  end

  # Свой отказ — как есть; неожиданное исключение — с его классом, чтобы было что искать.
  def reason_of(error)
    error.is_a?(AgentError) ? error.message : "#{error.class}: #{error.message}"
  end

  def parse_client(json)
    client = JSON.parse(json.to_s)
    raise AgentError, 'клиент в add_client — не объект JSON' unless client.is_a?(Hash)

    client
  rescue JSON::ParserError => e
    raise AgentError, "клиент в add_client — не JSON: #{e.message}"
  end

  # У add_client в журнал идёт только email клиента, без uuid.
  def log_refusal(request, reason)
    command, argument = request.to_s.split(' ', 2)
    target = command == 'add_client' ? client_email(argument) : argument
    warn "#{Time.now.strftime('%F %T')} #{[command, target].compact.join(' ')}: #{reason}"
  end

  def client_email(json)
    JSON.parse(json.to_s)['email']
  rescue StandardError
    nil
  end
end
