#!/usr/bin/env python3
"""
tests.py — автоматичні тести для Simple Inventory (mywebapp).
Запуск: pytest app/tests.py --cov=app --cov-report=term-missing
"""

import sys
import os
import unittest
import json
from unittest.mock import patch, MagicMock

sys.path.insert(0, os.path.dirname(__file__))

from app import app  # noqa: E402


class TestHealthEndpoints(unittest.TestCase):
    """Тести health-ендпоінтів."""

    def setUp(self):
        app.config["TESTING"] = True
        self.client = app.test_client()

    def test_health_alive(self):
        """GET /health/alive завжди повертає 200 OK."""
        resp = self.client.get("/health/alive")
        self.assertEqual(resp.status_code, 200)
        self.assertEqual(resp.data, b"OK")

    @patch("app.get_db")
    def test_health_ready_ok(self, mock_get_db):
        """GET /health/ready повертає 200 коли БД доступна."""
        mock_conn = MagicMock()
        mock_get_db.return_value = mock_conn

        resp = self.client.get("/health/ready")
        self.assertEqual(resp.status_code, 200)
        self.assertEqual(resp.data, b"OK")
        mock_conn.close.assert_called_once()

    @patch("app.get_db")
    def test_health_ready_db_error(self, mock_get_db):
        """GET /health/ready повертає 500 коли БД недоступна."""
        mock_get_db.side_effect = Exception("Connection refused")

        resp = self.client.get("/health/ready")
        self.assertEqual(resp.status_code, 500)
        self.assertIn(b"DB unavailable", resp.data)


class TestIndexEndpoint(unittest.TestCase):
    """Тести кореневого ендпоінту."""

    def setUp(self):
        app.config["TESTING"] = True
        self.client = app.test_client()

    def test_index_returns_html(self):
        """GET / повертає HTML-сторінку з описом API."""
        resp = self.client.get("/")
        self.assertEqual(resp.status_code, 200)
        self.assertIn(b"Simple Inventory", resp.data)
        self.assertIn(b"/items", resp.data)


class TestListItems(unittest.TestCase):
    """Тести GET /items."""

    def setUp(self):
        app.config["TESTING"] = True
        self.client = app.test_client()

    @patch("app.get_db")
    def test_list_items_json_empty(self, mock_get_db):
        """GET /items повертає порожній JSON-масив коли таблиця пуста."""
        mock_conn = MagicMock()
        mock_cursor = MagicMock()
        mock_cursor.fetchall.return_value = []
        mock_conn.cursor.return_value = mock_cursor
        mock_get_db.return_value = mock_conn

        resp = self.client.get("/items", headers={"Accept": "application/json"})
        self.assertEqual(resp.status_code, 200)
        data = json.loads(resp.data)
        self.assertEqual(data, [])

    @patch("app.get_db")
    def test_list_items_json_with_data(self, mock_get_db):
        """GET /items повертає список предметів у JSON."""
        mock_conn = MagicMock()
        mock_cursor = MagicMock()
        mock_cursor.fetchall.return_value = [
            {"id": 1, "name": "Monitor"},
            {"id": 2, "name": "Keyboard"},
        ]
        mock_conn.cursor.return_value = mock_cursor
        mock_get_db.return_value = mock_conn

        resp = self.client.get("/items", headers={"Accept": "application/json"})
        self.assertEqual(resp.status_code, 200)
        data = json.loads(resp.data)
        self.assertEqual(len(data), 2)
        self.assertEqual(data[0]["name"], "Monitor")

    @patch("app.get_db")
    def test_list_items_html(self, mock_get_db):
        """GET /items з Accept: text/html повертає HTML-таблицю."""
        mock_conn = MagicMock()
        mock_cursor = MagicMock()
        mock_cursor.fetchall.return_value = [{"id": 1, "name": "Monitor"}]
        mock_conn.cursor.return_value = mock_cursor
        mock_get_db.return_value = mock_conn

        resp = self.client.get("/items", headers={"Accept": "text/html"})
        self.assertEqual(resp.status_code, 200)
        self.assertIn(b"<table", resp.data)
        self.assertIn(b"Monitor", resp.data)


class TestCreateItem(unittest.TestCase):
    """Тести POST /items."""

    def setUp(self):
        app.config["TESTING"] = True
        self.client = app.test_client()

    @patch("app.get_db")
    def test_create_item_success_json(self, mock_get_db):
        """POST /items з валідними даними повертає 201 і створений предмет."""
        mock_conn = MagicMock()
        mock_cursor = MagicMock()
        mock_cursor.lastrowid = 42
        mock_conn.cursor.return_value = mock_cursor
        mock_get_db.return_value = mock_conn

        resp = self.client.post(
            "/items",
            data=json.dumps({"name": "Monitor", "quantity": 3}),
            content_type="application/json",
        )
        self.assertEqual(resp.status_code, 201)
        data = json.loads(resp.data)
        self.assertEqual(data["id"], 42)
        self.assertEqual(data["name"], "Monitor")
        self.assertEqual(data["quantity"], 3)

    def test_create_item_missing_name(self):
        """POST /items без name повертає 400."""
        resp = self.client.post(
            "/items",
            data=json.dumps({"quantity": 3}),
            content_type="application/json",
        )
        self.assertEqual(resp.status_code, 400)
        self.assertIn(b"name is required", resp.data)

    def test_create_item_invalid_quantity(self):
        """POST /items з нечисловим quantity повертає 400."""
        resp = self.client.post(
            "/items",
            data=json.dumps({"name": "Monitor", "quantity": "abc"}),
            content_type="application/json",
        )
        self.assertEqual(resp.status_code, 400)
        self.assertIn(b"quantity must be integer", resp.data)

    def test_create_item_missing_quantity(self):
        """POST /items без quantity повертає 400."""
        resp = self.client.post(
            "/items",
            data=json.dumps({"name": "Monitor"}),
            content_type="application/json",
        )
        self.assertEqual(resp.status_code, 400)

    @patch("app.get_db")
    def test_create_item_html_response(self, mock_get_db):
        """POST /items з Accept: text/html повертає HTML з id."""
        mock_conn = MagicMock()
        mock_cursor = MagicMock()
        mock_cursor.lastrowid = 5
        mock_conn.cursor.return_value = mock_cursor
        mock_get_db.return_value = mock_conn

        resp = self.client.post(
            "/items",
            data=json.dumps({"name": "Laptop", "quantity": 1}),
            content_type="application/json",
            headers={"Accept": "text/html"},
        )
        self.assertEqual(resp.status_code, 201)
        self.assertIn(b"id=5", resp.data)


class TestGetItem(unittest.TestCase):
    """Тести GET /items/<id>."""

    def setUp(self):
        app.config["TESTING"] = True
        self.client = app.test_client()

    @patch("app.get_db")
    def test_get_item_found_json(self, mock_get_db):
        """GET /items/1 повертає деталі предмету у JSON."""
        mock_conn = MagicMock()
        mock_cursor = MagicMock()
        mock_cursor.fetchone.return_value = {
            "id": 1,
            "name": "Monitor",
            "quantity": 3,
            "created_at": "2026-01-01 00:00:00",
        }
        mock_conn.cursor.return_value = mock_cursor
        mock_get_db.return_value = mock_conn

        resp = self.client.get("/items/1", headers={"Accept": "application/json"})
        self.assertEqual(resp.status_code, 200)
        data = json.loads(resp.data)
        self.assertEqual(data["id"], 1)
        self.assertEqual(data["name"], "Monitor")
        self.assertEqual(data["quantity"], 3)

    @patch("app.get_db")
    def test_get_item_not_found_json(self, mock_get_db):
        """GET /items/999 повертає 404 у JSON."""
        mock_conn = MagicMock()
        mock_cursor = MagicMock()
        mock_cursor.fetchone.return_value = None
        mock_conn.cursor.return_value = mock_cursor
        mock_get_db.return_value = mock_conn

        resp = self.client.get("/items/999", headers={"Accept": "application/json"})
        self.assertEqual(resp.status_code, 404)
        data = json.loads(resp.data)
        self.assertEqual(data["error"], "not found")

    @patch("app.get_db")
    def test_get_item_not_found_html(self, mock_get_db):
        """GET /items/999 з Accept: text/html повертає 404 HTML."""
        mock_conn = MagicMock()
        mock_cursor = MagicMock()
        mock_cursor.fetchone.return_value = None
        mock_conn.cursor.return_value = mock_cursor
        mock_get_db.return_value = mock_conn

        resp = self.client.get("/items/999", headers={"Accept": "text/html"})
        self.assertEqual(resp.status_code, 404)
        self.assertIn(b"Not found", resp.data)

    @patch("app.get_db")
    def test_get_item_found_html(self, mock_get_db):
        """GET /items/1 з Accept: text/html повертає HTML-таблицю."""
        mock_conn = MagicMock()
        mock_cursor = MagicMock()
        mock_cursor.fetchone.return_value = {
            "id": 1,
            "name": "Monitor",
            "quantity": 3,
            "created_at": "2026-01-01 00:00:00",
        }
        mock_conn.cursor.return_value = mock_cursor
        mock_get_db.return_value = mock_conn

        resp = self.client.get("/items/1", headers={"Accept": "text/html"})
        self.assertEqual(resp.status_code, 200)
        self.assertIn(b"<table", resp.data)
        self.assertIn(b"Monitor", resp.data)


if __name__ == "__main__":
    unittest.main()
