import pytest
from fastapi.testclient import TestClient
from main import app

@pytest.fixture(scope="module")
def client():
    with TestClient(app, raise_server_exceptions=False) as c:
        yield c


def test_health_ok(client):
    response = client.get("/health")
    assert response.status_code == 200
    assert response.json()["status"] == "ok"
    assert response.json()["database"] == "connected"


def test_incidents_returns_list(client):
    response = client.get("/incidents")
    assert response.status_code == 200
    assert "incidents" in response.json()
    assert isinstance(response.json()["incidents"], list)


def test_metrics_endpoint(client):
    response = client.get("/metrics")
    assert response.status_code == 200