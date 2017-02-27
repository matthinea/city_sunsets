require 'twitter_ebooks'
require 'json'
require 'timezone'
require 'httparty'
require 'dotenv'
require 'pry-byebug'
require 'time'
require 'action_view'
require 'action_view/helpers'
require 'active_support/core_ext/numeric/time'
require 'uri'
require_relative 'us_states'


class MyBot < Ebooks::Bot

  def configure
    Dotenv.load   

    self.consumer_key = ENV['CONSUMER_KEY']
    self.consumer_secret = ENV['CONSUMER_SECRET']

    # Users to block instead of interacting with
    # self.blacklist = ['tnietzschequote']

    # Range in seconds to randomize delay when bot.delay is called
    # self.delay_range = 1..6

    @@cities = JSON.parse(File.read("cities.json"))
    @@all_cities = JSON.parse(File.read("world-cities.json"))

    Timezone::Lookup.config(:google) do |c|
      c.api_key = ENV['GOOGLE_MAPS_API_KEY']
    end

  end

  def on_startup
    # See https://github.com/jmettraux/rufus-scheduler
    scheduler.every '10s' do |job|
      if rand(10) > 7
        tweet_major_city
      else 
        tweet_minor_city
      end

      # tweet every 8 - 16 hours
      job.next_time = Time.now + rand(480..960) * 60
    end
  end


  def on_message(dm)
    reply_with_sun_data(dm)
  end

  def on_mention(tweet)
    reply_with_sun_data(tweet)
  end

  private

  def tweet_major_city
    puts 'tweeting major city'
    city = @@cities[@@cities.keys.sample]
    city_name = city['city']
    lat = city['lat']
    long = city['lon']
    send_tweet(city_name, lat, long)
  end

  def tweet_minor_city
    puts 'tweeting minor city'
    city = @@all_cities.sample
    city_name = "#{city['name']}, #{city['subcountry']}"
    geoname_id = city['geonameid']   
    coords = get_coordinates(geoname_id)
    lat = coords[0]
    long = coords[1]
    send_tweet(city_name, lat, long)
  end

  def send_tweet(city_name, lat, long)
    next_tweet = generate_tweet(city_name, lat, long)
    next_tweet = URI.unescape(next_tweet)
    puts next_tweet
    tweet(next_tweet)
  end

  def generate_tweet(city_name, lat, long)
    local_time = get_local_time(lat, long)
    next_sun_event = get_next_sun_event(lat, long, local_time)
    next_tweet = format_tweet(city_name, next_sun_event)
    pretty_print(city_name, local_time, next_sun_event, next_tweet)
    next_tweet
  end

  def pretty_print(city_name, local_time, next_sun_event, next_tweet)
    puts
    puts city_name
    puts 'local time: '
    puts local_time
    puts next_sun_event
  end

  def get_next_sun_event(lat, long, local_time)
    next_day = 0
    search_date = local_time 

    loop do 
      date = search_date.strftime("%Y-%m-%d")
      puts 'date: ' + date
      sun_times = get_sun_times(lat, long, date)

      utc_sunrise_time = parse_utc_time(sun_times['sunrise'])
      utc_sunset_time = parse_utc_time(sun_times['sunset'])

      sunrise_time = utc_to_local(lat, long, utc_sunrise_time)
      sunset_time = utc_to_local(lat, long, utc_sunset_time)

      # set dates to same day for simplicity

      sunrise_time = Time.parse(sunrise_time.strftime("%H:%M:%S"))
      sunset_time = Time.parse(sunset_time.strftime("%H:%M:%S"))
      local_time = Time.parse(local_time.strftime("%H:%M:%S"))

      # if past both times, add days to sunrise_time, sunset_time
      if next_day > 0
        sunrise_time = sunrise_time + next_day.day
        sunset_time = sunset_time + next_day.day
      end

      p 'sunrise time: '
      puts sunrise_time
      p 'sunset time: '
      puts sunset_time
      p 'local time: '
      puts local_time

      seconds_to_sunrise = sunrise_time - local_time
      seconds_to_sunset = sunset_time - local_time

      puts 'seconds to sunrise:'
      puts seconds_to_sunrise
      puts 'seconds to sunset:'
      puts seconds_to_sunset

      if seconds_to_sunrise > 0
        return ["sunrise", stringify_seconds(seconds_to_sunrise)]
      elsif seconds_to_sunset > 0
        return ["sunset", stringify_seconds(seconds_to_sunset)]
      else
        search_date = search_date + 1.day # retry using next day's sun events
        next_day += 1
      end
    end
  end


  def get_sun_times(lat, long, date)
    base_uri = "http://api.sunrise-sunset.org/json?"
    request = base_uri + "lat=" + lat.to_s + "&lng=" + long.to_s + "&date=" + date
    results = HTTParty.get(request)['results']
    puts 'get_sun_times results: '
    puts results
    
    results
  end


  def format_tweet(city_name, next_sun_event) 
    cleaned_time = clean_time_string(next_sun_event)
    event_type = next_sun_event[0]
    tweet_string = "#{cleaned_time} until #{event_type} in #{city_name}"
  end


  def clean_time_string(next_sun_event) 
    times_array = next_sun_event[1].split(", ")

    times_array = remove_zero_data(times_array)

    # insert serial 'and' (optional)
    # times_array[-1] = "and " + times_array[-1] if times_array.length > 1

    cleaned_string = times_array.join(', ')

    # remove serial comma (optional)
    # cleaned_string = remove_serial_comma(cleaned_string)

    cleaned_string
  end


  def remove_serial_comma(string)
    comma_count = 0
    string.chars.each do |char|
      comma_count += 1 if char == ","
    end
    if comma_count > 0 
      new_comma_count = 0
      string.chars.each_with_index do |char, index|
        if char == ","
          new_comma_count += 1
          if new_comma_count == comma_count
            string.slice!(index) 
            break
          end
        end
      end
    end
    string
  end


  def remove_zero_data(times_array)
    ii = 0
    while ii < times_array.length 
      if times_array[ii][0] == "0"
        times_array.delete_at(ii)
      else
        ii += 1
      end 
    end
    times_array
  end


  def stringify_seconds(t)
    mm, ss = t.divmod(60)
    hh, mm = mm.divmod(60)
    dd, hh = hh.divmod(24)
    days = ActionView::Base.new.pluralize(dd, 'day')
    hours = ActionView::Base.new.pluralize(hh, 'hour')
    minutes = ActionView::Base.new.pluralize(mm, 'minute')
    # seconds = ActionView::Base.new.pluralize(ss, 'second')
    "#{days}, #{hours}, #{minutes}"
  end


  def reply_with_sun_data(message)
    puts 'hello'
    if message.text.match(",")
      reply_using_region(message)
    else
      puts 'here'
      city_name = get_city_name(message)
      coords = get_coords_from_primary_file(city_name)
      if coords
        # local_time = get_local_time(coords[0], coords[1])
        # reply(message, reply_text(city_name, local_time))
        coords[0] = lat
        coords[1] = long
        response = generate_tweet(city_name, lat, long)
        reply(message, response)
      else
        reply_using_secondary_file(city_name, message)
      end
    end
  end

  def reply_using_region(message)
    data = message.text.split(",").map{|m|m.chomp.strip}
    city_name = data[0]
    area = parse_country_codes(data[1])
    @@all_cities.each do |value|
      if value['country'].casecmp(area) == 0 || value['subcountry'].casecmp(area) == 0
        if value['name'].casecmp(city_name) == 0
          coords = get_coordinates(value['geonameid'])
          # local_time = get_local_time(coords[0], coords[1])
          respond_with_data(coords, city_name, message)
          return 
        end 
      end
    end
  end

  def reply_using_secondary_file(city_name, message)
    geoname_id = get_geoname_id(city_name)    
    if geoname_id
      coords = get_coordinates(geoname_id)
      # local_time = get_local_time(coords[0], coords[1])
      # reply(message, reply_text(city_name, local_time))
      respond_with_data(coords, city_name, message)
    end
  end

  def respond_with_data(coords, city_name, message)
    lat = coords[0]
    long = coords[1]
    response = generate_tweet(city_name, lat, long)
    reply(message, response)
  end

  def get_local_time(lat, long)
    local_timezone = Timezone.lookup(lat, long)
    time = local_timezone.time_with_offset(Time.now.utc)
    time
  end

  def utc_to_local(lat, long, utc_time)
    local_timezone = Timezone.lookup(lat, long)
    time = local_timezone.utc_to_local(utc_time)
    time
  end

  def get_coords_from_primary_file(city_name)
    @@cities.each do |key, value|
      if value['city'].casecmp(city_name) == 0
        lat = value['lat']
        lon = value['lon']
        return [lat, lon]
      end
    end
    false
  end

  def get_coordinates(geoname_id)
    base_uri = "http://api.geonames.org/get?geonameId="
    username = "matthewhinea"
    request = base_uri + geoname_id + "&username=" + username
    response = HTTParty.get(request)

    lat = response['geoname']['lat']
    long = response['geoname']['lng']
    [lat, long]
  end

  def get_city_name(message)
    message.text.gsub("@city_timestamps", "").chomp.strip
  end

  def get_geoname_id(city_name)
    @@all_cities.each do |city|
      if city['name'].casecmp(city_name) == 0
        puts city
        return city['geonameid']
      end
    end
    false
  end

  def parse_country_codes(area)
    case area
    when "US", "USA", "United States of America"
      return "United States"
    when "UAE"
      return "United Arab Emirates"
    when "UK"
      return "United Kingdom"
    else
      return US_STATES[area.to_sym] if US_STATES[area.to_sym]
      return area
    end
  end


  # H E L P E R S 

  def parse_utc_time(time_string)
    time = Time.parse(time_string)
    utc_offset = Time.zone_offset(time.to_s.split(' ')[-1])

    time.utc + utc_offset
  end

end


MyBot.new("city_suntimes") do |bot|
  bot.access_token = ENV['ACCESS_TOKEN']
  bot.access_token_secret = ENV['ACCESS_TOKEN_SECRET']
end
