#
# $Id: tocparser.rb 4268 2009-05-27 04:17:08Z kmuto $
#
# Copyright (c) 2002-2007 Minero Aoki
#               2008-2009 Minero Aoki, Kenshi Muto
#
# This program is free software.
# You can distribute or modify this program under the terms of
# the GNU LGPL, Lesser General Public License version 2.1.
# For details of the GNU LGPL, see the file "COPYING".
#

require 'review/preprocessor'
require 'review/book'
require 'review/textbuilder'

module ReVIEW

  class TOCParser
    def TOCParser.parse(chap)
      chap.open do |f|
        stream = Preprocessor::Strip.new(f)
        new.parse(stream, chap).map do |root|
          root.number = chap.number
          root
        end
      end
    end

    def parse(f, chap)
      roots = [] ## list of chapters
      node_stack = []
      filename = chap.path
      while line = f.gets
        line.sub!(/\A\xEF\xBB\xBF/u, '') # remove BOM
        case line
        when /\A\#@/
          ;
        when /\A\s*\z/
          ;
        when /\A(={2,})[\[\s\{]/
          lev = $1.size
          error! filename, f.lineno, "section level too deep: #{lev}" if lev > 5
          label = get_label(line)
          if node_stack.empty?
            # missing chapter label
            dummy_chapter = Chapter.new(label, chap)
            node_stack.push dummy_chapter
            roots.push dummy_chapter
          end
          next if label =~ /\A\[\// # ex) "[/column]"
          sec = Section.new(lev, label.gsub(/\A\{.*?\}\s?/, ""))
          until node_stack.last.level < sec.level
            node_stack.pop
          end
          node_stack.last.add_child sec
          node_stack.push sec

        when /\A= /
          label = get_label(line)
          node_stack.clear
          new_chapter = Chapter.new(label, chap)
          node_stack.push new_chapter
          roots.push new_chapter

        when %r<\A//\w+(?:\[.*?\])*\{\s*\z>
          if node_stack.empty?
            error! filename, f.lineno, 'list found before section label'
          end
          node_stack.last.add_child(list = List.new)
          beg = f.lineno
          list.add line
          while line = f.gets
            break if %r<\A//\}> =~ line
            list.add line
          end
          error! filename, beg, 'unterminated list' unless line

        when %r<\A//\w>
          ;
        else
          #if node_stack.empty?
          #  error! filename, f.lineno, 'text found before section label'
          #end
          next if node_stack.empty?
          node_stack.last.add_child(par = Paragraph.new(chap))
          par.add line
          while line = f.gets
            break if /\A\s*\z/ =~ line
            par.add line
          end
        end
      end

      roots
    end

    def get_label(line)
      line = line.strip.sub(/\A=+\s*/, '')
      compile_label(line)
    end

    def compile_label(line)
      b = ReVIEW::TEXTBuilder.new
      dummy_book = ReVIEW::Book::Base.load
      dummy_chapter = ReVIEW::Book::Chapter.new(dummy_book, 1, '-', nil, StringIO.new)
      dummy_loc = Location.new("", StringIO.new)
      b.bind(ReVIEW::Compiler.new(b), dummy_chapter, dummy_loc)
      b.compile_inline(line)
    end

    def error!(filename, lineno, msg)
      raise "#{filename}:#{lineno}: #{msg}"
    end


    class Node

      def initialize(children = [])
        @children = children
      end

      attr_reader :children

      def add_child(c)
        @children.push c
      end

      def each_node(&block)
        @children.each do |c|
          yield c
          c.each(&block)
        end
      end

      def each_child(&block)
        @children.each(&block)
      end

      def chapter?
        false
      end

      def each_section(&block)
        @children.each do |n|
          n.yield_section(&block)
        end
      end

      def each_section_with_index
        i = 0
        each_section do |n|
          yield n, i
          i += 1
        end
      end

      def section_size
        cnt = 0
        @children.each do |n|
          n.yield_section { cnt += 1 }
        end
        cnt
      end

    end


    class Section < Node

      def initialize(level, label, path = nil)
        super()
        @level = level
        @label = label
        @filename = (path ? real_filename(path) : nil)
      end

      def real_filename(path)
        if FileTest.symlink?(path)
          File.basename(File.readlink(path))
        else
          File.basename(path)
        end
      end
      private :real_filename

      attr_reader :level
      attr_reader :label

      def estimated_lines
        @children.inject(0) {|sum, n| sum + n.estimated_lines }
      end

      def yield_section
        yield self
      end

      def inspect
        "\#<#{self.class} level=#{@level} #{@label}>"
      end

    end


    class Chapter < Section

      def initialize(label, chap)
        super 1, label, chap.path
        @chapter = chap
        @chapter_id = chap.id
        @path = chap.path
        @page_metric = chap.book.page_metric
        @volume = nil
        @number = nil
      end

      attr_accessor :number

      def chapter?
        true
      end

      attr_reader :chapter_id

      def volume
        return @volume if @volume
        @volume = @chapter.volume
        @volume.lines = estimated_lines()
        @volume
      end

      def inspect
        "\#<#{self.class} #{@filename}>"
      end

    end


    class Paragraph < Node

      def initialize(chap)
        @bytes = 0
        @page_metric = chap.book.page_metric
      end

      def inspect
        "\#<#{self.class}>"
      end

      def add(line)
        @bytes += line.strip.bytesize
      end

      def estimated_lines
        (@bytes + 2) / @page_metric.text.n_columns + 1
      end

      def yield_section
      end

    end


    class List < Node

      def initialize
        @lines = 0
      end

      def inspect
        "\#<#{self.class}>"
      end

      def add(line)
        @lines += 1
      end

      def estimated_lines
        @lines + 2
      end

      def yield_section
      end

    end

  end


  module TOCRoot
    def level
      0
    end

    def chapter?
      false
    end

    def each_section_with_index
      idx = -1
      each_section do |node|
        yield node, (idx += 1)
      end
    end

    def each_section(&block)
      each_chapter do |chap|
        yield chap.toc
      end
    end

    def section_size
      chapters.size
    end

    def estimated_lines
      chapters.inject(0) {|sum, chap| sum + chap.toc.estimated_lines }
    end
  end

  class Book::Base # reopen
    include TOCRoot
  end

  class Book::Part
    include TOCRoot
  end

  class Book::Chapter # reopen
    def toc
      @toc ||= TOCParser.parse(self)
      unless @toc.size == 1
        $stderr.puts "warning: chapter #{@toc.join} contains more than 1 chapter"
      end
      @toc.first
    end
  end

end
