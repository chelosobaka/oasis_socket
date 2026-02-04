# xray_api.rb
require 'grpc'

$LOAD_PATH.unshift(File.expand_path("generated", __dir__))

begin
  require_relative "generated/app/proxyman/command/command_pb"
  require_relative "generated/app/proxyman/command/command_services_pb"
  require_relative "generated/app/proxyman/config_pb"
  require_relative "generated/proxy/vless/account_pb"
  require_relative "generated/common/protocol/user_pb"
  require_relative "generated/common/serial/typed_message_pb"
  require_relative "generated/transport/internet/config_pb"
  require_relative "generated/common/net/port_pb"
rescue LoadError => e
  puts "Warning: Could not load protobuf files: #{e.message}"
end

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

    def add_user(email, uuid, flow, inbound_tag = 'inbound-443')
      account = new_account(uuid, flow)
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

    def new_account(uuid)
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
    rescue GRPC::Unknown => e
      return true if e.message.include?("User #{email} not found")  
      false
    rescue StandardError => e
      false
    end
  end
end
