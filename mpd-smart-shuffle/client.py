#!/usr/bin/env python
# vim: ai ts=4 sw=4 sts=4 expandtab fileencoding=utf-8

from mpd import MPDClient
import logging
from paths import load_config

log = logging.getLogger('mpd_client')

def connect(host=None, port=None, password=None):
    """Connect to MPD server with config fallback"""
    # Load configuration if no parameters provided
    if host is None or port is None:
        config = load_config()

        host = host or config.get('mpd', 'host', fallback='localhost')
        port = port or config.get('mpd', 'port', fallback='6600')
        password = password or config.get('mpd', 'password', fallback=None)

    client = MPDClient()
    client.timeout = 10  # Connection timeout in seconds
    client.idletimeout = None  # No timeout for idle mode

    try:
        log.debug(f"Connecting to MPD at {host}:{port}")
        client.connect(host=host, port=int(port))
        
        if password:
            log.debug("Authenticating with MPD")
            client.password(password)
            
        log.info("Successfully connected to MPD")
        return client
        
    except Exception as e:
        log.error(f"MPD connection failed: {str(e)}")
        client.disconnect()
        raise

def test_connection():
    """Test MPD connection and return status"""
    try:
        client = connect()
        version = client.mpd_version
        client.disconnect()
        return True, f"Connected to MPD {version}"
    except Exception as e:
        return False, str(e)
