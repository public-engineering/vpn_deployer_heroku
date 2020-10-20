require 'rubygems'
require 'bundler/setup'
require 'sinatra'
require 'omniauth-digitalocean'
require 'httparty'
require 'json'
require 'thin'
require 'rack/ssl'
require 'net/https'

class DigitalOceanExample < Sinatra::Base
  use Rack::Session::Cookie
  set :environment, :production
  # ENV['RACK_ENV'] = "development"
  # set :port, 8080

  def notify(user, token, message)
    url = URI.parse("https://api.pushover.net/1/messages.json")
    req = Net::HTTP::Post.new(url.path)
    req.set_form_data({
      :token => "#{token}",
      :user => "#{user}",
      :message => "#{message}",
    })
    res = Net::HTTP.new(url.host, url.port)
    res.use_ssl = true
    res.verify_mode = OpenSSL::SSL::VERIFY_PEER
    res.start {|http| http.request(req) }
  end

  get '/' do
    erb :index
  end

  get '/auth/login' do
    redirect '/auth/digitalocean'
  end

  get '/auth/:provider/callback' do
    hostname = "vpn-" + (0...8).map { (65 + rand(26)).chr }.join
    user_data = HTTParty.get("https://raw.githubusercontent.com/jmarhee/dockvpn/master/provision.sh").body.to_s

    token = request.env['omniauth.auth'].to_hash['credentials']['token'].to_s
    email = request.env['omniauth.auth'].to_hash['info']['email'].to_s

    regions = ["sfo2","nyc3","ams3","sgp1"]
    region = regions.sample

    response = HTTParty.post("https://api.digitalocean.com/v2/droplets", :headers => { 'Content-Type' => 'application/json', 'Authorization' => "Bearer #{token}" }, :body => {
        :name => "#{hostname.downcase}.vpn.public.engineering",
        :region => "#{region}",
        :size => '1gb',
        :image => 'ubuntu-16-04-x64',
        :ssh_keys => [],
        :backups => false,
        :ipv6 => true,
        :user_data => "#{user_data}",
        :private_networking => "null",
        :tags => ['openvpn-public-engineering']
      }.to_json)

    puts response.body    
    
    did = response.body
    droplet_id = JSON.parse(did)['droplet']['id']
    
    sleep 5
    
    ip_response = HTTParty.get("https://api.digitalocean.com/v2/droplets/#{droplet_id}", :headers => { 'Content-Type' => 'application/json', 'Authorization' => "Bearer #{token}" } )
    ip_address = JSON.parse(ip_response.body)['droplet']['networks']['v4'][0]['ip_address'].to_s

    puts ip_address

    message = "#{email} deployed Droplet (#{droplet_id}: #{ip_address}) created in *#{region}*. "
    puts message
    notify(ENV['PUSHOVER_USER'], ENV['PUSHOVER_TOKEN'], message)

    erb :confirmation, :locals => {:droplet_id => droplet_id, :ip_address => ip_address }
  end

  get '/auth/failure' do
    content_type 'text/plain'
    request.env['omniauth.auth'].to_hash.inspect rescue "No Data"
  end

  use OmniAuth::Builder do
    provider OmniAuth::Strategies::Digitalocean, ENV['client_id'], ENV['client_secret'], scope: "read write"
  end
end

run DigitalOceanExample.run!
