import os
from http.server import SimpleHTTPRequestHandler, HTTPServer
import sys

# BEGIN User Editable Block
image_dir = "placeholder_image_dir"
# END User Editable Block

# Define a simple HTTP request handler
class ImageServer(SimpleHTTPRequestHandler):
    def end_headers(self):
        self.send_header('Access-Control-Allow-Origin', '*')
        super().end_headers()

    def is_image_file(self, path):
        # Check if the file extension is in the list of image extensions
        image_extensions = ['.jpg', '.jpeg', '.png', '.gif']
        _, ext = os.path.splitext(path)
        return ext.lower() in image_extensions

    def do_GET(self):
        if self.is_image_file(self.path):
            # If it's an image file, serve it
            super().do_GET()
        else:
            # If it's not an image file, return a 403 Forbidden status
            self.send_response(403)
            self.end_headers()
            self.wfile.write(b'Forbidden: Only image files are allowed.')

if len(sys.argv) > 1:
    port = int(sys.argv[1])
else:
    port = 9555  # Default port if not specified

# Run the HTTP server on the specified port
try:
    with HTTPServer(('localhost', port), ImageServer) as server:
        print(f'Server started on http://localhost:{port}')
        server.serve_forever()
except KeyboardInterrupt:
    print('\nServer stopped.')

