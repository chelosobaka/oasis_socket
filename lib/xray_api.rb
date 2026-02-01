# xray_api.rb
require 'grpc'

# Загрузка protobuf файлов
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

module Xray
  class XRayAPI
    def initialize(host: "127.0.0.1", port: 10085)
      begin
        if defined?(App::Proxyman::Command::HandlerService::Stub)
          @handler_service_client = App::Proxyman::Command::HandlerService::Stub.new(
            "#{host}:#{port}",
            :this_channel_is_insecure
          )
        else
          puts "Warning: Protobuf classes not loaded, using dummy implementation"
          @handler_service_client = nil
        end
      rescue => e
        puts "Warning: Failed to initialize gRPC client: #{e.message}"
        @handler_service_client = nil
      end
    end

    def add_user(email:, uuid:, tag:, flow: "")
      return false unless @handler_service_client
      
      begin
        # Создаем аккаунт VLESS
        account = Proxy::Vless::Account.new(
          id: uuid,
          flow: flow,
          encryption: 'none'
        )
        
        # Создаем typed message для аккаунта
        account_typed = Common::Serial::TypedMessage.new(
          type: "xray.proxy.vless.Account",
          value: Google::Protobuf.encode(account)
        )
        
        # Создаем пользователя
        user = Common::Protocol::User.new(
          email: email,
          level: 0,
          account: account_typed
        )
        
        # Создаем операцию добавления пользователя
        operation = App::Proxyman::Command::AddUserOperation.new(user: user)
        operation_typed = Common::Serial::TypedMessage.new(
          type: "xray.app.proxyman.command.AddUserOperation",
          value: Google::Protobuf.encode(operation)
        )
        
        # Отправляем запрос
        request = App::Proxyman::Command::AlterInboundRequest.new(
          tag: tag,
          operation: operation_typed
        )
        
        @handler_service_client.alter_inbound(request)
        true
      rescue => e
        puts "Add user error: #{e.message}"
        false
      end
    end

    def remove_user(email:, tag:)
      return false unless @handler_service_client
      
      begin
        # Создаем операцию удаления пользователя
        operation = App::Proxyman::Command::RemoveUserOperation.new(email: email)
        operation_typed = Common::Serial::TypedMessage.new(
          type: "xray.app.proxyman.command.RemoveUserOperation",
          value: Google::Protobuf.encode(operation)
        )
        
        # Отправляем запрос
        request = App::Proxyman::Command::AlterInboundRequest.new(
          tag: tag,
          operation: operation_typed
        )
        
        @handler_service_client.alter_inbound(request)
        true
      rescue => e
        # Если пользователь не найден, считаем успешным
        return true if e.message.include?("not found")
        puts "Remove user error: #{e.message}"
        false
      end
    end

    def recreate_inbound(inbound_json)
      return false unless @handler_service_client

      p inbound_json
      begin
        tag = inbound_json['tag']
        
        # 1. Удаляем старый inbound
        remove_request = App::Proxyman::Command::RemoveInboundRequest.new(tag: tag)
        @handler_service_client.remove_inbound(remove_request)
        
        # 2. Создаем новый inbound
        # Конвертируем JSON в protobuf
        inbound_proto = json_to_inbound_config(inbound_json)
        
        add_request = App::Proxyman::Command::AddInboundRequest.new(inbound: inbound_proto)
        @handler_service_client.add_inbound(add_request)
        
        true
      rescue => e
        puts "Recreate inbound error: #{e.message}"
        false
      end
    end

    private

    def safe_set(obj, field, value)
      setter = "#{field}="

      if obj.respond_to?(setter)
        obj.public_send(setter, value)
      else
        puts "⚠️ Поле #{field} отсутствует у #{obj.class}"
      end
    end

  def json_to_inbound_config(json)
    config = App::Proxyman::InboundConfig.new

    # Безопасно задаём базовые поля
    safe_set(config, :tag, json['tag'])
    safe_set(config, :listen, json['listen']) if json['listen']
    safe_set(config, :port, json['port'])

    # settings
    if json['settings']
      settings = App::Proxyman::ReceiverConfig.new

      if json['settings']['clients']
        users = json['settings']['clients'].map do |client|
          account = Proxy::Vless::Account.new(
            id: client['id'],
            flow: client['flow'] || '',
            encryption: 'none'
          )

          account_typed = Common::Serial::TypedMessage.new(
            type: "xray.proxy.vless.Account",
            value: Google::Protobuf.encode(account)
          )

          Common::Protocol::User.new(
            email: client['email'],
            level: 0,
            account: account_typed
          )
        end

        # В protobuf поле может называться user или users
        if settings.respond_to?(:user=)
          settings.user = users
        elsif settings.respond_to?(:users=)
          settings.users = users
        else
          puts "⚠️ ReceiverConfig не поддерживает user/users"
        end
      end

      # Название поля settings в InboundConfig может быть другим
      if config.respond_to?(:settings=)
        config.settings = settings
      elsif config.respond_to?(:receiver_settings=)
        config.receiver_settings = settings
      else
        puts "⚠️ InboundConfig не поддерживает settings"
      end
    end

    config
  end


    def json_to_stream_settings(json)
      # Простая реализация - в реальности нужно обрабатывать все поля
      return nil unless json
      
      # Базовые настройки транспорта
      transport_config = Transport::Internet::StreamConfig.new
      transport_config.protocol_name = json['network'] || 'tcp'
      
      # Настройки безопасности
      if json['security'] == 'reality'
        reality_settings = json['realitySettings']
        if reality_settings
          # Здесь нужно создать reality settings
          # Это сложная структура, упрощаем
          transport_config.security_type = 'reality'
        end
      end
      
      transport_config
    end

    def to_typed_message(message)
      return nil if message.nil?
      
      Common::Serial::TypedMessage.new(
        type: message.class.descriptor.name,
        value: Google::Protobuf.encode(message)
      )
    end
  end
end