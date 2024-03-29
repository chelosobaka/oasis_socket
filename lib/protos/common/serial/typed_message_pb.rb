# frozen_string_literal: true

# Generated by the protocol buffer compiler.  DO NOT EDIT!
# source: typed_message.proto

require 'google/protobuf'

descriptor_data = "\n\x13typed_message.proto\x12\x12xray.common.serial\"+\n\x0cTypedMessage\x12\x0c\n\x04type\x18\x01 \x01(\t\x12\r\n\x05value\x18\x02 \x01(\x0c\x42X\n\x16\x63om.xray.common.serialP\x01Z\'github.com/xtls/xray-core/common/serial\xaa\x02\x12Xray.Common.Serialb\x06proto3"

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
  module Common
    module Serial
      TypedMessage = ::Google::Protobuf::DescriptorPool.generated_pool.lookup('xray.common.serial.TypedMessage').msgclass
    end
  end
end
