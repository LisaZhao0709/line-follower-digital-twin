"""L7 Application Layer: visualization, interaction and experiment presentation.
Outputs dashboards, trajectory plots, diagnostics and downloads."""
from .web_api import create_app

__all__ = [
    'create_app',
]

