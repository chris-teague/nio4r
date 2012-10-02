require 'thread'
require 'nio/version'

# New I/O for Ruby
module NIO
  # NIO implementation, one of the following (as a string):
  # * select: in pure Ruby using Kernel.select
  # * libev: as a C extension using libev
  # * java: using Java NIO
  def self.engine; ENGINE end
end

def windows?
  !!(RbConfig::CONFIG['host_os'] =~ /mswin|win32|dos|mingw32/i)
end

if ENV["NIO4R_PURE"] || windows?
  require 'nio/monitor'
  require 'nio/selector'
  NIO::ENGINE = 'select'
else
  require 'nio4r_ext'

  if defined?(JRUBY_VERSION)
    require 'java'
    require 'jruby'
    org.nio4r.Nio4r.new.load(JRuby.runtime, false)
    NIO::ENGINE = 'java'
  else
    NIO::ENGINE = 'libev'
  end
end
