require 'helpers'

$channel = nil
$message = nil

class Redis
  def initialize(options = {})
  end

  def pipelined
    yield self
  end

  def set(key, message)
    $command = :set
    $key = key
    $message = message
  end

  def rpush(key, message)
    $command = :rpush
    $key = key
    $message = message
  end

  def lpush(key, message)
    $command = :lpush
    $key = key
    $message = message
  end

  def sadd(key, message)
    $command = :sadd
    $key = key
    $message = message
  end

  def zadd(key, score, message)
    $command = :zadd
    $key = key
    $score = score
    $message = message
  end

  def expire(key, ttl)
    $expire_key = key
    $ttl = ttl
  end

  def publish(channel, message)
    $command = :publish
    $channel = channel
    $message = message
  end

  def quit
  end
end

class RedisStoreOutputTest < Test::Unit::TestCase
  def setup
    Fluent::Test.setup
  end

  def create_driver(conf)
    Fluent::Test::Driver::Output.new(Fluent::Plugin::RedisStoreOutput).configure(conf)
  end

  def test_configure_defaults
    config = %[
      url redis://redis:6379/12
      key_path a
      score_path b
    ]
    d = create_driver(config)
    assert_equal("redis://redis:6379/12", d.instance.url)
    assert_equal(nil, d.instance.password)
    assert_equal(nil, d.instance.db)
    assert_equal(5.0, d.instance.timeout)
    assert_equal('json', d.instance.format_type)
    assert_equal('', d.instance.key_prefix)
    assert_equal('', d.instance.key_suffix)
    assert_equal('zset', d.instance.store_type)
    assert_equal('a', d.instance.key_path)
    assert_equal(nil, d.instance.key)
    assert_equal('b', d.instance.score_path)
    assert_equal('', d.instance.value_path)
    assert_equal(-1, d.instance.key_expire)
    assert_equal(-1, d.instance.value_expire)
    assert_equal(-1, d.instance.value_length)
    assert_equal('asc', d.instance.order)
    assert_equal(nil, d.instance.collision_policy)
  end

  def test_configure_uri
    config = %[
      url redis://redis:6379/12
      key a
      score_path b
    ]
    d = create_driver(config)
    assert_equal 'redis://redis:6379/12', d.instance.url
  end

  def test_configure_sentinels
    config = %[
      sentinel_hosts ["redis-0"]
      sentinel_ports [26379]
      db 5
      key a
      score_path b
    ]
    d = create_driver(config)
    assert_equal [{ host: 'redis-0', port: 26379}], d.instance.sentinels
    assert_equal "mymaster", d.instance.sentinel_name
    assert_equal 5, d.instance.db
  end

  def test_configure_sentinels_name
    config = %[
      url redis://redis:6379/12
      sentinel_name mymaster2
      sentinel_hosts ["redis-0", "redis-2"]
      sentinel_ports [26379, 26372]
      key a
      score_path b
    ]
    d = create_driver(config)
    assert_equal [{ host: 'redis-0', port: 26379}, { host: 'redis-2', port: 26372}], d.instance.sentinels
    assert_equal [{ host: 'redis-0', port: 26379}, { host: 'redis-2', port: 26372}], d.instance.sentinels
    assert_equal "mymaster2", d.instance.sentinel_name
  end

  def test_configure_path
    config = %[
      url redis://redis:6379/12
      key a
      score_path b
    ]
    d = create_driver(config)

    assert_equal "redis://redis:6379/12", d.instance.url
  end

  def test_configure_exception
    assert_raise(Fluent::ConfigError) do
      create_driver(%[])
    end
  end

#  def test_write
#    d = create_driver(CONFIG1)
#
#    time = event_time("2011-01-02 13:14:15 UTC")
#    d.run(default_tag 'test') do
#      d.feed({ "foo" => "bar" }, time)
#    end
#
#    assert_equal "test", $channel
#    assert_equal(%Q[{"foo":"bar","time":#{time}}], $message)
#  end

  def get_time
    event_time("2011-01-02 13:14:15 UTC")
  end

  # it should return whole message
  def test_omit_value_path
    config = %[
      url redis://redis:6379/12
      format_type plain
      store_type string
      key_path   user
    ]
    d = create_driver(config)
    message = {
      'user' => 'george',
      'stat' => { 'attack' => 7 }
    }
    $ttl = nil
    d.run(default_tag: 'test') do
      d.feed(get_time, message)
    end

    assert_equal "george", $key
    assert_equal message, $message
    assert_equal nil, $ttl
  end

  def test_key_value_paths
    config = %[
      url redis://redis:6379/12
      format_type plain
      store_type string
      key_path   user.name
      value_path stat.attack
      key_expire 3
    ]
    d = create_driver(config)
    message = {
      'user' => { 'name' => 'george' },
      'stat' => { 'attack' => 7 }
    }
    $ttl = nil
    d.run(default_tag: 'test') do
      d.feed(get_time, message)
    end

    assert_equal "george", $key
    assert_equal 7, $message
    assert_equal 3, $ttl
  end

  def test_json
    config = %[
      url redis://redis:6379/12
      format_type json
      store_type string
      key_path   user
    ]
    d = create_driver(config)
    message = {
      'user' => 'george',
      'stat' => { 'attack' => 7 }
    }
    $ttl = nil
    d.run(default_tag: 'test') do
      d.feed(get_time, message)
    end

    assert_equal "george", $key
    assert_equal message.to_json, $message
  end

  def test_msgpack
    config = %[
      url redis://redis:6379/12
      format_type msgpack
      store_type string
      key_path   user
    ]
    d = create_driver(config)
    message = {
      'user' => 'george',
      'stat' => { 'attack' => 7 }
    }
    $ttl = nil
    d.run(default_tag: 'test') do
      d.feed(get_time, message)
    end

    assert_equal "george", $key
    assert_equal message.to_msgpack, $message
  end

  def test_list_asc
    config = %[
      url redis://redis:6379/12
      format_type plain
      store_type list
      key_path   user
    ]
    d = create_driver(config)
    message = {
      'user' => 'george',
      'stat' => { 'attack' => 7 }
    }
    d.run(default_tag: 'test') do
      d.feed(get_time, message)
    end

    assert_equal :rpush, $command
    assert_equal "george", $key
    assert_equal message, $message
  end

  def test_list_desc
    config = %[
      url redis://redis:6379/12
      format_type plain
      store_type list
      key_path   user
      order      desc
    ]
    d = create_driver(config)
    message = {
      'user' => 'george',
      'stat' => { 'attack' => 7 }
    }
    d.run(default_tag: 'test') do
      d.feed(get_time, message)
    end

    assert_equal :lpush, $command
    assert_equal "george", $key
    assert_equal message, $message
  end

  def test_set
    config = %[
      url redis://redis:6379/12
      format_type plain
      store_type set
      key_path   user
      order      desc
    ]
    d = create_driver(config)
    message = {
      'user' => 'george',
      'stat' => { 'attack' => 7 }
    }
    d.run(default_tag: 'test') do
      d.feed(get_time, message)
    end

    assert_equal :sadd, $command
    assert_equal "george", $key
    assert_equal message, $message
  end

  def test_zset
    config = %[
      url redis://redis:6379/12
      format_type plain
      store_type zset
      key_path   user
      score_path result
    ]

    d = create_driver(config)
    message = {
      'user' => 'george',
      'stat' => { 'attack' => 7 },
      'result' => 81
    }
    d.run(default_tag: 'test') do
      d.feed(get_time, message)
    end

    assert_equal :zadd, $command
    assert_equal "george", $key
    assert_equal 81, $score
    assert_equal message, $message
  end

  def test_zset_with_no_score_path
    config = %[
      url redis://redis:6379/12
      format_type plain
      store_type zset
      key_path   user
    ]

    d = create_driver(config)
    message = {
      'user' => 'george',
      'stat' => { 'attack' => 7 },
      'result' => 81
    }
    d.run(default_tag: 'test') do
      d.feed(get_time, message)
    end

    assert_equal :zadd, $command
    assert_equal "george", $key
    assert_equal get_time, $score
    assert_equal message, $message
  end

  def test_publish
    config = %[
      url redis://redis:6379/12
      format_type plain
      store_type publish
      key_path   user
    ]

    d = create_driver(config)
    message = {
      'user' => 'george'
    }
    d.run(default_tag: 'test') do
      d.feed(get_time, message)
    end

    assert_equal :publish, $command
    assert_equal "george", $channel
    assert_equal message, $message
  end

  def test_empty_key
    config = %[
      url redis://redis:6379/12
      format_type plain
      store_type string
      key_path   none
    ]

    d = create_driver(config)
    message = { 'user' => 'george' }
    suppress_output do
      assert_raise(Fluent::ConfigError) do
        d.run(default_tag: 'test') do
          d.feed(get_time, message)
        end
      end
    end
  end

  def suppress_output
    begin
      original_stderr = $stderr.clone
      original_stdout = $stdout.clone
      $stderr.reopen(File.new('/dev/null', 'w'))
      $stdout.reopen(File.new('/dev/null', 'w'))
      retval = yield
    rescue Exception => e
      $stdout.reopen(original_stdout)
      $stderr.reopen(original_stderr)
      raise e
    ensure
      $stdout.reopen(original_stdout)
      $stderr.reopen(original_stderr)
    end
    retval
  end
end
