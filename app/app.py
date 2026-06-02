#!/usr/bin/env python3
"""
mywebapp - Simple Inventory Service.

Variant: N=8, V2=1, V3=3, V5=4
Configuration is supplied through command-line arguments.
"""

import argparse
import os

import mysql.connector
from flask import Flask, request, jsonify, Response
from gunicorn.app.base import BaseApplication

app = Flask(__name__)

DB_CONFIG: dict[str, object] = {}


def configure_db(args):
    DB_CONFIG.update({
        "host": args.db_host,
        "port": args.db_port,
        "database": args.db_name,
        "user": args.db_user,
        "password": args.db_password,
    })


def get_db():
    config = DB_CONFIG or {
        "host": os.environ.get("DB_HOST", "127.0.0.1"),
        "port": int(os.environ.get("DB_PORT", 3306)),
        "database": os.environ.get("DB_NAME", "mywebapp"),
        "user": os.environ.get("DB_USER", "mywebapp"),
        "password": os.environ.get("DB_PASSWORD", ""),
    }
    return mysql.connector.connect(**config)


def accepts_html():
    accept = request.headers.get("Accept", "")
    return "text/html" in accept and "application/json" not in accept


def html_response(body, status=200):
    return Response(f"<!DOCTYPE html><html><body>{body}</body></html>",
                    status=status, mimetype="text/html")


@app.route("/health/alive")
def health_alive():
    return Response("OK", status=200, mimetype="text/plain")


@app.route("/health/ready")
def health_ready():
    try:
        conn = get_db()
        conn.close()
        return Response("OK", status=200, mimetype="text/plain")
    except Exception as e:
        return Response(f"DB unavailable: {e}", status=500, mimetype="text/plain")


@app.route("/")
def index():
    html = """
    <h1>Simple Inventory API</h1>
    <ul>
      <li>GET /items - list inventory items</li>
      <li>POST /items - create item with name and quantity</li>
      <li>GET /items/&lt;id&gt; - show item details</li>
    </ul>
    """
    return html_response(html)


@app.route("/items", methods=["GET"])
def list_items():
    conn = get_db()
    cur = conn.cursor(dictionary=True)
    cur.execute("SELECT id, name FROM items ORDER BY id")
    rows = cur.fetchall()
    cur.close()
    conn.close()
    if accepts_html():
        tr = "".join(f"<tr><td>{r['id']}</td><td>{r['name']}</td></tr>" for r in rows)
        return html_response(f"<h1>Inventory</h1><table border=1><tr><th>ID</th><th>Name</th></tr>{tr}</table>")
    return jsonify(rows)


@app.route("/items", methods=["POST"])
def create_item():
    data = request.get_json(silent=True) or request.form
    name = (data.get("name") or "").strip()
    quantity = data.get("quantity", "")
    if not name:
        return Response("name is required", status=400, mimetype="text/plain")
    try:
        quantity = int(quantity)
    except (TypeError, ValueError):
        return Response("quantity must be integer", status=400, mimetype="text/plain")
    conn = get_db()
    cur = conn.cursor()
    cur.execute("INSERT INTO items (name, quantity) VALUES (%s, %s)", (name, quantity))
    conn.commit()
    item_id = cur.lastrowid
    cur.close()
    conn.close()
    if accepts_html():
        return html_response(f"<p>Created item id={item_id}</p>", status=201)
    return jsonify({"id": item_id, "name": name, "quantity": quantity}), 201


@app.route("/items/<int:item_id>", methods=["GET"])
def get_item(item_id):
    conn = get_db()
    cur = conn.cursor(dictionary=True)
    cur.execute("SELECT id, name, quantity, created_at FROM items WHERE id=%s", (item_id,))
    row = cur.fetchone()
    cur.close()
    conn.close()
    if row is None:
        if accepts_html():
            return html_response("<p>Not found</p>", status=404)
        return jsonify({"error": "not found"}), 404
    if accepts_html():
        return html_response(
            f"<table border=1>"
            f"<tr><td>ID</td><td>{row['id']}</td></tr>"
            f"<tr><td>Name</td><td>{row['name']}</td></tr>"
            f"<tr><td>Quantity</td><td>{row['quantity']}</td></tr>"
            f"<tr><td>Created</td><td>{row['created_at']}</td></tr>"
            f"</table>"
        )
    row["created_at"] = str(row["created_at"])
    return jsonify(row)


class GunicornApplication(BaseApplication):
    def __init__(self, application, options):
        self.application = application
        self.options = options
        super().__init__()

    def load_config(self):
        for key, value in self.options.items():
            if key in self.cfg.settings and value is not None:
                self.cfg.set(key.lower(), value)

    def load(self):
        return self.application


def parse_args():
    parser = argparse.ArgumentParser(description="Simple Inventory web service")
    parser.add_argument("--host", default="127.0.0.1", help="Listen host")
    parser.add_argument("--port", type=int, default=8000, help="Listen port")
    parser.add_argument("--db-host", default="127.0.0.1", help="MariaDB host")
    parser.add_argument("--db-port", type=int, default=3306, help="MariaDB port")
    parser.add_argument("--db-name", required=True, help="Database name")
    parser.add_argument("--db-user", required=True, help="Database user")
    parser.add_argument("--db-password", required=True, help="Database password")
    parser.add_argument("--workers", type=int, default=1, help="Worker processes")
    return parser.parse_args()


def main():
    args = parse_args()
    configure_db(args)
    options = {
        "workers": args.workers,
        "accesslog": "-",
        "errorlog": "-",
    }
    if "LISTEN_FDS" not in os.environ:
        options["bind"] = f"{args.host}:{args.port}"
    GunicornApplication(app, options).run()


if __name__ == "__main__":
    main()
def broken_syntax
