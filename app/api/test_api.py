import pytest
from fastapi.testclient import TestClient
from main import app

client = TestClient(app)


def test_health_ok():
    response = client.get("/health")
    assert response.status_code == 200
    assert response.json()["status"] == "ok"
    assert response.json()["database"] == "connected"


def test_incidents_returns_list():
    response = client.get("/incidents")
    assert response.status_code == 200
    assert "incidents" in response.json()
    assert isinstance(response.json()["incidents"], list)


def test_metrics_endpoint():
    response = client.get("/metrics")
    assert response.status_code == 200