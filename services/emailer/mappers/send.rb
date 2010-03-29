#!/usr/bin/env ruby

require "rubygems"
require "dbi"
require "enumerator"
require "json"
require 'resque'
require 'redis'
require 'syslog'
require File.dirname(__FILE__) + '/../../../services/emailer/actors/normal'
require File.dirname(__FILE__) + '/../../../services/emailer/actors/test'
require File.dirname(__FILE__) + '/../../../services/emailer/actors/priority'
require File.dirname(__FILE__) + '/../../../lib/tenjin'
require File.dirname(__FILE__) + '/../../../lib/senderoptparse.rb'

options = SenderOptparse.parse(ARGV)

@listname = options.listname
@test = options.test
@priority = options.priority
@push_count = 0

# Format the content to insert tracking codes and unsub links  (we are CAN-SPAM compliant!)
def format_content(filename)
  # Remove outdated content files.
  if File.exist?("#{MAPPER_CONTENT_PATH}/#{filename}")
    FileUtils.rm "#{MAPPER_CONTENT_PATH}/#{filename}", :force => true
  end

  buffer = []
  File.new("#{CONTENT_DIRECTORY}/#{filename}", 'r').each { |line| buffer << line }

  # Create the formatted content directory if it doesn't exist
  unless File.exist?("#{MAPPER_CONTENT_PATH}")
    FileUtils.mkdir_p "#{MAPPER_CONTENT_PATH}"
  end

  # Content formatting..  Add tracking codes and unsub links
  out_file = File.new("#{MAPPER_CONTENT_PATH}/#{filename}", 'w', 0644)
  buffer.each do |row|
    if (/monster\.com\/unsub/ =~ row)
      row.gsub!("monster.com/unsub",'monster.com/unsub?eml=#{@hash}')
    elsif
      if ((/redlog\.cgi/ =~ row) || (/outlog\.cgi/ =~ row))
        if (/ESRC[^">]*code/ =~ row)
          row.gsub!(/(ESRC[^">]*)(code[^"'>]*)(["|'|>])/, '\1\2&eml=#{@hash}\3')
        elsif (/url[^">]*code/ =~ row)
          row.gsub!(/(url[^">]*)(code[^"'>]*)(["|'|>])/, '\1\2&eml=#{@hash}\3')
        end
      end
    end
    if (/\{\{\{\$fname\}\}\}/ =~ row)
      row.gsub!('{{{$fname}}}','"#{@fname}"')
    end
    if (/\{\{\{\$lname\}\}\}/ =~ row)
      row.gsub!('{{{$lname}}}','"#{@lname}"')
    end
    if (/\{\{\{\$email\}\}\}/ =~ row)
      row.gsub!('{{{$email}}}','"#{@email}"')
    end
    out_file.puts row
  end
  out_file.close
end

# Method to take a payload and push it to a nanite mapper.  We are also mapping 
# the class of the payload to the correct mapper.  This is so we can send test
# sends and priority sends to a different set of agents and a different queue in
# rabbit so that they are not backed up waiting on regular production sends.
def push_payload(data,listname)
  content_hash = { "timestamp" => Time.now.to_i, "listname" => listname }
  if @test
    payload = JSON.generate Array[content_hash, data]
    Resque.enqueue(Test, payload)
    @push_count += 1
  elsif @priority
    data.each_slice(ENVELOPESIZE) do |envelope|
      payload = JSON.generate Array[content_hash, envelope]
      Resque.enqueue(Priority, payload)
      @push_count += 1
    end
  else
    data.each_slice(ENVELOPESIZE) do |envelope|
      payload = JSON.generate Array[content_hash, envelope]
      Resque.enqueue(Normal, payload)
      @push_count += 1
    end
  end
end

dbh = DBI.connect("dbi:Mysql:sns:#{DB_SERVER}","#{DB_USER}","#{DB_PASSWD}")

listid_sth = dbh.prepare("select listid from valid_lists where name = ?")

# Is this a test send?
if options.test.is_a?(FalseClass)
  listid_sth.execute(@listname)
else
  listid_sth.execute(TEST_LIST)
end

listid_sth.fetch do |lid|
  @listid = lid.first
end
listid_sth.finish

list_data = dbh.prepare("select lower(addys.full_addy) as email, user_data.* from addys, mail_lists, user_data where mail_lists.listid = ? and addys.mailid = mail_lists.mailid and addys.mailid = user_data.mailid and addys.Black_list = 0 and addys.bounce = 0 and mail_lists.active = 1 order by addys.domain desc")

list_data.execute(@listid)

@data = Array.new

engine = ::Tenjin::Engine.new()
context = { :fname => '', :lname => '', :email => '', :hash => '' }

format_content("#{@listname}.htm")
format_content("#{@listname}.txt")
format_content("#{@listname}.sub")

html_source = "#{MAPPER_CONTENT_PATH}/#{@listname}.htm"
html_cache = "#{MAPPER_CONTENT_PATH}/#{@listname}.htm.cache"

txt_source = "#{MAPPER_CONTENT_PATH}/#{@listname}.txt"
txt_cache = "#{MAPPER_CONTENT_PATH}/#{@listname}.txt.cache"

sub_source = "#{MAPPER_CONTENT_PATH}/#{@listname}.sub"
sub_cache = "#{MAPPER_CONTENT_PATH}/#{@listname}.sub.cache"

engine.render(html_source, context)    
engine.render(txt_source, context)
engine.render(sub_source, context)

content_store = Redis.new :host => REDIS_HOST, :port => REDIS_PORT

content_store.delete "#{@listname}-html"
content_store.delete "#{@listname}-chtml"
content_store.delete "#{@listname}-txt"
content_store.delete "#{@listname}-ctxt"
content_store.delete "#{@listname}-sub"
content_store.delete "#{@listname}-csub"

content_store["#{@listname}-html"] = IO.read(html_source)
content_store["#{@listname}-chtml"] = IO.read(html_cache)
content_store["#{@listname}-txt"] = IO.read(txt_source)
content_store["#{@listname}-ctxt"] = IO.read(txt_cache)
content_store["#{@listname}-sub"] = IO.read(sub_source)
content_store["#{@listname}-csub"] = IO.read(sub_cache)

member_hash = ::Hash.new
content_hash = ::Hash.new
payload = ::Array.new

while row = list_data.fetch do
     member_hash = { "listid" => @listid, 
                     "email" => row[0], 
                     "fname" => row[3], 
                     "lname" => row[4], 
                     "hash" => ''  
                   }
     @data << member_hash
end
list_data.finish

@test ? (list = ("#{@listname}_test")) : (list = @listname)

Content.to_syslog("Emailer Send:", "Sent #{@data.size} emails for #{list} (ID: #{@listid}).  #{@push_count} envelopes to Redis.")

push_payload(@data,@listname)

@push_count = 0
