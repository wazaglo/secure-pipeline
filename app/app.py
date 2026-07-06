from flask import Flask, jsonify
import os

app = Flask(__name__)

@app.route('/health')
def health():
    return jsonify(status='ok', service='employee-api')

@app.route('/employees')
def employees():
    return jsonify(employees=[
        {'id': 1, 'name': 'Alice', 'role': 'Engineer'},
        {'id': 2, 'name': 'Bob', 'role': 'Manager'},
    ])

if __name__ == '__main__':
    app.run(host='0.0.0.0', port=5000, debug=True)
