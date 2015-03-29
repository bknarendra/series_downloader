%w(redis nori rest-client kat json open3).each {|lib| require lib}


class SeriesDownloader

  attr_accessor :logger
  def initialize
    @constants = YAML.load(File.read('./constants.yml'))['constants'].symbolize_keys
    @db_store = DbStore.new('redis_store', @constants[:redis])
    @tv_maze_api = TvMazeApi.new
    @logger = []
  end

  def record_errors(params)
    params.merge!(date: Time.now.inspect)
    @logger << params.inspect
    @db_store.append('errors', "\n#{params.to_json}")
  end

  def series_to_monitor
    @series_to_monitor ||= @constants[:series_to_monitor]
  end

  def get_magnet_link(series, params)
    if Time.now.to_i - (DateTime.parse(params[:air_date]).to_time).to_i < 0
      @logger <<  "Episode not aired yet. Series: #{series} Params : #{params.inspect}"
      return {err: 'episode_not_aired_yet', err_msg: "Episode not aired yet. Series: #{series} Params : #{params.inspect}"}
    end
    kickass_search_res = Kat.quick_search(series)
    kickass_search_res.select!{|x| x[:title].index(/S?0*#{params[:season]}[xE]0*#{params[:episode]}/) }
    return { err: 'err1', class: self.class, method: __method__,  file: __FILE__, line: __LINE__, 
             err_msg: "Could not any magnet link. Series: #{series} Params : #{params.inspect}" } if kickass_search_res.nil? || kickass_search_res.length == 0 
    { err: nil, result: kickass_search_res[0][:magnet] }
  end

  def get_next_episode_to_download(series)
    res = @db_store.get(series)
    res = JSON.parse(res) rescue nil
    res.symbolize_keys unless res.nil?
  end

  def set_next_episode_to_download(series)
    result = @tv_maze_api.next_episode_details(series)
    unless result[:err].nil?
      record_errors(result)
      return
    end
    episode_details = { season: result[:result].next_season_no, episode: result[:result].next_episode_no, air_date: result[:result].next_air_date }
    @db_store.set(series, episode_details.to_json)
  end

  def drop_torrent(magnet_link)
    begin
      @logger << "starting torrent download"
      cmd = "node dnode.js \"#{magnet_link}\""
      Utils::Subprocess.new cmd do |stdout, stderr, thread|
        @logger << "stdout: #{stdout}"
        @logger << "stderr: #{stderr}"
        puts thread.pid
      end
    rescue Exception => e
      record_errors({err_msg: e.message, backtrace: e.backtrace.inspect})
    end
  end

  def send_simple_message(params)
    RestClient.post @constants[:mailgun_api_url],
                    from: @constants[:from_email],
                    to: @constants[:to_email],
                    subject: "#{params[:series]} S0#{params[:season]}E#{params[:episode]} downloaded on Dropbox",
                    text: "#{params[:series]} S0#{params[:season]}E#{params[:episode]} downloaded on Dropbox."
  end

  def process
    series_to_monitor.each do |series|
      series_episode_details = get_next_episode_to_download(series)
      if series_episode_details.nil?
        set_next_episode_to_download(series)
        next
      end
      result = get_magnet_link(series, series_episode_details)
      next if result[:err] == 'episode_not_aired_yet'
      unless result[:err].nil?
        record_errors(result)      
        next
      end
      @db_store.del(series)
      set_next_episode_to_download(series)
      @logger <<  "#{result[:result]}"
      drop_torrent(result[:result])
      send_simple_message(series_episode_details)
    end
  end

end

class TvMazeApi
  API_URL = 'http://api.tvmaze.com/'

  def search(series)
    result = JSON.parse(RestClient.get(search_url(series)))
    return { err: 'err1', class: self.class, method: __method__,  file: __FILE__, line: __LINE__,
             err_msg: "Could not find next episodes. Series: #{series}"} if result['_links']['nextepisode'].nil?
    {err: nil, result: result['_links']['nextepisode']['href']}
  end

  def next_episode_details(series)
    result = search(series)
    return result unless result[:err].nil?
    result = JSON.parse RestClient.get(result[:result])
    result = Series.new(result)
    { err: nil, result: result }
  end

  def search_url(query)
    "#{API_URL}singlesearch/shows?q=#{URI.encode(query)}"
  end

  class Series

    def initialize(params)
      @params = params
    end

    def next_air_date
      @params['airstamp']
    end

    def next_season_no
      @params['season']
    end

    def next_episode_no
      @params['number']
    end

  end

end

class DbStore

  def initialize(store, params)
    @store = Object.const_get(store.camelize).new(params)
  end

  def set(key, value)
    @store.set(key, value)
  end

  def get(key)
    @store.get(key)
  end

  def del(key)
    @store.del(key)
  end

  def append(key, value)
    @store.append(key, value)
  end

end

class RedisStore
 
  def initialize(params)
    @conn = Redis.new(params)
  end

  def method_missing(method, *args, &block)
    if @conn.respond_to?(method)
      @conn.send(method, *args)
    else
      super
    end
  end

end

class String

  def camelize
    self.split('_').collect(&:capitalize).join
  end

end

class Hash

  def symbolize_keys
    inject({}){|result, (key, value)|
      new_key = case key
                when String then key.to_sym
                else key
                end
      new_value = case value
                  when Hash then value.symbolize_keys
                  else value
                  end
      result[new_key] = new_value
      result
    }
  end

end

module Utils
  class Subprocess
    def initialize(cmd, &block)
      # see: http://stackoverflow.com/a/1162850/83386
      Open3.popen3(cmd) do |stdin, stdout, stderr, thread|
        # read each stream from a new thread
        { :out => stdout, :err => stderr }.each do |key, stream|
          Thread.new do
            puts "started new thread"
            puts "stream.gets => #{stream.gets.inspect}"
            until (line = stream.gets).nil? do
              puts line
              # yield the block depending on the stream
              if key == :out
                yield line, nil, thread if block_given?
              else
                yield nil, line, thread if block_given?
              end
            end
          end
        end
        thread.join # don't exit until the external process is done
      end
    end
  end
end