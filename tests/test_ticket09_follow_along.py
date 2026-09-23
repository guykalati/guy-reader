"""User-facing browser bridge contracts for click-to-read and shared transport."""
from concurrent.futures import ThreadPoolExecutor
import sys
from pathlib import Path
sys.path.insert(0, str(Path(__file__).resolve().parents[1]))
from fastapi.testclient import TestClient
from speech_engine import app


def test_browser_trigger_requires_page_acknowledgement():
    with TestClient(app) as client, client.websocket_connect('/ws') as ws:
        ws.send_json({'action':'register'})
        ws.receive_json()
        with ThreadPoolExecutor() as pool:
            request = pool.submit(client.post, '/trigger', json={'action':'read-from-selection'})
            command = ws.receive_json()
            assert command.get('requestId'), 'Desktop must correlate actual page acknowledgement'
            assert command.get('expiresAt'), 'Late commands need an explicit expiry'
            ws.send_json({'action':'command-result','requestId':command['requestId'],'success':False})
            result = request.result(timeout=3)
            assert result.json()['status'] == 'no_extension'
