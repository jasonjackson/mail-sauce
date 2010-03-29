#!/usr/bin/env ruby  

require 'rubygems'
require 'optparse'
require 'ostruct'

class SenderOptparse

  # Return a structure describing the options.
  #
  def self.parse(args)
    # The options specified on the command line will be collected in *options*.
    # We set default values here.
    options = OpenStruct.new
    options.listname = []
    options.test = false
    options.priority = false
    options.verbose = false

    opts = OptionParser.new do |opts|
      opts.banner = "Usage: send.rb [options]"

      opts.separator ""
      opts.separator "Specific options:"

      # Mandatory argument.
      opts.on("-l", "--listname LISTNAME",
              "LISTNAME of the campaign to be sent.") do |lib|
        options.listname << lib
      end

      opts.on("-t", "--test",
              "Send the list in the test environment.") do |test|
        options.test = true
      end

      opts.on("-p", "--priority",
              "Send the list as a priority send.") do |priority|
        options.priority = true
      end

      # Boolean switch.
      opts.on("-v", "--[no-]verbose", "Run verbosely") do |v|
        options.verbose = v
      end

      opts.separator ""
      opts.separator "Common options:"

      # No argument, shows at tail.  This will print an options summary.
      # Try it and see!
      opts.on_tail("-h", "--help", "Show this message") do
        puts opts
        exit
      end

      # Another typical switch to print the version.
      opts.on_tail("--version", "Show version") do
        puts OptionParser::Version.join('.')
        exit
      end
    end

    opts.parse!(args)
    options
  end  # parse()

end  # class OptparseExample

