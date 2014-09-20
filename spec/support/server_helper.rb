# Adapted from excon's tests/test_helper.rb
module ServerHelper

  extend self

  def server_path(*parts)
    File.expand_path(File.join(File.dirname(__FILE__), "..", "servers", *parts))
  end

  def with_server(name)
    require "open4"
    pid, w, r, e = Open4.popen4(server_path("#{name}.rb"))

    until val = e.gets; val =~ /ready/ || val.nil?
      puts val
    end

    yield
  ensure
    Process.kill(9, pid)
    Process.wait(pid)
  end
end
