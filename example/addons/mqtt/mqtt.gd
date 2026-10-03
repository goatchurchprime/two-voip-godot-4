extends Node

# MQTT client implementation in GDScript
# Loosely based on https://github.com/pycom/pycom-libraries/blob/master/lib/mqtt/mqtt.py
# and initial work by Alex J Lennon <ajlennon@dynamicdevices.co.uk>
# but then heavily rewritten to follow https://docs.oasis-open.org/mqtt/mqtt/v3.1.1/mqtt-v3.1.1.html

# mosquitto_sub -h test.mosquitto.org -v -t "metest/#"
# mosquitto_pub -h test.mosquitto.org -t "metest/retain" -m "retained message" -r

@export var client_id = ""
@export var verbose_level = 2  # 0 quiet, 1 connections and subscriptions, 2 all messages
@export var binarymessages = false
@export var pinginterval = 30

var socket = null
var sslsocket = null
var websocket = null

const BCM_NOCONNECTION = 0
const BCM_WAITING_WEBSOCKET_CONNECTION = 1
const BCM_WAITING_SOCKET_CONNECTION = 2
const BCM_WAITING_SSL_SOCKET_CONNECTION = 3
const BCM_FAILED_CONNECTION = 5
const BCM_WAITING_CONNMESSAGE = 10
const BCM_WAITING_CONNACK = 19
const BCM_CONNECTED = 20

var brokerconnectmode = BCM_NOCONNECTION

var regexbrokerurl = RegEx.new()

const DEFAULTBROKERPORT_TCP = 1883
const DEFAULTBROKERPORT_SSL = 8886
const DEFAULTBROKERPORT_WS = 8080
const DEFAULTBROKERPORT_WSS = 8081

const CP_PINGREQ = 0xc0
const CP_PINGRESP = 0xd0
const CP_CONNACK = 0x20
const CP_CONNECT = 0x10
const CP_PUBLISH = 0x30
const CP_SUBSCRIBE = 0x82
const CP_UNSUBSCRIBE = 0xa2
const CP_PUBACK = 0x40
const CP_PUBREC = 0x50
const CP_SUBACK = 0x90
const CP_UNSUBACK = 0xb0

const MAX_PACKET_SIZE = 2097151
const MAX_PACKETS_PER_FRAME = 64

var pid = 0
var user = null
var pswd = null
var keepalive = 120
var lw_topic = null
var lw_msg = null
var lw_qos = 0
var lw_retain = false

signal received_message(topic, message)
signal broker_connected()
signal broker_disconnected()
signal broker_connection_failed()
signal publish_acknowledge(pid)

var receivedbuffer : PackedByteArray = PackedByteArray()

var common_name = null

func senddata(data):
	var E = 0
	if sslsocket != null:
		E = sslsocket.put_data(data)
	elif socket != null:
		E = socket.put_data(data)
	elif websocket != null:
		E = websocket.put_packet(data)
	if E != 0:
		print("bad senddata packet E=", E)
	
func receiveintobuffer():
	if sslsocket != null:
		var sslsocketstatus = sslsocket.get_status()
		if sslsocketstatus == StreamPeerTLS.STATUS_CONNECTED or sslsocketstatus == StreamPeerTLS.STATUS_HANDSHAKING:
			var E = sslsocket.poll()
			if E != 0:
				printerr("Socket poll error: ", E)
				return E
			var n = sslsocket.get_available_bytes()
			if n == -1:
				printerr("get_available_bytes returned -1")
				return FAILED
			if n != 0:
				var sv = sslsocket.get_data(n)
				if sv[0] != OK:
					printerr("TLS socket read error: ", sv[0])
					return sv[0]
				receivedbuffer.append_array(sv[1])
		else:
			return ERR_CONNECTION_ERROR
				
	elif socket != null:
		var E = socket.poll()
		if E != 0:
			printerr("Socket poll error: ", E)
			return E
		if socket.get_status() != StreamPeerTCP.STATUS_CONNECTED:
			return ERR_CONNECTION_ERROR
		var n = socket.get_available_bytes()
		if n == -1:
			printerr("get_available_bytes returned -1")
			return FAILED
		if n != 0:
			var sv = socket.get_data(n)
			if sv[0] != OK:
				printerr("TCP socket read error: ", sv[0])
				return sv[0]
			receivedbuffer.append_array(sv[1])
			
	elif websocket != null:
		websocket.poll()
		if websocket.get_ready_state() != WebSocketPeer.STATE_OPEN:
			return ERR_CONNECTION_ERROR
		while websocket.get_available_packet_count() != 0:
			receivedbuffer.append_array(websocket.get_packet())
	
var pingticksnext0 = 0

func _process(delta):
	if brokerconnectmode == BCM_NOCONNECTION:
		pass
	elif brokerconnectmode == BCM_WAITING_WEBSOCKET_CONNECTION:
		websocket.poll()
		var websocketstate = websocket.get_ready_state()
		if websocketstate == WebSocketPeer.STATE_CLOSED:
			if verbose_level:
				print("WebSocket closed with code: %d, reason %s." % [websocket.get_close_code(), websocket.get_close_reason()])
			brokerconnectmode = BCM_FAILED_CONNECTION
			emit_signal("broker_connection_failed")
		elif websocketstate == WebSocketPeer.STATE_OPEN:
			brokerconnectmode = BCM_WAITING_CONNMESSAGE
			if verbose_level:
				print("Websocket connection now open")
			
	elif brokerconnectmode == BCM_WAITING_SOCKET_CONNECTION:
		socket.poll()
		var socketstatus = socket.get_status()
		if socketstatus == StreamPeerTCP.STATUS_ERROR:
			if verbose_level:
				print("TCP socket error")
			brokerconnectmode = BCM_FAILED_CONNECTION
			emit_signal("broker_connection_failed")
		if socketstatus == StreamPeerTCP.STATUS_CONNECTED:
			brokerconnectmode = BCM_WAITING_CONNMESSAGE

	elif brokerconnectmode == BCM_WAITING_SSL_SOCKET_CONNECTION:
		socket.poll()
		var socketstatus = socket.get_status()
		if socketstatus == StreamPeerTCP.STATUS_ERROR:
			if verbose_level:
				print("TCP socket error before SSL")
			brokerconnectmode = BCM_FAILED_CONNECTION
			emit_signal("broker_connection_failed")
		if socketstatus == StreamPeerTCP.STATUS_CONNECTED:
			if sslsocket == null:
				sslsocket = StreamPeerTLS.new()
				if verbose_level:
					print("Connecting socket to SSL with common_name=", common_name)
				var E3 = sslsocket.connect_to_stream(socket, common_name)
				if E3 != 0:
					print("bad sslsocket.connect_to_stream E=", E3)
					brokerconnectmode = BCM_FAILED_CONNECTION
					emit_signal("broker_connection_failed")
					sslsocket = null
			if sslsocket != null:
				sslsocket.poll()
				var sslsocketstatus = sslsocket.get_status()
				if sslsocketstatus == StreamPeerTLS.STATUS_CONNECTED:
					brokerconnectmode = BCM_WAITING_CONNMESSAGE
				elif sslsocketstatus >= StreamPeerTLS.STATUS_ERROR:
					print("bad sslsocket.connect_to_stream")
					brokerconnectmode = BCM_FAILED_CONNECTION
					emit_signal("broker_connection_failed")
				
	elif brokerconnectmode == BCM_WAITING_CONNMESSAGE:
		senddata(firstmessagetoserver())
		brokerconnectmode = BCM_WAITING_CONNACK
		
	elif brokerconnectmode == BCM_WAITING_CONNACK or brokerconnectmode == BCM_CONNECTED:
		var receive_error = receiveintobuffer()
		if receive_error != null and receive_error != OK:
			_fail_connection("Socket receive failed: %s" % receive_error)
			return
		var packets_processed := 0
		while packets_processed < MAX_PACKETS_PER_FRAME and wait_msg():
			packets_processed += 1
		if brokerconnectmode == BCM_CONNECTED and pingticksnext0 < Time.get_ticks_msec():
			pingreq()
			pingticksnext0 = Time.get_ticks_msec() + pinginterval*1000

	elif brokerconnectmode == BCM_FAILED_CONNECTION:
		cleanupsockets()

func _ready():
	regexbrokerurl.compile('^(tcp://|wss://|ws://|ssl://)?([^:\\s]+)(:\\d+)?(/\\S*)?$')
	if client_id == "":
		randomize()
		client_id = "rr%d" % randi()

func set_last_will(stopic, smsg, retain=false, qos=0):
	if qos < 0 or qos > 1:
		push_error("MQTT QoS %d is not supported; use QoS 0 or 1" % qos)
		return false
	if not stopic:
		push_error("MQTT last-will topic must not be empty")
		return false
	self.lw_topic = stopic.to_ascii_buffer()
	self.lw_msg = smsg if binarymessages else smsg.to_ascii_buffer()
	self.lw_qos = qos
	self.lw_retain = retain
	if verbose_level:
		print("LASTWILL%s topic=%s msg=%s" % [ " <retain>" if retain else "", stopic, smsg])
	return true

func set_user_pass(suser, spswd):
	if suser != null:
		self.user = suser.to_ascii_buffer()
		self.pswd = spswd.to_ascii_buffer()
	else:
		self.user = null
		self.pswd = null


static func encoderemaininglength(pkt, sz):
	assert(sz <= MAX_PACKET_SIZE)
	var i = 1
	while sz > 0x7f:
		pkt[i] = (sz & 0x7f) | 0x80
		sz >>= 7
		i += 1
		if i + 1 > len(pkt):
			pkt.append(0x00);
	pkt[i] = sz

static func encodeshortint(pkt, n):
	assert (n >= 0 and n < 65536)
	pkt.append((n >> 8) & 0xFF)
	pkt.append(n & 0xFF)

static func encodevarstr(pkt, bs):
	encodeshortint(pkt, len(bs))
	pkt.append_array(bs)

func firstmessagetoserver():
	var clean_session = true
	var pkt = PackedByteArray()
	pkt.append(CP_CONNECT);
	pkt.append(0x00);
	var sz = 10 + (2+len(self.client_id)) + \
			(2+len(self.user)+2+len(self.pswd) if self.user != null else 0) + \
			(2+len(self.lw_topic)+2+len(self.lw_msg) if self.lw_topic else 0)
	encoderemaininglength(pkt, sz)
	var remstartpos = len(pkt)
	encodevarstr(pkt, [0x4D, 0x51, 0x54, 0x54]); # "MQTT".to_ascii_buffer()
	var protocollevel = 0x04  # MQTT v3.1.1
	var connectflags = (0xC0 if self.user != null else 0) | \
					   (0x20 if self.lw_retain else 0) | \
					   (self.lw_qos << 3) | \
					   (0x04 if self.lw_topic else 0) | \
					   (0x02 if clean_session else 0)
	pkt.append(protocollevel);
	pkt.append(connectflags);
	encodeshortint(pkt, self.keepalive)
	encodevarstr(pkt, self.client_id.to_ascii_buffer())
	if self.lw_topic:
		encodevarstr(pkt, self.lw_topic)
		encodevarstr(pkt, self.lw_msg)
	if self.user != null:
		encodevarstr(pkt, self.user)
		encodevarstr(pkt, self.pswd)
	assert (len(pkt) - remstartpos == sz)
	return pkt

func cleanupsockets(retval=false):
	if verbose_level:
		print("cleanupsockets")
	if socket:
		if sslsocket:
			sslsocket = null
		socket.disconnect_from_host()
		socket = null
	else:
		assert (sslsocket == null)

	if websocket:
		websocket.close()
		websocket = null
	brokerconnectmode = BCM_NOCONNECTION
	return retval

func connect_to_broker(brokerurl):
	assert (brokerconnectmode == BCM_NOCONNECTION)
	var brokermatch = regexbrokerurl.search(brokerurl)
	if brokermatch == null:
		print("ERROR: unrecognized brokerurl pattern:", brokerurl)
		return cleanupsockets(false)
	var brokercomponents = brokermatch.strings
	var brokerprotocol = brokercomponents[1]
	var brokerserver = brokercomponents[2]
	var iswebsocket = (brokerprotocol == "ws://" or brokerprotocol == "wss://")
	var isssl = (brokerprotocol == "ssl://" or brokerprotocol == "wss://")
	var brokerport = ((DEFAULTBROKERPORT_WSS if isssl else DEFAULTBROKERPORT_WS) if iswebsocket else (DEFAULTBROKERPORT_SSL if isssl else DEFAULTBROKERPORT_TCP))
	if brokercomponents[3]:
		brokerport = int(brokercomponents[3].substr(1)) 
	var brokerpath = brokercomponents[4] if brokercomponents[4] else ""
	
	common_name = null	
	if iswebsocket:
		websocket = WebSocketPeer.new()
		websocket.supported_protocols = PackedStringArray(["mqttv3.1"])
		var websocketurl = ("wss://" if isssl else "ws://") + brokerserver + ":" + str(brokerport) + brokerpath
		if verbose_level:
			print("Connecting to websocketurl: ", websocketurl)
		var E = websocket.connect_to_url(websocketurl)
		if E != 0:
			print("ERROR: websocketclient.connect_to_url Err: ", E)
			return cleanupsockets(false)
		print("Websocket get_requested_url ", websocket.get_requested_url())
		brokerconnectmode = BCM_WAITING_WEBSOCKET_CONNECTION

	else:
		socket = StreamPeerTCP.new()
		if verbose_level:
			print("Connecting to %s:%s" % [brokerserver, brokerport])
		var E = socket.connect_to_host(brokerserver, brokerport)
		if E != 0:
			print("ERROR: socketclient.connect_to_url Err: ", E)
			return cleanupsockets(false)
		if isssl:
			brokerconnectmode = BCM_WAITING_SSL_SOCKET_CONNECTION
			common_name = brokerserver
		else:
			brokerconnectmode = BCM_WAITING_SOCKET_CONNECTION
		
	return true


func disconnect_from_server():
	if brokerconnectmode == BCM_CONNECTED:
		senddata(PackedByteArray([0xE0, 0x00]))
		emit_signal("broker_disconnected")
	cleanupsockets()
	

func publish(stopic, smsg, retain=false, qos=0):
	if qos < 0 or qos > 1:
		push_error("MQTT QoS %d is not supported; use QoS 0 or 1" % qos)
		return 0
	var msg = smsg.to_ascii_buffer() if not binarymessages else smsg
	var topic = stopic.to_ascii_buffer()
	
	var pkt = PackedByteArray()
	pkt.append(CP_PUBLISH | (2 if qos else 0) | (1 if retain else 0));
	pkt.append(0x00);
	var sz = 2 + len(topic) + len(msg) + (2 if qos > 0 else 0)
	encoderemaininglength(pkt, sz)
	var remstartpos = len(pkt)
	encodevarstr(pkt, topic)
	if qos > 0:
		pid = _next_pid()
		encodeshortint(pkt, pid)
	pkt.append_array(msg)
	assert (len(pkt) - remstartpos == sz)
	senddata(pkt)
	if verbose_level >= 2:
		print("CP_PUBLISH%s%s topic=%s msg=%s" % [ "[%d]"%pid if qos else "", " <retain>" if retain else "", stopic, smsg])
	return pid

func subscribe(stopic, qos=0):
	if qos < 0 or qos > 1:
		push_error("MQTT QoS %d is not supported; use QoS 0 or 1" % qos)
		return 0
	pid = _next_pid()
	var topic = stopic.to_ascii_buffer()
	var sz = 2 + 2 + len(topic) + 1
	var pkt = PackedByteArray()
	pkt.append(CP_SUBSCRIBE);
	pkt.append(0x00);
	encoderemaininglength(pkt, sz)
	var remstartpos = len(pkt)
	encodeshortint(pkt, pid)
	encodevarstr(pkt, topic)
	pkt.append(qos);
	assert (len(pkt) - remstartpos == sz)
	if verbose_level:
		print("SUBSCRIBE[%d] topic=%s" % [pid, stopic])
	senddata(pkt)
	return pid

func pingreq():
	if verbose_level >= 2:
		print("PINGREQ")
	senddata(PackedByteArray([CP_PINGREQ, 0x00]))

func unsubscribe(stopic):
	pid = _next_pid()
	var topic = stopic.to_ascii_buffer()
	var sz = 2 + 2 + len(topic)
	var pkt = PackedByteArray()
	pkt.append(CP_UNSUBSCRIBE);
	pkt.append(0x00)
	encoderemaininglength(pkt, sz)
	var remstartpos = len(pkt)
	encodeshortint(pkt, pid)
	encodevarstr(pkt, topic)
	if verbose_level:
		print("UNSUBSCRIBE[%d] topic=%s" % [pid, stopic])
	assert (len(pkt) - remstartpos == sz)
	senddata(pkt)
	return pid


func _next_pid():
	return (pid % 65535) + 1

func wait_msg():
	var n = receivedbuffer.size()
	if n < 2:
		return false
	var op = receivedbuffer[0]
	var i = 1
	var sz = 0
	var multiplier = 1
	var remaining_length_bytes = 0
	while true:
		if i == n:
			return false
		var encoded_byte = receivedbuffer[i]
		i += 1
		remaining_length_bytes += 1
		sz += (encoded_byte & 0x7f) * multiplier
		if (encoded_byte & 0x80) == 0:
			break
		if remaining_length_bytes == 4:
			return _protocol_error("remaining length exceeds four bytes")
		multiplier *= 128
	if sz > MAX_PACKET_SIZE:
		return _protocol_error("packet exceeds the %d byte limit" % MAX_PACKET_SIZE)
	if n < i + sz:
		return false

	if op == CP_PINGRESP:
		if sz != 0:
			return _protocol_error("PINGRESP must have an empty payload")
		if verbose_level >= 2:
			print("PINGRESP")

	elif op & 0xf0 == CP_PUBLISH:
		if sz < 2:
			return _protocol_error("PUBLISH is missing its topic length")
		var qos = (op >> 1) & 0x03
		if qos == 2:
			return _protocol_error("incoming QoS 2 PUBLISH is not supported")
		if qos == 3:
			return _protocol_error("PUBLISH contains invalid QoS flags")
		var topic_len = (receivedbuffer[i] << 8) + receivedbuffer[i+1]
		var im = i + 2
		if topic_len == 0 or im + topic_len > i + sz:
			return _protocol_error("PUBLISH contains an invalid topic length")
		var topic = receivedbuffer.slice(im, im + topic_len).get_string_from_ascii()
		im += topic_len
		var pid1 = 0
		if qos == 1:
			if im + 2 > i + sz:
				return _protocol_error("PUBLISH is missing its packet identifier")
			pid1 = (receivedbuffer[im] << 8) + receivedbuffer[im+1]
			if pid1 == 0:
				return _protocol_error("PUBLISH packet identifier must not be zero")
			im += 2
		var data = receivedbuffer.slice(im, i + sz)
		var msg = data if binarymessages else data.get_string_from_ascii()

		if verbose_level >= 2:
			print("received topic=", topic, " msg=", msg)
		emit_signal("received_message", topic, msg)

		if qos == 1:
			senddata(PackedByteArray([CP_PUBACK, 0x02, (pid1 >> 8), (pid1 & 0xFF)]))

	elif op == CP_CONNACK:
		if sz != 2:
			return _protocol_error("CONNACK payload must be two bytes")
		var retcode = receivedbuffer[i+1]
		if verbose_level:
			print("CONNACK ret=%02x" % retcode)
		if retcode == 0x00:
			brokerconnectmode = BCM_CONNECTED
			emit_signal("broker_connected")
		else:
			if verbose_level:
				print("Bad connection retcode=", retcode)
			brokerconnectmode = BCM_FAILED_CONNECTION
			emit_signal("broker_connection_failed")

	elif op == CP_PUBACK:
		if sz != 2:
			return _protocol_error("PUBACK payload must be two bytes")
		var apid = (receivedbuffer[i] << 8) + receivedbuffer[i+1]
		if verbose_level >= 2:
			print("PUBACK[%d]" % apid)
		emit_signal("publish_acknowledge", apid)

	elif op == CP_SUBACK:
		if sz != 3:
			return _protocol_error("SUBACK payload must be three bytes")
		var apid = (receivedbuffer[i] << 8) + receivedbuffer[i+1]
		if verbose_level:
			print("SUBACK[%d] ret=%02x" % [apid, receivedbuffer[i+2]])

	elif op == CP_UNSUBACK:
		if sz != 2:
			return _protocol_error("UNSUBACK payload must be two bytes")
		var apid = (receivedbuffer[i] << 8) + receivedbuffer[i+1]
		if verbose_level:
			print("UNSUBACK[%d]" % apid)

	else:
		if verbose_level:
			print("Unknown MQTT opcode op=%x" % op)

	trimreceivedbuffer(i + sz)
	return true


func _protocol_error(message: String):
	push_error("Malformed MQTT packet: " + message)
	receivedbuffer.clear()
	if brokerconnectmode != BCM_NOCONNECTION:
		cleanupsockets()
		emit_signal("broker_disconnected")
	return false


func _fail_connection(message: String):
	printerr(message)
	brokerconnectmode = BCM_FAILED_CONNECTION
	emit_signal("broker_connection_failed")

func trimreceivedbuffer(n):
	if n == receivedbuffer.size():
		receivedbuffer = PackedByteArray()
	else:
		assert (n <= receivedbuffer.size())
		receivedbuffer = receivedbuffer.slice(n)
