require 'sinatra'
require './series_downloader.rb'
require 'thread'

@@hash, @@previous_hash = [], []

Thread.new do
  @@hash << "started thread"
  while true
    begin
      @@hash << "#{Time.now} Waking up.....<br>Starting the SeriesDownloader process.....<br>#{'=' * 140}"
      series_downloader = SeriesDownloader.new
      series_downloader.process
      @@hash += series_downloader.logger
      @@hash << "#{Time.now} Done processing.......<br>#{'=' * 140}"
      @@previous_hash = @@hash
      @@hash = Array.new
      @@hash << "#{Time.now} Sleeping for 2 hours. This will run after 2 hours"
      sleep 60 * 60 * 2
      GC.start
    rescue Exception => e
      @@hash <<  "Exception:: #{CGI::escape_html(e.message)}<br>#{CGI::escape_html(e.backtrace.inspect)}"
    end
  end
end

get '/' do
  "I am alive"
end

get '/b6920b5659a4f42e6ef720613cb9ec01' do # previously run cron logs
  @@previous_hash * '<br>'
end

get '/90d8ce5bb583d0a4b19ba8b369801027' do # currently running cron logs
  @@hash * '<br>'
end