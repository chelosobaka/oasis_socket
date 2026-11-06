# Тесты агента без Xray: config.json — во временной папке (XRAY_CONFIG_PATH), вместо API
# Xray — FakeXrayAPI. Запуск: ruby test/agent_test.rb (нужны гемы grpc и google-protobuf).
require 'minitest/autorun'
require 'tmpdir'
require 'fileutils'
require_relative '../lib/socket'

class FakeXrayAPI
  attr_reader :calls

  def initialize(refusal = nil)
    @refusal = refusal
    @calls = []
    @lock = Mutex.new
  end

  def add_user(tag, email, uuid, flow)
    @lock.synchronize { @calls << [:add, tag, email, uuid, flow] }
    raise AgentError, @refusal if @refusal

    true
  end

  def remove_user(tag, email)
    @lock.synchronize { @calls << [:remove, tag, email] }
    true
  end
end

class AgentTest < Minitest::Test
  API = { 'tag' => 'api', 'listen' => '127.0.0.1', 'port' => 10_085, 'protocol' => 'dokodemo-door',
          'settings' => { 'address' => '127.0.0.1' } }.freeze

  def setup
    @dir = Dir.mktmpdir
    @path = File.join(@dir, 'config.json')
    ENV['XRAY_CONFIG_PATH'] = @path
    @xray = FakeXrayAPI.new
    @agent = agent_with(@xray)
  end

  def teardown
    ENV.delete('XRAY_CONFIG_PATH')
    FileUtils.rm_rf(@dir)
  end

  def test_uses_inbounds_1_for_keys
    write_config(API, reality('inbound-443'))

    assert_equal ['true', nil], add('1-1', 'xtls-rprx-vision')
    assert_equal [[:add, 'inbound-443', '1-1', 'uuid-1-1', 'xtls-rprx-vision']], @xray.calls
    assert_equal [{ 'id' => 'uuid-1-1', 'email' => '1-1', 'flow' => 'xtls-rprx-vision' }], clients
  end

  def test_leaves_inbounds_0_alone_even_when_it_is_also_vless
    write_config(reality('system-0'), grpc('keys-1'))

    assert_equal ['true', nil], add('1-1', '')
    assert_equal 'keys-1', only(@xray.calls)[1]
    assert_equal ['1-1'], clients.map { |client| client['email'] }
  end

  def test_grpc_and_xhttp_clients_get_an_empty_flow_whatever_rails_sends
    [grpc('grpc-in'), xhttp('xhttp-in')].each do |inbound|
      write_config(API, inbound)
      @xray.calls.clear

      assert_equal ['true', nil], add('1-1', 'xtls-rprx-vision')
      assert_equal '', only(@xray.calls).last
      assert_equal '', only(clients)['flow']
    end
  end

  def test_reality_takes_the_flow_rails_sends
    write_config(API, reality('vless-in'))

    add('1-1', '')
    assert_equal '', only(@xray.calls).last
  end

  def test_replaces_a_stale_file_entry_with_the_same_email
    write_config(API, reality('vless-in', [{ 'id' => 'old', 'email' => '1-1', 'flow' => '' }]))

    add('1-1', 'xtls-rprx-vision')
    assert_equal [{ 'id' => 'uuid-1-1', 'email' => '1-1', 'flow' => 'xtls-rprx-vision' }], clients
  end

  def test_refuses_when_there_is_no_inbounds_1
    write_config(API)

    answer, reason = add('1-1', '')
    assert_equal 'false', answer
    assert_equal "в #{@path} нет inbounds[1] для ключей (inbounds[0] — системный)", reason
    assert_empty @xray.calls
  end

  def test_refuses_when_inbounds_1_is_not_vless
    write_config(API, API)

    assert_equal ['false', "inbounds[1] в #{@path} — не VLESS (protocol: dokodemo-door)"], add('1-1', '')
  end

  def test_refuses_an_inbound_without_a_tag
    write_config(API, reality(nil))

    assert_match(/нет тега/, add('1-1', '').last)
  end

  def test_passes_the_xray_refusal_and_keeps_the_file
    write_config(API, reality('vless-in'))
    @agent = agent_with(FakeXrayAPI.new('Xray API 127.0.0.1:10085 (inbound vless-in): User 1-1 already exists.'))

    assert_equal ['false', 'Xray API 127.0.0.1:10085 (inbound vless-in): User 1-1 already exists.'], add('1-1', '')
    assert_empty clients
  end

  def test_takes_the_client_back_from_xray_when_the_file_is_not_written
    write_config(API, reality('vless-in'))
    @agent.define_singleton_method(:write_config) { |_config| raise Errno::ENOSPC }

    answer, reason = add('1-1', 'xtls-rprx-vision')
    assert_equal 'false', answer
    assert_equal "не удалось записать #{@path}: No space left on device", reason
    assert_equal [:remove, 'vless-in', '1-1'], @xray.calls.last
  end

  def test_keeps_the_old_file_when_writing_fails
    write_config(API, reality('vless-in'))
    before = File.read(@path)
    File.singleton_class.alias_method(:original_rename, :rename)
    File.define_singleton_method(:rename) { |*| raise Errno::EACCES }

    assert_equal 'false', add('1-1', '').first
    assert_equal before, File.read(@path)
    refute File.exist?("#{@path}.tmp")
  ensure
    File.singleton_class.alias_method(:rename, :original_rename)
  end

  def test_refuses_a_client_that_is_not_json
    write_config(API, reality('vless-in'))

    answer, reason = @agent.respond_to_request('add_client {oops')
    assert_equal 'false', answer
    assert_match(/\Aклиент в add_client — не JSON/, reason)
  end

  def test_removes_a_client_from_xray_and_the_file
    write_config(API, grpc('grpc-in', [{ 'id' => 'u', 'email' => '1-1', 'flow' => '' }, { 'id' => 'v', 'email' => '1-2', 'flow' => '' }]))

    assert_equal ['true', nil], @agent.respond_to_request('remove_client 1-1')
    assert_equal [[:remove, 'grpc-in', '1-1']], @xray.calls
    assert_equal ['1-2'], clients.map { |client| client['email'] }
  end

  def test_finds_a_client_in_the_file
    write_config(API, reality('vless-in', [{ 'id' => 'u', 'email' => '1-1', 'flow' => '' }]))

    assert_equal ['true', nil], @agent.respond_to_request('find_client 1-1')
    assert_equal ['false', nil], @agent.respond_to_request('find_client 1-2')
  end

  def test_file_exist_names_the_missing_file
    assert_equal ['false', "нет файла #{@path}"], @agent.respond_to_request('file_exist?')
    write_config(API, reality('vless-in'))
    assert_equal ['true', nil], @agent.respond_to_request('file_exist?')
  end

  def test_server_values_of_a_reality_server_keep_the_old_fields
    write_config(API, reality('inbound-443'))

    values = JSON.parse(@agent.respond_to_request('server_values').first)
    assert_equal({ 'port' => 443, 'security' => 'reality', 'sni' => 'www.example.com', 'fp' => 'chrome',
                   'pbk' => 'PUBLIC', 'sid' => 'ab12', 'network_type' => 'tcp', 'flow' => 'xtls-rprx-vision',
                   'config_type' => 'reality', 'tag' => 'inbound-443', 'service_name' => nil, 'path' => nil,
                   'mode' => nil }, values)
  end

  def test_server_values_of_grpc_and_xhttp_servers
    write_config(API, grpc('grpc-in'))
    grpc_values = JSON.parse(@agent.respond_to_request('server_values').first)
    assert_equal %w[grpc grpc reality ab12 PUBLIC], grpc_values.values_at('config_type', 'service_name', 'security', 'sid', 'pbk')
    assert_equal '', grpc_values['flow']

    write_config(API, xhttp('xhttp-in'))
    xhttp_values = JSON.parse(@agent.respond_to_request('server_values').first)
    assert_equal ['xhttp', 'vpn.example.com', 8443, '/api/v3/download', 'stream-up', ''],
                 xhttp_values.values_at('config_type', 'sni', 'port', 'path', 'mode', 'flow')
  end

  def test_server_values_answer_an_empty_object_and_the_reason
    assert_equal ['{}', "нет файла #{@path}"], @agent.respond_to_request('server_values')
  end

  def test_reload_config_passes_the_systemctl_error
    bin = File.join(@dir, 'bin')
    FileUtils.mkdir_p(bin)
    File.write(File.join(bin, 'systemctl'), "#!/bin/sh\necho 'Job for xray.service failed.' >&2\nexit 1\n")
    File.chmod(0o755, File.join(bin, 'systemctl'))
    original_path = ENV.fetch('PATH')
    ENV['PATH'] = "#{bin}:#{original_path}"

    assert_equal ['false', 'systemctl restart xray: Job for xray.service failed.'], @agent.respond_to_request('reload_config')
  ensure
    ENV['PATH'] = original_path
  end

  def test_unknown_command
    assert_equal ['Invalid request', 'неизвестная команда «bogus»'], @agent.respond_to_request('bogus 1')
  end

  def test_parallel_adds_keep_every_client_in_the_file
    write_config(API, reality('inbound-443'))

    Array.new(20) { |i| Thread.new { add("1-#{i}", 'xtls-rprx-vision') } }.each(&:join)
    assert_equal 20, clients.size
  end

  def test_answers_over_tcp_with_the_reason_on_the_second_line
    write_config(API)
    server = OasisTCPSocket.new('127.0.0.1', 0)
    server.instance_variable_set(:@xray_api, @xray)
    port = server.instance_variable_get(:@server).addr[1]
    thread = Thread.new { server.start }

    assert_equal ['false', "в #{@path} нет inbounds[1] для ключей (inbounds[0] — системный)"], ask(port, 'add_client {"id":"u","email":"1-1","flow":""}')
    write_config(API, reality('inbound-443'))
    assert_equal ['true'], ask(port, 'add_client {"id":"u","email":"1-1","flow":""}')
    assert_equal 'reality', JSON.parse(only(ask(port, 'server_values')))['config_type']
  ensure
    thread&.kill
  end

  private

  def agent_with(xray)
    OasisTCPSocket.allocate.tap { |agent| agent.instance_variable_set(:@xray_api, xray) }
  end

  def add(email, flow)
    @agent.respond_to_request("add_client #{{ id: "uuid-#{email}", email: email, flow: flow }.to_json}")
  end

  def ask(port, request)
    TCPSocket.open('127.0.0.1', port) do |socket|
      socket.puts(request)
      socket.read.force_encoding(Encoding::UTF_8).lines.map(&:chomp)
    end
  end

  def only(items)
    assert_equal 1, items.size, items.inspect
    items.first
  end

  def clients
    JSON.parse(File.read(@path))['inbounds'][1]['settings']['clients']
  end

  def write_config(*inbounds)
    File.write(@path, JSON.pretty_generate('inbounds' => inbounds))
  end

  def reality(tag, clients = [])
    vless(tag, clients, 443, 'network' => 'tcp', 'security' => 'reality', 'realitySettings' => reality_settings)
  end

  def grpc(tag, clients = [])
    vless(tag, clients, 443, 'network' => 'grpc', 'security' => 'reality', 'realitySettings' => reality_settings,
                             'grpcSettings' => { 'serviceName' => 'grpc' })
  end

  def xhttp(tag, clients = [])
    vless(tag, clients, 8443, 'network' => 'xhttp', 'security' => 'tls',
                              'tlsSettings' => { 'serverName' => 'vpn.example.com' },
                              'xhttpSettings' => { 'path' => '/api/v3/download', 'mode' => 'stream-up' })
  end

  def vless(tag, clients, port, stream)
    { 'tag' => tag, 'port' => port, 'protocol' => 'vless',
      'settings' => { 'clients' => clients, 'decryption' => 'none' }, 'streamSettings' => stream }.compact
  end

  def reality_settings
    { 'serverNames' => ['www.example.com'], 'privateKey' => 'PRIVATE', 'shortIds' => ['ab12'],
      'settings' => { 'publicKey' => 'PUBLIC', 'fingerprint' => 'chrome' } }
  end
end
