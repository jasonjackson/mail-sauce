# Inspired by rabbitmq.rake the Redbox project at http://github.com/rick/redbox/tree/master
require 'fileutils'
require 'open-uri'

class RedisRunner

  def self.redisdir
    "/tmp/redis/"
  end

  def self.redisconfdir
    server_dir = File.dirname(`which redis-server`)
    conf_file = "#{server_dir}/../etc/redis.conf"
    unless File.exists? conf_file
      conf_file = "#{server_dir}/../../etc/redis.conf"
    end
    conf_file
  end

  def self.dtach_socket
    '/tmp/redis.dtach'
  end

  # Just check for existance of dtach socket
  def self.running?
    File.exists? dtach_socket
  end

  def self.start
    puts 'Detach with Ctrl+\  Re-attach with rake redis:attach'
    sleep 1
    command = "dtach -A #{dtach_socket} redis-server #{redisconfdir}"
    sh command
  end

  def self.attach
    exec "dtach -a #{dtach_socket}"
  end

  def self.stop
    sh 'echo "SHUTDOWN" | nc localhost 6379'
  end

end

namespace :redis do

  desc 'About redis'
  task :about do
    puts "\nSee http://code.google.com/p/redis/ for information about redis.\n\n"
  end

  desc 'Start redis'
  task :start do
    RedisRunner.start
  end

  desc 'Stop redis'
  task :stop do
    RedisRunner.stop
  end

  desc 'Restart redis'
  task :restart do
    RedisRunner.stop
    RedisRunner.start
  end

  desc 'Attach to redis dtach socket'
  task :attach do
    RedisRunner.attach
  end

  desc 'Install the latest verison of Redis from Github (requires git, duh)'
  task :install => [:about, :download, :make] do
    ENV['PREFIX'] and bin_dir = "#{ENV['PREFIX']}/bin" or bin_dir = '/usr/bin'
    %w(redis-benchmark redis-cli redis-server).each do |bin|
      sh "cp /tmp/redis/#{bin} #{bin_dir}"
    end

    puts "Installed redis-benchmark, redis-cli and redis-server to #{bin_dir}"

    ENV['PREFIX'] and conf_dir = "#{ENV['PREFIX']}/etc" or conf_dir = '/etc'
    unless File.exists?("#{conf_dir}/redis.conf")
      sh "mkdir #{conf_dir}" unless File.exists?("#{conf_dir}")
      sh "cp /tmp/redis/redis.conf #{conf_dir}/redis.conf"
      puts "Installed redis.conf to #{conf_dir} \n You should look at this file!"
    end
  end

  task :make do
    sh "cd #{RedisRunner.redisdir} && make clean"
    sh "cd #{RedisRunner.redisdir} && make"
  end

  desc "Download package"
  task :download do
    sh 'rm -rf /tmp/redis/' if File.exists?("#{RedisRunner.redisdir}/.svn")
    sh 'git clone git://github.com/antirez/redis.git /tmp/redis' unless File.exists?(RedisRunner.redisdir)
    sh "cd #{RedisRunner.redisdir} && git pull" if File.exists?("#{RedisRunner.redisdir}/.git")
  end

end

namespace :dtach do

  desc 'About dtach'
  task :about do
    puts "\nSee http://dtach.sourceforge.net/ for information about dtach.\n\n"
  end

  desc 'Install dtach 0.8 from source'
  task :install => [:about] do

    Dir.chdir('/tmp/')
    unless File.exists?('/tmp/dtach-0.8.tar.gz')
      require 'net/http'

      url = 'http://downloads.sourceforge.net/project/dtach/dtach/0.8/dtach-0.8.tar.gz'
      open('/tmp/dtach-0.8.tar.gz', 'wb') do |file| file.write(open(url).read) end
    end

    unless File.directory?('/tmp/dtach-0.8')
      system('tar xzf dtach-0.8.tar.gz')
    end

    ENV['PREFIX'] and bin_dir = "#{ENV['PREFIX']}/bin" or bin_dir = "/usr/bin"
    Dir.chdir('/tmp/dtach-0.8/')
    sh 'cd /tmp/dtach-0.8/ && ./configure && make'
    sh "cp /tmp/dtach-0.8/dtach #{bin_dir}"

    puts "Dtach successfully installed to #{bin_dir}"
  end
end

