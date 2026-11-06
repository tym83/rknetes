#!/usr/bin/env python3
import socket,threading,http.server
class Server(http.server.BaseHTTPRequestHandler):
 def do_GET(self):
  self.send_response(200);self.end_headers();self.wfile.write(b'RKARCHIVE: real lab application payload\n')
 def log_message(self,*args):pass
def udp():
 s=socket.socket(socket.AF_INET,socket.SOCK_DGRAM);s.bind(('0.0.0.0',8081))
 while True:s.recvfrom(65535)
threading.Thread(target=udp,daemon=True).start()
http.server.HTTPServer(('0.0.0.0',8080),Server).serve_forever()
