import os
import sys
import http.server
import socketserver
import webbrowser
import threading

PORT = 8000

def get_free_port():
    # Attempt to use 8000, if occupied find any free port
    s = socket.socket(socket.AF_INET, socket.SOCK_STREAM)
    try:
        s.bind(('localhost', PORT))
        s.close()
        return PORT
    except socket.error:
        # Port 8000 is in use, find another one
        s = socket.socket(socket.AF_INET, socket.SOCK_STREAM)
        s.bind(('', 0))
        port = s.getsockname()[1]
        s.close()
        return port

import socket

def main():
    # Make sure we run from the project root directory
    script_dir = os.path.dirname(os.path.abspath(__file__))
    project_root = os.path.dirname(script_dir)
    os.chdir(project_root)

    port = get_free_port()
    
    # Define custom Handler to suppress logging output if desired, or keep it standard
    Handler = http.server.SimpleHTTPRequestHandler
    
    # Start server
    httpd = socketserver.TCPServer(('localhost', port), Handler)
    
    url = f"http://localhost:{port}/host/rta_visualizer.html?trace=/rta_trace.json"
    print(f"Starting local server at {url}")
    print("Press Ctrl+C to stop the server.")

    # Open web browser after a short delay
    def open_browser():
        webbrowser.open(url)
        
    threading.Thread(target=open_browser, daemon=True).start()

    try:
        httpd.serve_forever()
    except KeyboardInterrupt:
        print("\nShutting down server...")
        httpd.shutdown()

if __name__ == "__main__":
    main()
