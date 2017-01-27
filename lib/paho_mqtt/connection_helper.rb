module PahoMqtt
  class ConnectionHelper

    attr_accessor :sender

    def initialize(sender)
      @cs = MQTT_CS_DISCONNECT
      @socket = nil
      @host = ""
      @port = nil
      @sender = sender
    end

    def do_connect(reconnection=false, handler, ack_timeout)
      handler.socket = @socket
      # Waiting a Connack packet for "ack_timeout" second from the remote
      connect_timeout = Time.now + ack_timeout
      while (Time.now <= connect_timeout) && (!is_connected?) do
        @cs = handler.receive_packet
        sleep 0.0001
      end
      unless is_connected?
        @logger.warn("Connection failed. Couldn't recieve a Connack packet from: #{@host}, socket is \"#{@socket}\".") if PahoMqtt.logger?
        raise Exception.new("Connection failed. Check log for more details.") unless reconnection
      end
      @cs
    end

    def is_connected?
      @cs == MQTT_CS_CONNECTED
    end

    def do_disconnect(publisher, explicit, mqtt_thread)
      @logger.debug("Disconnecting from #{@host}") if PahoMqtt.logger?
      if explicit
        @sender.flush_waiting_packet
        send_disconnect
        mqtt_thread.kill if mqtt_thread && mqtt_thread.alive?
        publisher.flush_publisher unless publisher.nil?
      end
      @socket.close unless @socket.nil? || @socket.closed?
      @socket = nil
    end

    def setup_connection(host, port, ssl, ssl_context=nil, ack_timeout)
      clean_start(host, port)
      config_socket(ssl, ssl_context)
      unless @socket.nil?
        @sender = Sender.new(ack_timeout) if @sender.nil?
        @sender.socket = @socket
      end
    end

    def config_socket(ssl, ssl_context)
      @logger.debug("Atempt to connect to host: #{@host}") if PahoMqtt.logger?
      begin
        tcp_socket = TCPSocket.new(@host, @port)
      rescue ::Exception => exp
        @logger.warn("Could not open a socket with #{@host} on port #{@port}") if PahoMqtt.logger?
      end
      if ssl
        unless ssl_context.nil?
          @socket = OpenSSL::SSL::SSLSocket.new(tcp_socket, ssl_context)
          @socket.sync_close = true
          @socket.connect
        else
          @logger.error("The ssl context was found as nil while the socket's opening.") if PahoMqtt.logger?
          raise Exception
        end
      else
        @socket = tcp_socket
      end
    end

    def clean_start(host, port)
      if host.nil? || host == ""
        @logger.error("The host was found as nil while the connection setup.") if PahoMqtt.logger?
        raise ArgumentError
      else
        @host = host
      end
      if port.to_i <= 0
        @logger.error("The port value is invalid (<= 0). Could not setup the connection.") if PahoMqtt.logger?
        raise ArgumentError
      else
        @port = port
      end
      unless @socket.nil?
        @socket.close unless @socket.closed?
        @socket = nil
      end
    end
    
    def send_connect(mqtt_version, clean_session, keep_alive, client_id, username, password, will_topic, will_payload,will_qos, will_retain)
      packet = PahoMqtt::Packet::Connect.new(
        :version => mqtt_version,
        :clean_session => clean_session,
        :keep_alive => keep_alive,
        :client_id => client_id,
        :username => username,
        :password => password,
        :will_topic => will_topic,
        :will_payload => will_payload,
        :will_qos => will_qos,
        :will_retain => will_retain
      )
      @sender.send_packet(packet)
      MQTT_ERR_SUCCESS
    end

    def send_disconnect
      packet = PahoMqtt::Packet::Disconnect.new
      @sender.send_packet(packet)
      MQTT_ERR_SUCCESS
    end

    def send_pingreq
      packet = PahoMqtt::Packet::Pingreq.new
      @sender.send_packet(packet)
      MQTT_ERR_SUCCESS
    end
 
    def check_keep_alive(persistent, last_ping_resp, keep_alive)
      now = Time.now
      timeout_req = (@sender.last_ping_req + (keep_alive * 0.7).ceil)
 
      if timeout_req <= now && persistent
        @logger.debug("Checking if server is still alive.") if PahoMqtt.logger?
        send_pingreq
      end
      
      timeout_resp = last_ping_resp + (keep_alive * 1.1).ceil
      if timeout_resp <= now
        @logger.debug("No activity period over timeout, disconnecting from #{@host}") if PahoMqtt.logger?
        @cs = MQTT_CS_DISCONNECT
      end
      @cs
    end
  end
end