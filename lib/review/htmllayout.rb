# Copyright (c) 2009 Narihiro Nakamura <authornari@gmail.com>
require 'erb'

class HTMLLayout
  include ERB::Util

  def initialize(params, template)
    @body = params['body']
    @title = params['title']
    @toc = params['toc']
    @next = params['next']
    @prev = params['prev']
    @builder = params['builder']
    @language = params['language']
    @stylesheets = params['stylesheets']
    @template = template
  end
  attr_reader :body, :title, :toc

  def next_chapter
    if @next.present?
      "<a href='#{h @next.id}.html'>#{h @builder.compile_inline @next.title}</a>"
    else
      ""
    end
  end

  def prev_chapter
    if @prev.present?
      "<a href='#{h @prev.id}.html'>#{h @builder.compile_inline @prev.title}</a>"
    else
      ""
    end
  end

  def result
    if File.exist?(@template)
      return ERB.new(IO.read(@template)).result(binding)
    else
      return @src
    end
  end
end
