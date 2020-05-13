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
  return nil if line.end_with? "<unfinished ...>"
  return nil if line.end_with? "resumed>)      = ?"
  return nil if line.end_with? "+++ exited with 0 +++"
  # accept4(3,
  return nil if line.end_with? ", "
  return nil if line.end_with? "<detached ...>"
  return nil if line.include? "resuming interrupted call"

  matcher = line.match /^(?<pid>\d*)\s?(?<time>\d\d:\d\d:\d\d\.?\d*)?\s?(?<interrupted>\<\.\.\.)?(?<call>[^\(]+)(?<middle>.*)?\<(?<timing>\d+\.\d+)\>$/

  #63796 11:18:12 clock_gettime(CLOCK_MONOTONIC, {tv_sec=27510, tv_nsec=693534954}) = 0 <0.000108>
  #63796 11:18:12 <... clock_gettime resumed> {tv_sec=27510, tv_nsec=648632454}) = 0 <0.000356>

  call, middle = if matcher[:interrupted]
    syscall, rest = matcher[:call].split(" ")
    [syscall, rest]
  else
    [matcher[:call], matcher[:middle]]
  end

  timing = Float matcher[:timing] rescue 0.0

  if matcher
    {
      pid: matcher[:pid],
      call: call,
      middle: middle,
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
      "#".green*(obj[:normalized] == 0 ? 1 : obj[:normalized])
    ].join " "
  else
    matches = filter.match /^(?<comparator>at|gt|lt|ge|le|eq)=(?<value>\d+\.?\d*)$/
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
    when "eq","at"
      :==
    end

    target = if comparator == "at"
      obj[:time].round(4)
    else
      obj[:timing]
    end

    strace_ignores = ENV.fetch("STRACES_IGNORE", "").split(",")
    fucked_up = obj[:call].split(" ").last
    next if strace_ignores.include? fucked_up

    if target.send(ruby_comparator, value)
      if ENV["STRACES_SUM"]
        $total ||= 0
        $total = $total + objs[i][:timing]
        puts "#{$total.round(2)}s \t #{objs[i][:timing].round(3)}s #{objs[i-1][:middle]} #{objs[i][:call]}"
      else
        terminal_width=Integer `tput cols`
        puts "-"*terminal_width
        puts objs[i-lines_before..i-1].map {|o| format(o) + "\n" + "#".green*(o[:normalized] == 0 ? 1 : o[:normalized])}
        puts format(objs[i]).red + "\n" + "#".green*(objs[i][:normalized] == 0 ? 1 : objs[i][:normalized])
        puts objs[i+1..i+lines_after].map {|o| format(o) + "\n" + "#".green*(o[:normalized] == 0 ? 1 : o[:normalized])}
        puts ""
      end

    end
  end
end
