require_relative 'protos/account_pb'
require_relative 'protos/command_services_pb'

# grpc_tools_ruby_protoc -I./ -I./ --ruby_out=./ --grpc_out=./ ./command.proto
module Xray
  class XrayAPI
    def initialize
      @handler_service_client = Xray::App::Proxyman::Command::HandlerService::Stub.new('127.0.0.1:10085',
                                                                                       :this_channel_is_insecure)
    end

    def to_typed_message(message)
      return nil if message.nil?

      settings = Google::Protobuf.encode(message)
      Xray::Common::Serial::TypedMessage.new(
        type: get_message_type(message),
        value: settings
      )
    end

    def get_message_type(message)
      message.class.descriptor.name
    end

    def add_user(email, uuid, inbound_tag = 'inbound-443')
      account = new_accaunt(uuid)
      client = @handler_service_client

      _, err = client.alter_inbound(
                Xray::App::Proxyman::Command::AlterInboundRequest.new(
                  tag: inbound_tag,
                  operation: to_typed_message(
                    Xray::App::Proxyman::Command::AddUserOperation.new(
                      user: Xray::Common::Protocol::User.new(email: email, account: account)
                    )
                  )
                )
              )
      err ? false : true
    rescue
      false
    end

    def new_accaunt(uuid)
      to_typed_message(
        Xray::Proxy::Vless::Account.new(
          id: uuid,
          flow: 'xtls-rprx-vision'
        )
      )
    end

    def remove_user(email, inbound_tag = 'inbound-443')
      client = @handler_service_client
      _, err = client.alter_inbound(
                Xray::App::Proxyman::Command::AlterInboundRequest.new(
                  tag: inbound_tag,
                  operation: to_typed_message(
                    Xray::App::Proxyman::Command::RemoveUserOperation.new(
                      email: email
                    )
                  )
                )
              )
      err ? false : true
    rescue
      false
    end
  end
end
