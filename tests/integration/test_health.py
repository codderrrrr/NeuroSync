import pytest
import pytest_asyncio
from httpx import ASGITransport, AsyncClient, codes

from neurosync.main import app


@pytest_asyncio.fixture
async def client() -> AsyncClient:
    transport = ASGITransport(app=app)
    async with AsyncClient(transport=transport, base_url="http://test") as ac:
        yield ac


@pytest.mark.asyncio
async def test_health_check(client: AsyncClient) -> None:
    response = await client.get("/health")
    assert response.status_code == codes.OK
    data = response.json()
    assert data["status"] == "healthy"
    assert data["service"] == "NeuroSync"
    assert "version" in data
