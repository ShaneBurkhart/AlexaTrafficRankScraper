require 'cgi'
require 'open-uri'
require 'nokogiri'
require 'net/http'
require 'uri'
require 'csv'

require './awis.rb'

# Otherwise we can't see logs in docker.
STDOUT.sync = true

KEYWORDS = [
  "",
]

SEARCH_FORMATS = [
  "%s blog",
  "%s store",
]

# Google constant
RESULTS_PER_PAGE = 10

NUM_RESULTS_TO_SCRAPE = 100
PAGES_TO_SCRAPE = (NUM_RESULTS_TO_SCRAPE / RESULTS_PER_PAGE).ceil

def google_keyword_query(keyword, page_num)
  start = (page_num.to_i - 1) * RESULTS_PER_PAGE
  "http://google.com/search?q=#{URI.encode(keyword)}"
end

MONTHLY_ALEXA_COEFFICIENT = 104943144672
MONTHLY_ALEXA_POWER = -1.008

def alexa_rank_to_est_traffic(rank)
  MONTHLY_ALEXA_COEFFICIENT * (rank.to_i ** MONTHLY_ALEXA_POWER)
end

SCRAPED_HOSTS_FILE = "scraped_hosts.txt"

scraped_hosts_raw = File.read(SCRAPED_HOSTS_FILE) || ""
SCRAPED_HOSTS = scraped_hosts_raw.split("\n") || []

def has_been_scraped?(host)
  host = host.downcase
  start_idx = 0
  end_idx = SCRAPED_HOSTS.length - 1

  return false if SCRAPED_HOSTS.length == 0
  return true if SCRAPED_HOSTS.length == 1 and SCRAPED_HOSTS[0] == host

  while start_idx <= end_idx
    mid_idx = start_idx + (end_idx - start_idx) / 2
    mid_val = SCRAPED_HOSTS[mid_idx]

    return true if host == mid_val
    return false if start_idx == end_idx

    if mid_val > host
      end_idx = mid_idx
    elsif mid_val < host
      start_idx = mid_idx + 1
    end
  end

  return false
end

def add_scraped_host(host)
  host = host.downcase
  start_idx = 0
  end_idx = SCRAPED_HOSTS.length - 1

  if SCRAPED_HOSTS.length == 0
    SCRAPED_HOSTS << host
    return
  end

  if SCRAPED_HOSTS.length == 1
    return if SCRAPED_HOSTS.first == host
    SCRAPED_HOSTS.insert(SCRAPED_HOSTS.first < host ? 1 : 0, host)
    return
  end

  while start_idx <= end_idx
    mid_idx = start_idx + (end_idx - start_idx) / 2
    mid_val = SCRAPED_HOSTS[mid_idx]

    # The host already exists in the list.
    return if host == mid_val
    break if start_idx == end_idx

    if mid_val > host
      end_idx = mid_idx
    elsif mid_val < host
      start_idx = mid_idx + 1
    end
  end

  if SCRAPED_HOSTS[start_idx] > host
    SCRAPED_HOSTS.insert(start_idx, host)
  else
    SCRAPED_HOSTS.insert(start_idx + 1, host)
  end
end

CSV.open("output.csv", "a+") do |csv|
  KEYWORDS.each do |keyword|
    SEARCH_FORMATS.each do |format|
      (1..PAGES_TO_SCRAPE).each do |page_num|
        search_keywords = format % keyword
        puts "Page #{page_num} of #{PAGES_TO_SCRAPE}. Keyword: '#{search_keywords}'"

        doc = Nokogiri::HTML(open(google_keyword_query(search_keywords, page_num)))

        doc.css('h3.r a').each do |google_link|
          title = google_link.content
          google_href = google_link['href']
          href = CGI.parse(URI.parse(google_href).query)['q'].first
          next unless href.include?("http")

          host = URI.parse(href).host

          if has_been_scraped?(host)
            puts "Already scraped #{host}"
            next
          end

          data = awis_request(host)
          begin
            resp = data["TrafficHistoryResponse"]["Response"]
            traffic_res = resp["TrafficHistoryResult"]
            alexa_resp = traffic_res["Alexa"]
            first_day = alexa_resp["TrafficHistory"]["HistoricalData"]["Data"].last
            rank = first_day["Rank"]
          rescue NoMethodError
            puts "Some key wasn't in the response."
            # I'm not checkin' that shit
            next
          end

          est_traffic = alexa_rank_to_est_traffic(rank)
          csv << [host, rank, est_traffic.floor]

          add_scraped_host(host)
        end
      end
    end
  end
end

File.open(SCRAPED_HOSTS_FILE, 'w') { |file| file.write(SCRAPED_HOSTS.join("\n")) }
