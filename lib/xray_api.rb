require_relative 'protos/account_pb'
require_relative 'protos/command_services_pb'
require_relative 'protos/core/config_pb'
require_relative 'protos/transport/internet/config_pb'
require_relative 'protos/common/serial/typed_message_pb'
require_relative 'protos/common/protocol/user_pb'

module Xray
  class XrayAPI
    def initialize
      @handler_service_client = Xray::App::Proxyman::Command::HandlerService::Stub.new(
        '127.0.0.1:10085',
        :this_channel_is_insecure
      )
    end

    # -----------------------------
    # Протобаф-обертка
    # -----------------------------
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

    # -----------------------------
    # Добавление/удаление пользователя через AlterInbound
    # -----------------------------
    def add_user(email, uuid, inbound_tag = 'inbound-443')
      account = new_account(uuid)
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

    def new_account(uuid)
      to_typed_message(
        Xray::Proxy::Vless::Account.new(
          id: uuid,
          flow: 'xtls-rprx-vision'
        )
      )
    end

    # -----------------------------
    # Пересоздание xHTTP inbound через gRPC
    # -----------------------------
    def reload_inbound_xhttp_grpc(inbound_json)
      tag = inbound_json["tag"]

      # 1) Удаляем inbound
      @handler_service_client.remove_inbound(
        Xray::App::Proxyman::Command::RemoveInboundRequest.new(tag: tag)
      )

      # 2) Строим protobuf для xHTTP inbound
      inbound_proto = build_xhttp_inbound(inbound_json)

      # 3) Добавляем inbound обратно
      @handler_service_client.add_inbound(
        Xray::App::Proxyman::Command::AddInboundRequest.new(
          inbound: inbound_proto
        )
      )

      true
    rescue => e
      puts "reload_inbound_xhttp_grpc error: #{e.message}"
      false
    end

    private

    # -----------------------------
    # Построение InboundHandlerConfig для xHTTP
    # -----------------------------
    def build_xhttp_inbound(inbound)
      # -----------------------------
      # Receiver (port)
      # -----------------------------
      receiver = Xray::Core::ReceiverConfig.new(
        port_range: Xray::Common::Net::PortRange.new(
          from: inbound["port"],
          to: inbound["port"]
        )
      )

      # -----------------------------
      # VLESS Clients
      # -----------------------------
      clients = inbound["settings"]["clients"].map do |c|
        Xray::Common::Protocol::User.new(
          email: c["email"],
          account: new_account(c["id"])
        )
      end

      # -----------------------------
      # Proxy settings (VLESS)
      # -----------------------------
      proxy = Xray::Proxy::Vless::InboundConfig.new(
        clients: clients,
        decryption: inbound["settings"]["decryption"] || "none"
      )

      # -----------------------------
      # TLS Settings
      # -----------------------------
      tls_json = inbound.dig("streamSettings", "tlsSettings") || {}
      tls_config = Xray::Transport::Internet::TlsConfig.new(
        server_name: tls_json["serverName"],
        alpn: tls_json["alpn"] || [],
        min_version: tls_json["minVersion"],
        max_version: tls_json["maxVersion"],
        allow_insecure: tls_json["allowInsecure"] || false,
        certificates: (tls_json["certificates"] || []).map do |cert|
          Xray::Transport::Internet::Certificate.new(
            certificate_file: cert["certificateFile"],
            key_file: cert["keyFile"]
          )
        end
      )

      # -----------------------------
      # XHTTP Settings
      # -----------------------------
      xhttp_json = inbound.dig("streamSettings", "xhttpSettings") || {}
      xhttp_config = Xray::Transport::Internet::XhttpConfig.new(
        path: xhttp_json["path"] || "/",
        mode: xhttp_json["mode"] || "auto"
      )

      # -----------------------------
      # StreamConfig
      # -----------------------------
      stream = Xray::Transport::Internet::StreamConfig.new(
        protocol_name: inbound.dig("streamSettings", "network") || "xhttp",
        security_type: inbound.dig("streamSettings", "security") || "tls",
        tls_settings: to_typed_message(tls_config),
        transport_settings: [
          Xray::Transport::Internet::TransportConfig.new(
            protocol_name: "xhttp",
            settings: to_typed_message(xhttp_config)
          )
        ]
      )

      # -----------------------------
      # InboundHandlerConfig
      # -----------------------------
      Xray::Core::InboundHandlerConfig.new(
        tag: inbound["tag"],
        receiver_settings: to_typed_message(receiver),
        proxy_settings: to_typed_message(proxy),
        stream_settings: to_typed_message(stream)
      )
    end
  end
end
