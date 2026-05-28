#!/usr/bin/env python3
"""
migrate.py — створює таблиці та індекси для Simple Inventory.
Запускається перед стартом застосунку.
"""

import argparse
import sys
import mysql.connector
from mysql.connector import Error


CREATE_ITEMS = """
CREATE TABLE IF NOT EXISTS items (
    id         INT UNSIGNED AUTO_INCREMENT PRIMARY KEY,
    name       VARCHAR(255) NOT NULL,
    quantity   INT          NOT NULL DEFAULT 0,
    created_at DATETIME     NOT NULL DEFAULT CURRENT_TIMESTAMP
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4;
"""

CREATE_IDX_NAME = """
CREATE INDEX IF NOT EXISTS idx_items_name ON items (name);
"""


def migrate(conn):
    cur = conn.cursor()
    print("[migrate] Creating table 'items'...")
    cur.execute(CREATE_ITEMS)
    print("[migrate] Creating index idx_items_name...")
    try:
        cur.execute(CREATE_IDX_NAME)
    except Error:
        pass  # index may already exist on older MariaDB
    conn.commit()
    cur.close()
    print("[migrate] Done.")


def parse_args():
    p = argparse.ArgumentParser(description="DB migration for mywebapp")
    p.add_argument("--db-host",     default="127.0.0.1")
    p.add_argument("--db-port",     type=int, default=3306)
    p.add_argument("--db-name",     required=True)
    p.add_argument("--db-user",     required=True)
    p.add_argument("--db-password", required=True)
    return p.parse_args()


if __name__ == "__main__":
    args = parse_args()
    try:
        conn = mysql.connector.connect(
            host=args.db_host,
            port=args.db_port,
            database=args.db_name,
            user=args.db_user,
            password=args.db_password,
        )
        migrate(conn)
        conn.close()
    except Error as e:
        print(f"[migrate] ERROR: {e}", file=sys.stderr)
        sys.exit(1)
