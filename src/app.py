from flask import Flask, jsonify

import redis, os, socket

from flask_cors import CORS

app = Flask(__name__)
CORS(app)
r = redis.Redis(host='redis', port=6379, decode_responses=True)

@app.route('/vote/<item>', methods=['POST'])

def vote(item):
   count = r.incr(f'vote:{item}')
   return jsonify({'item': item, 'votes': count, 'served_by': socket.gethostname()})

@app.route('/votes')

def votes():
   keys = r.keys('vote:*')
   results = {k.replace('vote:',''):r.get(k) for k in keys}
   return jsonify({'results': results, 'served_by': socket.gethostname()})

@app.route('/health')

def health():
   return jsonify({'status': 'ok', 'host': socket.gethostname()})

app.run(host='0.0.0.0', port=5000)
