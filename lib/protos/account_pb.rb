# frozen_string_literal: true

# Generated by the protocol buffer compiler.  DO NOT EDIT!
# source: account.proto

require 'google/protobuf'

descriptor_data = "\n\raccount.proto\x12\x10xray.proxy.vless\"7\n\x07\x41\x63\x63ount\x12\n\n\x02id\x18\x01 \x01(\t\x12\x0c\n\x04\x66low\x18\x02 \x01(\t\x12\x12\n\nencryption\x18\x03 \x01(\tBR\n\x14\x63om.xray.proxy.vlessP\x01Z%github.com/xtls/xray-core/proxy/vless\xaa\x02\x10Xray.Proxy.Vlessb\x06proto3"

pool = Google::Protobuf::DescriptorPool.generated_pool

begin
  pool.add_serialized_file(descriptor_data)
rescue TypeError
  # Compatibility code: will be removed in the next major version.
  require 'google/protobuf/descriptor_pb'
  parsed = Google::Protobuf::FileDescriptorProto.decode(descriptor_data)
  parsed.clear_dependency
  serialized = parsed.class.encode(parsed)
  file = pool.add_serialized_file(serialized)
  warn "Warning: Protobuf detected an import path issue while loading generated file #{__FILE__}"
  imports = []
  imports.each do |type_name, expected_filename|
    import_file = pool.lookup(type_name).file_descriptor
    if import_file.name != expected_filename
      warn "- #{file.name} imports #{expected_filename}, but that import was loaded as #{import_file.name}"
    end
  end
  warn 'Each proto file must use a consistent fully-qualified name.'
  warn 'This will become an error in the next major version.'
end

module Xray
  module Proxy
    module Vless
      Account = ::Google::Protobuf::DescriptorPool.generated_pool.lookup('xray.proxy.vless.Account').msgclass
    end
  end
end
