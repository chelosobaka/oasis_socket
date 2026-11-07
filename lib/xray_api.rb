require_relative 'agent_error'
require_relative 'protos/account_pb'
require_relative 'protos/command_services_pb'

# grpc_tools_ruby_protoc -I./ -I./ --ruby_out=./ --grpc_out=./ ./command.proto
module Xray
  # gRPC-клиент к API Xray (HandlerService.AlterInbound): добавить или убрать пользователя
  # в работающем Xray без перезапуска. Тег inbound'а и flow передаёт вызывающий
  # (ServerConfigMethods берёт их из config.json и от Rails).
  #
  # Ошибку Xray (нет inbound'а с таким тегом, пользователь уже есть, API не отвечает)
  # поднимает как AgentError с текстом от Xray: он уходит в Rails причиной отказа.
  class XrayAPI
    ADDRESS = ENV.fetch('XRAY_API_ADDRESS', '127.0.0.1:10085')
    # Секунд на вызов API: зависший Xray не должен держать соединение с Rails.
    TIMEOUT = 5

    def initialize
      @handler_service_client = Xray::App::Proxyman::Command::HandlerService::Stub.new(ADDRESS,
                                                                                       :this_channel_is_insecure)
    end

    def add_user(inbound_tag, email, uuid, flow)
      user = Xray::Common::Protocol::User.new(email: email, account: account(uuid, flow))
      alter_inbound(inbound_tag, Xray::App::Proxyman::Command::AddUserOperation.new(user: user))
    end

    # Пользователя и так нет в Xray — это тоже успех: убирать нечего.
    def remove_user(inbound_tag, email)
      alter_inbound(inbound_tag, Xray::App::Proxyman::Command::RemoveUserOperation.new(email: email))
    rescue AgentError => e
      raise unless e.message.include?("User #{email} not found")

      true
    end

    private

    # flow — xtls-rprx-vision только для Reality по TCP; для gRPC и XHTTP пустой, иначе
    # Xray не пустит клиента без vision.
    def account(uuid, flow)
      to_typed_message(Xray::Proxy::Vless::Account.new(id: uuid, flow: flow))
    end

    def alter_inbound(inbound_tag, operation)
      request = Xray::App::Proxyman::Command::AlterInboundRequest.new(tag: inbound_tag,
                                                                      operation: to_typed_message(operation))
      @handler_service_client.alter_inbound(request, deadline: Time.now + TIMEOUT)
      true
    rescue GRPC::BadStatus => e
      raise AgentError, "Xray API #{ADDRESS} (inbound #{inbound_tag}): #{e.details}"
    end

    def to_typed_message(message)
      return nil if message.nil?

      Xray::Common::Serial::TypedMessage.new(
        type: message.class.descriptor.name,
        value: Google::Protobuf.encode(message)
      )
    end
  end
end
