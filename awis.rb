#/usr/bin/ruby
require "cgi"
require "base64"
require "openssl"
require "uri"
require "net/https"
require "rexml/document"
require "time"
require 'active_support'
require 'active_support/core_ext'
require "json"

SERVICE_HOST = "awis.amazonaws.com"
SERVICE_ENDPOINT = "awis.us-west-1.amazonaws.com"
SERVICE_PORT = 443
SERVICE_URI = "/api"
SERVICE_REGION = "us-west-1"
SERVICE_NAME = "awis"

def getSignatureKey(key, dateStamp, regionName, serviceName)
  kDate    = OpenSSL::HMAC.digest('sha256', "AWS4" + key, dateStamp)
  kRegion  = OpenSSL::HMAC.digest('sha256', kDate, regionName)
  kService = OpenSSL::HMAC.digest('sha256', kRegion, serviceName)
  kSigning = OpenSSL::HMAC.digest('sha256', kService, "aws4_request")
  kSigning
end

# escape str to RFC 3986
def escapeRFC3986(str)
  return URI.escape(str,/[^A-Za-z0-9\-_.~]/)
end

def awis_request(site)
  access_key_id = ENV['AWS_ACCESS_KEY_ID']
  secret_access_key = ENV['AWS_SECRET_ACCESS_KEY']
  action = "TrafficHistory"
  responseGroup = "History"
  timestamp = ( Time::now ).utc.strftime("%Y%m%dT%H%M%SZ")
  datestamp = ( Time::now ).utc.strftime("%Y%m%d")

  headers = { "host" => SERVICE_ENDPOINT, "x-amz-date" => timestamp }
  query = { "Action" => action, "ResponseGroup" => responseGroup, "Url" => site }

  query_str = query.sort.map{|k,v| k + "=" + escapeRFC3986(v.to_s())}.join('&')
  headers_str = headers.sort.map{|k,v| k + ":" + v}.join("\n") + "\n"
  headers_lst = headers.sort.map{|k,v| k}.join(";")
  payload_hash = Digest::SHA256.hexdigest ""
  canonical_request = "GET" + "\n" + SERVICE_URI + "\n" + query_str + "\n" + headers_str + "\n" + headers_lst + "\n" + payload_hash
  algorithm = "AWS4-HMAC-SHA256"
  credential_scope = datestamp + "/" + SERVICE_REGION + "/" + SERVICE_NAME + "/" + "aws4_request"
  string_to_sign = algorithm + "\n" +  timestamp + "\n" +  credential_scope + "\n" + (Digest::SHA256.hexdigest canonical_request)
  signing_key = getSignatureKey(secret_access_key, datestamp, SERVICE_REGION, SERVICE_NAME)
  signature=OpenSSL::HMAC.hexdigest('sha256', signing_key, string_to_sign)
  authorization_header = algorithm + " " + "Credential=" + access_key_id + "/" + credential_scope + ", " +  "SignedHeaders=" + headers_lst + ", " + "Signature=" + signature;

  url = "https://" + SERVICE_HOST + SERVICE_URI + "?" + query_str
  uri = URI(url)
  puts "=== > Making request to Alexa for: #{site}"
  req = Net::HTTP::Get.new(uri)
  req["Accept"] = "application/xml"
  req["Content-Type"] = "application/xml"
  req["x-amz-date"] = timestamp
  req["Authorization"] = authorization_header

  res = Net::HTTP.start(uri.host, uri.port,
    :use_ssl => uri.scheme == 'https') {|http|
    http.request(req)
  }

  return Hash.from_xml(res.body)
  #xml  = REXML::Document.new( res.body )

  #print "Response:\n\n"
  #print "Links in count: "
  #REXML::XPath.each(xml,"//aws:LinksInCount"){|el| puts el.text}
  #print "Rank: "
  #REXML::XPath.each(xml,"//aws:Rank"){|el| puts el.text}
end
