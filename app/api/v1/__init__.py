"""Versioned API entrypoint for SystemDashboard."""

from flask import Blueprint

from .routes import register_routes

api_v1 = Blueprint('api_v1', __name__, url_prefix='/api/v1')
register_routes(api_v1)

__all__ = ['api_v1']
