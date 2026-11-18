"""Compatibility exports for broker.

Implementations live in the corresponding modules under layers/."""
from layers.l3_communication.broker import serve

__all__ = [
    'serve',
]

if __name__ == '__main__':
    import argparse
    import asyncio
    import logging
    parser = argparse.ArgumentParser()
    parser.add_argument('--port', type=int, default=18884)
    args = parser.parse_args()
    logging.basicConfig(level=logging.WARNING)
    try:
        asyncio.run(serve(args.port))
    except KeyboardInterrupt:
        pass
