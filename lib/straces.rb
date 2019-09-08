unless ARGV[0]
  puts "USAGE: [STRACES_IGNORE=accept4,gettimeofday] [STRACES_FOCUS=sendto,recvfrom] straces dump [gt|ge|lt|le|eq=value] [lines_before] [lines_after]"
  exit 1
end

contents = File.read ARGV[0]
filter = ARGV[1]
lines_before = Float ARGV[2] rescue 1
lines_after = Float ARGV[3] rescue 1
syscalls_ignored = ENV['STRACES_IGNORE']&.split(",") || []
syscalls_focused = ENV['STRACES_FOCUS']&.split(",") || []

class String
def black;          "\e[30m#{self}\e[0m" end
def red;            "\e[31m#{self}\e[0m" end
def green;          "\e[32m#{self}\e[0m" end
def brown;          "\e[33m#{self}\e[0m" end
def blue;           "\e[34m#{self}\e[0m" end
def magenta;        "\e[35m#{self}\e[0m" end
def cyan;           "\e[36m#{self}\e[0m" end
def gray;           "\e[37m#{self}\e[0m" end

def bg_black;       "\e[40m#{self}\e[0m" end
def bg_red;         "\e[41m#{self}\e[0m" end
def bg_green;       "\e[42m#{self}\e[0m" end
def bg_brown;       "\e[43m#{self}\e[0m" end
def bg_blue;        "\e[44m#{self}\e[0m" end
def bg_magenta;     "\e[45m#{self}\e[0m" end
def bg_cyan;        "\e[46m#{self}\e[0m" end
def bg_gray;        "\e[47m#{self}\e[0m" end

def bold;           "\e[1m#{self}\e[22m" end
def italic;         "\e[3m#{self}\e[23m" end
def underline;      "\e[4m#{self}\e[24m" end
def blink;          "\e[5m#{self}\e[25m" end
def reverse_color;  "\e[7m#{self}\e[27m" end
end


def strace_parse(line)
  matcher = line.match /^(?<time>\d\d:\d\d:\d\d\.?\d*)?\s?(?<pid>\d*)\s?(?<call>[^\(]+)(?<middle>.*)\<(?<timing>\d+\.\d+)\>$/

  # <detached ..>
  timing = Float matcher[:timing] rescue 0.0

  if matcher
    {
      pid: matcher[:pid],
      call: matcher[:call],
      middle: matcher[:middle],
      timing: timing
    }
  else
    nil
  end
end

def process(lines, syscalls_ignored, syscalls_focused)
  last_obj = {
    time: 0.0
  }

  objs = lines.map do |line|
    obj = strace_parse(line)
    next unless obj

    if syscalls_focused.length > 0
      next unless syscalls_focused.include? obj[:call]
    end
    next if syscalls_ignored.include? obj[:call]

    obj[:time] = obj[:timing] + last_obj[:time]
    last_obj = obj
    obj
  end
  objs.compact
end

def format(obj)
  [
    obj[:time].round(4).to_s.ljust(6, "0"),
    obj[:timing].round(6).to_s.ljust(8, "0"),
    obj[:call].ljust(16),
    obj[:middle],
  ].join(" ")
end

objs = process(contents.split("\n"), syscalls_ignored, syscalls_focused)
min = (objs.min_by {|e| e[:timing] })[:timing]
max = (objs.max_by {|e| e[:timing] })[:timing]
range = max - min

objs.each do |obj|
  obj[:normalized] = (
    (obj[:timing] - min) * 100 / range
  ).round(0)
end

objs.each_with_index do |obj, i|
  #p [obj[:time], obj[:timing], obj[:normalized]]

  unless filter
    puts [

      obj[:time].round(4).to_s.ljust(6, "0"),
      obj[:timing].round(6).to_s.ljust(8, "0"),
      obj[:call].ljust(16),
      "#"*(obj[:normalized] == 0 ? 1 : obj[:normalized])
    ].join " "
  else
    matches = filter.match /^(?<comparator>gt|lt|ge|le|eq)=(?<value>\d+\.?\d*)$/
    comparator = matches && matches[:comparator]
    value = Float matches[:value] rescue nil
    if comparator.nil? || value.nil?
      puts "invalid filter #{filter}"
      exit 1
    end

    ruby_comparator = case comparator
    when "gt"
      :>
    when "ge"
      :>=
    when "lt"
      :<
    when "lte"
      :<=
    when "eq"
      :==
    end

    if obj[:timing].send(ruby_comparator, value)
      terminal_width=Integer `tput cols`
      puts "-"*terminal_width
      puts objs[i-lines_before..i-1].map {|o| format(o)}
      puts format(objs[i]).red
      puts objs[i+1..i+lines_after].map {|o| format(o)}

      puts ""
    end
  end
end
