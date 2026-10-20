#!/usr/bin/env python3
"""Exercise the built CLI and pinned MCP against a disposable names-only fake broker."""
import argparse
import base64
import json
import os
from pathlib import Path
import select
import socket
import subprocess
import tempfile
import threading
import unittest

P = argparse.ArgumentParser()
P.add_argument('--exe', required=True)
ARGS, REST = P.parse_known_args()
EXE = str(Path(ARGS.exe).resolve())


class Broker:
    def __init__(self, supported=True):
        self.root = tempfile.TemporaryDirectory(prefix='cellar-fields-', dir='/tmp')
        self.path = str(Path(self.root.name) / 'cli.sock')
        self.listener = socket.socket(socket.AF_UNIX)
        self.listener.bind(self.path)
        self.listener.listen(4)
        self.listener.settimeout(.2)
        self.supported, self.messages, self.errors, self.stop = supported, [], [], False
        self.thread = threading.Thread(target=self.serve, daemon=True)
        self.thread.start()

    def serve(self):
        while not self.stop:
            try:
                connection, _ = self.listener.accept()
            except socket.timeout:
                continue
            except OSError:
                return
            try:
                with connection, connection.makefile('rb') as source:
                    connection.settimeout(5)
                    message = json.loads(source.readline())
                    self.messages.append(message)
                    if message.get('kind') == 'status':
                        payload = {'locked': False, 'capabilities': ['field-selection-v1'] if self.supported else []}
                    elif message.get('kind') == 'api-request':
                        payload = {'status': 200, 'body': 'SYNTHETIC_ROUTER_ONLY', 'credentialDelivery': 'broker_only'}
                    else:
                        payload = None
                    if payload is not None:
                        data = base64.b64encode(json.dumps(payload).encode()).decode()
                        connection.sendall(json.dumps({'kind': 'stdout', 'data': data}).encode() + b'\n')
                    connection.sendall(b'{"kind":"exit","exitCode":0}\n')
            except Exception as error:
                self.errors.append(type(error).__name__)

    def __enter__(self):
        return self

    def __exit__(self, *_):
        self.stop = True
        self.listener.close()
        self.thread.join(1)
        self.root.cleanup()
        assert not self.errors, self.errors

    def env(self):
        return {**os.environ, 'KEYDESK_SOCKET_PATH': self.path}


class WireTests(unittest.TestCase):
    def cli(self, broker, *args):
        return subprocess.run([EXE, *args], stdin=subprocess.DEVNULL, capture_output=True, env=broker.env(), timeout=10)

    def test_repeatable_selectors_reach_broker_without_document_contents(self):
        with Broker() as broker:
            result = self.cli(broker, 'run', '--project', 'fixture', '--env', 'dev', '--select', 'TOKEN=CONFIG#/nested/token', '--select', 'PORT=CONFIG#/ports/0', '--stdin-key', 'TOKEN', '--', '/usr/bin/true')
            self.assertEqual(result.returncode, 0, result.stderr)
            self.assertEqual(len(broker.messages), 2)
            self.assertEqual(broker.messages[0]['kind'], 'status')
            self.assertEqual(broker.messages[1]['selections'], [{'variable': 'TOKEN', 'source': 'CONFIG', 'pointer': '/nested/token'}, {'variable': 'PORT', 'source': 'CONFIG', 'pointer': '/ports/0'}])
            self.assertEqual(broker.messages[1]['stdinKey'], 'TOKEN')

    def test_empty_root_pointer_is_preserved(self):
        with Broker() as broker:
            result = self.cli(broker, 'run', '--project', 'fixture', '--select', 'TOKEN=CONFIG#', '--', '/usr/bin/true')
            self.assertEqual(result.returncode, 0, result.stderr)
            self.assertEqual(broker.messages[-1]['selections'][0]['pointer'], '')

    def test_old_broker_never_receives_selection_invocation(self):
        with Broker(supported=False) as broker:
            result = self.cli(broker, 'run', '--project', 'fixture', '--select', 'TOKEN=CONFIG#/token', '--', '/usr/bin/true')
            self.assertNotEqual(result.returncode, 0)
            self.assertIn(b'0.7.20', result.stderr)
            self.assertEqual([x['kind'] for x in broker.messages], ['status'])

    def test_api_field_and_provider_wire_contract(self):
        with Broker() as broker:
            result = self.cli(broker, 'request', '--project', 'fixture', '--key', 'CONFIG', '--field', '/token', '--provider', 'OpenAI', '--url', 'https://api.openai.com/v1/models')
            self.assertEqual(result.returncode, 0, result.stderr)
            self.assertEqual(broker.messages[-1]['field'], '/token')
            self.assertEqual(broker.messages[-1]['provider'], 'OpenAI')

    def test_plain_key_request_stays_compatible_without_probe(self):
        with Broker(supported=False) as broker:
            result = self.cli(broker, 'request', '--project', 'fixture', '--key', 'TOKEN', '--url', 'https://api.openai.com/v1/models')
            self.assertEqual(result.returncode, 0, result.stderr)
            self.assertEqual(len(broker.messages), 1)
            self.assertNotIn('field', broker.messages[0])

    def test_pinned_mcp_selects_field_after_capability_probe(self):
        with Broker() as broker:
            process = subprocess.Popen([EXE, 'mcp', '--project', '11111111-1111-1111-1111-111111111111'], stdin=subprocess.PIPE, stdout=subprocess.PIPE, stderr=subprocess.PIPE, env=broker.env())
            try:
                def send(message):
                    process.stdin.write(json.dumps(message).encode() + b'\n'); process.stdin.flush()
                def receive():
                    self.assertTrue(select.select([process.stdout], [], [], 10)[0], 'MCP response timeout')
                    return json.loads(process.stdout.readline())
                send({'jsonrpc': '2.0', 'id': 1, 'method': 'initialize', 'params': {'protocolVersion': '2025-11-25'}})
                receive()
                send({'jsonrpc': '2.0', 'method': 'notifications/initialized'})
                send({'jsonrpc': '2.0', 'id': 2, 'method': 'tools/call', 'params': {'name': 'request_http', 'arguments': {'key': 'CONFIG', 'field': '/token', 'provider': 'OpenAI', 'method': 'GET', 'url': 'https://api.openai.com/v1/models'}}})
                response = receive()
                self.assertFalse(response['result']['isError'])
                self.assertEqual([x.get('kind') for x in broker.messages], ['status', 'api-request'])
                self.assertEqual(broker.messages[-1]['field'], '/token')
            finally:
                process.stdin.close()
                process.wait(timeout=5)
                process.stdout.close(); process.stderr.close()


if __name__ == '__main__':
    unittest.main(argv=[__file__, *REST])
