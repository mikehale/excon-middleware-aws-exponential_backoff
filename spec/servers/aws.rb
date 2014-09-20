#!/usr/bin/env ruby

require "sinatra/base"

class PathRequestCounter
  def initialize(app)
    @app = app
    @counter = {}
  end

  def call(env)
    path_info = env['PATH_INFO']
    @counter[path_info] ||= 1
    env['path_info.request.counter'] = @counter[path_info]

    @app.call(env).tap do
      @counter[path_info] += 1
    end
  end
end

class AWS < Sinatra::Base
  configure do
    set :port, 9292
  end

  use PathRequestCounter

  get '/throttle/:count' do
    count = request.env['path_info.request.counter']
     if count <= Integer(params[:count] || 0)
      [400, {}, ["<Code>Throttling</Code>"]]
    else
      [200, {}, "OK"]
    end
  end

  if app_file == $0
    start! do
      $stderr.puts "ready"
    end
  end
end
