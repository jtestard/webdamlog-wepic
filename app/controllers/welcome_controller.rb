require 'lib/wl_launcher'

class WelcomeController < ApplicationController
  include WLLauncher
  
  def index
    @account = Account.new
  end
  
  def existing
    username = params[:username]
    @account = Account.find(:first,:conditions => {:username=>username})
    #If the account cannot be found
    if @account.nil?
      respond_to do |format|
        format.html {redirect_to :welcome, :alert => 'No account exists with this username.'}
      end
      return
    end
    #If the server for account is down.
    url = "http://#{@account.ip}:#{@account.port}"
    if port_open?(@account.ip,@account.port)
      start_server(@account.port)
      respond_to do |format|
        format.html {redirect_to url, :notice => "Server was rebooted"}
      end
      #If the server for account is up.
    else
      respond_to do |format|
        format.html {redirect_to url}
      end
    end    
  end
  
  def new
    username = params[:username]
    #Temporary, need a better specification of URL.
    ip = "localhost"
    default_port_number = 9999
    #Here is specification of port
    max = Account.maximum(:id)
    max = 0 if max.nil?
    port = default_port_number + max + 1
    #This will override the port
    exit_server(port) if !port_open?(ip,port)
    puts "starting server..."
    start_server(port)
    #This code does not check if call to rails failed. This operations requires interprocess communication.
    @account = Account.new(:username => username, :ip=> ip, :port => port)
    if @account.save
      respond_to do |format|
        sleep(5) #very ugly of making the user wait for the external server to be ready. We probably can do better.
        format.html {redirect_to "http://#{ip}:#{port}"}
      end
    else
      respond_to do |format|
        format.html {redirect_to :welcome, :alert => "New WLInstance was not set properly"}
      end
    end
  end
end